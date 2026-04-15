import Foundation

// Marketplace sources often already expose structured HTML, so keep that structure instead of flattening it into plain text.
enum SkillPreviewHTMLComposer {
    static func compose(
        summary: String?,
        contentHTML: String?,
        installCommand: String?
    ) -> String? {
        var fragments: [String] = []

        if let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fragments.append("<section class=\"preview-section preview-summary\">\(summary)</section>")
        }

        if let contentHTML, !contentHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fragments.append("<section class=\"preview-section preview-content\">\(contentHTML)</section>")
        }

        if let installCommand, !installCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fragments.append(
                """
                <section class="preview-section preview-install">
                    <h2>Install</h2>
                    <pre><code class="language-bash">\(SkillMarkdownHTMLRenderer.escapeHTML(installCommand))</code></pre>
                </section>
                """
            )
        }

        let bodyHTML = fragments.joined(separator: "\n")
        return bodyHTML.isEmpty ? nil : bodyHTML
    }
}
