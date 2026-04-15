import Down
import Foundation

// The renderer now delegates Markdown parsing to Down-gfm so GitHub-style SKILL.md documents keep their structure.
enum SkillMarkdownHTMLRenderer {
    static func document(for markdown: String, theme: SkillMarkdownTheme = .dark) -> String {
        let bodyHTML = renderedBodyHTML(for: markdown)
        return document(bodyHTML: bodyHTML, theme: theme)
    }

    static func document(forHTML bodyHTML: String, theme: SkillMarkdownTheme = .dark) -> String {
        let decoratedBodyHTML = SkillMarkdownHTMLPostProcessor.decorate(bodyHTML)
        return document(bodyHTML: decoratedBodyHTML, theme: theme)
    }

    private static func document(bodyHTML: String, theme: SkillMarkdownTheme) -> String {
        let contentHTML = bodyHTML.isEmpty ? "<p class=\"empty\">No preview available</p>" : bodyHTML

        return """
        <!doctype html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(theme.styleSheet)
        </style>
        </head>
        <body>
        <article class="markdown-body">\(contentHTML)</article>
        </body>
        </html>
        """
    }

    private static func renderedBodyHTML(for markdown: String) -> String {
        let normalizedMarkdown = markdown.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMarkdown.isEmpty else { return "" }
        let preprocessingResult = SkillMarkdownTablePreprocessor.process(normalizedMarkdown)

        do {
            let rawHTML = try Down(markdownString: preprocessingResult.markdown).toHTML()
            let decoratedHTML = SkillMarkdownHTMLPostProcessor.decorate(rawHTML)
            return SkillMarkdownTablePreprocessor.restoreTables(in: decoratedHTML, tables: preprocessingResult.tables)
        } catch {
            // Falling back to escaped text keeps the preview readable even if a malformed document trips the parser.
            return """
            <pre class="markdown-fallback"><code>\(escapeHTML(normalizedMarkdown))</code></pre>
            """
        }
    }

    static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func escapeAttribute(_ text: String) -> String {
        escapeHTML(text).replacingOccurrences(of: "\"", with: "&quot;")
    }
}
