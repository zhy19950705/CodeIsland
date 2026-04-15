import Foundation

// Mayidata uses custom HTML pages and install-command snippets, so parsing stays local to this source file.
extension SkillManager {
    func fetchMayidataItems(
        query: String,
        limit: Int
    ) async throws -> [SkillMarketplaceItem] {
        var components = URLComponents(url: Self.mayidataSkillHubURL, resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        }

        var request = URLRequest(url: components.url!)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.google.com/", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw SkillPlatformError.gitFailed("Guandata Skill Hub request failed")
        }

        var items = parseMayidataListingHTML(html)
        if !query.isEmpty {
            let needle = query.lowercased()
            items = items.filter { item in
                item.title.lowercased().contains(needle)
                    || item.repoFullName.lowercased().contains(needle)
                    || item.description.lowercased().contains(needle)
                    || item.topics.contains(where: { $0.lowercased().contains(needle) })
            }
        }
        return Array(items.prefix(limit))
    }

    func previewDocumentFromMayidata(for item: SkillMarketplaceItem) async throws -> SkillPreviewDocument {
        var request = URLRequest(url: item.htmlURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.google.com/", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw SkillPlatformError.gitFailed("Guandata Skill Hub detail page could not be loaded")
        }

        let title = firstMatch(in: html, pattern: #"<h1>(.*?)</h1>"#).map(decodeHTML) ?? item.title
        let description = firstMatch(
            in: html,
            pattern: #"<div class="detail-summary">.*?<div class="detail-summary__title-row">.*?</div><p>(.*?)</p></div>"#,
            options: [.dotMatchesLineSeparators]
        ).map(decodeHTML) ?? item.description
        let repository = firstMatch(in: html, pattern: #"<li>仓库：<!-- -->(.*?)</li>"#).map(decodeHTML) ?? item.repoFullName
        let author = firstMatch(
            in: html,
            pattern: #"<li>作者：<!-- -->\s*(?:<span class="detail-author">)?(.*?)(?:</span>)?</li>"#,
            options: [.dotMatchesLineSeparators]
        ).map(stripHTML).map(decodeHTML)
        let updatedAt = firstMatch(in: html, pattern: #"<li>更新时间：<!-- -->(.*?)</li>"#).map(decodeHTML)
        let createdAt = firstMatch(in: html, pattern: #"<li>创建时间：<!-- -->(.*?)</li>"#).map(decodeHTML)
        let installCommand = firstMatch(
            in: html,
            pattern: #"<pre class="install-command"><code>(.*?)</code></pre>"#,
            options: [.dotMatchesLineSeparators]
        ).map(decodeHTML)

        let markdownHTML = firstMatch(
            in: html,
            pattern: #"<section class="markdown-panel">.*?<div class="markdown-content">(.*?)</div></section>"#,
            options: [.dotMatchesLineSeparators]
        )
        let bodyHTML = SkillPreviewHTMLComposer.compose(
            summary: "<p>\(SkillMarkdownHTMLRenderer.escapeHTML(description))</p>",
            contentHTML: markdownHTML,
            installCommand: installCommand
        )
        let markdownBody = markdownHTML.flatMap(htmlToPlainText)?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let installSection = installCommand.map { "Install\n\n\($0)" } ?? ""
        let body = [
            description.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            markdownBody,
            installSection,
        ].filter { !$0.isEmpty }.joined(separator: "\n\n")

        var metadata: [String] = ["Source Guandata Skill Hub"]
        if !repository.isEmpty { metadata.append("Repository \(repository)") }
        if let author, !author.isEmpty { metadata.append("Author \(author)") }
        if let updatedAt, !updatedAt.isEmpty { metadata.append("Updated \(updatedAt)") }
        if let createdAt, !createdAt.isEmpty { metadata.append("Created \(createdAt)") }
        if !item.topics.isEmpty { metadata.append("Tags \(item.topics.joined(separator: ", "))") }

        return SkillPreviewDocument(
            id: "mayidata:\(item.id)",
            title: title,
            subtitle: repository,
            body: body.isEmpty ? item.description : body,
            bodyHTML: bodyHTML,
            sourceURL: item.htmlURL,
            metadata: metadata
        )
    }

    func fetchMayidataInstallReference(for item: SkillMarketplaceItem) async throws -> ParsedInstallReference {
        var request = URLRequest(url: item.htmlURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.google.com/", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw SkillPlatformError.gitFailed("Guandata Skill Hub detail page could not be loaded")
        }

        let installCommand = firstMatch(
            in: html,
            pattern: #"<pre class="install-command"><code>(.*?)</code></pre>"#,
            options: [.dotMatchesLineSeparators]
        ).map(decodeHTML)

        guard let installCommand,
              let parsedReference = parseInstallReference(from: installCommand) else {
            throw SkillPlatformError.invalidRepositoryReference
        }

        return parsedReference
    }

    func parseMayidataListingHTML(_ html: String) -> [SkillMarketplaceItem] {
        let cardPattern = #"<a class="skill-card" href="([^"]+)">(.*?)</a>"#
        let regex = try? NSRegularExpression(pattern: cardPattern, options: [.dotMatchesLineSeparators])
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)

        return regex?.matches(in: html, options: [], range: nsRange).compactMap { match in
            guard match.numberOfRanges >= 3,
                  let hrefRange = Range(match.range(at: 1), in: html),
                  let bodyRange = Range(match.range(at: 2), in: html) else {
                return nil
            }

            let href = String(html[hrefRange])
            let body = String(html[bodyRange])
            guard let url = URL(string: href, relativeTo: Self.mayidataSkillHubURL)?.absoluteURL else {
                return nil
            }

            let repo = firstMatch(in: body, pattern: #"<p class="skill-card__repo">(.*?)</p>"#).map(decodeHTML) ?? ""
            let title = firstMatch(in: body, pattern: #"<h3>(.*?)</h3>"#).map(decodeHTML) ?? ""
            let description = firstMatch(
                in: body,
                pattern: #"<h3>.*?</h3><p>(.*?)</p>"#,
                options: [.dotMatchesLineSeparators]
            ).map(decodeHTML) ?? "No description"
            let author = firstMatch(in: body, pattern: #"<p class="skill-card__author">(.*?)</p>"#).map(decodeHTML)
            let updatedAtRaw = firstMatch(in: body, pattern: #"<p class="skill-card__updated-at">更新于 <!-- -->(.*?)</p>"#).map(decodeHTML)
            let tags = allMatches(in: body, pattern: #"<span class="skill-pill[^"]*">(.*?)</span>"#).map(decodeHTML)

            return SkillMarketplaceItem(
                id: "mayidata:\(href)",
                source: .mayidata,
                title: title,
                repoFullName: repo,
                description: description,
                htmlURL: url,
                installReference: repo,
                stars: nil,
                updatedAt: updatedAtRaw.flatMap(parseMayidataDate),
                language: nil,
                topics: tags.isEmpty ? (author.flatMap { $0.isEmpty ? nil : [$0] } ?? []) : tags,
                installsText: nil,
                rank: nil,
                canInstallDirectly: true
            )
        } ?? []
    }

    func parseMayidataDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy/M/d"
        return formatter.date(from: string.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
