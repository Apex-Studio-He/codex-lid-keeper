import Darwin
import Foundation

public enum LaunchdJobHealth {
    public static func runningPID(
        fromPrintOutput output: String
    ) -> Int32? {
        var states: [String] = []
        var processIdentifiers: [String] = []

        for rawLine in output.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ) {
            guard rawLine.first == "\t",
                  rawLine.dropFirst().first != "\t" else {
                continue
            }
            let line = rawLine.dropFirst()
            if line.hasPrefix("state = ") {
                states.append(String(line.dropFirst("state = ".count)))
            } else if line.hasPrefix("pid = ") {
                processIdentifiers.append(
                    String(line.dropFirst("pid = ".count))
                )
            }
        }

        guard states == ["running"],
              processIdentifiers.count == 1,
              let processIdentifier = Int32(processIdentifiers[0]),
              processIdentifier > 0 else {
            return nil
        }
        return processIdentifier
    }

    public static func daemonLockIsHeld(at file: URL) -> Bool {
        let descriptor = Darwin.open(
            file.path,
            O_RDWR | O_EXLOCK | O_NONBLOCK | O_CLOEXEC
        )
        guard descriptor < 0 else {
            _ = Darwin.close(descriptor)
            return false
        }
        return errno == EWOULDBLOCK || errno == EAGAIN
    }

    public static func processIsAlive(_ processIdentifier: Int32) -> Bool {
        guard processIdentifier > 0 else { return false }
        if Darwin.kill(processIdentifier, 0) == 0 {
            return true
        }
        return errno == EPERM
    }
}

public enum PowerHeartbeatHealth {
    public static func isFresh(
        modificationDate: Date?,
        now: Date = Date(),
        maximumAge: TimeInterval
    ) -> Bool {
        guard let modificationDate,
              maximumAge > 0 else {
            return false
        }
        let age = now.timeIntervalSince(modificationDate)
        return age >= 0 && age <= maximumAge
    }
}
