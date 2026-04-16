import Foundation
import SuperIslandCore

/// Codex rollout parsing focuses on user/assistant turns plus tool-call envelopes from response items.
extension ConversationParser {
    func parseCodexConversation(
        sessionId: String,
        session: SessionSnapshot,
        sessionsBasePath: String? = nil
    ) -> SessionConversationState {
        guard let sourcePath = resolveCodexRolloutPath(
            sessionId: sessionId,
            session: session,
            sessionsBasePath: sessionsBasePath
        ) else {
            return fallbackConversationState(sessionId: sessionId, session: session)
        }

        let fileManager = FileManager.default
        let attributes = try? fileManager.attributesOfItem(atPath: sourcePath)
        let token = ConversationCacheToken.file(
            modifiedAt: attributes?[.modificationDate] as? Date ?? .distantPast,
            fileSize: attributes?[.size] as? UInt64 ?? 0
        )

        if let cached = cachedState(sessionId: sessionId, token: token, sourcePath: sourcePath) {
            return cached
        }

        guard let objects = allJSONObjects(from: URL(fileURLWithPath: sourcePath)) else {
            return SessionConversationState(items: [], isLoading: false, errorText: "Rollout unavailable", sourcePath: sourcePath)
        }

        var items: [ConversationHistoryItem] = []
        var toolIndexByCallID: [String: Int] = [:]
        var timestamp = Date()

        for object in objects {
            if let unixSeconds = numberAsDouble(object["timestamp"]) {
                timestamp = Date(timeIntervalSince1970: unixSeconds)
            }

            switch object["type"] as? String {
            case "event_msg":
                applyCodexEventMessage(
                    payload: object["payload"] as? [String: Any],
                    timestamp: timestamp,
                    items: &items
                )
            case "response_item":
                applyCodexResponseItem(
                    payload: object["payload"] as? [String: Any],
                    timestamp: timestamp,
                    items: &items,
                    toolIndexByCallID: &toolIndexByCallID
                )
            default:
                continue
            }
        }

        return storeCache(sessionId: sessionId, token: token, sourcePath: sourcePath, items: items)
    }

    /// Scanning the recent session folders avoids coupling the live panel to Codex's SQLite schema.
    private func resolveCodexRolloutPath(
        sessionId: String,
        session: SessionSnapshot,
        sessionsBasePath: String?
    ) -> String? {
        let fileManager = FileManager.default
        let sessionsBase = sessionsBasePath ?? "\(fileManager.homeDirectoryForCurrentUser.path)/.codex/sessions"
        guard fileManager.fileExists(atPath: sessionsBase) else { return nil }

        let calendar = Calendar.current
        let expectedThreadId = session.providerSessionId ?? sessionId
        let expectedCwd = session.cwd

        for daysBack in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -daysBack, to: Date()) else { continue }
            let directory = String(format: "%@/%04d/%02d/%02d", sessionsBase, calendar.component(.year, from: date), calendar.component(.month, from: date), calendar.component(.day, from: date))
            guard let files = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }

            for file in files.sorted(by: >) where file.hasSuffix(".jsonl") {
                let path = "\(directory)/\(file)"
                guard rolloutMatches(path: path, expectedThreadId: expectedThreadId, expectedCwd: expectedCwd) else { continue }
                return path
            }
        }

        return nil
    }

    private func rolloutMatches(path: String, expectedThreadId: String, expectedCwd: String?) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }

        let header = handle.readData(ofLength: 12_000)
        guard let text = String(data: header, encoding: .utf8) else { return false }

        for line in text.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if object["type"] as? String == "session_meta",
               let payload = object["payload"] as? [String: Any] {
                let threadID = payload["id"] as? String ?? payload["thread_id"] as? String
                let cwd = payload["cwd"] as? String
                if threadID == expectedThreadId {
                    if let expectedCwd {
                        return cwd == expectedCwd
                    }
                    return true
                }
            }
        }

        return false
    }

    /// Streaming the full rollout keeps long Codex chats intact without materializing the whole file as one giant string.
    private func allJSONObjects(from url: URL) -> [[String: Any]]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let chunkSize = 64 * 1024
        var objects: [[String: Any]] = []
        var pendingLineBuffer = Data()

        while true {
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: chunkSize) ?? Data()
            } catch {
                return nil
            }

            guard !chunk.isEmpty else { break }
            pendingLineBuffer.append(chunk)
            appendCompleteJSONLines(from: &pendingLineBuffer, to: &objects)
        }

        appendTrailingJSONLine(from: &pendingLineBuffer, to: &objects)
        return objects
    }

    /// Keep the last partial line buffered so chunk boundaries never corrupt the JSONL parser.
    private func appendCompleteJSONLines(from buffer: inout Data, to objects: inout [[String: Any]]) {
        let segments = buffer.split(separator: 0x0A, omittingEmptySubsequences: false)
        guard !segments.isEmpty else { return }

        let endsWithNewline = buffer.last == 0x0A
        let completeSegments = endsWithNewline ? ArraySlice(segments) : segments.dropLast()

        for line in completeSegments {
            appendJSONObject(from: Data(line), to: &objects)
        }

        buffer = endsWithNewline ? Data() : Data(segments.last ?? Data())
    }

    /// Flush the final buffered line after EOF so the parser does not silently drop the last event.
    private func appendTrailingJSONLine(from buffer: inout Data, to objects: inout [[String: Any]]) {
        guard !buffer.isEmpty else { return }
        appendJSONObject(from: buffer, to: &objects)
        buffer.removeAll(keepingCapacity: false)
    }

    /// Invalid or blank lines are ignored so one malformed event does not hide the rest of the rollout.
    private func appendJSONObject(from lineData: Data, to objects: inout [[String: Any]]) {
        guard !lineData.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
            return
        }
        objects.append(object)
    }

    private func applyCodexEventMessage(
        payload: [String: Any]?,
        timestamp: Date,
        items: inout [ConversationHistoryItem]
    ) {
        guard let payload, let eventType = payload["type"] as? String else { return }
        switch eventType {
        case "user_message":
            if let message = payload["message"] as? String, !message.isEmpty {
                items.append(ConversationHistoryItem(id: UUID().uuidString, kind: .user(message), timestamp: timestamp))
            }
        case "agent_message":
            if let message = payload["message"] as? String, !message.isEmpty {
                items.append(ConversationHistoryItem(id: UUID().uuidString, kind: .assistant(message), timestamp: timestamp))
            }
        default:
            break
        }
    }

    /// Codex function_call items are surfaced as tool rows, and outputs complete them when call_id matches.
    private func applyCodexResponseItem(
        payload: [String: Any]?,
        timestamp: Date,
        items: inout [ConversationHistoryItem],
        toolIndexByCallID: inout [String: Int]
    ) {
        guard let payload, let payloadType = payload["type"] as? String else { return }

        switch payloadType {
        case "function_call":
            let callID = payload["call_id"] as? String ?? UUID().uuidString
            let displayName = codexDisplayName(for: payload["name"] as? String ?? "tool")
            let tool = ConversationToolCall(
                id: callID,
                name: displayName,
                input: decodeCodexArguments(payload["arguments"] as? String),
                status: .running,
                resultText: nil,
                structuredResult: nil
            )
            toolIndexByCallID[callID] = items.count
            items.append(ConversationHistoryItem(id: callID, kind: .toolCall(tool), timestamp: timestamp))
        case "function_call_output", "custom_tool_call_output":
            guard let callID = payload["call_id"] as? String,
                  let index = toolIndexByCallID[callID],
                  case .toolCall(var tool) = items[index].kind else {
                return
            }
            tool.status = .success
            tool.resultText = payload["output"] as? String
                ?? payload["result"] as? String
                ?? payload["content"] as? String
            tool.structuredResult = parseStructuredCodexResult(
                toolName: tool.name,
                payload: payload,
                input: tool.input
            )
            items[index] = ConversationHistoryItem(id: items[index].id, kind: .toolCall(tool), timestamp: items[index].timestamp)
        case "message":
            guard payload["role"] as? String == "assistant" else { return }
            if let message = extractCodexAssistantMessage(payload["content"]) {
                items.append(ConversationHistoryItem(id: UUID().uuidString, kind: .assistant(message), timestamp: timestamp))
            }
        default:
            break
        }
    }

    private func codexDisplayName(for rawName: String) -> String {
        switch rawName {
        case "exec_command":
            return "Bash"
        case "apply_patch":
            return "Edit"
        case "multi_tool_use.parallel":
            return "Parallel"
        case "spawn_agent":
            return "Task"
        case "wait_agent":
            return "Wait"
        default:
            return rawName.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".", with: " ").capitalized
        }
    }

    private func decodeCodexArguments(_ rawArguments: String?) -> [String: String] {
        guard let rawArguments,
              let data = rawArguments.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

        var result: [String: String] = [:]
        for (key, value) in payload {
            switch value {
            case let string as String:
                result[key] = string
            case let int as Int:
                result[key] = String(int)
            case let bool as Bool:
                result[key] = bool ? "true" : "false"
            default:
                continue
            }
        }
        return result
    }

    private func extractCodexAssistantMessage(_ rawContent: Any?) -> String? {
        guard let items = rawContent as? [[String: Any]] else { return nil }
        let fragments = items.compactMap { item -> String? in
            guard let type = item["type"] as? String, type == "output_text" || type == "input_text" else { return nil }
            return item["text"] as? String
        }
        let text = fragments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func numberAsDouble(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }
}
