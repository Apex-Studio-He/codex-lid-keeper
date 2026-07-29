import AppKit
import CodexLidKeeperCore
import Foundation
import UserNotifications

@MainActor
final class DashboardModel: ObservableObject {
    @Published private(set) var status: KeeperStatusSnapshot?
    @Published private(set) var errorMessage: String?
    @Published private(set) var hookInstallMessage: String?
    @Published private(set) var isPreparedToClose = false
    @Published private(set) var helperInstalled = false
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
        refreshCapabilities()
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

    private func refreshCapabilities() {
        helperInstalled = demoMode || FileManager.default.isExecutableFile(
            atPath: KeeperConstants.installedExecutable
        )
        hooksInstalled = demoMode || readHooksInstalled()
        brightnessAvailable = demoMode
            || BrightnessController.shared.canControlBrightness
    }

    private func readHooksInstalled() -> Bool {
        let hooks = controller.paths.homeDirectory
            .appendingPathComponent(".codex/hooks.json")
        guard let data = try? Data(contentsOf: hooks),
              let text = String(data: data, encoding: .utf8) else {
            return false
        }
        return text.contains(KeeperConstants.integrationMarker)
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
            && helperInstalled
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
        do {
            let newStatus = try controller.status()
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
        guard helperInstalled else {
            openInstallGuide()
            return
        }
        guard let script = Bundle.main.url(
            forResource: "hooks_config",
            withExtension: "py"
        ) else {
            errorMessage = "App 内缺少 Hook 安装组件，请重新运行完整安装脚本。"
            return
        }

        let hooks = controller.paths.homeDirectory
            .appendingPathComponent(".codex/hooks.json")
        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(
            fileURLWithPath: "/usr/bin/python3"
        )
        process.arguments = [
            script.path,
            "install",
            "--file",
            hooks.path,
            "--command",
            "\(KeeperConstants.installedExecutable) hook",
        ]
        process.standardError = errors
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let data = errors.fileHandleForReading.readDataToEndOfFile()
                let detail = String(
                    decoding: data,
                    as: UTF8.self
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                throw HookInstallError.failed(detail)
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(
                "/hooks",
                forType: .string
            )
            hookInstallMessage =
                "Hook 已合并并备份原配置，/hooks 已复制到剪贴板。请在 Codex 中粘贴并信任五个新 Hook。"
            refreshCapabilities()
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
