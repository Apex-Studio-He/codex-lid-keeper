import Darwin
import CoreFoundation
import Foundation

public struct HooksConfigurationUpdate {
    public let changed: Bool
    public let backup: URL?

    public init(changed: Bool, backup: URL?) {
        self.changed = changed
        self.backup = backup
    }
}

public enum HooksConfigurationError: Error, LocalizedError {
    case invalidDocument(String)
    case invalidHooks
    case invalidEvent(String)
    case invalidGroup(String, Int)
    case invalidHandlerList(String, Int)
    case invalidHandler(String, Int, Int)
    case invalidSchema(String)
    case cannotRead(String, String)
    case cannotLock(String, String)
    case concurrentModification(String)
    case cannotCreateBackup(String)
    case cannotSecureBackup(String, String)
    case cannotCreateTemporaryFile(String)
    case cannotReplace(String, String)

    public var errorDescription: String? {
        switch self {
        case .invalidDocument(let path):
            return "\(path) must contain a valid UTF-8 JSON object."
        case .invalidHooks:
            return "The top-level 'hooks' value must be an object."
        case .invalidEvent(let event):
            return "hooks.\(event) must be an array."
        case .invalidGroup(let event, let index):
            return "hooks.\(event)[\(index)] must be an object."
        case .invalidHandlerList(let event, let group):
            return "hooks.\(event)[\(group)].hooks must be an array."
        case .invalidHandler(let event, let group, let index):
            return "hooks.\(event)[\(group)].hooks[\(index)] must be an object."
        case .invalidSchema(let detail):
            return "Invalid Codex Hooks configuration: \(detail)"
        case .cannotRead(let path, let detail):
            return "Could not read \(path): \(detail)"
        case .cannotLock(let path, let detail):
            return "Could not lock \(path): \(detail)"
        case .concurrentModification(let path):
            return "\(path) changed while it was being updated; no changes were written. Try again."
        case .cannotCreateBackup(let path):
            return "Could not create a private backup at \(path)."
        case .cannotSecureBackup(let path, let detail):
            return "Could not secure backup \(path): \(detail)"
        case .cannotCreateTemporaryFile(let path):
            return "Could not create a private temporary file beside \(path)."
        case .cannotReplace(let path, let detail):
            return "Could not atomically replace \(path): \(detail)"
        }
    }
}

public enum HooksConfiguration {
    public static let events = [
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "Stop",
        "SessionEnd",
    ]
    private static let supportedEvents = [
        "PreToolUse",
        "PermissionRequest",
        "PostToolUse",
        "PreCompact",
        "PostCompact",
        "SessionStart",
        "SessionEnd",
        "UserPromptSubmit",
        "SubagentStart",
        "SubagentStop",
        "Stop",
    ]
    public static let timeoutSeconds = 1

    public static func install(
        file: URL,
        command: String
    ) throws -> HooksConfigurationUpdate {
        try withExclusiveLock(file: file) {
            let loaded = try load(file: file)
            var document = loaded.document
            let before = try canonicalData(document)
            removeKeeperHooks(from: &document, command: command)

            var hooks: [String: Any]
            if let existing = document["hooks"] {
                guard let typed = existing as? [String: Any] else {
                    throw HooksConfigurationError.invalidHooks
                }
                hooks = typed
            } else {
                hooks = [:]
            }

            for event in events {
                var groups: [Any]
                if let existing = hooks[event] {
                    guard let typed = existing as? [Any] else {
                        throw HooksConfigurationError.invalidEvent(event)
                    }
                    groups = typed
                } else {
                    groups = []
                }
                groups.append([
                    "hooks": [
                        [
                            "type": "command",
                            "command": command,
                            "timeout": timeoutSeconds,
                        ],
                    ],
                ])
                hooks[event] = groups
            }
            document["hooks"] = hooks

            guard try canonicalData(document) != before else {
                return HooksConfigurationUpdate(changed: false, backup: nil)
            }
            let backup = try write(
                file: file,
                document: document,
                expectedData: loaded.data,
                makeBackup: true
            )
            return HooksConfigurationUpdate(changed: true, backup: backup)
        }
    }

    public static func remove(
        file: URL,
        command: String
    ) throws -> HooksConfigurationUpdate {
        try withExclusiveLock(file: file) {
            let loaded = try load(file: file)
            var document = loaded.document
            guard removeKeeperHooks(from: &document, command: command) else {
                return HooksConfigurationUpdate(changed: false, backup: nil)
            }
            let backup = try write(
                file: file,
                document: document,
                expectedData: loaded.data,
                makeBackup: true
            )
            return HooksConfigurationUpdate(changed: true, backup: backup)
        }
    }

    public static func verify(
        file: URL,
        command: String
    ) throws -> [String] {
        let document = try load(file: file).document
        guard let hooks = document["hooks"] as? [String: Any] else {
            return events
        }

        return events.filter { event in
            guard let groups = hooks[event] as? [Any] else {
                return true
            }
            let keeperHandlers = groups.reduce(into: [Any]()) {
                result,
                value in
                guard let group = value as? [String: Any],
                      let handlers = group["hooks"] as? [Any] else {
                    return
                }
                result.append(contentsOf: handlers.filter {
                    isKeeperHandler($0, command: command)
                })
            }
            guard keeperHandlers.count == 1,
                  let handler = keeperHandlers.first else {
                return true
            }
            return !isExpectedKeeperHandler(
                handler,
                command: command
            )
        }
    }

    private struct LoadedDocument {
        let document: [String: Any]
        let data: Data?
    }

    private static func load(file: URL) throws -> LoadedDocument {
        guard let data = try readDataIfPresent(file: file) else {
            return LoadedDocument(document: [:], data: nil)
        }
        do {
            guard let document = try JSONSerialization.jsonObject(
                with: data
            ) as? [String: Any] else {
                throw HooksConfigurationError.invalidDocument(file.path)
            }
            if let hooks = document["hooks"],
               !(hooks is [String: Any]) {
                throw HooksConfigurationError.invalidHooks
            }
            try validateKnownEvents(document)
            return LoadedDocument(document: document, data: data)
        } catch let error as HooksConfigurationError {
            throw error
        } catch {
            throw HooksConfigurationError.invalidDocument(file.path)
        }
    }

    private static func validateKnownEvents(
        _ document: [String: Any]
    ) throws {
        let supportedTopLevel = Set(["description", "hooks"])
        if let unsupported = document.keys.first(
            where: { !supportedTopLevel.contains($0) }
        ) {
            throw HooksConfigurationError.invalidSchema(
                "unsupported top-level field '\(unsupported)'."
            )
        }
        if let description = document["description"],
           !(description is String),
           !(description is NSNull) {
            throw HooksConfigurationError.invalidSchema(
                "'description' must be a string."
            )
        }
        guard let hooks = document["hooks"] as? [String: Any] else {
            return
        }
        for event in supportedEvents {
            guard let value = hooks[event] else {
                continue
            }
            guard let groups = value as? [Any] else {
                throw HooksConfigurationError.invalidEvent(event)
            }
            for (groupIndex, value) in groups.enumerated() {
                guard let group = value as? [String: Any] else {
                    throw HooksConfigurationError.invalidGroup(
                        event,
                        groupIndex
                    )
                }
                if let matcher = group["matcher"],
                   !(matcher is String),
                   !(matcher is NSNull) {
                    throw HooksConfigurationError.invalidSchema(
                        "hooks.\(event)[\(groupIndex)].matcher must be a string."
                    )
                }
                guard let configuredHandlers = group["hooks"] else {
                    continue
                }
                guard let handlers = configuredHandlers as? [Any] else {
                    throw HooksConfigurationError.invalidHandlerList(
                        event,
                        groupIndex
                    )
                }
                for (handlerIndex, handler) in handlers.enumerated()
                {
                    guard let handler = handler as? [String: Any] else {
                        throw HooksConfigurationError.invalidHandler(
                            event,
                            groupIndex,
                            handlerIndex
                        )
                    }
                    try validateHandler(
                        handler,
                        path: "hooks.\(event)[\(groupIndex)].hooks[\(handlerIndex)]"
                    )
                }
            }
        }
    }

    private static func validateHandler(
        _ handler: [String: Any],
        path: String
    ) throws {
        guard let type = handler["type"] as? String,
              ["command", "prompt", "agent"].contains(type) else {
            throw HooksConfigurationError.invalidSchema(
                "\(path).type must be 'command', 'prompt', or 'agent'."
            )
        }
        guard type == "command" else {
            return
        }
        guard handler["command"] is String else {
            throw HooksConfigurationError.invalidSchema(
                "\(path).command must be a string."
            )
        }
        if handler["commandWindows"] != nil,
           handler["command_windows"] != nil {
            throw HooksConfigurationError.invalidSchema(
                "\(path) cannot contain both commandWindows and command_windows."
            )
        }
        try validateOptionalString(
            handler["commandWindows"],
            path: "\(path).commandWindows"
        )
        try validateOptionalString(
            handler["command_windows"],
            path: "\(path).command_windows"
        )
        try validateOptionalUnsignedInteger(
            handler["timeout"],
            path: "\(path).timeout"
        )
        if let async = handler["async"],
           !isBoolean(async) {
            throw HooksConfigurationError.invalidSchema(
                "\(path).async must be a boolean."
            )
        }
        try validateOptionalString(
            handler["statusMessage"],
            path: "\(path).statusMessage"
        )
        try validateOptionalUnsignedInteger(
            handler["additionalContextLimit"],
            path: "\(path).additionalContextLimit"
        )
    }

    private static func validateOptionalString(
        _ value: Any?,
        path: String
    ) throws {
        guard let value, !(value is NSNull) else {
            return
        }
        guard value is String else {
            throw HooksConfigurationError.invalidSchema(
                "\(path) must be a string."
            )
        }
    }

    private static func validateOptionalUnsignedInteger(
        _ value: Any?,
        path: String
    ) throws {
        guard let value, !(value is NSNull) else {
            return
        }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              !CFNumberIsFloatType(number),
              UInt64(number.stringValue) != nil else {
            throw HooksConfigurationError.invalidSchema(
                "\(path) must be an unsigned integer."
            )
        }
    }

    private static func isBoolean(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else {
            return false
        }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func readDataIfPresent(file: URL) throws -> Data? {
        do {
            return try Data(contentsOf: file)
        } catch {
            let cocoaError = error as NSError
            if cocoaError.domain == NSCocoaErrorDomain,
               (
                   cocoaError.code == NSFileReadNoSuchFileError
                       || cocoaError.code == NSFileNoSuchFileError
               ) {
                return nil
            }
            throw HooksConfigurationError.cannotRead(
                file.path,
                cocoaError.localizedDescription
            )
        }
    }

    private static func withExclusiveLock<T>(
        file: URL,
        operation: () throws -> T
    ) throws -> T {
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let lock = directory.appendingPathComponent(
            ".\(file.lastPathComponent).codex-lid-keeper.lock"
        )
        let descriptor = Darwin.open(
            lock.path,
            O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_EXLOCK,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            let detail = String(cString: strerror(errno))
            throw HooksConfigurationError.cannotLock(lock.path, detail)
        }
        defer {
            _ = Darwin.close(descriptor)
        }
        guard Darwin.fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
            let detail = String(cString: strerror(errno))
            throw HooksConfigurationError.cannotLock(lock.path, detail)
        }
        return try operation()
    }

    @discardableResult
    private static func removeKeeperHooks(
        from document: inout [String: Any],
        command: String
    ) -> Bool {
        guard var hooks = document["hooks"] as? [String: Any] else {
            return false
        }

        var changed = false
        for event in events {
            guard let groups = hooks[event] as? [Any] else {
                continue
            }
            var keptGroups: [Any] = []
            for value in groups {
                guard var group = value as? [String: Any],
                      let handlers = group["hooks"] as? [Any] else {
                    keptGroups.append(value)
                    continue
                }
                let filtered = handlers.filter {
                    !isKeeperHandler($0, command: command)
                }
                let removedCount = handlers.count - filtered.count
                if removedCount > 0 {
                    changed = true
                }
                if removedCount == 0 {
                    keptGroups.append(value)
                } else if !filtered.isEmpty {
                    group["hooks"] = filtered
                    keptGroups.append(group)
                }
            }
            if keptGroups.isEmpty {
                if hooks.removeValue(forKey: event) != nil {
                    changed = true
                }
            } else {
                hooks[event] = keptGroups
            }
        }
        document["hooks"] = hooks
        return changed
    }

    private static func isKeeperHandler(
        _ value: Any,
        command: String
    ) -> Bool {
        guard let handler = value as? [String: Any] else {
            return false
        }
        return handler["type"] as? String == "command"
            && handler["command"] as? String == command
    }

    private static func isExpectedKeeperHandler(
        _ value: Any,
        command: String
    ) -> Bool {
        guard isKeeperHandler(value, command: command),
              let handler = value as? [String: Any],
              let timeout = handler["timeout"] as? NSNumber else {
            return false
        }
        guard CFGetTypeID(timeout) != CFBooleanGetTypeID() else {
            return false
        }
        guard !CFNumberIsFloatType(timeout) else {
            return false
        }
        return timeout.int64Value == Int64(timeoutSeconds)
    }

    private static func canonicalData(
        _ document: [String: Any]
    ) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: document,
            options: [.sortedKeys]
        )
    }

    private static func write(
        file: URL,
        document: [String: Any],
        expectedData: Data?,
        makeBackup: Bool
    ) throws -> URL? {
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let currentData = try readDataIfPresent(file: file)
        guard currentData == expectedData else {
            throw HooksConfigurationError.concurrentModification(file.path)
        }

        var backup: URL?
        if makeBackup, let currentData {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            var candidate = file
                .deletingLastPathComponent()
                .appendingPathComponent(
                    "\(file.lastPathComponent).backup.\(formatter.string(from: Date()))"
                )
            if FileManager.default.fileExists(atPath: candidate.path) {
                candidate.appendPathExtension(UUID().uuidString)
            }
            guard FileManager.default.createFile(
                atPath: candidate.path,
                contents: currentData,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw HooksConfigurationError.cannotCreateBackup(
                    candidate.path
                )
            }
            guard Darwin.chmod(candidate.path, 0o600) == 0 else {
                let detail = String(cString: strerror(errno))
                try? FileManager.default.removeItem(at: candidate)
                throw HooksConfigurationError.cannotSecureBackup(
                    candidate.path,
                    detail
                )
            }
            backup = candidate
        }

        var payload = try JSONSerialization.data(
            withJSONObject: document,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        payload.append(0x0A)

        let temporary = directory.appendingPathComponent(
            ".\(file.lastPathComponent).\(UUID().uuidString)"
        )
        guard FileManager.default.createFile(
            atPath: temporary.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw HooksConfigurationError.cannotCreateTemporaryFile(file.path)
        }
        defer {
            try? FileManager.default.removeItem(at: temporary)
        }

        let handle = try FileHandle(forWritingTo: temporary)
        do {
            try handle.write(contentsOf: payload)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        _ = Darwin.chmod(temporary.path, 0o600)

        guard try readDataIfPresent(file: file) == expectedData else {
            throw HooksConfigurationError.concurrentModification(file.path)
        }
        guard Darwin.rename(temporary.path, file.path) == 0 else {
            let detail = String(cString: strerror(errno))
            throw HooksConfigurationError.cannotReplace(file.path, detail)
        }
        return backup
    }
}
