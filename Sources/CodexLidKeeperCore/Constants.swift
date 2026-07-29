import Foundation

public enum KeeperConstants {
    public static let schemaVersion = 2
    public static let eventSchemaVersion = 1
    public static let hookInputLimit = 1_048_576
    public static let eventFileLimit = 65_536
    public static let eventBatchLimit = 512
    public static let pendingEventLimit = 4_096
    public static let maximumEventFutureSkew: TimeInterval = 5 * 60
    public static let recentEventIDLimit = 8_192
    public static let logFileLimit = 1_048_576
    public static let integrationMarker = "com.zundu.codex-lid-keeper"
    public static let installedExecutable =
        "/Library/PrivilegedHelperTools/com.zundu.codex-lid-keeper"
    public static let rootOwnershipFile = "/var/db/com.zundu.codex-lid-keeper.power.json"
    public static let rootWatchdogMaximumAge: TimeInterval = 120
}

public struct RuntimeConfiguration: Codable, Equatable, Sendable {
    public var minimumBatteryPercent: Int
    public var leaseDuration: TimeInterval
    public var releaseDelay: TimeInterval
    public var eventPollInterval: TimeInterval
    public var powerHeartbeatInterval: TimeInterval

    public init(
        minimumBatteryPercent: Int = 30,
        leaseDuration: TimeInterval = 8 * 60 * 60,
        releaseDelay: TimeInterval = 20,
        eventPollInterval: TimeInterval = 1,
        powerHeartbeatInterval: TimeInterval = 10
    ) {
        self.minimumBatteryPercent = minimumBatteryPercent
        self.leaseDuration = leaseDuration
        self.releaseDelay = releaseDelay
        self.eventPollInterval = eventPollInterval
        self.powerHeartbeatInterval = powerHeartbeatInterval
    }

    public static let `default` = RuntimeConfiguration()

    public func validated() throws -> RuntimeConfiguration {
        guard (30...100).contains(minimumBatteryPercent) else {
            throw RuntimeConfigurationError.invalidMinimumBatteryPercent
        }
        guard (60...(24 * 60 * 60)).contains(leaseDuration) else {
            throw RuntimeConfigurationError.invalidLeaseDuration
        }
        guard (0...300).contains(releaseDelay) else {
            throw RuntimeConfigurationError.invalidReleaseDelay
        }
        guard (0.25...5).contains(eventPollInterval) else {
            throw RuntimeConfigurationError.invalidEventPollInterval
        }
        guard (5...30).contains(powerHeartbeatInterval) else {
            throw RuntimeConfigurationError.invalidPowerHeartbeatInterval
        }
        return self
    }

    enum CodingKeys: String, CodingKey {
        case minimumBatteryPercent
        case leaseDuration
        case releaseDelay
        case eventPollInterval
        case powerHeartbeatInterval
        case legacyPollInterval = "pollInterval"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        minimumBatteryPercent = try values.decodeIfPresent(
            Int.self,
            forKey: .minimumBatteryPercent
        ) ?? 30
        leaseDuration = try values.decodeIfPresent(
            TimeInterval.self,
            forKey: .leaseDuration
        ) ?? 8 * 60 * 60
        releaseDelay = try values.decodeIfPresent(
            TimeInterval.self,
            forKey: .releaseDelay
        ) ?? 20
        eventPollInterval = try values.decodeIfPresent(
            TimeInterval.self,
            forKey: .eventPollInterval
        ) ?? 1
        powerHeartbeatInterval = try values.decodeIfPresent(
            TimeInterval.self,
            forKey: .powerHeartbeatInterval
        ) ?? values.decodeIfPresent(
            TimeInterval.self,
            forKey: .legacyPollInterval
        ) ?? 10
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(minimumBatteryPercent, forKey: .minimumBatteryPercent)
        try values.encode(leaseDuration, forKey: .leaseDuration)
        try values.encode(releaseDelay, forKey: .releaseDelay)
        try values.encode(eventPollInterval, forKey: .eventPollInterval)
        try values.encode(powerHeartbeatInterval, forKey: .powerHeartbeatInterval)
    }
}

public enum RuntimeConfigurationError: Error, LocalizedError, Equatable {
    case invalidMinimumBatteryPercent
    case invalidLeaseDuration
    case invalidReleaseDelay
    case invalidEventPollInterval
    case invalidPowerHeartbeatInterval

    public var errorDescription: String? {
        switch self {
        case .invalidMinimumBatteryPercent:
            return "minimumBatteryPercent must be between 30 and 100."
        case .invalidLeaseDuration:
            return "leaseDuration must be between 60 seconds and 24 hours."
        case .invalidReleaseDelay:
            return "releaseDelay must be between 0 and 300 seconds."
        case .invalidEventPollInterval:
            return "eventPollInterval must be between 0.25 and 5 seconds."
        case .invalidPowerHeartbeatInterval:
            return "powerHeartbeatInterval must be between 5 and 30 seconds."
        }
    }
}
