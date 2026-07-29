import Foundation

public enum PrivilegedPowerError: Error, LocalizedError, Equatable {
    case malformedOwnershipRecord
    case missingACPowerProfile
    case missingBatteryPowerProfile

    public var errorDescription: String? {
        switch self {
        case .malformedOwnershipRecord:
            return "The root power ownership record is malformed; refusing to guess the prior setting."
        case .missingACPowerProfile:
            return "Could not find the AC Power profile in pmset output; refusing to change it."
        case .missingBatteryPowerProfile:
            return "Could not find the Battery Power profile in pmset output; refusing to change it."
        }
    }
}

public final class PrivilegedPowerManager {
    public let ownershipFile: URL
    private let runner: CommandRunning
    private let fileManager: FileManager

    public init(
        ownershipFile: URL = URL(fileURLWithPath: KeeperConstants.rootOwnershipFile),
        runner: CommandRunning = FoundationCommandRunner(),
        fileManager: FileManager = .default
    ) {
        self.ownershipFile = ownershipFile
        self.runner = runner
        self.fileManager = fileManager
    }

    public func enable(
        mode: GuardPowerMode = .acOnly,
        now: Date = Date()
    ) throws {
        if fileManager.fileExists(atPath: ownershipFile.path) {
            let existing = try readOwnershipRecord()
            if existing.mode == mode {
                try touchOwnershipFile(now: now)
                return
            }
            try restore()
        }

        let previous = try queryDisableSleepProfiles()
        guard let previousAC = previous.ac else {
            throw PrivilegedPowerError.missingACPowerProfile
        }
        if mode == .allowBattery, previous.battery == nil {
            throw PrivilegedPowerError.missingBatteryPowerProfile
        }
        let record = PowerOwnershipRecord(
            mode: mode,
            previousACDisableSleepEnabled: previousAC,
            previousBatteryDisableSleepEnabled:
                mode == .allowBattery ? previous.battery : nil,
            createdAt: now
        )
        try writeOwnershipRecord(record)

        do {
            try setDisableSleep(profile: "-c", enabled: true)
            if mode == .allowBattery {
                try setDisableSleep(profile: "-b", enabled: true)
            }
            try touchOwnershipFile(now: now)
        } catch {
            try? restore()
            throw error
        }
    }

    public func restore() throws {
        guard fileManager.fileExists(atPath: ownershipFile.path) else {
            return
        }

        let record = try readOwnershipRecord()

        if !record.previousACDisableSleepEnabled {
            try setDisableSleep(profile: "-c", enabled: false)
        }
        if record.mode == .allowBattery {
            guard let previousBattery =
                record.previousBatteryDisableSleepEnabled else {
                throw PrivilegedPowerError.malformedOwnershipRecord
            }
            if !previousBattery {
                try setDisableSleep(profile: "-b", enabled: false)
            }
        }
        try fileManager.removeItem(at: ownershipFile)
    }

    @discardableResult
    public func restoreIfHeartbeatExpired(
        now: Date = Date(),
        maximumAge: TimeInterval = KeeperConstants.rootWatchdogMaximumAge
    ) throws -> Bool {
        guard fileManager.fileExists(atPath: ownershipFile.path) else {
            return false
        }
        let attributes = try fileManager.attributesOfItem(atPath: ownershipFile.path)
        guard let modificationDate = attributes[.modificationDate] as? Date else {
            try restore()
            return true
        }
        guard now.timeIntervalSince(modificationDate) >= maximumAge else {
            return false
        }
        try restore()
        return true
    }

    @discardableResult
    public func restoreIfPowerUnsafe(
        snapshot: PowerSnapshot,
        minimumBatteryPercent: Int =
            RuntimeConfiguration.default.minimumBatteryPercent
    ) throws -> Bool {
        guard fileManager.fileExists(atPath: ownershipFile.path) else {
            return false
        }
        let record = try readOwnershipRecord()
        guard let isOnACPower = snapshot.isOnACPower else {
            try restore()
            return true
        }
        if !isOnACPower, record.mode == .acOnly {
            try restore()
            return true
        }
        if !isOnACPower, snapshot.batteryPercent == nil {
            try restore()
            return true
        }
        if let batteryPercent = snapshot.batteryPercent,
           batteryPercent < minimumBatteryPercent {
            try restore()
            return true
        }
        return false
    }

    public func queryDisableSleepEnabled() throws -> Bool {
        let profiles = try queryDisableSleepProfiles()
        guard let ac = profiles.ac else {
            throw PrivilegedPowerError.missingACPowerProfile
        }
        return ac
    }

    private func queryDisableSleepProfiles() throws -> PowerProfileSnapshot {
        let result = try runner.run(
            executable: "/usr/bin/pmset",
            arguments: ["-g", "custom"],
            timeout: 3
        )
        var currentProfile: PowerProfile?
        var ac: Bool?
        var battery: Bool?

        for rawLine in result.outputString.split(
            omittingEmptySubsequences: false,
            whereSeparator: \.isNewline
        ) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isProfileHeader = line.first.map { !$0.isWhitespace } == true
                && trimmed.hasSuffix(":")
            if isProfileHeader {
                if trimmed.caseInsensitiveCompare("AC Power:")
                    == .orderedSame {
                    currentProfile = .ac
                    ac = false
                } else if trimmed.caseInsensitiveCompare("Battery Power:")
                    == .orderedSame {
                    currentProfile = .battery
                    battery = false
                } else {
                    currentProfile = nil
                }
                continue
            }
            guard let currentProfile else { continue }
            let fields = trimmed.split(whereSeparator: \.isWhitespace)
            if fields.count >= 2, fields[0].lowercased() == "disablesleep" {
                switch currentProfile {
                case .ac:
                    ac = fields[1] == "1"
                case .battery:
                    battery = fields[1] == "1"
                }
            }
        }
        return PowerProfileSnapshot(ac: ac, battery: battery)
    }

    private func writeOwnershipRecord(_ record: PowerOwnershipRecord) throws {
        try fileManager.createDirectory(
            at: ownershipFile.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o755))]
        )
        let data = try LockedStateStore.encoder.encode(record)
        try data.write(to: ownershipFile, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: ownershipFile.path
        )
    }

    private func touchOwnershipFile(now: Date) throws {
        try fileManager.setAttributes(
            [.modificationDate: now],
            ofItemAtPath: ownershipFile.path
        )
    }

    private func readOwnershipRecord() throws -> PowerOwnershipRecord {
        do {
            let data = try Data(contentsOf: ownershipFile)
            let record = try LockedStateStore.decoder.decode(
                PowerOwnershipRecord.self,
                from: data
            )
            guard record.schemaVersion > 0,
                  record.schemaVersion <= KeeperConstants.schemaVersion,
                  record.mode == .acOnly
                    || record.previousBatteryDisableSleepEnabled != nil else {
                throw PrivilegedPowerError.malformedOwnershipRecord
            }
            return record
        } catch {
            throw PrivilegedPowerError.malformedOwnershipRecord
        }
    }

    private func setDisableSleep(
        profile: String,
        enabled: Bool
    ) throws {
        _ = try runner.run(
            executable: "/usr/bin/pmset",
            arguments: [
                profile,
                "disablesleep",
                enabled ? "1" : "0"
            ],
            timeout: 3
        )
    }
}

private enum PowerProfile {
    case ac
    case battery
}

private struct PowerProfileSnapshot {
    let ac: Bool?
    let battery: Bool?
}
