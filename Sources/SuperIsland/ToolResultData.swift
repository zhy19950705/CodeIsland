import Foundation

/// Structured tool result data parsed from transcript tool_result blocks.
enum ToolResultData: Equatable, Sendable {
    case read(ReadResult)
    case edit(EditResult)
    case write(WriteResult)
    case bash(BashResult)
    case grep(GrepResult)
    case glob(GlobResult)
    case task(TaskResult)
    case webFetch(WebFetchResult)
    case webSearch(WebSearchResult)
    case askUserQuestion(AskUserQuestionResult)
    case bashOutput(BashOutputResult)
    case killShell(KillShellResult)
    case exitPlanMode(ExitPlanModeResult)
    case mcp(MCPResult)
    case generic(GenericResult)
}

struct ReadResult: Equatable, Sendable {
    let filePath: String
    let content: String
    let startLine: Int
    let totalLines: Int

    var filename: String { URL(fileURLWithPath: filePath).lastPathComponent }
}

struct EditResult: Equatable, Sendable {
    let filePath: String
    let oldString: String
    let newString: String
    let replaceAll: Bool
    let userModified: Bool
    let structuredPatch: [PatchHunk]?

    var filename: String { URL(fileURLWithPath: filePath).lastPathComponent }
}

struct PatchHunk: Equatable, Sendable {
    let oldStart: Int
    let oldLines: Int
    let newStart: Int
    let newLines: Int
    let lines: [String]
}

struct WriteResult: Equatable, Sendable {
    enum WriteType: String, Equatable, Sendable {
        case create
        case overwrite
    }

    let type: WriteType
    let filePath: String
    let content: String
    let structuredPatch: [PatchHunk]?

    var filename: String { URL(fileURLWithPath: filePath).lastPathComponent }
}

struct BashResult: Equatable, Sendable {
    let stdout: String
    let stderr: String
    let interrupted: Bool
    let returnCodeInterpretation: String?
    let backgroundTaskId: String?

    var hasOutput: Bool { !stdout.isEmpty || !stderr.isEmpty }
}

struct GrepResult: Equatable, Sendable {
    enum Mode: String, Equatable, Sendable {
        case filesWithMatches = "files_with_matches"
        case content
        case count
    }

    let mode: Mode
    let filenames: [String]
    let content: String?
    let numFiles: Int
}

struct GlobResult: Equatable, Sendable {
    let filenames: [String]
    let numFiles: Int
    let truncated: Bool
}

struct TaskResult: Equatable, Sendable {
    let agentId: String
    let status: String
    let content: String
    let totalDurationMs: Int?
    let totalToolUseCount: Int?
}

struct WebFetchResult: Equatable, Sendable {
    let url: String
    let code: Int
    let codeText: String
    let bytes: Int
    let durationMs: Int
    let result: String
}

struct WebSearchResult: Equatable, Sendable {
    let query: String
    let durationSeconds: Double
    let results: [SearchResultItem]
}

struct SearchResultItem: Equatable, Sendable {
    let title: String
    let url: String
    let snippet: String
}

struct AskUserQuestionResult: Equatable, Sendable {
    let questions: [QuestionItem]
    let answers: [String: String]
}

struct QuestionItem: Equatable, Sendable {
    let question: String
    let header: String?
    let options: [QuestionOption]
}

struct QuestionOption: Equatable, Sendable {
    let label: String
    let description: String?
}

struct BashOutputResult: Equatable, Sendable {
    let shellId: String
    let status: String
    let stdout: String
    let stderr: String
    let exitCode: Int?
    let command: String?
}

struct KillShellResult: Equatable, Sendable {
    let shellId: String
    let message: String
}

struct ExitPlanModeResult: Equatable, Sendable {
    let filePath: String?
    let plan: String?
    let isAgent: Bool
}

struct MCPResult: Equatable, @unchecked Sendable {
    let serverName: String
    let toolName: String
    let rawResult: [String: Any]

    static func == (lhs: MCPResult, rhs: MCPResult) -> Bool {
        lhs.serverName == rhs.serverName
            && lhs.toolName == rhs.toolName
            && NSDictionary(dictionary: lhs.rawResult).isEqual(to: rhs.rawResult)
    }
}

struct GenericResult: Equatable, @unchecked Sendable {
    let rawContent: String?
    let rawData: [String: Any]?

    static func == (lhs: GenericResult, rhs: GenericResult) -> Bool {
        lhs.rawContent == rhs.rawContent
    }
}
