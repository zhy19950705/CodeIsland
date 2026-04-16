import Foundation

/// Timeline item used by the inline session conversation view.
struct ConversationHistoryItem: Identifiable, Equatable {
    let id: String
    let kind: ConversationHistoryItemKind
    let timestamp: Date
}

/// Supported item kinds map closely to the Claude/Codex transcript block types.
enum ConversationHistoryItemKind: Equatable {
    case user(String)
    case assistant(String)
    case toolCall(ConversationToolCall)
    case thinking(String)
    case interrupted(String)
}

/// Unified status used by transcript-derived tool calls across providers.
enum ConversationToolStatus: String, Equatable, Sendable {
    case running
    case waitingForApproval
    case success
    case error
    case interrupted

    /// Short label keeps the compact transcript UI readable in the notch panel.
    var label: String {
        switch self {
        case .running:
            return "running"
        case .waitingForApproval:
            return "approval"
        case .success:
            return "done"
        case .error:
            return "error"
        case .interrupted:
            return "stopped"
        }
    }
}

/// Parsed tool-call entry with optional structured result data.
struct ConversationToolCall: Identifiable, Equatable {
    let id: String
    let name: String
    let input: [String: String]
    var status: ConversationToolStatus
    var resultText: String?
    var structuredResult: ToolResultData?

    /// Compact preview text matches the top-line summary used by the tool row header.
    var inputPreview: String {
        if let filePath = input["file_path"] ?? input["path"] ?? input["filePath"] {
            return URL(fileURLWithPath: filePath).lastPathComponent
        }
        if let command = input["command"] {
            return collapsedSingleLine(command, limit: 90)
        }
        if let pattern = input["pattern"] {
            return collapsedSingleLine(pattern, limit: 90)
        }
        if let query = input["query"] {
            return collapsedSingleLine(query, limit: 90)
        }
        if let url = input["url"] ?? input["doc_url"] {
            return collapsedSingleLine(url, limit: 90)
        }
        if let description = input["description"] ?? input["prompt"] ?? input["message"] {
            return collapsedSingleLine(description, limit: 90)
        }
        if let firstValue = input.values.first {
            return collapsedSingleLine(firstValue, limit: 90)
        }
        return ""
    }

    /// A short detail line shown under the header when there is no structured renderer.
    var fallbackDisplayText: String? {
        if let resultText, !resultText.isEmpty {
            return collapsedSingleLine(resultText, limit: 180)
        }
        if !inputPreview.isEmpty {
            return inputPreview
        }
        return nil
    }

    private func collapsedSingleLine(_ value: String, limit: Int) -> String {
        let collapsed = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit - 1)) + "…"
    }
}

/// Simple loading state keeps the inline transcript view deterministic.
struct SessionConversationState: Equatable {
    var items: [ConversationHistoryItem] = []
    var isLoading = false
    var errorText: String?
    var sourcePath: String?

    static let empty = SessionConversationState()
}

/// Internal helper for transcript parsing before items are materialized.
struct ParsedConversationToolUse {
    let id: String
    let name: String
    let input: [String: String]
}

/// Intermediate representation for provider transcript blocks.
enum ParsedConversationBlock {
    case user(String)
    case assistant(String)
    case toolUse(ParsedConversationToolUse)
    case thinking(String)
    case interrupted(String)
}
