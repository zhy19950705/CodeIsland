import SwiftUI

/// Dispatches structured tool results into specialized renderers.
struct ToolResultContent: View {
    let tool: ConversationToolCall
    let linkContext: EditorLinkContext

    var body: some View {
        if let structured = tool.structuredResult {
            switch structured {
            case .read(let result):
                ReadResultContent(result: result, linkContext: linkContext)
            case .edit(let result):
                EditResultContent(result: result, toolInput: tool.input, linkContext: linkContext)
            case .write(let result):
                WriteResultContent(result: result, linkContext: linkContext)
            case .bash(let result):
                BashResultContent(result: result)
            case .grep(let result):
                GrepResultContent(result: result, linkContext: linkContext)
            case .glob(let result):
                GlobResultContent(result: result, linkContext: linkContext)
            case .task(let result):
                TaskResultContent(result: result)
            case .webFetch(let result):
                WebFetchResultContent(result: result)
            case .webSearch(let result):
                WebSearchResultContent(result: result)
            case .askUserQuestion(let result):
                AskUserQuestionResultContent(result: result)
            case .bashOutput(let result):
                BashOutputResultContent(result: result)
            case .killShell(let result):
                KillShellResultContent(result: result)
            case .exitPlanMode(let result):
                ExitPlanModeResultContent(result: result, linkContext: linkContext)
            case .mcp(let result):
                MCPResultContent(result: result)
            case .generic(let result):
                GenericResultContent(result: result)
            }
        } else if tool.name == "Edit" {
            EditInputDiffView(input: tool.input, linkContext: linkContext)
        } else if let fallback = tool.fallbackDisplayText {
            GenericTextContent(text: fallback)
        }
    }
}

/// Fallback diff uses tool input when a transcript did not emit a structured edit result.
struct EditInputDiffView: View {
    let input: [String: String]
    let linkContext: EditorLinkContext

    var body: some View {
        if !oldString.isEmpty || !newString.isEmpty {
            SimpleDiffView(
                oldString: oldString,
                newString: newString,
                filename: filename,
                filePath: filePath,
                linkContext: linkContext
            )
        }
    }

    private var filename: String {
        if let filePath {
            return URL(fileURLWithPath: filePath).lastPathComponent
        }
        return "file"
    }

    private var filePath: String? { input["file_path"] ?? input["filePath"] }
    private var oldString: String { input["old_string"] ?? input["oldString"] ?? "" }
    private var newString: String { input["new_string"] ?? input["newString"] ?? "" }
}

/// Compact file preview with optional line numbers for read results.
struct FileCodeView: View {
    let filePath: String
    let filename: String
    let content: String
    let startLine: Int
    let totalLines: Int
    let maxLines: Int
    let linkContext: EditorLinkContext

    var body: some View {
        let lines = content.components(separatedBy: "\n")
        let visibleLines = Array(lines.prefix(maxLines))

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                EditorFileLinkButton(
                    filePath: filePath,
                    line: max(startLine, 1),
                    linkContext: linkContext
                ) {
                    Text(filename)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.74))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06))

            ForEach(Array(visibleLines.enumerated()), id: \.offset) { index, line in
                HStack(spacing: 0) {
                    Text("\(startLine + index)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.32))
                        .frame(width: 30, alignment: .trailing)
                        .padding(.trailing, 8)
                    Text(line.isEmpty ? " " : line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 8)
                .background(Color.white.opacity(0.04))
            }

            if startLine > 1 || totalLines > visibleLines.count {
                Text("…")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Shared mini code preview keeps shell and file outputs visually consistent.
struct CodePreview: View {
    let content: String
    let maxLines: Int

    var body: some View {
        let lines = content.components(separatedBy: "\n")
        let visibleLines = Array(lines.prefix(maxLines))
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(visibleLines.enumerated()), id: \.offset) { _, line in
                Text(line.isEmpty ? " " : line)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.76))
            }
            if lines.count > maxLines {
                Text("+\(lines.count - maxLines) more lines")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.34))
                    .padding(.top, 2)
            }
        }
    }
}

/// Small list renderer for search, grep, and glob outputs.
struct FileListView: View {
    let files: [String]
    let limit: Int
    let linkContext: EditorLinkContext

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(files.prefix(limit).enumerated()), id: \.offset) { _, file in
                HStack(spacing: 4) {
                    Image(systemName: "doc")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                    EditorFileLinkButton(filePath: file, line: nil, linkContext: linkContext) {
                        Text(URL(fileURLWithPath: file).lastPathComponent)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(1)
                    }
                }
            }
            if files.count > limit {
                Text("+\(files.count - limit) more")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.34))
            }
        }
    }
}
