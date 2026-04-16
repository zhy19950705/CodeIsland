import Foundation
import SuperIslandCore

/// Claude transcript parsing and structured tool-result decoding.
extension ConversationParser {
    func parseClaudeConversation(sessionId: String, session: SessionSnapshot) async -> SessionConversationState {
        guard let sourcePath = session.claudeTranscriptPath
            ?? ClaudeTranscriptUsageSupport.resolveTranscriptPath(
                sessionId: session.providerSessionId ?? sessionId,
                cwd: session.cwd,
                cachedPath: session.claudeTranscriptPath
            ) else {
            return fallbackConversationState(sessionId: sessionId, session: session)
        }

        let sourceURL = URL(fileURLWithPath: sourcePath)
        let fileManager = FileManager.default
        let attributes = try? fileManager.attributesOfItem(atPath: sourcePath)
        let token = ConversationCacheToken.file(
            modifiedAt: attributes?[.modificationDate] as? Date ?? .distantPast,
            fileSize: attributes?[.size] as? UInt64 ?? 0
        )

        if let cached = cachedState(sessionId: sessionId, token: token, sourcePath: sourcePath) {
            return cached
        }

        guard let contents = try? String(contentsOf: sourceURL, encoding: .utf8) else {
            return SessionConversationState(items: [], isLoading: false, errorText: "Transcript unavailable", sourcePath: sourcePath)
        }

        var items: [ConversationHistoryItem] = []
        var toolIndexById: [String: Int] = [:]
        var toolNameById: [String: String] = [:]

        for line in contents.split(whereSeparator: \.isNewline) {
            let rawLine = String(line)

            guard let data = rawLine.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // Claude `/clear` starts a fresh visible conversation in MioIsland, so SuperIsland
            // should drop all earlier parsed timeline items instead of showing the entire
            // pre-clear history in the detail panel.
            if isClaudeClearCommand(json: json) {
                items.removeAll(keepingCapacity: true)
                toolIndexById.removeAll(keepingCapacity: true)
                toolNameById.removeAll(keepingCapacity: true)
                continue
            }

            if let message = json["message"] as? [String: Any],
               let blocks = parseClaudeMessageBlocks(json: json, message: message, toolNameById: &toolNameById) {
                for (index, block) in blocks.enumerated() {
                    if let item = makeConversationItem(
                        sessionId: sessionId,
                        timestamp: parseClaudeTimestamp(json["timestamp"]),
                        lineUUID: json["uuid"] as? String ?? UUID().uuidString,
                        blockIndex: index,
                        block: block
                    ) {
                        if case .toolCall(let tool) = item.kind {
                            toolIndexById[tool.id] = items.count
                        }
                        items.append(item)
                    }
                }
            }

            applyClaudeToolResult(
                json: json,
                items: &items,
                toolIndexById: toolIndexById,
                toolNameById: toolNameById
            )
        }

        return storeCache(sessionId: sessionId, token: token, sourcePath: sourcePath, items: items)
    }

    /// Claude message lines can contain text, thinking, or tool_use blocks in a single array payload.
    private func parseClaudeMessageBlocks(
        json: [String: Any],
        message: [String: Any],
        toolNameById: inout [String: String]
    ) -> [ParsedConversationBlock]? {
        guard json["isMeta"] as? Bool != true else { return nil }
        guard let role = message["role"] as? String else { return nil }

        if let content = message["content"] as? String {
            guard !isClaudeSystemMessage(content) else { return nil }
            let block: ParsedConversationBlock = content.hasPrefix("[Request interrupted by user")
                ? .interrupted(content)
                : (role == "user" ? .user(content) : .assistant(content))
            return [block]
        }

        guard let contentArray = message["content"] as? [[String: Any]] else { return nil }
        var blocks: [ParsedConversationBlock] = []

        for block in contentArray {
            switch block["type"] as? String {
            case "text":
                if let text = block["text"] as? String, !isClaudeSystemMessage(text) {
                    blocks.append(role == "user" ? .user(text) : .assistant(text))
                }
            case "thinking":
                if let thinking = block["thinking"] as? String, !thinking.isEmpty {
                    blocks.append(.thinking(thinking))
                }
            case "tool_use":
                guard let toolId = block["id"] as? String,
                      let toolName = block["name"] as? String else {
                    continue
                }
                toolNameById[toolId] = toolName
                blocks.append(.toolUse(
                    ParsedConversationToolUse(
                        id: toolId,
                        name: toolName,
                        input: stringifyToolInput(block["input"] as? [String: Any] ?? [:])
                    )
                ))
            default:
                continue
            }
        }

        return blocks.isEmpty ? nil : blocks
    }

    private func makeConversationItem(
        sessionId: String,
        timestamp: Date,
        lineUUID: String,
        blockIndex: Int,
        block: ParsedConversationBlock
    ) -> ConversationHistoryItem? {
        switch block {
        case .user(let text):
            return ConversationHistoryItem(id: "\(lineUUID)-user-\(blockIndex)", kind: .user(text), timestamp: timestamp)
        case .assistant(let text):
            return ConversationHistoryItem(id: "\(lineUUID)-assistant-\(blockIndex)", kind: .assistant(text), timestamp: timestamp)
        case .thinking(let text):
            return ConversationHistoryItem(id: "\(lineUUID)-thinking-\(blockIndex)", kind: .thinking(text), timestamp: timestamp)
        case .interrupted(let text):
            return ConversationHistoryItem(id: "\(lineUUID)-interrupted-\(blockIndex)", kind: .interrupted(text), timestamp: timestamp)
        case .toolUse(let tool):
            return ConversationHistoryItem(
                id: tool.id,
                kind: .toolCall(
                    ConversationToolCall(
                        id: tool.id,
                        name: tool.name,
                        input: tool.input,
                        status: .running,
                        resultText: nil,
                        structuredResult: nil
                    )
                ),
                timestamp: timestamp
            )
        }
    }

    /// Claude emits tool_result data separately from tool_use blocks, so matching is done by tool_use_id.
    private func applyClaudeToolResult(
        json: [String: Any],
        items: inout [ConversationHistoryItem],
        toolIndexById: [String: Int],
        toolNameById: [String: String]
    ) {
        guard let toolUseResult = json["toolUseResult"] as? [String: Any],
              let message = json["message"] as? [String: Any],
              let contentArray = message["content"] as? [[String: Any]] else {
            return
        }

        let stdout = toolUseResult["stdout"] as? String
        let stderr = toolUseResult["stderr"] as? String
        let topLevelToolName = json["toolName"] as? String

        for block in contentArray where block["type"] as? String == "tool_result" {
            guard let toolId = block["tool_use_id"] as? String,
                  let itemIndex = toolIndexById[toolId],
                  case .toolCall(var tool) = items[itemIndex].kind else {
                continue
            }

            let content = block["content"] as? String
            let isError = block["is_error"] as? Bool ?? false
            let toolName = topLevelToolName ?? toolNameById[toolId] ?? tool.name
            tool.resultText = firstNonEmpty(stdout, stderr, content)
            tool.status = isError ? .error : .success
            tool.structuredResult = parseStructuredToolResult(
                toolName: toolName,
                payload: toolUseResult,
                isError: isError
            )
            items[itemIndex] = ConversationHistoryItem(id: items[itemIndex].id, kind: .toolCall(tool), timestamp: items[itemIndex].timestamp)
        }
    }

    private func parseClaudeTimestamp(_ rawTimestamp: Any?) -> Date {
        guard let rawTimestamp = rawTimestamp as? String else { return Date() }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: rawTimestamp) ?? Date()
    }

    private func isClaudeSystemMessage(_ text: String) -> Bool {
        text.hasPrefix("<command-name>")
            || text.hasPrefix("<local-command")
            || text.hasPrefix("<task-notification>")
            || text.hasPrefix("<system-reminder>")
            || text.hasPrefix("Caveat:")
    }

    private func isClaudeClearCommand(json: [String: Any]) -> Bool {
        guard let message = json["message"] as? [String: Any] else { return false }

        if let content = message["content"] as? String {
            return content.contains("<command-name>/clear</command-name>")
        }

        guard let contentArray = message["content"] as? [[String: Any]] else { return false }
        for block in contentArray {
            if let text = block["text"] as? String,
               text.contains("<command-name>/clear</command-name>") {
                return true
            }
        }
        return false
    }

    /// Claude tool inputs can contain mixed scalar types; stringifying here keeps UI models small and stable.
    private func stringifyToolInput(_ input: [String: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in input {
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

    private func firstNonEmpty(_ values: String?...) -> String? {
        values.first { value in
            if let value {
                return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return false
        } ?? nil
    }
}
