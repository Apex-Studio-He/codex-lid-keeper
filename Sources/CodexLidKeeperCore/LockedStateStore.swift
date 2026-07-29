import Darwin
import Foundation

public enum StateStoreError: Error, LocalizedError {
    case cannotOpenLock
    case cannotLock
    case unsupportedSchema(Int)

    public var errorDescription: String? {
        switch self {
        case .cannotOpenLock:
            return "Could not open the state lock file."
        case .cannotLock:
            return "Could not acquire the state lock."
        case .unsupportedSchema(let version):
            return "State schema \(version) is not supported."
        }
    }
}

public final class LockedStateStore {
    public let stateFile: URL
    public let lockFile: URL
    private let fileManager: FileManager

    public init(
        stateFile: URL,
        lockFile: URL,
        fileManager: FileManager = .default
    ) {
        self.stateFile = stateFile
        self.lockFile = lockFile
        self.fileManager = fileManager
    }

    public func read() throws -> KeeperState {
        try withLock {
            try loadUnlocked()
        }
    }

    @discardableResult
    public func update<T>(_ body: (inout KeeperState) throws -> T) throws -> T {
        try withLock {
            var state = try loadUnlocked()
            let result = try body(&state)
            try saveUnlocked(state)
            return result
        }
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        try ensureDirectory()
        let descriptor = Darwin.open(
            lockFile.path,
            O_CREAT | O_RDWR | O_EXLOCK,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw StateStoreError.cannotOpenLock
        }
        defer {
            Darwin.close(descriptor)
        }
        return try body()
    }

    private func loadUnlocked() throws -> KeeperState {
        guard fileManager.fileExists(atPath: stateFile.path) else {
            return KeeperState()
        }
        let data = try Data(contentsOf: stateFile)
        var state = try Self.decoder.decode(KeeperState.self, from: data)
        guard state.schemaVersion > 0,
              state.schemaVersion
                <= KeeperConstants.maximumReadableSchemaVersion else {
            throw StateStoreError.unsupportedSchema(state.schemaVersion)
        }
        state.schemaVersion = KeeperConstants.schemaVersion
        return state
    }

    private func saveUnlocked(_ state: KeeperState) throws {
        try ensureDirectory()
        let data = try Self.encoder.encode(state)
        try data.write(to: stateFile, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: stateFile.path
        )
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(
            at: stateFile.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )
    }

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
