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

    private var lastReconciledAt: Date?
    private var lastHeartbeatAt: Date?
    private var lastResult: ReconcileResult?

    public init(
        eventDirectory: URL,
        stateStore: LockedStateStore,
        powerSourceProvider: PowerSourceProviding,
        powerController: PowerControlling,
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

        let needsMaintenance = lastResult.map {
            $0.activeLeaseCount > 0 || $0.powerOwned
        } ?? true
        let maintenanceDue = isDue(
            since: lastReconciledAt,
            interval: configuration.powerHeartbeatInterval,
            now: now
        )
        guard consumption.appliedCount > 0
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
