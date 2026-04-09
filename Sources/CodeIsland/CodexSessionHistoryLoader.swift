import Foundation
import SQLite3
import CodeIslandCore

private struct CodexHistoryThreadRecord {
    let id: String
    let rolloutPath: String
    let updatedAtUnix: TimeInterval
    let cwd: String
    let title: String?
    let firstUserMessage: String?
}

private struct HistoricalToolCall {
    let rawName: String
    let rawArguments: String?

    var displayName: String {
        switch rawName {
        case "exec_command":
            return "Bash"
        case "apply_patch":
            return "Patch"
        case "multi_tool_use.parallel":
            return "Parallel"
        case "spawn_agent":
            return "Subagent"
        case "wait_agent":
            return "Wait"
        case "open":
            return "Open"
        case "click":
            return "Click"
        case "find":
            return "Find"
        case "search_query", "image_query":
            return "Search"
        default:
            return rawName
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: ".", with: " ")
                .capitalized
        }
    }

    var displaySummary: String? {
        guard let rawArguments else { return nil }
        guard let data = rawArguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any] else {
            return CodexSessionHistoryLoader.normalizedInlineText(rawArguments, limit: 120)
        }

        let directKeys = ["cmd", "message", "query", "url", "doc_url"]
        for key in directKeys {
            if let value = payload[key] as? String {
                return CodexSessionHistoryLoader.normalizedInlineText(value, limit: 120)
            }
        }

        if let targets = payload["targets"] as? [String], !targets.isEmpty {
            return CodexSessionHistoryLoader.normalizedInlineText(targets.joined(separator: ", "), limit: 120)
        }

        return CodexSessionHistoryLoader.normalizedInlineText(rawArguments, limit: 120)
    }
}

private struct CodexRolloutSnapshot {
    var lastUserMessage: String?
    var lastAssistantMessage: String?
    var lastToolCall: HistoricalToolCall?
    var status: AgentStatus = .idle
}

enum CodexSessionHistoryLoader {
    private static let defaultSessionLimit = 12
    private static let rolloutTailByteCount: UInt64 = 256 * 1024
    private static let assistantSummaryLimit = 6_000
    private static let fallbackToolSummaryLimit = 320

    static func loadRecentSessions(limit: Int = defaultSessionLimit) -> [(sessionId: String, snapshot: SessionSnapshot)] {
        guard limit > 0,
              let databaseURL = defaultDatabaseURL(),
              let database = openReadOnlyDatabase(at: databaseURL.path) else {
            return []
        }
        defer { sqlite3_close(database) }

        return fetchRecentThreads(from: database, limit: limit).compactMap(makeHistoricalSession(from:))
    }

    fileprivate static func normalizedInlineText(_ raw: String?, limit: Int) -> String? {
        guard let raw else { return nil }
        let collapsed = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit - 1)) + "…"
    }

    private static func defaultDatabaseURL() -> URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("state_5.sqlite", isDirectory: false)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func openReadOnlyDatabase(at path: String) -> OpaquePointer? {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(path, &database, flags, nil) == SQLITE_OK else {
            sqlite3_close(database)
            return nil
        }
        return database
    }

    private static func fetchRecentThreads(from database: OpaquePointer, limit: Int) -> [CodexHistoryThreadRecord] {
        let sql = """
        SELECT
            id,
            COALESCE(rollout_path, '') AS rollout_path,
            updated_at,
            COALESCE(cwd, '') AS cwd,
            NULLIF(title, '') AS title,
            NULLIF(first_user_message, '') AS first_user_message
        FROM threads
        WHERE model_provider = 'openai'
          AND archived = 0
        ORDER BY updated_at DESC
        LIMIT ?
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(limit))

        var rows: [CodexHistoryThreadRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(
                CodexHistoryThreadRecord(
                    id: stringValue(in: statement, column: 0),
                    rolloutPath: stringValue(in: statement, column: 1),
                    updatedAtUnix: sqlite3_column_double(statement, 2),
                    cwd: stringValue(in: statement, column: 3),
                    title: optionalStringValue(in: statement, column: 4),
                    firstUserMessage: optionalStringValue(in: statement, column: 5)
                )
            )
        }
        return rows
    }

    private static func makeHistoricalSession(from record: CodexHistoryThreadRecord) -> (sessionId: String, snapshot: SessionSnapshot)? {
        guard !record.id.isEmpty else { return nil }

        let rolloutSnapshot = readRolloutSnapshot(at: record.rolloutPath)
        let latestPrompt = rolloutSnapshot.lastUserMessage ?? record.firstUserMessage
        let updatedAt = Date(timeIntervalSince1970: record.updatedAtUnix)

        var snapshot = SessionSnapshot(startTime: updatedAt)
        snapshot.source = "codex"
        snapshot.cwd = record.cwd.isEmpty ? nil : record.cwd
        snapshot.status = rolloutSnapshot.status
        snapshot.currentTool = rolloutSnapshot.lastToolCall?.displayName
        snapshot.toolDescription = rolloutSnapshot.lastToolCall?.displaySummary
        snapshot.lastUserPrompt = latestPrompt
        snapshot.lastAssistantMessage = rolloutSnapshot.lastAssistantMessage
        snapshot.lastActivity = updatedAt
        snapshot.sessionTitle = normalizedTitle(
            cwd: record.cwd,
            rawTitle: record.title,
            prompt: latestPrompt,
            fallbackID: record.id
        )
        snapshot.sessionTitleSource = .codexThreadName
        snapshot.providerSessionId = record.id
        snapshot.isHistoricalSnapshot = true

        if let latestPrompt {
            snapshot.addRecentMessage(ChatMessage(isUser: true, text: latestPrompt))
        }
        if let assistant = rolloutSnapshot.lastAssistantMessage {
            snapshot.addRecentMessage(ChatMessage(isUser: false, text: assistant))
        }

        return (record.id, snapshot)
    }

    private static func normalizedTitle(cwd: String, rawTitle: String?, prompt: String?, fallbackID: String) -> String {
        let workspaceName = URL(fileURLWithPath: cwd).lastPathComponent
        let base = workspaceName.isEmpty ? fallbackID : workspaceName
        let snippet = normalizedInlineText(rawTitle, limit: 58)
            ?? normalizedInlineText(prompt, limit: 58)

        guard let snippet, !snippet.isEmpty else { return base }
        if snippet.localizedCaseInsensitiveContains(base) {
            return snippet
        }
        return "\(base) · \(snippet)"
    }

    private static func readRolloutSnapshot(at path: String) -> CodexRolloutSnapshot {
        guard !path.isEmpty else { return CodexRolloutSnapshot() }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let lines = recentJSONObjects(from: url) else {
            return CodexRolloutSnapshot()
        }

        var snapshot = CodexRolloutSnapshot()
        var pendingToolCallIDs = Set<String>()

        for object in lines {
            guard let type = object["type"] as? String else { continue }
            switch type {
            case "event_msg":
                applyEventMessage(
                    object["payload"] as? [String: Any],
                    snapshot: &snapshot,
                    pendingToolCallIDs: &pendingToolCallIDs
                )
            case "response_item":
                applyResponseItem(
                    object["payload"] as? [String: Any],
                    snapshot: &snapshot,
                    pendingToolCallIDs: &pendingToolCallIDs
                )
            default:
                continue
            }
        }

        if !pendingToolCallIDs.isEmpty {
            snapshot.status = .running
        }

        if snapshot.status == .idle && snapshot.lastAssistantMessage == nil {
            snapshot.lastAssistantMessage = normalizedInlineText(
                snapshot.lastToolCall?.displaySummary,
                limit: fallbackToolSummaryLimit
            )
        }

        return snapshot
    }

    private static func applyEventMessage(
        _ payload: [String: Any]?,
        snapshot: inout CodexRolloutSnapshot,
        pendingToolCallIDs: inout Set<String>
    ) {
        guard let payload, let eventType = payload["type"] as? String else { return }

        switch eventType {
        case "user_message":
            snapshot.lastUserMessage = normalizedInlineText(payload["message"] as? String, limit: 180)
            if pendingToolCallIDs.isEmpty {
                snapshot.status = .processing
            }
        case "agent_message":
            snapshot.lastAssistantMessage = normalizedInlineText(
                payload["message"] as? String,
                limit: assistantSummaryLimit
            )
            if pendingToolCallIDs.isEmpty, snapshot.status != .idle {
                snapshot.status = .processing
            }
        case "task_started":
            if pendingToolCallIDs.isEmpty {
                snapshot.status = .processing
            }
        case "task_complete":
            snapshot.lastAssistantMessage = normalizedInlineText(
                payload["last_agent_message"] as? String,
                limit: assistantSummaryLimit
            ) ?? snapshot.lastAssistantMessage
            pendingToolCallIDs.removeAll()
            snapshot.status = .idle
        default:
            break
        }
    }

    private static func applyResponseItem(
        _ payload: [String: Any]?,
        snapshot: inout CodexRolloutSnapshot,
        pendingToolCallIDs: inout Set<String>
    ) {
        guard let payload, let payloadType = payload["type"] as? String else { return }

        switch payloadType {
        case "function_call":
            if let callID = payload["call_id"] as? String, !callID.isEmpty {
                pendingToolCallIDs.insert(callID)
            }
            snapshot.lastToolCall = HistoricalToolCall(
                rawName: payload["name"] as? String ?? "tool",
                rawArguments: payload["arguments"] as? String
            )
            snapshot.status = .running
        case "function_call_output", "custom_tool_call_output":
            if let callID = payload["call_id"] as? String {
                pendingToolCallIDs.remove(callID)
            }
            if pendingToolCallIDs.isEmpty, snapshot.status == .running {
                snapshot.status = .processing
            }
        case "message":
            guard payload["role"] as? String == "assistant" else { return }
            snapshot.lastAssistantMessage = extractAssistantText(from: payload["content"]) ?? snapshot.lastAssistantMessage
            if pendingToolCallIDs.isEmpty, snapshot.status != .idle {
                snapshot.status = .processing
            }
        default:
            break
        }
    }

    private static func extractAssistantText(from rawContent: Any?) -> String? {
        guard let items = rawContent as? [[String: Any]] else { return nil }
        let fragments = items.compactMap { item -> String? in
            guard let type = item["type"] as? String else { return nil }
            guard type == "output_text" || type == "input_text" else { return nil }
            return item["text"] as? String
        }
        return normalizedInlineText(fragments.joined(separator: " "), limit: assistantSummaryLimit)
    }

    private static func recentJSONObjects(from url: URL) -> [[String: Any]]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let fileSize = try? handle.seekToEnd() else { return nil }
        let offset = fileSize > rolloutTailByteCount ? (fileSize - rolloutTailByteCount) : 0
        try? handle.seek(toOffset: offset)

        var data = handle.readDataToEndOfFile()
        if offset > 0, let firstNewline = data.firstIndex(of: 0x0A) {
            data = data[(data.index(after: firstNewline))...]
        }

        return data
            .split(separator: 0x0A)
            .compactMap { line in
                guard !line.isEmpty else { return nil }
                guard let object = try? JSONSerialization.jsonObject(with: Data(line)) else { return nil }
                return object as? [String: Any]
            }
    }

    private static func stringValue(in statement: OpaquePointer?, column: Int32) -> String {
        optionalStringValue(in: statement, column: column) ?? ""
    }

    private static func optionalStringValue(in statement: OpaquePointer?, column: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: value)
    }
}
