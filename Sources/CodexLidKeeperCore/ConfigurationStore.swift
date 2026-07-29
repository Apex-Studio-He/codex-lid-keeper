import Foundation

public final class ConfigurationStore {
    public let file: URL
    private let fileManager: FileManager

    public init(file: URL, fileManager: FileManager = .default) {
        self.file = file
        self.fileManager = fileManager
    }

    public func load() throws -> RuntimeConfiguration {
        guard fileManager.fileExists(atPath: file.path) else {
            return .default
        }
        let data = try Data(contentsOf: file)
        return try LockedStateStore.decoder
            .decode(RuntimeConfiguration.self, from: data)
            .validated()
    }

    public func createDefaultIfMissing() throws {
        guard !fileManager.fileExists(atPath: file.path) else { return }
        try fileManager.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )
        let data = try LockedStateStore.encoder.encode(RuntimeConfiguration.default)
        try data.write(to: file, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: file.path
        )
    }
}
