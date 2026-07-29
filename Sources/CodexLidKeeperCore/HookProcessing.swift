import Foundation

public enum HookProcessingError: Error, LocalizedError, Equatable {
    case inputTooLarge
    case invalidInput
    case unsupportedEvent(String)
    case missingTurnID(String)

    public var errorDescription: String? {
        switch self {
        case .inputTooLarge:
            return "Codex Hook input exceeded the 1 MiB safety limit."
        case .invalidInput:
            return "Codex Hook input is not valid JSON or is missing required fields."
        case .unsupportedEvent(let event):
            return "Unsupported Codex Hook event: \(event)."
        case .missingTurnID(let event):
            return "Codex Hook event \(event) did not include turn_id."
        }
    }
}

public enum HookProcessor {
    public static func decode(_ data: Data) throws -> CodexHookInput {
        guard data.count <= KeeperConstants.hookInputLimit else {
            throw HookProcessingError.inputTooLarge
        }

        let input: CodexHookInput
        do {
            input = try JSONDecoder().decode(CodexHookInput.self, from: data)
        } catch {
            throw HookProcessingError.invalidInput
        }

        guard !input.sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !input.cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !input.hookEventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HookProcessingError.invalidInput
        }
        _ = try action(for: input)
        return input
    }

    public static func action(for input: CodexHookInput) throws -> HookAction {
        switch input.hookEventName {
        case "UserPromptSubmit":
            guard nonempty(input.turnID) else {
                throw HookProcessingError.missingTurnID(input.hookEventName)
            }
            return .acquire
        case "PreToolUse", "PostToolUse":
            guard nonempty(input.turnID) else {
                throw HookProcessingError.missingTurnID(input.hookEventName)
            }
            return .renew
        case "Stop":
            guard nonempty(input.turnID) else {
                throw HookProcessingError.missingTurnID(input.hookEventName)
            }
            return .releaseTurn
        case "SessionEnd":
            return .releaseSession
        default:
            throw HookProcessingError.unsupportedEvent(input.hookEventName)
        }
    }

    public static func leaseID(sessionID: String, turnID: String) -> String {
        "\(sessionID)\u{1F}\(turnID)"
    }

    public static func makeEvent(
        from input: CodexHookInput,
        id: UUID = UUID(),
        occurredAt: Date = Date()
    ) throws -> LifecycleEvent {
        try LifecycleEvent(
            id: id,
            action: action(for: input),
            sessionID: input.sessionID,
            turnID: input.turnID,
            projectName: projectName(from: input.cwd),
            occurredAt: occurredAt
        ).validated()
    }

    public static func projectName(from cwd: String) -> String {
        let trimmed = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = URL(fileURLWithPath: trimmed).lastPathComponent
        return name.isEmpty ? "Unknown Project" : name
    }

    private static func nonempty(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
