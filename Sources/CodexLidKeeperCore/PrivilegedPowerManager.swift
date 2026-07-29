import Foundation

public enum PrivilegedPowerError: Error, LocalizedError, Equatable {
    case malformedOwnershipRecord
    case missingACPowerProfile

    public var errorDescription: String? {
        switch self {
        case .malformedOwnershipRecord:
            return "The root power ownership record is malformed; refusing to guess the prior setting."
        case .missingACPowerProfile:
            return "Could not find the AC Power profile in pmset output; refusing to change it."
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

    public func enable(now: Date = Date()) throws {
        if fileManager.fileExists(atPath: ownershipFile.path) {
            _ = try readOwnershipRecord()
            try touchOwnershipFile(now: now)
            return
        }

        let previousEnabled = try queryDisableSleepEnabled()
        let record = PowerOwnershipRecord(
            previousDisableSleepEnabled: previousEnabled,
            createdAt: now
        )
        try writeOwnershipRecord(record)

        do {
            _ = try runner.run(
                executable: "/usr/bin/pmset",
                arguments: ["-c", "disablesleep", "1"],
                timeout: 3
            )
            try touchOwnershipFile(now: now)
        } catch {
            try? fileManager.removeItem(at: ownershipFile)
            throw error
        }
    }

    public func restore() throws {
        guard fileManager.fileExists(atPath: ownershipFile.path) else {
            return
        }

        let record = try readOwnershipRecord()

        if !record.previousDisableSleepEnabled {
            _ = try runner.run(
                executable: "/usr/bin/pmset",
                arguments: ["-c", "disablesleep", "0"],
                timeout: 3
            )
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

    public func queryDisableSleepEnabled() throws -> Bool {
        let result = try runner.run(
            executable: "/usr/bin/pmset",
            arguments: ["-g", "custom"],
            timeout: 3
        )
        var foundACProfile = false
        var inACProfile = false

        for rawLine in result.outputString.split(
            omittingEmptySubsequences: false,
            whereSeparator: \.isNewline
        ) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isProfileHeader = line.first.map { !$0.isWhitespace } == true
                && trimmed.hasSuffix(":")
            if isProfileHeader {
                inACProfile = trimmed.caseInsensitiveCompare("AC Power:") == .orderedSame
                foundACProfile = foundACProfile || inACProfile
                continue
            }
            guard inACProfile else { continue }
            let fields = trimmed.split(whereSeparator: \.isWhitespace)
            if fields.count >= 2, fields[0].lowercased() == "disablesleep" {
                return fields[1] == "1"
            }
        }

        guard foundACProfile else {
            throw PrivilegedPowerError.missingACPowerProfile
        }
        return false
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
            [.posixPermissions: NSNumber(value: Int16(0o644))],
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
            return try LockedStateStore.decoder.decode(
                PowerOwnershipRecord.self,
                from: data
            )
        } catch {
            throw PrivilegedPowerError.malformedOwnershipRecord
        }
    }
}
