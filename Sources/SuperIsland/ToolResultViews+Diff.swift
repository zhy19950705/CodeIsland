import SwiftUI

struct ReadResultContent: View {
    let result: ReadResult
    let linkContext: EditorLinkContext

    var body: some View {
        if !result.content.isEmpty {
            FileCodeView(
                filePath: result.filePath,
                filename: result.filename,
                content: result.content,
                startLine: max(result.startLine, 1),
                totalLines: max(result.totalLines, result.content.components(separatedBy: "\n").count),
                maxLines: 10,
                linkContext: linkContext
            )
        }
    }
}

struct EditResultContent: View {
    let result: EditResult
    let toolInput: [String: String]
    let linkContext: EditorLinkContext

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !effectiveOldString.isEmpty || !effectiveNewString.isEmpty {
                SimpleDiffView(
                    oldString: effectiveOldString,
                    newString: effectiveNewString,
                    filename: result.filename,
                    filePath: result.filePath,
                    linkContext: linkContext
                )
            }
            if result.userModified {
                Text("补丁应用前用户已修改该文件")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange.opacity(0.82))
            }
        }
    }

    private var effectiveOldString: String { result.oldString.isEmpty ? (toolInput["old_string"] ?? toolInput["oldString"] ?? "") : result.oldString }
    private var effectiveNewString: String { result.newString.isEmpty ? (toolInput["new_string"] ?? toolInput["newString"] ?? "") : result.newString }
}

struct WriteResultContent: View {
    let result: WriteResult
    let linkContext: EditorLinkContext

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(result.type == .create ? "已创建" : "已写入")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                EditorFileLinkButton(filePath: result.filePath, line: nil, linkContext: linkContext) {
                    Text(result.filename)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.76))
                }
            }
            if result.type == .create && !result.content.isEmpty {
                CodePreview(content: result.content, maxLines: 8)
            } else if let patch = result.structuredPatch, !patch.isEmpty {
                DiffView(patches: patch)
            }
        }
    }
}

struct DiffView: View {
    let patches: [PatchHunk]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(patches.prefix(3).enumerated()), id: \.offset) { _, patch in
                VStack(alignment: .leading, spacing: 1) {
                    Text("@@ -\(patch.oldStart),\(patch.oldLines) +\(patch.newStart),\(patch.newLines) @@")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.cyan.opacity(0.84))
                    ForEach(Array(patch.lines.prefix(12).enumerated()), id: \.offset) { _, line in
                        DiffLineView(line: line)
                    }
                }
            }
        }
    }
}

struct DiffLineView: View {
    let line: String

    var body: some View {
        Text(line)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(lineType.textColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(lineType.backgroundColor)
    }

    private var lineType: DiffLineType {
        if line.hasPrefix("+") {
            return .added
        }
        if line.hasPrefix("-") {
            return .removed
        }
        return .context
    }
}

private enum DiffLineType {
    case added
    case removed
    case context

    var textColor: Color {
        switch self {
        case .added:
            return Color(red: 0.45, green: 0.86, blue: 0.48)
        case .removed:
            return Color(red: 1.0, green: 0.55, blue: 0.55)
        case .context:
            return .white.opacity(0.56)
        }
    }

    var backgroundColor: Color {
        switch self {
        case .added:
            return Color(red: 0.18, green: 0.32, blue: 0.18).opacity(0.38)
        case .removed:
            return Color(red: 0.34, green: 0.16, blue: 0.16).opacity(0.36)
        case .context:
            return .clear
        }
    }
}

/// Simple LCS-based diff view keeps edits readable without a full patch parser dependency.
struct SimpleDiffView: View {
    let oldString: String
    let newString: String
    var filename: String? = nil
    var filePath: String? = nil
    var linkContext: EditorLinkContext = .empty

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let filename {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                    if let filePath {
                        EditorFileLinkButton(filePath: filePath, line: nil, linkContext: linkContext) {
                            Text(filename)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.76))
                        }
                    } else {
                        Text(filename)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.76))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06))
            }

            ForEach(Array(diffLines.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 0) {
                    Text("\(line.lineNumber)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(width: 28, alignment: .trailing)
                        .padding(.trailing, 8)
                    Text(line.text.isEmpty ? " " : line.text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(line.type.textColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(line.type.backgroundColor)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var diffLines: [SimpleDiffLine] {
        let oldLines = oldString.components(separatedBy: "\n")
        let newLines = newString.components(separatedBy: "\n")
        let lcs = computeLCS(oldLines, newLines)

        var result: [SimpleDiffLine] = []
        var oldIndex = 0
        var newIndex = 0
        var lcsIndex = 0

        while oldIndex < oldLines.count || newIndex < newLines.count {
            if result.count >= 16 { break }
            let lcsLine = lcsIndex < lcs.count ? lcs[lcsIndex] : nil

            if oldIndex < oldLines.count && (lcsLine == nil || oldLines[oldIndex] != lcsLine) {
                result.append(SimpleDiffLine(text: oldLines[oldIndex], type: .removed, lineNumber: oldIndex + 1))
                oldIndex += 1
            } else if newIndex < newLines.count && (lcsLine == nil || newLines[newIndex] != lcsLine) {
                result.append(SimpleDiffLine(text: newLines[newIndex], type: .added, lineNumber: newIndex + 1))
                newIndex += 1
            } else {
                oldIndex += 1
                newIndex += 1
                lcsIndex += 1
            }
        }

        return result
    }

    private func computeLCS(_ lhs: [String], _ rhs: [String]) -> [String] {
        let rows = lhs.count
        let columns = rhs.count
        var table = Array(repeating: Array(repeating: 0, count: columns + 1), count: rows + 1)

        if rows > 0 && columns > 0 {
            for row in 1...rows {
                for column in 1...columns {
                    if lhs[row - 1] == rhs[column - 1] {
                        table[row][column] = table[row - 1][column - 1] + 1
                    } else {
                        table[row][column] = max(table[row - 1][column], table[row][column - 1])
                    }
                }
            }
        }

        var lcs: [String] = []
        var row = rows
        var column = columns
        while row > 0 && column > 0 {
            if lhs[row - 1] == rhs[column - 1] {
                lcs.append(lhs[row - 1])
                row -= 1
                column -= 1
            } else if table[row - 1][column] > table[row][column - 1] {
                row -= 1
            } else {
                column -= 1
            }
        }
        return lcs.reversed()
    }
}

private struct SimpleDiffLine {
    let text: String
    let type: DiffLineType
    let lineNumber: Int
}
