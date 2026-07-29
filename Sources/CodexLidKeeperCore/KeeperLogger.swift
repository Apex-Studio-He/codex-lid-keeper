import Foundation

public final class KeeperLogger {
    private let file: URL
    private let fileManager: FileManager
    private let maximumBytes: Int
    private let lock = NSLock()

    public init(
        file: URL,
        fileManager: FileManager = .default,
        maximumBytes: Int = KeeperConstants.logFileLimit
    ) {
        self.file = file
        self.fileManager = fileManager
        self.maximumBytes = max(1, maximumBytes)
    }

    public func append(_ message: String, now: Date = Date()) {
        guard lock.try() else { return }
        defer { lock.unlock() }

        do {
            try fileManager.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
            )
            let formatter = ISO8601DateFormatter()
            let line = "\(formatter.string(from: now)) \(message.prefix(4_096))\n"
            let data = Data(line.utf8)
            try rotateIfNeeded(adding: data.count)
            if fileManager.fileExists(atPath: file.path) {
                let handle = try FileHandle(forWritingTo: file)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: file, options: .atomic)
                try fileManager.setAttributes(
                    [.posixPermissions: NSNumber(value: Int16(0o600))],
                    ofItemAtPath: file.path
                )
            }
        } catch {
            // Logging is best effort and must never block a Codex Hook.
        }
    }

    private func rotateIfNeeded(adding byteCount: Int) throws {
        guard fileManager.fileExists(atPath: file.path) else { return }
        let attributes = try fileManager.attributesOfItem(atPath: file.path)
        let currentBytes = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard currentBytes + byteCount > maximumBytes else { return }

        let rotated = file.appendingPathExtension("1")
        if fileManager.fileExists(atPath: rotated.path) {
            try fileManager.removeItem(at: rotated)
        }
        try fileManager.moveItem(at: file, to: rotated)
    }
}
