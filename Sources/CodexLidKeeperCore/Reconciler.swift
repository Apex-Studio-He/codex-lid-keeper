import Foundation

public enum KeeperReconciler {
    @discardableResult
    public static func reconcile(
        state: inout KeeperState,
        configuration: RuntimeConfiguration,
        powerSnapshot: PowerSnapshot,
        powerController: PowerControlling,
        refreshHeartbeat: Bool = true,
        now: Date = Date()
    ) -> ReconcileResult {
        let removed = LeaseReducer.pruneExpiredLeases(from: &state, now: now)
        let decision = decision(
            state: state,
            configuration: configuration,
            powerSnapshot: powerSnapshot
        )
        let shouldOwnPower = decision == .active

        do {
            if shouldOwnPower {
                if refreshHeartbeat || !powerController.isOwned() {
                    try powerController.heartbeat(
                        mode: configuration.powerMode
                    )
                }
            } else if powerController.isOwned() {
                try powerController.restore()
            }
            state.lastError = nil
        } catch {
            state.lastError = error.localizedDescription
        }

        state.powerRequested = shouldOwnPower && powerController.isOwned()
        state.lastDecision = decision
        state.lastPowerSnapshot = powerSnapshot
        state.lastReconciledAt = now

        return ReconcileResult(
            activeLeaseCount: state.activeTaskLeases.count,
            removedLeaseCount: removed,
            decision: decision,
            powerOwned: powerController.isOwned()
        )
    }

    public static func decision(
        state: KeeperState,
        configuration: RuntimeConfiguration,
        powerSnapshot: PowerSnapshot
    ) -> KeeperDecision {
        guard state.automationEnabled else {
            return .paused
        }
        guard state.hasActiveTasks else {
            return .noTasks
        }
        guard let isOnACPower = powerSnapshot.isOnACPower else {
            return .powerUnknown
        }
        if !isOnACPower, configuration.powerMode == .acOnly {
            return .onBattery
        }
        if !isOnACPower, powerSnapshot.batteryPercent == nil {
            return .powerUnknown
        }
        if let batteryPercent = powerSnapshot.batteryPercent,
           batteryPercent < configuration.minimumBatteryPercent {
            return .lowBattery
        }
        return .active
    }
}
