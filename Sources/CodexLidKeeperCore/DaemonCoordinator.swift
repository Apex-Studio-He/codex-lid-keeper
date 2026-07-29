import Foundation

public struct DaemonCycleReport: Equatable, Sendable {
    public let eventConsumption: EventConsumptionReport
    public let reconciliation: ReconcileResult?

    public init(
        eventConsumption: EventConsumptionReport,
        reconciliation: ReconcileResult?
    ) {
        self.eventConsumption = eventConsumption
        self.reconciliation = reconciliation
    }
}

public final class DaemonCoordinator {
    private let eventPipeline: HookEventPipeline
    private let stateStore: LockedStateStore
    private let powerSourceProvider: PowerSourceProviding
    private let powerController: PowerControlling
    private let runtimeTaskDetector: RuntimeTaskDetecting?

    private var lastReconciledAt: Date?
    private var lastHeartbeatAt: Date?
    private var lastResult: ReconcileResult?

    public init(
        eventDirectory: URL,
        stateStore: LockedStateStore,
        powerSourceProvider: PowerSourceProviding,
        powerController: PowerControlling,
        runtimeTaskDetector: RuntimeTaskDetecting? = nil,
        fileManager: FileManager = .default
    ) {
        eventPipeline = HookEventPipeline(
            directory: eventDirectory,
            stateStore: stateStore,
            fileManager: fileManager
        )
        self.stateStore = stateStore
        self.powerSourceProvider = powerSourceProvider
        self.powerController = powerController
        self.runtimeTaskDetector = runtimeTaskDetector
    }

    public func runCycle(
        configuration: RuntimeConfiguration,
        now: Date = Date()
    ) throws -> DaemonCycleReport {
        let configuration = try configuration.validated()
        let consumption = try eventPipeline.consume(
            configuration: configuration,
            now: now
        )
        let runtimeChanged = try synchronizeRuntimeTasks(
            configuration: configuration,
            now: now
        )

        let needsMaintenance = lastResult.map {
            $0.activeLeaseCount > 0 || $0.powerOwned
        } ?? true
        let maintenanceDue = isDue(
            since: lastReconciledAt,
            interval: configuration.powerHeartbeatInterval,
            now: now
        )
        guard consumption.appliedCount > 0
            || runtimeChanged
            || (needsMaintenance && maintenanceDue) else {
            return DaemonCycleReport(
                eventConsumption: consumption,
                reconciliation: nil
            )
        }

        let heartbeatDue = isDue(
            since: lastHeartbeatAt,
            interval: configuration.powerHeartbeatInterval,
            now: now
        )
        let snapshot = powerSourceProvider.currentSnapshot()
        let result = try stateStore.update { state in
            KeeperReconciler.reconcile(
                state: &state,
                configuration: configuration,
                powerSnapshot: snapshot,
                powerController: powerController,
                refreshHeartbeat: heartbeatDue,
                now: now
            )
        }

        lastReconciledAt = now
        lastResult = result
        if result.decision == .active {
            if heartbeatDue, result.powerOwned {
                lastHeartbeatAt = now
            }
        } else {
            lastHeartbeatAt = nil
        }

        return DaemonCycleReport(
            eventConsumption: consumption,
            reconciliation: result
        )
    }

    private func synchronizeRuntimeTasks(
        configuration: RuntimeConfiguration,
        now: Date
    ) throws -> Bool {
        guard let runtimeTaskDetector else { return false }
        let detection = runtimeTaskDetector.detectActiveTasks(
            now: now,
            maximumAge: configuration.leaseDuration
        )
        guard detection.sourceAvailable else { return false }
        let detected = Dictionary(
            uniqueKeysWithValues: detection.activeTasks.map {
                ($0.id, $0)
            }
        )
        let existing = try stateStore.read().runtimeLeases
        guard existing != detected else { return false }
        return try stateStore.update { state in
            guard state.runtimeLeases != detected else { return false }
            state.runtimeLeases = detected
            return true
        }
    }

    private func isDue(
        since previous: Date?,
        interval: TimeInterval,
        now: Date
    ) -> Bool {
        guard let previous else { return true }
        let elapsed = now.timeIntervalSince(previous)
        return elapsed < 0 || elapsed >= interval
    }
}
