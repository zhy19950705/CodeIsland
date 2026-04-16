import SwiftUI

struct BashResultContent: View {
    let result: BashResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let backgroundTaskId = result.backgroundTaskId {
                Text("Background task: \(backgroundTaskId)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.blue.opacity(0.82))
            }
            if let interpretation = result.returnCodeInterpretation, !interpretation.isEmpty {
                Text(interpretation)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.46))
            }
            if !result.stdout.isEmpty {
                CodePreview(content: result.stdout, maxLines: 12)
            }
            if !result.stderr.isEmpty {
                Text(result.stderr)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.red.opacity(0.82))
                    .lineLimit(10)
            }
            if !result.hasOutput && result.backgroundTaskId == nil && result.returnCodeInterpretation == nil {
                Text("(No output)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }
}

struct GrepResultContent: View {
    let result: GrepResult
    let linkContext: EditorLinkContext

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch result.mode {
            case .filesWithMatches:
                if result.filenames.isEmpty {
                    EmptyToolResultLabel("No matches")
                } else {
                    FileListView(files: result.filenames, limit: 10, linkContext: linkContext)
                }
            case .content:
                if let content = result.content, !content.isEmpty {
                    CodePreview(content: content, maxLines: 12)
                } else {
                    EmptyToolResultLabel("No matches")
                }
            case .count:
                Text("\(result.numFiles) files matched")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.56))
            }
        }
    }
}

struct GlobResultContent: View {
    let result: GlobResult
    let linkContext: EditorLinkContext

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if result.filenames.isEmpty {
                EmptyToolResultLabel("No files")
            } else {
                FileListView(files: result.filenames, limit: 10, linkContext: linkContext)
            }
            if result.truncated {
                Text("More results were truncated")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.32))
            }
        }
    }
}

struct TaskResultContent: View {
    let result: TaskResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(result.status.capitalized)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor)
                if let totalDurationMs = result.totalDurationMs {
                    Text(formatDuration(totalDurationMs))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.42))
                }
                if let totalToolUseCount = result.totalToolUseCount {
                    Text("\(totalToolUseCount) tools")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }
            if !result.content.isEmpty {
                Text(result.content)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(6)
            }
        }
    }

    private var statusColor: Color {
        switch result.status {
        case "completed":
            return .green.opacity(0.82)
        case "failed", "error":
            return .red.opacity(0.82)
        case "in_progress":
            return .orange.opacity(0.82)
        default:
            return .white.opacity(0.56)
        }
    }

    private func formatDuration(_ milliseconds: Int) -> String {
        if milliseconds >= 60_000 {
            return "\(milliseconds / 60_000)m \((milliseconds % 60_000) / 1000)s"
        }
        if milliseconds >= 1000 {
            return "\(milliseconds / 1000)s"
        }
        return "\(milliseconds)ms"
    }
}

struct WebFetchResultContent: View {
    let result: WebFetchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("\(result.code)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(result.code < 400 ? .green.opacity(0.82) : .red.opacity(0.82))
                Text(result.url)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
            }
            if !result.result.isEmpty {
                Text(result.result)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(8)
            }
        }
    }
}

struct WebSearchResultContent: View {
    let result: WebSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if result.results.isEmpty {
                EmptyToolResultLabel("No results")
            } else {
                ForEach(Array(result.results.prefix(5).enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.blue.opacity(0.9))
                            .lineLimit(1)
                        if !item.snippet.isEmpty {
                            Text(item.snippet)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.58))
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }
}

struct EmptyToolResultLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.white.opacity(0.3))
    }
}
