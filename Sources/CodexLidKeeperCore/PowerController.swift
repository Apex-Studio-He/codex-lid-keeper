import Foundation

public protocol PowerControlling {
    func isOwned() -> Bool
    func heartbeat() throws
    func restore() throws
}

public final class RootHelperPowerController: PowerControlling {
    private let executablePath: String
    private let ownershipFile: URL
    private let runner: CommandRunning

    public init(
        executablePath: String = KeeperConstants.installedExecutable,
        ownershipFile: URL = URL(fileURLWithPath: KeeperConstants.rootOwnershipFile),
        runner: CommandRunning = FoundationCommandRunner()
    ) {
        self.executablePath = executablePath
        self.ownershipFile = ownershipFile
        self.runner = runner
    }

    public func isOwned() -> Bool {
        FileManager.default.fileExists(atPath: ownershipFile.path)
    }

    public func heartbeat() throws {
        _ = try runner.run(
            executable: "/usr/bin/sudo",
            arguments: ["-n", executablePath, "power", "enable"],
            timeout: 2
        )
    }

    public func restore() throws {
        _ = try runner.run(
            executable: "/usr/bin/sudo",
            arguments: ["-n", executablePath, "power", "restore"],
            timeout: 2
        )
    }
}

public final class DryRunPowerController: PowerControlling {
    private let marker: URL
    private let fileManager: FileManager

    public init(marker: URL, fileManager: FileManager = .default) {
        self.marker = marker
        self.fileManager = fileManager
    }

    public func isOwned() -> Bool {
        fileManager.fileExists(atPath: marker.path)
    }

    public func heartbeat() throws {
        try fileManager.createDirectory(
            at: marker.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if isOwned() {
            try fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: marker.path)
        } else {
            try Data("dry-run\n".utf8).write(to: marker, options: .atomic)
        }
    }

    public func restore() throws {
        if isOwned() {
            try fileManager.removeItem(at: marker)
        }
    }
}
