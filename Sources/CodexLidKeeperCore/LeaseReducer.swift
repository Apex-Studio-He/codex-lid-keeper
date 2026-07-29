import Foundation

public enum LeaseTransition: Equatable, Sendable {
    case acquired(String)
    case renewed(String)
    case releaseScheduled(String)
    case sessionReleased(Int)
}

public enum LeaseReducer {
    @discardableResult
    public static func apply(
        event: LifecycleEvent,
        to state: inout KeeperState,
        configuration: RuntimeConfiguration
    ) throws -> LeaseTransition {
        let event = try event.validated()
        switch event.action {
        case .acquire, .renew:
            guard let turnID = event.turnID else {
                throw LifecycleEventError.missingTurnID
            }
            let id = HookProcessor.leaseID(sessionID: event.sessionID, turnID: turnID)
            let expiresAt = event.occurredAt.addingTimeInterval(
                configuration.leaseDuration
            )

            if var lease = state.leases[id] {
                guard event.occurredAt >= lease.lastActivityAt else {
                    return .renewed(id)
                }
                lease.projectName = event.projectName
                lease.lastActivityAt = event.occurredAt
                lease.expiresAt = expiresAt
                lease.releaseAfter = nil
                state.leases[id] = lease
                return .renewed(id)
            }

            state.leases[id] = TaskLease(
                id: id,
                sessionID: event.sessionID,
                turnID: turnID,
                projectName: event.projectName,
                startedAt: event.occurredAt,
                lastActivityAt: event.occurredAt,
                expiresAt: expiresAt
            )
            return .acquired(id)

        case .releaseTurn:
            guard let turnID = event.turnID else {
                throw LifecycleEventError.missingTurnID
            }
            let id = HookProcessor.leaseID(sessionID: event.sessionID, turnID: turnID)
            if var lease = state.leases[id] {
                guard event.occurredAt >= lease.lastActivityAt else {
                    return .releaseScheduled(id)
                }
                lease.releaseAfter = event.occurredAt.addingTimeInterval(
                    configuration.releaseDelay
                )
                state.leases[id] = lease
                return .releaseScheduled(id)
            }
            return .releaseScheduled(id)

        case .releaseSession:
            let matchingIDs = state.leases.values
                .filter {
                    $0.sessionID == event.sessionID
                        && $0.lastActivityAt <= event.occurredAt
                }
                .map(\.id)
            for id in matchingIDs {
                state.leases.removeValue(forKey: id)
            }
            return .sessionReleased(matchingIDs.count)
        }
    }

    @discardableResult
    public static func pruneExpiredLeases(
        from state: inout KeeperState,
        now: Date
    ) -> Int {
        let expiredIDs = state.leases.values.compactMap { lease -> String? in
            if lease.expiresAt <= now {
                return lease.id
            }
            if let releaseAfter = lease.releaseAfter, releaseAfter <= now {
                return lease.id
            }
            return nil
        }

        for id in expiredIDs {
            state.leases.removeValue(forKey: id)
        }
        return expiredIDs.count
    }
}
