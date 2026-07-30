import AppKit
import CodexLidKeeperCore
import Darwin
import Foundation
import UserNotifications

@MainActor
final class DashboardModel: ObservableObject {
    @Published private(set) var status: KeeperStatusSnapshot?
    @Published private(set) var errorMessage: String?
    @Published private(set) var hookInstallMessage: String?
    @Published private(set) var hooksConfigurationError: String?
    @Published private(set) var isPreparedToClose = false
    @Published private(set) var helperInstalled = false
    @Published private(set) var recoveryWatchdogLoaded = false
    @Published private(set) var userAgentLoaded = false
    @Published private(set) var powerHeartbeatFresh = false
    @Published private(set) var hooksInstalled = false
    @Published private(set) var brightnessAvailable = false
    @Published var dimWhenReady: Bool {
        didSet {
            defaults.set(dimWhenReady, forKey: dimPreferenceKey)
        }
    }

    private let controller: KeeperController
    private let defaults = UserDefaults.standard
    private let dimPreferenceKey =
        "com.zundu.codex-lid-keeper.dim-when-ready"
    private let demoMode: Bool
    private var timer: Timer?
    private var previouslyWorking = false
    private var lastRecoveryWatchdogCheck = Date.distantPast
    private let recoveryWatchdogCheckInterval: TimeInterval = 10

    init() {
        controller = KeeperController()
        demoMode = ProcessInfo.processInfo.environment[
            "CODEX_LID_KEEPER_DEMO"
        ] == "1"
        if defaults.object(forKey: dimPreferenceKey) == nil {
            dimWhenReady = true
        } else {
            dimWhenReady = defaults.bool(forKey: dimPreferenceKey)
        }
        refresh()
        timer = Timer.scheduledTimer(
            withTimeInterval: 2,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    private func refreshCapabilities(
        forceWatchdogCheck: Bool = false
    ) {
        helperInstalled = demoMode || FileManager.default.isExecutableFile(
            atPath: KeeperConstants.installedExecutable
        )
        if demoMode {
            recoveryWatchdogLoaded = true
            userAgentLoaded = true
            powerHeartbeatFresh = true
        } else if forceWatchdogCheck
            || Date().timeIntervalSince(lastRecoveryWatchdogCheck)
                >= recoveryWatchdogCheckInterval {
            recoveryWatchdogLoaded = readRecoveryWatchdogLoaded()
            userAgentLoaded = readUserAgentLoaded()
            lastRecoveryWatchdogCheck = Date()
        }
        if demoMode {
            hooksInstalled = true
            hooksConfigurationError = nil
        } else {
            do {
                hooksInstalled = try readHooksInstalled()
                hooksConfigurationError = nil
            } catch {
                hooksInstalled = false
                hooksConfigurationError = error.localizedDescription
            }
        }
        brightnessAvailable = demoMode
            || BrightnessController.shared.canControlBrightness
    }

    private func readHooksInstalled() throws -> Bool {
        let hooks = controller.paths.homeDirectory
            .appendingPathComponent(".codex/hooks.json")
        let command = "\(KeeperConstants.installedExecutable) hook"
        return try HooksConfiguration.verify(
            file: hooks,
            command: command
        ).isEmpty
    }

    private func readRecoveryWatchdogLoaded() -> Bool {
        guard FileManager.default.isReadableFile(
            atPath: KeeperConstants.recoveryDaemonPlist
        ) else {
            return false
        }
        return readLaunchdServiceLoaded(
            "system/\(KeeperConstants.recoveryDaemonLabel)"
        )
    }

    private func readUserAgentLoaded() -> Bool {
        let plist = controller.paths.homeDirectory
            .appendingPathComponent(
                "Library/LaunchAgents/\(KeeperConstants.userAgentLabel).plist"
            )
        guard FileManager.default.isReadableFile(atPath: plist.path) else {
            return false
        }
        guard let processIdentifier = readRunningLaunchdService(
            "gui/\(getuid())/\(KeeperConstants.userAgentLabel)"
        ) else {
            return false
        }
        return LaunchdJobHealth.processIsAlive(processIdentifier)
            && LaunchdJobHealth.daemonLockIsHeld(
                at: controller.paths.daemonLockFile
            )
    }

    private func readLaunchdServiceLoaded(_ service: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", service]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func readRunningLaunchdService(
        _ service: String
    ) -> Int32? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", service]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let text = String(data: data, encoding: .utf8) else {
                return nil
            }
            return LaunchdJobHealth.runningPID(
                fromPrintOutput: text
            )
        } catch {
            return nil
        }
    }

    private func readPowerHeartbeatFresh(
        for status: KeeperStatusSnapshot
    ) -> Bool {
        guard status.powerOwned else { return true }
        let attributes = try? FileManager.default.attributesOfItem(
            atPath: KeeperConstants.rootOwnershipFile
        )
        let modificationDate = attributes?[.modificationDate] as? Date
        let maximumAge = min(
            KeeperConstants.rootWatchdogMaximumAge - 10,
            max(
                30,
                status.configuration.powerHeartbeatInterval * 2 + 5
            )
        )
        return PowerHeartbeatHealth.isFresh(
            modificationDate: modificationDate,
            maximumAge: maximumAge
        )
    }

    var recoveryProtectionReady: Bool {
        recoveryWatchdogLoaded && powerHeartbeatFresh
    }

    var systemComponentsReady: Bool {
        helperInstalled && recoveryProtectionReady && userAgentLoaded
    }

    var hookTrackingConfirmed: Bool {
        status?.runtimeDetectionAvailable == true
            || status?.hasObservedHookEvent == true
    }

    var readyToClose: Bool {
        guard let status else { return false }
        return status.codexIsWorking
            && status.automationEnabled
            && status.decision == .active
            && status.powerOwned
            && systemComponentsReady
            && hooksInstalled
    }

    var menuSymbol: String {
        guard let status else { return "laptopcomputer.slash" }
        if errorMessage != nil || status.lastError != nil {
            return "exclamationmark.triangle.fill"
        }
        if isPreparedToClose {
            return "checkmark.circle.fill"
        }
        if status.powerOwned {
            return "bolt.shield.fill"
        }
        if status.codexIsWorking {
            return "circle.dotted"
        }
        return "laptopcomputer"
    }

    var menuTitle: String {
        guard let status else { return "Codex Lid Keeper" }
        if isPreparedToClose { return "可以合盖" }
        if status.powerOwned { return "正在守护 Codex" }
        if status.codexIsWorking { return "Codex 正在工作" }
        return "等待任务"
    }

    func refresh() {
        refreshCapabilities()
        do {
            let newStatus = try controller.status()
            powerHeartbeatFresh = demoMode
                || readPowerHeartbeatFresh(for: newStatus)
            if status.map({
                !displayEquivalent($0, newStatus)
            }) ?? true {
                status = newStatus
            }
            errorMessage = nil

            if isPreparedToClose
                && (
                    !newStatus.codexIsWorking
                        || newStatus.decision != .active
                        || !systemComponentsReady
                        || !hooksInstalled
                ) {
                cancelReadyMode()
            }
            if previouslyWorking, !newStatus.codexIsWorking {
                notify(
                    title: "Codex work finished",
                    body: "Sleep and brightness settings were restored."
                )
            }
            previouslyWorking = newStatus.codexIsWorking
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setAutomationEnabled(_ enabled: Bool) {
        perform {
            try controller.setAutomationEnabled(enabled)
        }
    }

    func setPowerMode(_ mode: GuardPowerMode) {
        perform {
            guard var configuration = status?.configuration else { return }
            configuration.powerMode = mode
            try controller.saveConfiguration(configuration)
        }
    }

    func setMinimumBatteryPercent(_ value: Int) {
        perform {
            guard var configuration = status?.configuration else { return }
            configuration.minimumBatteryPercent = value
            try controller.saveConfiguration(configuration)
        }
    }

    func prepareToClose() {
        refreshCapabilities(forceWatchdogCheck: true)
        if let status {
            powerHeartbeatFresh = demoMode
                || readPowerHeartbeatFresh(for: status)
        }
        guard readyToClose else { return }
        do {
            if dimWhenReady, !demoMode {
                try BrightnessController.shared.dimAfterCountdown()
            }
            isPreparedToClose = true
            notify(
                title: "Ready to close",
                body: "Codex Lid Keeper is guarding the active task."
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelReadyMode() {
        BrightnessController.shared.restoreIfNeeded()
        isPreparedToClose = false
    }

    func emergencyRestore() {
        perform {
            BrightnessController.shared.restoreIfNeeded()
            try controller.emergencyRestore()
            isPreparedToClose = false
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func installHooksAndOpenCodex() {
        guard systemComponentsReady else {
            openBundledInstaller()
            return
        }

        let hooks = controller.paths.homeDirectory
            .appendingPathComponent(".codex/hooks.json")
        do {
            let command = "\(KeeperConstants.installedExecutable) hook"
            let update = try HooksConfiguration.install(
                file: hooks,
                command: command
            )
            let missing = try HooksConfiguration.verify(
                file: hooks,
                command: command
            )
            guard missing.isEmpty else {
                throw HookInstallError.failed(
                    "以下事件缺失或重复：\(missing.joined(separator: "、"))"
                )
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(
                "/hooks",
                forType: .string
            )
            let backupText = update.backup == nil
                ? ""
                : "原配置已备份。"
            hookInstallMessage =
                "Hook 已合并。\(backupText)/hooks 已复制到剪贴板，请在 Codex 中粘贴并信任五个新 Hook。"
            refresh()
            openCodex()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearHookInstallMessage() {
        hookInstallMessage = nil
    }

    func openInstallGuide() {
        guard let url = URL(
            string:
                "https://github.com/Apex-Studio-He/codex-lid-keeper#install"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openBundledInstaller() {
        if let installer = Bundle.main.url(
            forResource: "Install Codex Lid Keeper",
            withExtension: "command"
        ),
           FileManager.default.isExecutableFile(atPath: installer.path),
           NSWorkspace.shared.open(installer) {
            return
        }
        errorMessage =
            "当前 App 缺少完整安装组件，已为你打开 GitHub 安装说明。"
        openInstallGuide()
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func displayEquivalent(
        _ lhs: KeeperStatusSnapshot,
        _ rhs: KeeperStatusSnapshot
    ) -> Bool {
        lhs.automationEnabled == rhs.automationEnabled
            && lhs.decision == rhs.decision
            && lhs.powerOwned == rhs.powerOwned
            && lhs.livePower == rhs.livePower
            && lhs.pendingEventCount == rhs.pendingEventCount
            && lhs.hasObservedHookEvent == rhs.hasObservedHookEvent
            && lhs.runtimeDetectionAvailable
                == rhs.runtimeDetectionAvailable
            && lhs.configuration == rhs.configuration
            && lhs.lastError == rhs.lastError
            && displayTasks(lhs.activeLeases)
                == displayTasks(rhs.activeLeases)
    }

    private func displayTasks(
        _ leases: [TaskLease]
    ) -> [DisplayTask] {
        leases.map {
            DisplayTask(
                id: $0.id,
                projectName: $0.projectName,
                startedAt: $0.startedAt
            )
        }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
        )
    }

    private func openCodex() {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.openai.codex"
        ) else {
            return
        }
        let configuration =
            NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(
            at: url,
            configuration: configuration
        )
    }

}

private struct DisplayTask: Equatable {
    let id: String
    let projectName: String
    let startedAt: Date
}

private enum HookInstallError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let detail):
            if detail.isEmpty {
                return "Codex Hook 安装失败。"
            }
            return "Codex Hook 安装失败：\(detail)"
        }
    }
}
