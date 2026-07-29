import Foundation

public struct CommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let standardOutput: Data
    public let standardError: Data

    public init(exitCode: Int32, standardOutput: Data, standardError: Data) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var outputString: String {
        String(data: standardOutput, encoding: .utf8) ?? ""
    }

    public var errorString: String {
        String(data: standardError, encoding: .utf8) ?? ""
    }
}

public enum CommandRunnerError: Error, LocalizedError {
    case timedOut(String)
    case failedToLaunch(String)
    case nonzeroExit(executable: String, code: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .timedOut(let executable):
            return "\(executable) timed out."
        case .failedToLaunch(let message):
            return "Could not launch command: \(message)"
        case .nonzeroExit(let executable, let code, let message):
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "\(executable) exited with status \(code)."
                : "\(executable) exited with status \(code): \(detail)"
        }
    }
}

public protocol CommandRunning {
    func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> CommandResult
}

public final class FoundationCommandRunner: CommandRunning {
    public init() {}

    public func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval = 3
    ) throws -> CommandResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let completion = DispatchSemaphore(value: 0)

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        process.terminationHandler = { _ in completion.signal() }

        do {
            try process.run()
        } catch {
            throw CommandRunnerError.failedToLaunch(error.localizedDescription)
        }

        if completion.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = completion.wait(timeout: .now() + 1)
            throw CommandRunnerError.timedOut(executable)
        }

        let result = CommandResult(
            exitCode: process.terminationStatus,
            standardOutput: stdout.fileHandleForReading.readDataToEndOfFile(),
            standardError: stderr.fileHandleForReading.readDataToEndOfFile()
        )
        guard result.exitCode == 0 else {
            throw CommandRunnerError.nonzeroExit(
                executable: executable,
                code: result.exitCode,
                message: result.errorString
            )
        }
        return result
    }
}
