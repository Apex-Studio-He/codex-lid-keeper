import Foundation

public struct CodexHookInput: Codable, Equatable, Sendable {
    public let sessionID: String
    public let turnID: String?
    public let cwd: String
    public let hookEventName: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case turnID = "turn_id"
        case cwd
        case hookEventName = "hook_event_name"
    }

    public init(sessionID: String, turnID: String?, cwd: String, hookEventName: String) {
        self.sessionID = sessionID
        self.turnID = turnID
        self.cwd = cwd
        self.hookEventName = hookEventName
    }
}

public enum HookAction: String, Codable, Equatable, Sendable {
    case acquire
    case renew
    case releaseTurn
    case releaseSession
}

public struct LifecycleEvent: Codable, Equatable, Identifiable, Sendable {
    public let schemaVersion: Int
    public let id: UUID
    public let action: HookAction
    public let sessionID: String
    public let turnID: String?
    public let projectName: String
    public let occurredAt: Date

    public init(
        schemaVersion: Int = KeeperConstants.eventSchemaVersion,
        id: UUID = UUID(),
        action: HookAction,
        sessionID: String,
        turnID: String?,
        projectName: String,
        occurredAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.action = action
        self.sessionID = sessionID
        self.turnID = turnID
        self.projectName = projectName
        self.occurredAt = occurredAt
    }

    public func validated() throws -> LifecycleEvent {
        guard schemaVersion == KeeperConstants.eventSchemaVersion else {
            throw LifecycleEventError.unsupportedSchema(schemaVersion)
        }
        guard !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LifecycleEventError.invalidFields
        }
        if action != .releaseSession {
            guard let turnID,
                  !turnID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LifecycleEventError.missingTurnID
            }
        }
        return self
    }
}

public enum LifecycleEventError: Error, LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case invalidFields
    case missingTurnID

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "Lifecycle event schema \(version) is not supported."
        case .invalidFields:
            return "Lifecycle event contains empty required fields."
        case .missingTurnID:
            return "Turn-scoped lifecycle event is missing turn_id."
        }
    }
}

public struct TaskLease: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let sessionID: String
    public let turnID: String
    public var projectName: String
    public let startedAt: Date
    public var lastActivityAt: Date
    public var expiresAt: Date
    public var releaseAfter: Date?

    public init(
        id: String,
        sessionID: String,
        turnID: String,
        projectName: String,
        startedAt: Date,
        lastActivityAt: Date,
        expiresAt: Date,
        releaseAfter: Date? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.turnID = turnID
        self.projectName = projectName
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.expiresAt = expiresAt
        self.releaseAfter = releaseAfter
    }
}

public struct PowerSnapshot: Codable, Equatable, Sendable {
    public var isOnACPower: Bool?
    public var batteryPercent: Int?

    public init(isOnACPower: Bool?, batteryPercent: Int?) {
        self.isOnACPower = isOnACPower
        self.batteryPercent = batteryPercent
    }

    public static let unknown = PowerSnapshot(isOnACPower: nil, batteryPercent: nil)
}

public enum KeeperDecision: String, Codable, Sendable {
    case active
    case paused
    case noTasks
    case onBattery
    case lowBattery
    case powerUnknown
}

public struct KeeperState: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var automationEnabled: Bool
    public var leases: [String: TaskLease]
    public var powerRequested: Bool
    public var lastDecision: KeeperDecision
    public var lastPowerSnapshot: PowerSnapshot
    public var lastError: String?
    public var lastReconciledAt: Date?
    public var recentEventIDs: [String]

    public init(
        schemaVersion: Int = KeeperConstants.schemaVersion,
        automationEnabled: Bool = true,
        leases: [String: TaskLease] = [:],
        powerRequested: Bool = false,
        lastDecision: KeeperDecision = .noTasks,
        lastPowerSnapshot: PowerSnapshot = .unknown,
        lastError: String? = nil,
        lastReconciledAt: Date? = nil,
        recentEventIDs: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.automationEnabled = automationEnabled
        self.leases = leases
        self.powerRequested = powerRequested
        self.lastDecision = lastDecision
        self.lastPowerSnapshot = lastPowerSnapshot
        self.lastError = lastError
        self.lastReconciledAt = lastReconciledAt
        self.recentEventIDs = recentEventIDs
    }

    public func hasProcessed(eventID: UUID) -> Bool {
        recentEventIDs.contains(eventID.uuidString)
    }

    public mutating func recordProcessed(eventID: UUID) {
        let value = eventID.uuidString
        guard !recentEventIDs.contains(value) else { return }
        recentEventIDs.append(value)
        if recentEventIDs.count > KeeperConstants.recentEventIDLimit {
            recentEventIDs.removeFirst(
                recentEventIDs.count - KeeperConstants.recentEventIDLimit
            )
        }
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case automationEnabled
        case leases
        case powerRequested
        case lastDecision
        case lastPowerSnapshot
        case lastError
        case lastReconciledAt
        case recentEventIDs
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(
            Int.self,
            forKey: .schemaVersion
        ) ?? 1
        automationEnabled = try values.decodeIfPresent(
            Bool.self,
            forKey: .automationEnabled
        ) ?? true
        leases = try values.decodeIfPresent(
            [String: TaskLease].self,
            forKey: .leases
        ) ?? [:]
        powerRequested = try values.decodeIfPresent(
            Bool.self,
            forKey: .powerRequested
        ) ?? false
        lastDecision = try values.decodeIfPresent(
            KeeperDecision.self,
            forKey: .lastDecision
        ) ?? .noTasks
        lastPowerSnapshot = try values.decodeIfPresent(
            PowerSnapshot.self,
            forKey: .lastPowerSnapshot
        ) ?? .unknown
        lastError = try values.decodeIfPresent(
            String.self,
            forKey: .lastError
        )
        lastReconciledAt = try values.decodeIfPresent(
            Date.self,
            forKey: .lastReconciledAt
        )
        recentEventIDs = try values.decodeIfPresent(
            [String].self,
            forKey: .recentEventIDs
        ) ?? []
    }
}

public struct ReconcileResult: Equatable, Sendable {
    public let activeLeaseCount: Int
    public let removedLeaseCount: Int
    public let decision: KeeperDecision
    public let powerOwned: Bool

    public init(
        activeLeaseCount: Int,
        removedLeaseCount: Int,
        decision: KeeperDecision,
        powerOwned: Bool
    ) {
        self.activeLeaseCount = activeLeaseCount
        self.removedLeaseCount = removedLeaseCount
        self.decision = decision
        self.powerOwned = powerOwned
    }
}

public struct PowerOwnershipRecord: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let previousDisableSleepEnabled: Bool
    public let createdAt: Date

    public init(
        schemaVersion: Int = KeeperConstants.schemaVersion,
        previousDisableSleepEnabled: Bool,
        createdAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.previousDisableSleepEnabled = previousDisableSleepEnabled
        self.createdAt = createdAt
    }
}
