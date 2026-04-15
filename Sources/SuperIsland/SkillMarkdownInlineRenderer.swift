import Foundation

extension SkillMarkdownHTMLRenderer {
    static func renderInline(_ text: String) -> String {
        var result = escapeHTML(text)
        var codeSegments: [String] = []

        // Protect code spans first so later emphasis and link replacements do not mutate their contents.
        result = replacingMatches(in: result, pattern: #"`([^`]+)`"#) { match, source in
            let code = range(for: match.range(at: 1), in: source).map { String(source[$0]) } ?? ""
            let token = "@@CODE\(codeSegments.count)@@"
            codeSegments.append("<code>\(escapeHTML(code))</code>")
            return token
        }

        result = replacingMatches(in: result, pattern: #"\[([^\]]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#) { match, source in
            guard let titleRange = range(for: match.range(at: 1), in: source),
                  let urlRange = range(for: match.range(at: 2), in: source) else {
                return source
            }
            let title = String(source[titleRange])
            let url = String(source[urlRange])
            return "<a href=\"\(escapeAttribute(url))\">\(title)</a>"
        }

        result = replacingMatches(in: result, pattern: #"\*\*(.+?)\*\*"#) { match, source in
            wrapInlineMatch(match, in: source, tag: "strong")
        }
        result = replacingMatches(in: result, pattern: #"__(.+?)__"#) { match, source in
            wrapInlineMatch(match, in: source, tag: "strong")
        }
        result = replacingMatches(in: result, pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#) { match, source in
            wrapInlineMatch(match, in: source, tag: "em")
        }
        result = replacingMatches(in: result, pattern: #"(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"#) { match, source in
            wrapInlineMatch(match, in: source, tag: "em")
        }

        for (index, html) in codeSegments.enumerated() {
            result = result.replacingOccurrences(of: "@@CODE\(index)@@", with: html)
        }
        return result
    }

    static func wrapInlineMatch(_ match: NSTextCheckingResult, in source: String, tag: String) -> String {
        guard let innerRange = range(for: match.range(at: 1), in: source) else { return source }
        return "<\(tag)>\(String(source[innerRange]))</\(tag)>"
    }

    static func replacingMatches(
        in source: String,
        pattern: String,
        using transform: (NSTextCheckingResult, String) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return source }
        let matches = regex.matches(in: source, options: [], range: NSRange(source.startIndex..., in: source))
        guard !matches.isEmpty else { return source }

        var result = source
        for match in matches.reversed() {
            guard let fullRange = range(for: match.range, in: result) else { continue }
            result.replaceSubrange(fullRange, with: transform(match, result))
        }
        return result
    }

    static func range(for nsRange: NSRange, in source: String) -> Range<String.Index>? {
        Range(nsRange, in: source)
    }
}
