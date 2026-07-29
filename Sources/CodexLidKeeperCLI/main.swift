import CodexLidKeeperCore
import Darwin
import Foundation

@main
struct CodexLidKeeperMain {
    static func main() {
        let code = autoreleasepool {
            run(arguments: Array(CommandLine.arguments.dropFirst()))
        }
        Darwin.exit(code)
    }

    private static func run(arguments: [String]) -> Int32 {
        guard let command = arguments.first else {
            printUsage()
            return 2
        }

        if command == "power" {
            return runPower(arguments: Array(arguments.dropFirst()))
        }

        let context = RuntimeContext()
        if command == "hook" {
            return runHook(context: context)
        }

        do {
            try context.configurationStore.createDefaultIfMissing()
            switch command {
            case "daemon":
                return try runDaemon(
                    context: context,
                    once: arguments.dropFirst().contains("--once")
                )
            case "status":
                try printStatus(
                    context: context,
                    asJSON: arguments.dropFirst().contains("--json")
                )
                return 0
            case "pause":
                try setAutomation(false, clearLeases: false, context: context)
                print("Codex Lid Keeper paused; owned sleep state restored.")
                return 0
            case "resume":
                try setAutomation(true, clearLeases: false, context: context)
                print("Codex Lid Keeper resumed.")
                return 0
            case "clear":
                try clearLeases(context: context, pause: false)
                print("Active task leases cleared; owned sleep state restored.")
                return 0
            case "emergency-restore":
                try emergencyRestore(context: context)
                print("Automation paused, task leases cleared, and owned sleep state restored.")
                return 0
            case "config":
                if arguments.dropFirst().first == "show" {
                    try printConfiguration(context: context)
                    return 0
                }
                fputs("Usage: codex-lid-keeper config show\n", stderr)
                return 2
            case "help", "--help", "-h":
                printUsage()
                return 0
            default:
                fputs("Unknown command: \(command)\n", stderr)
                printUsage()
                return 2
            }
        } catch {
            context.logger.append("command=\(command) result=failed error=\(error)")
            fputs("codex-lid-keeper: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private static func runHook(context: RuntimeContext) -> Int32 {
        defer {
            // Stop Hooks require valid JSON on successful exit. Empty JSON is
            // inert for all of the lifecycle events installed by this project.
            FileHandle.standardOutput.write(Data("{}\n".utf8))
        }

        do {
            guard let data = try FileHandle.standardInput.read(
                upToCount: KeeperConstants.hookInputLimit + 1
            ) else {
                return 0
            }
            let input = try HookProcessor.decode(data)
            _ = try context.eventPipeline.enqueue(input)
        } catch {
            // Hooks are deliberately fail-open: lifecycle telemetry must never
            // block the user's Codex task. The root watchdog remains the final
            // recovery boundary if a prior assertion was active.
            context.logger.append("hook result=ignored error=\(error)")
        }
        return 0
    }

    private static func runDaemon(context: RuntimeContext, once: Bool) throws -> Int32 {
        let daemonLock = try ProcessLock(file: context.paths.daemonLockFile)
        guard daemonLock.tryAcquire() else {
            if once {
                return 0
            }
            throw CLIError.daemonAlreadyRunning
        }

        let coordinator = DaemonCoordinator(
            eventDirectory: context.paths.eventSpoolDirectory,
            stateStore: context.stateStore,
            powerSourceProvider: context.powerSourceProvider,
            powerController: context.powerController,
            runtimeTaskDetector: context.runtimeTaskDetector
        )
        repeat {
            let configuration = try context.configurationStore.load()
            let cycle = try coordinator.runCycle(
                configuration: configuration
            )
            let consumption = cycle.eventConsumption
            let removedLeaseCount =
                cycle.reconciliation?.removedLeaseCount ?? 0
            if consumption.appliedCount > 0
                || consumption.duplicateCount > 0
                || consumption.rejectedCount > 0
                || removedLeaseCount > 0 {
                let active = cycle.reconciliation.map {
                    String($0.activeLeaseCount)
                } ?? "unchanged"
                context.logger.append(
                    "daemon events=\(consumption.appliedCount) duplicates=\(consumption.duplicateCount) rejected=\(consumption.rejectedCount) expired=\(removedLeaseCount) active=\(active)"
                )
            }
            if once {
                break
            }
            Thread.sleep(
                forTimeInterval: max(0.25, configuration.eventPollInterval)
            )
        } while true
        return 0
    }

    private static func setAutomation(
        _ enabled: Bool,
        clearLeases: Bool,
        context: RuntimeContext
    ) throws {
        let configuration = try context.configurationStore.load()
        let snapshot = context.powerSourceProvider.currentSnapshot()
        try context.stateStore.update { state in
            state.automationEnabled = enabled
            if clearLeases {
                state.leases.removeAll()
                state.runtimeLeases.removeAll()
            }
            _ = KeeperReconciler.reconcile(
                state: &state,
                configuration: configuration,
                powerSnapshot: snapshot,
                powerController: context.powerController
            )
        }
    }

    private static func clearLeases(context: RuntimeContext, pause: Bool) throws {
        _ = try context.eventPipeline.discardPending()
        let configuration = try context.configurationStore.load()
        let snapshot = context.powerSourceProvider.currentSnapshot()
        try context.stateStore.update { state in
            if pause {
                state.automationEnabled = false
            }
            state.leases.removeAll()
            state.runtimeLeases.removeAll()
            _ = KeeperReconciler.reconcile(
                state: &state,
                configuration: configuration,
                powerSnapshot: snapshot,
                powerController: context.powerController
            )
        }
    }

    private static func emergencyRestore(context: RuntimeContext) throws {
        _ = try? context.eventPipeline.discardPending()
        try context.stateStore.update { state in
            state.automationEnabled = false
            state.leases.removeAll()
            state.runtimeLeases.removeAll()
            state.powerRequested = false
            state.lastDecision = .paused
            state.lastReconciledAt = Date()
        }
        if context.powerController.isOwned() {
            try context.powerController.restore()
        }
    }

    private static func printStatus(context: RuntimeContext, asJSON: Bool) throws {
        let configuration = try context.configurationStore.load()
        let state = try context.stateStore.read()
        let livePower = context.powerSourceProvider.currentSnapshot()
        let pendingEventCount = try context.eventPipeline.pendingCount()
        let detection = context.runtimeTaskDetector.detectActiveTasks(
            now: Date(),
            maximumAge: configuration.leaseDuration
        )
        var statusState = state
        if detection.sourceAvailable {
            statusState.runtimeLeases = Dictionary(
                uniqueKeysWithValues: detection.activeTasks.map {
                    ($0.id, $0)
                }
            )
        }
        let status = StatusReport(
            automationEnabled: state.automationEnabled,
            activeLeases: statusState.activeTaskLeases,
            decision: state.lastDecision,
            powerOwned: context.powerController.isOwned(),
            livePower: livePower,
            pendingEventCount: pendingEventCount,
            runtimeDetectionAvailable: detection.sourceAvailable,
            configuration: configuration,
            lastError: state.lastError,
            lastReconciledAt: state.lastReconciledAt
        )

        if asJSON {
            let data = try LockedStateStore.encoder.encode(status)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("Codex Lid Keeper")
        print("  Automation: \(status.automationEnabled ? "enabled" : "paused")")
        print("  Active tasks: \(status.activeLeases.count)")
        print("  Pending events: \(status.pendingEventCount)")
        print(
            "  Runtime detection: "
                + (status.runtimeDetectionAvailable ? "available" : "unavailable")
        )
        print("  Decision: \(status.decision.rawValue)")
        print("  Sleep override owned: \(status.powerOwned ? "yes" : "no")")
        print("  AC power: \(display(status.livePower.isOnACPower))")
        print("  Battery: \(status.livePower.batteryPercent.map { "\($0)%" } ?? "unknown")")
        if let error = status.lastError {
            print("  Last error: \(error)")
        }
        for lease in status.activeLeases {
            print("  - \(lease.projectName) [\(lease.sessionID):\(lease.turnID)]")
        }
    }

    private static func printConfiguration(context: RuntimeContext) throws {
        let configuration = try context.configurationStore.load()
        let data = try LockedStateStore.encoder.encode(configuration)
        print(String(decoding: data, as: UTF8.self))
    }

    private static func display(_ value: Bool?) -> String {
        guard let value else { return "unknown" }
        return value ? "yes" : "no"
    }

    private static func runPower(arguments: [String]) -> Int32 {
        guard let command = arguments.first else {
            fputs(
                "Usage: codex-lid-keeper power {enable-ac|enable-battery|restore|watchdog|status}\n",
                stderr
            )
            return 2
        }

        let environment = ProcessInfo.processInfo.environment
        let ownershipPath = environment["CODEX_LID_KEEPER_OWNERSHIP_FILE"]
            ?? KeeperConstants.rootOwnershipFile
        let manager = PrivilegedPowerManager(
            ownershipFile: URL(fileURLWithPath: ownershipPath)
        )

        if command == "status" {
            let owned = FileManager.default.fileExists(atPath: ownershipPath)
            print(owned ? "owned" : "not-owned")
            return 0
        }

        guard geteuid() == 0 else {
            fputs("codex-lid-keeper: power \(command) must run as root.\n", stderr)
            return 1
        }

        do {
            switch command {
            case "enable", "enable-ac":
                try manager.enable(mode: .acOnly)
            case "enable-battery":
                try manager.enable(mode: .allowBattery)
            case "restore":
                try manager.restore()
            case "watchdog":
                guard FileManager.default.fileExists(atPath: ownershipPath) else {
                    return 0
                }
                let snapshot = SystemPowerSourceProvider().currentSnapshot()
                let restored = try manager.restoreIfPowerUnsafe(
                    snapshot: snapshot
                )
                if !restored {
                    _ = try manager.restoreIfHeartbeatExpired()
                }
            default:
                fputs("Unknown power command: \(command)\n", stderr)
                return 2
            }
            return 0
        } catch {
            fputs("codex-lid-keeper power: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private static func printUsage() {
        print(
            """
            Usage: codex-lid-keeper <command>

              hook                 Queue one Codex Hook JSON object from stdin
              daemon [--once]      Reconcile leases and power safety conditions
              status [--json]      Show current state without changing it
              pause                Stop automation and restore owned power state
              resume               Enable automation
              clear                Clear active leases and restore owned power state
              emergency-restore    Pause, clear leases, and restore immediately
              config show          Print the current safety configuration
              power ...            Internal privileged helper commands
            """
        )
    }
}

private final class RuntimeContext {
    let paths: KeeperPaths
    let stateStore: LockedStateStore
    let configurationStore: ConfigurationStore
    let logger: KeeperLogger
    let eventPipeline: HookEventPipeline
    let powerSourceProvider: PowerSourceProviding
    let powerController: PowerControlling
    let runtimeTaskDetector: RuntimeTaskDetecting

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let home = environment["CODEX_LID_KEEPER_HOME"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        paths = KeeperPaths(homeDirectory: home)
        stateStore = LockedStateStore(
            stateFile: paths.stateFile,
            lockFile: paths.stateLockFile
        )
        configurationStore = ConfigurationStore(file: paths.configFile)
        logger = KeeperLogger(file: paths.logFile)
        eventPipeline = HookEventPipeline(
            directory: paths.eventSpoolDirectory,
            stateStore: stateStore
        )
        runtimeTaskDetector = CodexRuntimeTaskDetector(
            homeDirectory: home
        )
        let dryRun = environment["CODEX_LID_KEEPER_DRY_RUN"] == "1"
        if dryRun, environment["CODEX_LID_KEEPER_TEST_POWER"] == "ac" {
            powerSourceProvider = StaticPowerSourceProvider(
                snapshot: PowerSnapshot(isOnACPower: true, batteryPercent: 80)
            )
        } else {
            powerSourceProvider = SystemPowerSourceProvider()
        }

        if dryRun {
            powerController = DryRunPowerController(
                marker: paths.applicationSupportDirectory
                    .appendingPathComponent("dry-run-power-owned")
            )
        } else {
            let helper = environment["CODEX_LID_KEEPER_HELPER"]
                ?? KeeperConstants.installedExecutable
            let ownership = environment["CODEX_LID_KEEPER_OWNERSHIP_FILE"]
                .map { URL(fileURLWithPath: $0) }
                ?? URL(fileURLWithPath: KeeperConstants.rootOwnershipFile)
            powerController = RootHelperPowerController(
                executablePath: helper,
                ownershipFile: ownership
            )
        }
    }
}

private struct StatusReport: Codable {
    let automationEnabled: Bool
    let activeLeases: [TaskLease]
    let decision: KeeperDecision
    let powerOwned: Bool
    let livePower: PowerSnapshot
    let pendingEventCount: Int
    let runtimeDetectionAvailable: Bool
    let configuration: RuntimeConfiguration
    let lastError: String?
    let lastReconciledAt: Date?
}

private final class ProcessLock {
    private let file: URL
    private var descriptor: Int32 = -1

    init(file: URL) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        self.file = file
    }

    func tryAcquire() -> Bool {
        descriptor = Darwin.open(
            file.path,
            O_CREAT | O_RDWR | O_EXLOCK | O_NONBLOCK,
            S_IRUSR | S_IWUSR
        )
        return descriptor >= 0
    }

    deinit {
        if descriptor >= 0 {
            Darwin.close(descriptor)
        }
    }
}

private enum CLIError: Error, LocalizedError {
    case daemonAlreadyRunning
    case cannotOpenDaemonLock

    var errorDescription: String? {
        switch self {
        case .daemonAlreadyRunning:
            return "A Codex Lid Keeper daemon is already running."
        case .cannotOpenDaemonLock:
            return "Could not open the daemon lock file."
        }
    }
}
