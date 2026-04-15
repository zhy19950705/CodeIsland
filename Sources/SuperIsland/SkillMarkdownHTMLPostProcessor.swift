import Foundation

// Small HTML post-processing keeps the preview styling hooks local without reimplementing Markdown parsing.
enum SkillMarkdownHTMLPostProcessor {
    // Regex replacement is enough here because Down emits stable HTML for fenced code blocks and tables.
    private static let codeBlockPattern = try! NSRegularExpression(
        pattern: #"<pre><code(?: class="([^"]*)")?>(.*?)</code></pre>"#,
        options: [.dotMatchesLineSeparators]
    )
    private static let tablePattern = try! NSRegularExpression(
        pattern: #"<table>(.*?)</table>"#,
        options: [.dotMatchesLineSeparators]
    )

    static func decorate(_ html: String) -> String {
        let withTables = replacingMatches(in: html, using: tablePattern, transform: wrapTable(match:in:))
        return replacingMatches(in: withTables, using: codeBlockPattern, transform: wrapCodeBlock(match:in:))
    }

    private static func wrapTable(match: NSTextCheckingResult, in html: String) -> String {
        let contentRange = match.range(at: 1)
        guard let content = substring(in: html, range: contentRange) else {
            return substring(in: html, range: match.range) ?? ""
        }

        return """
        <div class="table-scroll" tabindex="0"><table>\(content)</table></div>
        """
    }

    private static func wrapCodeBlock(match: NSTextCheckingResult, in html: String) -> String {
        let classList = substring(in: html, range: match.range(at: 1)) ?? ""
        let codeHTML = substring(in: html, range: match.range(at: 2)) ?? ""
        let language = languageLabel(from: classList)
        let normalizedClassList = normalizedCodeClasses(from: classList, language: language)
        let classAttribute = normalizedClassList.isEmpty ? "" : " class=\"\(escapeAttribute(normalizedClassList))\""

        return """
        <div class="code-block">
            <div class="code-toolbar">
                <span class="code-language">\(escapeHTML(language))</span>
                <button class="copy-button" type="button">Copy</button>
            </div>
            <pre><code\(classAttribute)>\(codeHTML)</code></pre>
        </div>
        """
    }

    private static func normalizedCodeClasses(from classList: String, language: String) -> String {
        let trimmed = classList.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "language-\(language)"
        }
        if trimmed.contains("language-") {
            return trimmed
        }
        return "\(trimmed) language-\(language)"
    }

    private static func languageLabel(from classList: String) -> String {
        let classes = classList
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        let languageClass = classes.first { $0.hasPrefix("language-") } ?? ""
        let rawLanguage = languageClass.replacingOccurrences(of: "language-", with: "")
        return rawLanguage.isEmpty ? "text" : rawLanguage
    }

    private static func replacingMatches(
        in html: String,
        using regex: NSRegularExpression,
        transform: (NSTextCheckingResult, String) -> String
    ) -> String {
        // Replacing from the end keeps the original match offsets valid without building a heavier HTML DOM layer.
        var decoratedHTML = html
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed()

        for match in matches {
            guard let range = Range(match.range, in: decoratedHTML) else { continue }
            decoratedHTML.replaceSubrange(range, with: transform(match, html))
        }

        return decoratedHTML
    }

    private static func substring(in html: String, range: NSRange) -> String? {
        guard range.location != NSNotFound, let stringRange = Range(range, in: html) else { return nil }
        return String(html[stringRange])
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttribute(_ text: String) -> String {
        escapeHTML(text).replacingOccurrences(of: "\"", with: "&quot;")
    }
}
