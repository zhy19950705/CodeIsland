import SwiftUI

/// Lightweight markdown renderer for chat transcripts without pulling in another cmark-based dependency.
struct MarkdownText: View {
    let text: String
    let baseColor: Color
    let fontSize: CGFloat
    let linkContext: EditorLinkContext

    init(
        _ text: String,
        color: Color = .white.opacity(0.88),
        fontSize: CGFloat = 12,
        linkContext: EditorLinkContext = .empty
    ) {
        self.text = text
        self.baseColor = color
        self.fontSize = fontSize
        self.linkContext = linkContext
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(parseBlocks(text).enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block, baseColor: baseColor, fontSize: fontSize)
            }
        }
        // Transcript markdown can contain relative file links, so the renderer intercepts them before AppKit hands them to Finder.
        .environment(
            \.openURL,
             OpenURLAction { url in
                 EditorLinkSupport.open(url: url, context: linkContext)
             }
        )
    }

    /// A small block parser is enough for transcript rendering and avoids the cmark symbol clash with Down-gfm.
    private func parseBlocks(_ source: String) -> [MarkdownBlock] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3))
                index += 1
                var codeLines: [String] = []
                while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                blocks.append(.code(language: language, code: codeLines.joined(separator: "\n")))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    guard current.hasPrefix(">") else { break }
                    quoteLines.append(String(current.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }

            if let heading = headingBlock(for: trimmed) {
                blocks.append(heading)
                index += 1
                continue
            }

            if listMarker(for: trimmed) != nil {
                let ordered = orderedListPrefix(for: trimmed) != nil
                var items: [String] = []
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    guard let marker = listMarker(for: current) else { break }
                    items.append(String(current.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(ordered ? .orderedList(items) : .unorderedList(items))
                continue
            }

            var paragraphLines: [String] = [trimmed]
            index += 1
            while index < lines.count {
                let current = lines[index].trimmingCharacters(in: .whitespaces)
                guard !current.isEmpty else { break }
                guard !current.hasPrefix("```"),
                      !current.hasPrefix(">"),
                      headingBlock(for: current) == nil,
                      listMarker(for: current) == nil else {
                    break
                }
                paragraphLines.append(current)
                index += 1
            }
            blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
        }

        return blocks
    }

    private func headingBlock(for line: String) -> MarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }
        guard !hashes.isEmpty, hashes.count <= 6 else { return nil }
        let content = line.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }
        return .heading(level: hashes.count, text: content)
    }

    private func listMarker(for line: String) -> String? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return String(line.prefix(2))
        }
        return orderedListPrefix(for: line)
    }

    private func orderedListPrefix(for line: String) -> String? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let suffix = line.dropFirst(digits.count)
        guard suffix.hasPrefix(". ") else { return nil }
        return String(line.prefix(digits.count + 2))
    }
}

private enum MarkdownBlock {
    case paragraph(String)
    case heading(level: Int, text: String)
    case quote(String)
    case unorderedList([String])
    case orderedList([String])
    case code(language: String, code: String)
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let baseColor: Color
    let fontSize: CGFloat

    var body: some View {
        switch block {
        case .paragraph(let text):
            MarkdownInlineText(text: text, baseColor: baseColor, fontSize: fontSize)
        case .heading(let level, let text):
            MarkdownInlineText(text: text, baseColor: baseColor, fontSize: headingFontSize(level))
                .fontWeight(.semibold)
        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(baseColor.opacity(0.35))
                    .frame(width: 2)
                MarkdownInlineText(text: text, baseColor: baseColor.opacity(0.85), fontSize: fontSize)
            }
        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.system(size: fontSize, weight: .semibold))
                            .foregroundStyle(baseColor.opacity(0.72))
                            .frame(width: 10, alignment: .center)
                        MarkdownInlineText(text: item, baseColor: baseColor, fontSize: fontSize)
                    }
                }
            }
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.system(size: fontSize, weight: .semibold))
                            .foregroundStyle(baseColor.opacity(0.72))
                            .frame(width: 20, alignment: .trailing)
                        MarkdownInlineText(text: item, baseColor: baseColor, fontSize: fontSize)
                    }
                }
            }
        case .code(_, let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.86))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
        }
    }

    private func headingFontSize(_ level: Int) -> CGFloat {
        switch level {
        case 1:
            return max(fontSize + 4, 15)
        case 2:
            return max(fontSize + 2, 14)
        default:
            return max(fontSize + 1, 13)
        }
    }
}

private struct MarkdownInlineText: View {
    let text: String
    let baseColor: Color
    let fontSize: CGFloat

    var body: some View {
        Text(attributedText)
            .font(.system(size: fontSize))
            .foregroundStyle(baseColor)
    }

    /// AttributedString gives us inline emphasis, links, code spans, and strikethrough without a full parser dependency.
    private var attributedText: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        if let parsed = try? AttributedString(markdown: text, options: options) {
            return parsed
        }
        return AttributedString(text)
    }
}
