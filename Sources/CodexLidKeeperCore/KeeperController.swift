import Foundation

public struct KeeperStatusSnapshot: Codable, Equatable, Sendable {
    public let automationEnabled: Bool
    public let activeLeases: [TaskLease]
    public let decision: KeeperDecision
    public let powerOwned: Bool
    public let livePower: PowerSnapshot
    public let pendingEventCount: Int
    public let hasObservedHookEvent: Bool
    public let runtimeDetectionAvailable: Bool
    public let configuration: RuntimeConfiguration
    public let lastError: String?
    public let lastReconciledAt: Date?

    public init(
        automationEnabled: Bool,
        activeLeases: [TaskLease],
        decision: KeeperDecision,
        powerOwned: Bool,
        livePower: PowerSnapshot,
        pendingEventCount: Int,
        hasObservedHookEvent: Bool,
        runtimeDetectionAvailable: Bool,
        configuration: RuntimeConfiguration,
        lastError: String?,
        lastReconciledAt: Date?
    ) {
        self.automationEnabled = automationEnabled
        self.activeLeases = activeLeases
        self.decision = decision
        self.powerOwned = powerOwned
        self.livePower = livePower
        self.pendingEventCount = pendingEventCount
        self.hasObservedHookEvent = hasObservedHookEvent
        self.runtimeDetectionAvailable = runtimeDetectionAvailable
        self.configuration = configuration
        self.lastError = lastError
        self.lastReconciledAt = lastReconciledAt
    }

    public var codexIsWorking: Bool {
        !activeLeases.isEmpty || pendingEventCount > 0
    }
}

public final class KeeperController {
    public let paths: KeeperPaths

    private let stateStore: LockedStateStore
    private let configurationStore: ConfigurationStore
    private let eventPipeline: HookEventPipeline
    private let powerSourceProvider: PowerSourceProviding
    private let powerController: PowerControlling
    private let runtimeTaskDetector: RuntimeTaskDetecting

    public init(
        paths: KeeperPaths = KeeperPaths(),
        powerSourceProvider: PowerSourceProviding =
            SystemPowerSourceProvider(),
        powerController: PowerControlling = RootHelperPowerController(),
        runtimeTaskDetector: RuntimeTaskDetecting? = nil
    ) {
        self.paths = paths
        stateStore = LockedStateStore(
            stateFile: paths.stateFile,
            lockFile: paths.stateLockFile
        )
        configurationStore = ConfigurationStore(file: paths.configFile)
        eventPipeline = HookEventPipeline(
            directory: paths.eventSpoolDirectory,
            stateStore: stateStore
        )
        self.powerSourceProvider = powerSourceProvider
        self.powerController = powerController
        self.runtimeTaskDetector = runtimeTaskDetector
            ?? CodexRuntimeTaskDetector(homeDirectory: paths.homeDirectory)
    }

    public func prepare() throws {
        try configurationStore.createDefaultIfMissing()
    }

    public func status() throws -> KeeperStatusSnapshot {
        try prepare()
        let configuration = try configurationStore.load()
        let state = try stateStore.read()
        let pendingEventCount = try eventPipeline.pendingCount()
        let detection = runtimeTaskDetector.detectActiveTasks(
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
        return KeeperStatusSnapshot(
            automationEnabled: state.automationEnabled,
            activeLeases: statusState.activeTaskLeases,
            decision: state.lastDecision,
            powerOwned: powerController.isOwned(),
            livePower: powerSourceProvider.currentSnapshot(),
            pendingEventCount: pendingEventCount,
            hasObservedHookEvent:
                pendingEventCount > 0 || !state.recentEventIDs.isEmpty,
            runtimeDetectionAvailable: detection.sourceAvailable,
            configuration: configuration,
            lastError: state.lastError,
            lastReconciledAt: state.lastReconciledAt
        )
    }

    public func saveConfiguration(
        _ configuration: RuntimeConfiguration
    ) throws {
        try configurationStore.save(configuration)
    }

    public func setAutomationEnabled(_ enabled: Bool) throws {
        let configuration = try configurationStore.load()
        let powerSnapshot = powerSourceProvider.currentSnapshot()
        try stateStore.update { state in
            state.automationEnabled = enabled
            _ = KeeperReconciler.reconcile(
                state: &state,
                configuration: configuration,
                powerSnapshot: powerSnapshot,
                powerController: powerController
            )
        }
    }

    public func clearLeases(pause: Bool = false) throws {
        _ = try eventPipeline.discardPending()
        let configuration = try configurationStore.load()
        let powerSnapshot = powerSourceProvider.currentSnapshot()
        try stateStore.update { state in
            if pause {
                state.automationEnabled = false
            }
            state.leases.removeAll()
            state.runtimeLeases.removeAll()
            _ = KeeperReconciler.reconcile(
                state: &state,
                configuration: configuration,
                powerSnapshot: powerSnapshot,
                powerController: powerController
            )
        }
    }

    public func emergencyRestore() throws {
        _ = try? eventPipeline.discardPending()
        try stateStore.update { state in
            state.automationEnabled = false
            state.leases.removeAll()
            state.runtimeLeases.removeAll()
            state.powerRequested = false
            state.lastDecision = .paused
            state.lastReconciledAt = Date()
        }
        if powerController.isOwned() {
            try powerController.restore()
        }
    }
}
