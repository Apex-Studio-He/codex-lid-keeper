import Darwin
import Foundation

public struct EventConsumptionReport: Equatable, Sendable {
    public let appliedCount: Int
    public let duplicateCount: Int
    public let rejectedCount: Int
    public let deletionFailureCount: Int
    public let remainingCount: Int

    public init(
        appliedCount: Int,
        duplicateCount: Int,
        rejectedCount: Int,
        deletionFailureCount: Int,
        remainingCount: Int
    ) {
        self.appliedCount = appliedCount
        self.duplicateCount = duplicateCount
        self.rejectedCount = rejectedCount
        self.deletionFailureCount = deletionFailureCount
        self.remainingCount = remainingCount
    }
}

public enum HookEventPipelineError: Error, LocalizedError {
    case cannotCreateEventFile
    case cannotWriteEventFile
    case cannotCommitEventFile
    case cannotSyncEventDirectory
    case eventFileTooLarge
    case eventTimestampTooFarInFuture
    case queueFull

    public var errorDescription: String? {
        switch self {
        case .cannotCreateEventFile:
            return "Could not create a private lifecycle event file."
        case .cannotWriteEventFile:
            return "Could not write the complete lifecycle event."
        case .cannotCommitEventFile:
            return "Could not atomically commit the lifecycle event."
        case .cannotSyncEventDirectory:
            return "Could not durably commit the lifecycle event directory."
        case .eventFileTooLarge:
            return "Lifecycle event file exceeded the safety limit."
        case .eventTimestampTooFarInFuture:
            return "Lifecycle event timestamp is too far in the future."
        case .queueFull:
            return "Lifecycle event queue reached its safety limit."
        }
    }
}

public final class HookEventPipeline {
    public let directory: URL
    private let stateStore: LockedStateStore
    private let fileManager: FileManager
    private let maximumPendingEventCount: Int

    public init(
        directory: URL,
        stateStore: LockedStateStore,
        fileManager: FileManager = .default,
        maximumPendingEventCount: Int = KeeperConstants.pendingEventLimit
    ) {
        self.directory = directory
        self.stateStore = stateStore
        self.fileManager = fileManager
        self.maximumPendingEventCount = max(1, maximumPendingEventCount)
    }

    @discardableResult
    public func enqueue(
        _ input: CodexHookInput,
        id: UUID = UUID(),
        occurredAt: Date = Date()
    ) throws -> UUID {
        let event = try HookProcessor.makeEvent(
            from: input,
            id: id,
            occurredAt: occurredAt
        )
        try ensureDirectory()
        let data = try LockedStateStore.encoder.encode(event)
        guard data.count <= KeeperConstants.eventFileLimit else {
            throw HookEventPipelineError.eventFileTooLarge
        }

        let timestamp = Int64(occurredAt.timeIntervalSince1970 * 1_000_000)
        let filename = String(format: "%020lld-%@.json", timestamp, id.uuidString)
        let destination = directory.appendingPathComponent(filename)
        try writeAtomically(data, to: destination, id: id)
        if try pendingCount() > maximumPendingEventCount {
            try? fileManager.removeItem(at: destination)
            throw HookEventPipelineError.queueFull
        }
        return id
    }

    public func consume(
        configuration: RuntimeConfiguration,
        limit: Int = KeeperConstants.eventBatchLimit,
        now: Date = Date()
    ) throws -> EventConsumptionReport {
        let files = try pendingFiles(limit: max(1, limit))
        guard !files.isEmpty else {
            return EventConsumptionReport(
                appliedCount: 0,
                duplicateCount: 0,
                rejectedCount: 0,
                deletionFailureCount: 0,
                remainingCount: 0
            )
        }

        var valid: [(url: URL, event: LifecycleEvent)] = []
        var rejected: [URL] = []
        for file in files {
            do {
                let values = try file.resourceValues(forKeys: [.fileSizeKey])
                guard let size = values.fileSize,
                      size <= KeeperConstants.eventFileLimit else {
                    throw HookEventPipelineError.eventFileTooLarge
                }
                let data = try Data(contentsOf: file)
                let event = try LockedStateStore.decoder
                    .decode(LifecycleEvent.self, from: data)
                    .validated()
                guard event.occurredAt
                    <= now.addingTimeInterval(
                        KeeperConstants.maximumEventFutureSkew
                    ) else {
                    throw HookEventPipelineError.eventTimestampTooFarInFuture
                }
                valid.append((file, event))
            } catch {
                rejected.append(file)
            }
        }

        var appliedCount = 0
        var duplicateCount = 0
        if !valid.isEmpty {
            try stateStore.update { state in
                for item in valid {
                    if state.hasProcessed(eventID: item.event.id) {
                        duplicateCount += 1
                        continue
                    }
                    _ = try LeaseReducer.apply(
                        event: item.event,
                        to: &state,
                        configuration: configuration
                    )
                    state.recordProcessed(eventID: item.event.id)
                    appliedCount += 1
                }
            }
        }

        var deletionFailureCount = 0
        for file in valid.map(\.url) + rejected {
            do {
                try fileManager.removeItem(at: file)
            } catch {
                deletionFailureCount += 1
            }
        }

        return EventConsumptionReport(
            appliedCount: appliedCount,
            duplicateCount: duplicateCount,
            rejectedCount: rejected.count,
            deletionFailureCount: deletionFailureCount,
            remainingCount: try pendingCount()
        )
    }

    public func pendingCount() throws -> Int {
        try ensureDirectory()
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).lazy.filter { $0.pathExtension == "json" }.count
    }

    @discardableResult
    public func discardPending() throws -> Int {
        let files = try pendingFiles(limit: Int.max)
        var removed = 0
        for file in files {
            try fileManager.removeItem(at: file)
            removed += 1
        }
        return removed
    }

    private func pendingFiles(limit: Int) throws -> [URL] {
        try ensureDirectory()
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .prefix(limit)
        .map { $0 }
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: directory.path
        )
    }

    private func writeAtomically(_ data: Data, to destination: URL, id: UUID) throws {
        let temporary = directory.appendingPathComponent(".\(id.uuidString).tmp")
        let descriptor = Darwin.open(
            temporary.path,
            O_WRONLY | O_CREAT | O_EXCL,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw HookEventPipelineError.cannotCreateEventFile
        }

        var writeSucceeded = false
        defer {
            Darwin.close(descriptor)
            if !writeSucceeded {
                try? fileManager.removeItem(at: temporary)
            }
        }

        let complete = data.withUnsafeBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress else {
                return data.isEmpty
            }
            var offset = 0
            while offset < rawBuffer.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                guard written > 0 else { return false }
                offset += written
            }
            return true
        }
        guard complete, Darwin.fsync(descriptor) == 0 else {
            throw HookEventPipelineError.cannotWriteEventFile
        }
        guard Darwin.rename(temporary.path, destination.path) == 0 else {
            throw HookEventPipelineError.cannotCommitEventFile
        }
        writeSucceeded = true
        let directoryDescriptor = Darwin.open(directory.path, O_RDONLY)
        guard directoryDescriptor >= 0 else {
            throw HookEventPipelineError.cannotSyncEventDirectory
        }
        defer { Darwin.close(directoryDescriptor) }
        guard Darwin.fsync(directoryDescriptor) == 0 else {
            throw HookEventPipelineError.cannotSyncEventDirectory
        }
    }
}
