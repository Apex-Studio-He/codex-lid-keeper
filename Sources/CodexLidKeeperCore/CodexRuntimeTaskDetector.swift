import Foundation
import SQLite3

public struct RuntimeTaskDetection: Equatable, Sendable {
    public let sourceAvailable: Bool
    public let activeTasks: [TaskLease]
    public let observedSessionIDs: Set<String>

    public init(
        sourceAvailable: Bool,
        activeTasks: [TaskLease],
        observedSessionIDs: Set<String> = []
    ) {
        self.sourceAvailable = sourceAvailable
        self.activeTasks = activeTasks
        self.observedSessionIDs = observedSessionIDs
    }

    public static let unavailable = RuntimeTaskDetection(
        sourceAvailable: false,
        activeTasks: []
    )
}

public protocol RuntimeTaskDetecting {
    func detectActiveTasks(
        now: Date,
        maximumAge: TimeInterval
    ) -> RuntimeTaskDetection
}

public final class CodexRuntimeTaskDetector: RuntimeTaskDetecting {
    private let logsDatabase: URL
    private let stateDatabase: URL
    private let rowLimit: Int
    private let fileManager: FileManager
    private let rolloutDetector: CodexRolloutTaskDetector
    private let lock = NSLock()
    private var candidates: [String: TurnCandidate] = [:]
    private var projectDirectories: [String: String] = [:]
    private var lastScannedLogTimestamp: Int64?
    private var scannedMaximumAge: TimeInterval = 0

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        rowLimit: Int = KeeperConstants.runtimeLogRowLimit,
        fileManager: FileManager = .default
    ) {
        let codexDirectory = homeDirectory
            .appendingPathComponent(".codex", isDirectory: true)
        logsDatabase = codexDirectory.appendingPathComponent("logs_2.sqlite")
        stateDatabase = codexDirectory.appendingPathComponent("state_5.sqlite")
        self.rowLimit = max(1, rowLimit)
        self.fileManager = fileManager
        rolloutDetector = CodexRolloutTaskDetector(
            stateDatabase: stateDatabase,
            fileManager: fileManager
        )
    }

    public func detectActiveTasks(
        now: Date = Date(),
        maximumAge: TimeInterval
    ) -> RuntimeTaskDetection {
        let rollout = rolloutDetector.detectActiveTasks(
            now: now,
            maximumAge: maximumAge
        )
        let log = detectLogTasks(
            now: now,
            maximumAge: maximumAge
        )
        guard rollout.sourceAvailable || log.sourceAvailable else {
            return .unavailable
        }

        var tasksBySession: [String: TaskLease] = [:]
        for task in log.activeTasks
        where !rollout.observedSessionIDs.contains(task.sessionID) {
            tasksBySession[task.sessionID] = task
        }
        for task in rollout.activeTasks {
            tasksBySession[task.sessionID] = task
        }
        let tasks = tasksBySession.values.sorted {
            if $0.startedAt == $1.startedAt {
                return $0.id < $1.id
            }
            return $0.startedAt < $1.startedAt
        }
        return RuntimeTaskDetection(
            sourceAvailable: true,
            activeTasks: tasks,
            observedSessionIDs: rollout.observedSessionIDs
        )
    }

    private func detectLogTasks(
        now: Date,
        maximumAge: TimeInterval
    ) -> RuntimeTaskDetection {
        lock.lock()
        defer { lock.unlock() }
        guard fileManager.fileExists(atPath: logsDatabase.path) else {
            return .unavailable
        }

        do {
            let newestLogTimestamp = try readNewestLogTimestamp()
            if let lastScannedLogTimestamp,
               newestLogTimestamp < lastScannedLogTimestamp {
                candidates.removeAll()
                projectDirectories.removeAll()
                self.lastScannedLogTimestamp = nil
                scannedMaximumAge = 0
            }
            let requiresFullScan = lastScannedLogTimestamp == nil
                || maximumAge != scannedMaximumAge
            let scanStart: Date
            if requiresFullScan {
                scanStart = now.addingTimeInterval(-maximumAge)
            } else {
                scanStart = Date(
                    timeIntervalSince1970: TimeInterval(
                        max(0, (lastScannedLogTimestamp ?? 0) - 1)
                    )
                )
            }
            let rows = try readTurnRows(since: scanStart)
            let parsed = parseLatestTurns(
                rows: rows,
                now: now
            )
            if requiresFullScan {
                candidates = parsed
            } else {
                merge(parsed)
            }
            let cutoff = now.addingTimeInterval(-maximumAge)
            candidates = candidates.filter {
                $0.value.latestActivityAt >= cutoff
            }
            lastScannedLogTimestamp = newestLogTimestamp
            scannedMaximumAge = maximumAge

            let active = candidates.values.filter(\.isActive)
            let missingProjects = active.map(\.threadID).filter {
                projectDirectories[$0] == nil
            }
            if !missingProjects.isEmpty,
               let projects = try? readProjectDirectories(
                   threadIDs: missingProjects
               ) {
                projectDirectories.merge(projects) { _, new in new }
            }
            let tasks = active.map { candidate in
                let cwd = projectDirectories[candidate.threadID]
                return TaskLease(
                    id: HookProcessor.leaseID(
                        sessionID: candidate.threadID,
                        turnID: candidate.turnID
                    ),
                    sessionID: candidate.threadID,
                    turnID: candidate.turnID,
                    projectName: cwd.map(HookProcessor.projectName)
                        ?? "Codex 任务",
                    startedAt: candidate.oldestActivityAt,
                    lastActivityAt: candidate.latestActivityAt,
                    expiresAt: candidate.latestActivityAt
                        .addingTimeInterval(maximumAge)
                )
            }
            .sorted {
                if $0.startedAt == $1.startedAt {
                    return $0.id < $1.id
                }
                return $0.startedAt < $1.startedAt
            }
            return RuntimeTaskDetection(
                sourceAvailable: true,
                activeTasks: tasks
            )
        } catch {
            return .unavailable
        }
    }

    private func readTurnRows(since: Date) throws -> [TurnLogRow] {
        let database = try SQLiteReadOnlyDatabase(path: logsDatabase.path)
        let sql = """
            SELECT ts, ts_nanos, feedback_log_body
            FROM logs INDEXED BY idx_logs_ts
            WHERE ts >= ? AND target = ?
            ORDER BY ts DESC, ts_nanos DESC
            LIMIT ?;
            """
        return try database.query(
            sql,
            bindings: [
                .integer(Int64(since.timeIntervalSince1970)),
                .text("codex_core::session::turn"),
                .integer(Int64(rowLimit))
            ]
        ) { statement in
            guard let bodyPointer = sqlite3_column_text(statement, 2) else {
                return nil
            }
            return TurnLogRow(
                timestamp: sqlite3_column_int64(statement, 0),
                timestampNanos: sqlite3_column_int64(statement, 1),
                body: String(cString: bodyPointer)
            )
        }
    }

    private func readNewestLogTimestamp() throws -> Int64 {
        let database = try SQLiteReadOnlyDatabase(path: logsDatabase.path)
        let values: [Int64] = try database.query(
            "SELECT COALESCE(MAX(ts), 0) FROM logs;",
            bindings: []
        ) { statement in
            sqlite3_column_int64(statement, 0)
        }
        return values.first ?? 0
    }

    private func parseLatestTurns(
        rows: [TurnLogRow],
        now: Date
    ) -> [String: TurnCandidate] {
        var result: [String: TurnCandidate] = [:]
        let maximumFutureTimestamp = now.addingTimeInterval(
            KeeperConstants.maximumEventFutureSkew
        ).timeIntervalSince1970

        for row in rows {
            guard Double(row.timestamp) <= maximumFutureTimestamp,
                  let threadID = identifier(
                    after: "session_loop{thread_id=",
                    in: row.body
                  ),
                  let turnID = identifier(after: " turn.id=", in: row.body),
                  let isActive = finalFollowUpState(in: row.body) else {
                continue
            }
            let activityAt = Date(
                timeIntervalSince1970: TimeInterval(row.timestamp)
            )
            if var candidate = result[threadID] {
                if candidate.isActive, candidate.turnID == turnID {
                    candidate.oldestActivityAt = min(
                        candidate.oldestActivityAt,
                        activityAt
                    )
                    result[threadID] = candidate
                }
                continue
            }
            result[threadID] = TurnCandidate(
                threadID: threadID,
                turnID: turnID,
                isActive: isActive,
                latestActivityAt: activityAt,
                latestActivityNanos: row.timestampNanos,
                oldestActivityAt: activityAt
            )
        }
        return result
    }

    private func merge(_ updates: [String: TurnCandidate]) {
        for (threadID, update) in updates {
            guard var current = candidates[threadID] else {
                candidates[threadID] = update
                continue
            }
            let updateIsNewer =
                update.latestActivityAt > current.latestActivityAt
                || (
                    update.latestActivityAt == current.latestActivityAt
                        && update.latestActivityNanos
                            > current.latestActivityNanos
                )
            if updateIsNewer {
                var replacement = update
                if current.isActive,
                   replacement.isActive,
                   current.turnID == replacement.turnID {
                    replacement.oldestActivityAt = min(
                        current.oldestActivityAt,
                        replacement.oldestActivityAt
                    )
                }
                candidates[threadID] = replacement
            } else if current.isActive,
                      update.isActive,
                      current.turnID == update.turnID {
                current.oldestActivityAt = min(
                    current.oldestActivityAt,
                    update.oldestActivityAt
                )
                candidates[threadID] = current
            }
        }
    }

    private func readProjectDirectories(
        threadIDs: [String]
    ) throws -> [String: String] {
        guard !threadIDs.isEmpty,
              fileManager.fileExists(atPath: stateDatabase.path) else {
            return [:]
        }
        let database = try SQLiteReadOnlyDatabase(path: stateDatabase.path)
        let placeholders = Array(
            repeating: "?",
            count: threadIDs.count
        ).joined(separator: ",")
        let sql = "SELECT id, cwd FROM threads WHERE id IN (\(placeholders));"
        let pairs: [(String, String)] = try database.query(
            sql,
            bindings: threadIDs.map(SQLiteBinding.text)
        ) { statement in
            guard let idPointer = sqlite3_column_text(statement, 0),
                  let cwdPointer = sqlite3_column_text(statement, 1) else {
                return nil
            }
            return (
                String(cString: idPointer),
                String(cString: cwdPointer)
            )
        }
        return Dictionary(uniqueKeysWithValues: pairs)
    }

    private func identifier(after marker: String, in text: String) -> String? {
        guard let markerRange = text.range(of: marker) else { return nil }
        let suffix = text[markerRange.upperBound...]
        guard let end = suffix.firstIndex(where: {
            $0 == " " || $0 == "}" || $0 == ":"
        }) else {
            return nil
        }
        let value = String(suffix[..<end])
        guard !value.isEmpty,
              value.count <= 128,
              value.utf8.allSatisfy({
                  ($0 >= 48 && $0 <= 57)
                      || ($0 >= 65 && $0 <= 90)
                      || ($0 >= 97 && $0 <= 122)
                      || $0 == 45
                      || $0 == 95
              }) else {
            return nil
        }
        return value
    }

    private func finalFollowUpState(in text: String) -> Bool? {
        let marker = "needs_follow_up="
        guard let range = text.range(of: marker, options: .backwards) else {
            return nil
        }
        let suffix = text[range.upperBound...]
        if suffix.hasPrefix("true") { return true }
        if suffix.hasPrefix("false") { return false }
        return nil
    }
}

private struct TurnLogRow {
    let timestamp: Int64
    let timestampNanos: Int64
    let body: String
}

private struct TurnCandidate {
    let threadID: String
    let turnID: String
    let isActive: Bool
    let latestActivityAt: Date
    let latestActivityNanos: Int64
    var oldestActivityAt: Date
}

private final class CodexRolloutTaskDetector {
    private static let candidateLimit = 512
    private static let initialTailByteLimit = 4 * 1_024 * 1_024
    private static let lifecycleLineByteLimit = 64 * 1_024
    private static let newline = UInt8(ascii: "\n")
    private static let taskStartedMarker = Data(
        "\"type\":\"task_started\"".utf8
    )
    private static let taskCompleteMarker = Data(
        "\"type\":\"task_complete\"".utf8
    )

    private let stateDatabase: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private let decoder = JSONDecoder()
    private var cache: [String: RolloutCacheEntry] = [:]

    init(
        stateDatabase: URL,
        fileManager: FileManager
    ) {
        self.stateDatabase = stateDatabase
        self.fileManager = fileManager
    }

    func detectActiveTasks(
        now: Date,
        maximumAge: TimeInterval
    ) -> RuntimeTaskDetection {
        lock.lock()
        defer { lock.unlock() }
        guard fileManager.fileExists(atPath: stateDatabase.path) else {
            return .unavailable
        }

        do {
            let cutoff = now.addingTimeInterval(-maximumAge)
            let threads = try readCandidateThreads(since: cutoff)
            let candidateIDs = Set(threads.map(\.id))
            cache = cache.filter { candidateIDs.contains($0.key) }

            var tasks: [TaskLease] = []
            var observedSessionIDs: Set<String> = []
            for thread in threads {
                let lifecycle = try refreshLifecycle(for: thread)
                guard let lifecycle,
                      lifecycle.occurredAt >= cutoff else {
                    continue
                }
                observedSessionIDs.insert(thread.id)
                guard lifecycle.isActive else { continue }

                tasks.append(
                    TaskLease(
                        id: HookProcessor.leaseID(
                            sessionID: thread.id,
                            turnID: lifecycle.turnID
                        ),
                        sessionID: thread.id,
                        turnID: lifecycle.turnID,
                        projectName: HookProcessor.projectName(
                            from: thread.cwd
                        ),
                        startedAt: lifecycle.startedAt,
                        lastActivityAt: lifecycle.occurredAt,
                        expiresAt: now.addingTimeInterval(maximumAge)
                    )
                )
            }
            tasks.sort {
                if $0.startedAt == $1.startedAt {
                    return $0.id < $1.id
                }
                return $0.startedAt < $1.startedAt
            }
            return RuntimeTaskDetection(
                sourceAvailable: true,
                activeTasks: tasks,
                observedSessionIDs: observedSessionIDs
            )
        } catch {
            return .unavailable
        }
    }

    private func readCandidateThreads(
        since cutoff: Date
    ) throws -> [RolloutThread] {
        let database = try SQLiteReadOnlyDatabase(path: stateDatabase.path)
        let sql = """
            SELECT id, rollout_path, cwd, updated_at
            FROM threads
            WHERE archived = 0 AND updated_at >= ?
            ORDER BY updated_at DESC
            LIMIT ?;
            """
        return try database.query(
            sql,
            bindings: [
                .integer(Int64(cutoff.timeIntervalSince1970)),
                .integer(Int64(Self.candidateLimit)),
            ]
        ) { statement in
            guard let idPointer = sqlite3_column_text(statement, 0),
                  let pathPointer = sqlite3_column_text(statement, 1),
                  let cwdPointer = sqlite3_column_text(statement, 2) else {
                return nil
            }
            return RolloutThread(
                id: String(cString: idPointer),
                path: String(cString: pathPointer),
                cwd: String(cString: cwdPointer),
                updatedAt: Date(
                    timeIntervalSince1970: TimeInterval(
                        sqlite3_column_int64(statement, 3)
                    )
                )
            )
        }
    }

    private func refreshLifecycle(
        for thread: RolloutThread
    ) throws -> RolloutLifecycle? {
        guard !thread.path.isEmpty,
              fileManager.fileExists(atPath: thread.path) else {
            cache.removeValue(forKey: thread.id)
            return nil
        }
        let attributes = try fileManager.attributesOfItem(
            atPath: thread.path
        )
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0

        var entry = cache[thread.id]
            ?? RolloutCacheEntry(
                path: thread.path,
                scannedByteCount: 0,
                pendingLine: Data(),
                latest: nil
            )
        if entry.path != thread.path
            || fileSize < entry.scannedByteCount {
            entry = RolloutCacheEntry(
                path: thread.path,
                scannedByteCount: 0,
                pendingLine: Data(),
                latest: nil
            )
        }
        guard fileSize != entry.scannedByteCount else {
            return entry.latest
        }

        let initialRead = entry.scannedByteCount == 0
        let desiredStart = initialRead
            ? fileSize.saturatingSubtract(
                UInt64(Self.initialTailByteLimit)
            )
            : entry.scannedByteCount
        let readStart = initialRead && desiredStart > 0
            ? desiredStart - 1
            : desiredStart
        let handle = try FileHandle(
            forReadingFrom: URL(fileURLWithPath: thread.path)
        )
        defer { try? handle.close() }
        try handle.seek(toOffset: readStart)
        let newData = try handle.readToEnd() ?? Data()

        var bytes = Data()
        if !initialRead {
            bytes.append(entry.pendingLine)
        }
        bytes.append(newData)
        var lines = bytes.split(
            separator: Self.newline,
            omittingEmptySubsequences: false
        )

        if initialRead, desiredStart > 0 {
            if newData.first == Self.newline {
                if !lines.isEmpty {
                    lines.removeFirst()
                }
            } else if !lines.isEmpty {
                lines.removeFirst()
            }
        }

        if bytes.last == Self.newline {
            entry.pendingLine.removeAll(keepingCapacity: true)
            if lines.last?.isEmpty == true {
                lines.removeLast()
            }
        } else if let partial = lines.popLast() {
            entry.pendingLine = partial.count
                    <= Self.lifecycleLineByteLimit
                ? Data(partial)
                : Data()
        }

        for line in lines {
            guard line.count <= Self.lifecycleLineByteLimit,
                  containsLifecycleMarker(line),
                  let event = try? decoder.decode(
                      RolloutLifecycleEnvelope.self,
                      from: Data(line)
                  ),
                  event.type == "event_msg",
                  let payload = event.payload,
                  let turnID = nonempty(payload.turnID),
                  let eventType = payload.type,
                  eventType == "task_started"
                      || eventType == "task_complete" else {
                continue
            }

            entry.latest = RolloutLifecycle(
                turnID: turnID,
                isActive: eventType == "task_started",
                occurredAt: thread.updatedAt,
                startedAt: turnStartDate(from: turnID)
                    ?? thread.updatedAt
            )
        }

        entry.scannedByteCount = fileSize
        cache[thread.id] = entry
        return entry.latest
    }

    private func containsLifecycleMarker(
        _ line: Data.SubSequence
    ) -> Bool {
        line.range(of: Self.taskStartedMarker) != nil
            || line.range(of: Self.taskCompleteMarker) != nil
    }

    private func turnStartDate(from turnID: String) -> Date? {
        let timestampHex = turnID
            .filter(\.isHexDigit)
            .prefix(12)
        guard timestampHex.count == 12,
              let milliseconds = UInt64(timestampHex, radix: 16) else {
            return nil
        }
        return Date(
            timeIntervalSince1970: TimeInterval(milliseconds) / 1_000
        )
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty else {
            return nil
        }
        return value
    }
}

private struct RolloutThread {
    let id: String
    let path: String
    let cwd: String
    let updatedAt: Date
}

private struct RolloutCacheEntry {
    let path: String
    var scannedByteCount: UInt64
    var pendingLine: Data
    var latest: RolloutLifecycle?
}

private struct RolloutLifecycle {
    let turnID: String
    let isActive: Bool
    let occurredAt: Date
    let startedAt: Date
}

private struct RolloutLifecycleEnvelope: Decodable {
    let type: String?
    let payload: RolloutLifecyclePayload?
}

private struct RolloutLifecyclePayload: Decodable {
    let type: String?
    let turnID: String?

    enum CodingKeys: String, CodingKey {
        case type
        case turnID = "turn_id"
    }
}

private extension UInt64 {
    func saturatingSubtract(_ value: UInt64) -> UInt64 {
        self >= value ? self - value : 0
    }
}

private enum SQLiteBinding {
    case integer(Int64)
    case text(String)
}

private enum SQLiteReadError: Error {
    case openFailed
    case prepareFailed
    case bindFailed
    case stepFailed
}

private final class SQLiteReadOnlyDatabase {
    private var handle: OpaquePointer?

    init(path: String) throws {
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK,
              handle != nil else {
            if let handle {
                sqlite3_close(handle)
            }
            throw SQLiteReadError.openFailed
        }
        sqlite3_busy_timeout(handle, 100)
    }

    deinit {
        if let handle {
            sqlite3_close(handle)
        }
    }

    func query<T>(
        _ sql: String,
        bindings: [SQLiteBinding],
        row: (OpaquePointer) -> T?
    ) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
            == SQLITE_OK,
            let statement else {
            throw SQLiteReadError.prepareFailed
        }
        defer { sqlite3_finalize(statement) }

        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch binding {
            case .integer(let value):
                result = sqlite3_bind_int64(statement, index, value)
            case .text(let value):
                result = value.withCString {
                    sqlite3_bind_text(
                        statement,
                        index,
                        $0,
                        -1,
                        sqliteTransient
                    )
                }
            }
            guard result == SQLITE_OK else {
                throw SQLiteReadError.bindFailed
            }
        }

        var values: [T] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                if let value = row(statement) {
                    values.append(value)
                }
            case SQLITE_DONE:
                return values
            default:
                throw SQLiteReadError.stepFailed
            }
        }
    }
}

private let sqliteTransient = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)
