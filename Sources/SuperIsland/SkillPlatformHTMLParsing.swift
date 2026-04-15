import AppKit
import Foundation

// HTML extraction is shared by multiple marketplace sources, so centralize the low-level helpers here.
extension SkillManager {
    func extractHTML(in html: String, startMarker: String, endMarker: String) -> String? {
        guard let start = html.range(of: startMarker)?.upperBound,
              let end = html.range(of: endMarker, range: start..<html.endIndex)?.lowerBound else {
            return nil
        }
        return String(html[start..<end])
    }

    func htmlToPlainText(_ html: String) -> String? {
        let wrapped = "<html><body>\(html)</body></html>"
        guard let data = wrapped.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
              ) else {
            return nil
        }
        return attributed.string
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func decodeHTML(_ string: String) -> String {
        guard let data = string.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
              ) else {
            return string
        }
        return attributed.string
    }

    func stripHTML(_ string: String) -> String {
        string.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    }

    func parseInstallReference(from command: String) -> ParsedInstallReference? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"skills add\s+(\S+)(?:\s+--skill\s+([^\s]+))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)),
              match.numberOfRanges >= 2,
              let referenceRange = Range(match.range(at: 1), in: trimmed) else {
            return nil
        }

        let skillName: String?
        if match.range(at: 2).location != NSNotFound,
           let skillRange = Range(match.range(at: 2), in: trimmed) {
            skillName = String(trimmed[skillRange])
        } else {
            skillName = nil
        }

        return ParsedInstallReference(
            reference: String(trimmed[referenceRange]),
            skillName: skillName
        )
    }

    func firstMatch(
        in html: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        let regex = try? NSRegularExpression(pattern: pattern, options: options)
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex?.firstMatch(in: html, options: [], range: nsRange),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[range])
    }

    func allMatches(
        in html: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> [String] {
        let regex = try? NSRegularExpression(pattern: pattern, options: options)
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex?.matches(in: html, options: [], range: nsRange).compactMap { match in
            guard match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: html) else {
                return nil
            }
            return String(html[range])
        } ?? []
    }
}
