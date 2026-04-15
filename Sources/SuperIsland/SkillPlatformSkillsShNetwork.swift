import Foundation

// skills.sh has both JSON and HTML paths; keep those source-specific rules together.
extension SkillManager {
    func fetchSkillsShItems(
        query: String,
        leaderboard: SkillsShLeaderboardKind,
        limit: Int
    ) async throws -> [SkillMarketplaceItem] {
        if !query.isEmpty {
            return try await searchSkillsShItems(query: query, limit: limit)
        }

        let targetLeaderboard: SkillsShLeaderboardKind = query.isEmpty ? leaderboard : .allTime
        var request = URLRequest(url: URL(string: "https://skills.sh\(targetLeaderboard.path)")!)
        request.setValue("SuperIsland", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw SkillPlatformError.gitFailed("skills.sh request failed")
        }

        return Array(parseSkillsShLeaderboardHTML(html).prefix(limit))
    }

    func searchSkillsShItems(
        query: String,
        limit: Int
    ) async throws -> [SkillMarketplaceItem] {
        var components = URLComponents(string: "https://skills.sh/api/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SuperIsland", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw SkillPlatformError.gitFailed("skills.sh search request failed")
        }

        let payload = try JSONDecoder().decode(SkillsShSearchResponse.self, from: data)
        return payload.skills.map { skill in
            let skillPath = skill.id.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let detailURL = URL(string: "https://skills.sh/\(skillPath)")!

            return SkillMarketplaceItem(
                id: "skills-sh:\(skill.id)",
                source: .skillsSh,
                title: skill.name,
                repoFullName: skill.source,
                description: "\(skill.name) from \(skill.source)",
                htmlURL: detailURL,
                installReference: skill.source,
                stars: nil,
                updatedAt: nil,
                language: nil,
                topics: [skill.skillId],
                installsText: String(skill.installs),
                rank: nil,
                canInstallDirectly: true
            )
        }
    }

    func previewDocumentFromSkillsSh(for item: SkillMarketplaceItem) async throws -> SkillPreviewDocument {
        var request = URLRequest(url: item.htmlURL)
        request.setValue("SuperIsland", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw SkillPlatformError.gitFailed("skills.sh detail page could not be loaded")
        }

        let summaryHTML = extractHTML(
            in: html,
            startMarker: "Summary</div>",
            endMarker: "<div class=\"bg-background\"><div class=\"flex items-center gap-2 text-sm font-mono text-white mb-4 pb-4 border-b border-border\"><span>SKILL.md</span></div>"
        )
        let skillHTML = extractHTML(
            in: html,
            startMarker: "<span>SKILL.md</span></div>",
            endMarker: "<div class=\" lg:col-span-3\">"
        )
        let bodyHTML = SkillPreviewHTMLComposer.compose(summary: summaryHTML, contentHTML: skillHTML, installCommand: nil)
        let sections: [String?] = [summaryHTML.flatMap(htmlToPlainText), skillHTML.flatMap(htmlToPlainText)]
        let body = sections
            .compactMap { $0?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        return SkillPreviewDocument(
            id: "skills-sh:\(item.id)",
            title: item.title,
            subtitle: item.repoFullName,
            body: body.isEmpty ? item.description : body,
            bodyHTML: bodyHTML,
            sourceURL: item.htmlURL,
            metadata: [
                item.installsText.map { "Weekly installs \($0)" },
                "Source skills.sh",
                item.repoFullName.isEmpty ? nil : "Repository \(item.repoFullName)",
                item.stars.map { "GitHub stars \($0)" },
            ].compactMap { $0 }
        )
    }

    func parseSkillsShLeaderboardHTML(_ html: String) -> [SkillMarketplaceItem] {
        let pattern = #"<a class="group grid [^"]*" href="(/([^"/]+/[^"/]+/[^"]+))">.*?<span class="text-sm lg:text-base text-\(--ds-gray-600\) font-mono">(\d+)</span>.*?<h3 class="font-semibold text-foreground truncate whitespace-nowrap">(.*?)</h3><p class="text-xs lg:text-sm text-\(--ds-gray-600\) font-mono mt-0\.5 lg:mt-0 truncate">(.*?)</p>.*?<span class="font-mono text-sm text-foreground">(.*?)</span>"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)

        return regex?.matches(in: html, options: [], range: nsRange).compactMap { match in
            guard match.numberOfRanges >= 7,
                  let pathRange = Range(match.range(at: 1), in: html),
                  let repoRange = Range(match.range(at: 2), in: html),
                  let rankRange = Range(match.range(at: 3), in: html),
                  let titleRange = Range(match.range(at: 4), in: html),
                  let repoFullNameRange = Range(match.range(at: 5), in: html),
                  let installsRange = Range(match.range(at: 6), in: html),
                  let url = URL(string: "https://skills.sh" + String(html[pathRange])) else {
                return nil
            }

            let title = decodeHTML(String(html[titleRange]))
            let repoFullName = decodeHTML(String(html[repoFullNameRange]))

            return SkillMarketplaceItem(
                id: "skills-sh:\(String(html[repoRange]))",
                source: .skillsSh,
                title: title,
                repoFullName: repoFullName,
                description: "\(title) from \(repoFullName)",
                htmlURL: url,
                installReference: repoFullName,
                stars: nil,
                updatedAt: nil,
                language: nil,
                topics: [],
                installsText: decodeHTML(String(html[installsRange])),
                rank: Int(String(html[rankRange])),
                canInstallDirectly: true
            )
        } ?? []
    }
}
