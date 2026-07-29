import Foundation

public struct KeeperPaths: Sendable {
    public let homeDirectory: URL
    public let applicationSupportDirectory: URL
    public let stateFile: URL
    public let stateLockFile: URL
    public let configFile: URL
    public let logFile: URL
    public let daemonLockFile: URL
    public let eventSpoolDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
        applicationSupportDirectory = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("CodexLidKeeper", isDirectory: true)
        stateFile = applicationSupportDirectory.appendingPathComponent("state.json")
        stateLockFile = applicationSupportDirectory.appendingPathComponent("state.lock")
        configFile = applicationSupportDirectory.appendingPathComponent("config.json")
        logFile = applicationSupportDirectory.appendingPathComponent("keeper.log")
        daemonLockFile = applicationSupportDirectory.appendingPathComponent("daemon.lock")
        eventSpoolDirectory = applicationSupportDirectory
            .appendingPathComponent("events", isDirectory: true)
            .appendingPathComponent("pending", isDirectory: true)
    }
}
