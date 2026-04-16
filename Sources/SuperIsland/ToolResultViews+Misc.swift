import SwiftUI

struct AskUserQuestionResultContent: View {
    let result: AskUserQuestionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(result.questions.enumerated()), id: \.offset) { index, question in
                VStack(alignment: .leading, spacing: 4) {
                    Text(question.question)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                    if let answer = result.answers["\(index)"] {
                        Text(answer)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.green.opacity(0.82))
                    }
                }
            }
        }
    }
}

struct BashOutputResultContent: View {
    let result: BashOutputResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(result.status)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.46))
                if let exitCode = result.exitCode {
                    Text("退出码 \(exitCode)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(exitCode == 0 ? .green.opacity(0.82) : .red.opacity(0.82))
                }
            }
            if !result.stdout.isEmpty {
                CodePreview(content: result.stdout, maxLines: 10)
            }
            if !result.stderr.isEmpty {
                Text(result.stderr)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.red.opacity(0.82))
                    .lineLimit(8)
            }
        }
    }
}

struct KillShellResultContent: View {
    let result: KillShellResult

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(.red.opacity(0.78))
            Text(result.message.isEmpty ? "Shell \(result.shellId) 已停止" : result.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

struct ExitPlanModeResultContent: View {
    let result: ExitPlanModeResult
    let linkContext: EditorLinkContext

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let filePath = result.filePath {
                EditorFileLinkButton(filePath: filePath, line: nil, linkContext: linkContext) {
                    Text(URL(fileURLWithPath: filePath).lastPathComponent)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.68))
                }
            }
            if let plan = result.plan, !plan.isEmpty {
                Text(plan)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(6)
            }
        }
    }
}

struct MCPResultContent: View {
    let result: MCPResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "puzzlepiece")
                    .font(.system(size: 11))
                Text("\(titleCased(result.serverName)) · \(titleCased(result.toolName))")
                    .font(.system(size: 11, design: .monospaced))
            }
            .foregroundStyle(.purple.opacity(0.8))

            ForEach(Array(result.rawResult.prefix(5)), id: \.key) { key, value in
                HStack(alignment: .top, spacing: 4) {
                    Text("\(key):")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.42))
                    Text(String(describing: value))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                }
            }
        }
    }

    private func titleCased(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".", with: " ").capitalized
    }
}

struct GenericResultContent: View {
    let result: GenericResult

    var body: some View {
        if let rawContent = result.rawContent, !rawContent.isEmpty {
            GenericTextContent(text: rawContent)
        } else {
            EmptyToolResultLabel("已完成")
        }
    }
}

struct GenericTextContent: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.white.opacity(0.58))
            .lineLimit(12)
    }
}
