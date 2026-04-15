import Foundation

// Down-gfm in its current Swift wrapper does not auto-enable GitHub table extensions, so tables are restored via placeholders.
enum SkillMarkdownTablePreprocessor {
    struct Result {
        let markdown: String
        let tables: [String]
    }

    static func process(_ markdown: String) -> Result {
        let lines = markdown.components(separatedBy: "\n")
        var output: [String] = []
        var tables: [String] = []
        var index = 0

        while index < lines.count {
            if isTableHeader(lines: lines, index: index) {
                let tableResult = renderTable(lines: lines, start: index)
                let token = placeholder(for: tables.count)
                tables.append(tableResult.html)
                output.append(token)
                index = tableResult.nextIndex
                continue
            }

            output.append(lines[index])
            index += 1
        }

        return Result(markdown: output.joined(separator: "\n"), tables: tables)
    }

    static func restoreTables(in html: String, tables: [String]) -> String {
        var restoredHTML = html

        for (index, tableHTML) in tables.enumerated() {
            let token = placeholder(for: index)
            restoredHTML = restoredHTML.replacingOccurrences(of: "<p>\(token)</p>", with: tableHTML)
            restoredHTML = restoredHTML.replacingOccurrences(of: token, with: tableHTML)
        }

        return restoredHTML
    }

    private static func renderTable(lines: [String], start: Int) -> (html: String, nextIndex: Int) {
        let header = parseTableRow(lines[start])
        var rows: [[String]] = []
        var index = start + 2

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("|"), !trimmed.isEmpty else { break }
            rows.append(parseTableRow(lines[index]))
            index += 1
        }

        let headerHTML = header.map { "<th>\(SkillMarkdownHTMLRenderer.renderInline($0))</th>" }.joined()
        let rowsHTML = rows.map { row in
            "<tr>\(row.map { "<td>\(SkillMarkdownHTMLRenderer.renderInline($0))</td>" }.joined())</tr>"
        }.joined()

        return (
            """
            <div class="table-scroll" tabindex="0"><table><thead><tr>\(headerHTML)</tr></thead><tbody>\(rowsHTML)</tbody></table></div>
            """,
            index
        )
    }

    private static func isTableHeader(lines: [String], index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        let header = lines[index].trimmingCharacters(in: .whitespaces)
        let divider = lines[index + 1].trimmingCharacters(in: .whitespaces)
        guard header.contains("|"), divider.contains("|") else { return false }
        let compactDivider = divider.replacingOccurrences(of: " ", with: "")
        return compactDivider.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" }
    }

    private static func parseTableRow(_ line: String) -> [String] {
        line
            .trimmingCharacters(in: CharacterSet(charactersIn: "| ").union(.whitespaces))
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func placeholder(for index: Int) -> String {
        "@@MARKDOWN_TABLE_\(index)@@"
    }
}
