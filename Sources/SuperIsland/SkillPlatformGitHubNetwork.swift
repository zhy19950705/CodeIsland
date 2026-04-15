import Foundation

// GitHub HTML search parsing is isolated here so marketplace behavior can evolve independently from install logic.
extension SkillManager {
    func fetchRepositories(query: String, limit: Int) async throws -> [SkillMarketplaceRepository] {
        var components = URLComponents(string: "https://github.com/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "repositories"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("SuperIsland", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw SkillPlatformError.gitFailed("GitHub search page request failed")
        }

        guard let embeddedData = firstMatch(
            in: html,
            pattern: #"<script type="application/json" data-target="react-app\.embeddedData">(.*?)</script>"#,
            options: [.dotMatchesLineSeparators]
        ) else {
            throw SkillPlatformError.gitFailed("GitHub search results could not be parsed")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(GitHubSearchEmbeddedData.self, from: Data(embeddedData.utf8))

        return payload.payload.results.prefix(limit).map { item in
            let owner = item.repo.repository.ownerLogin
            let name = item.repo.repository.name
            let fullName = "\(owner)/\(name)"
            let description = item.highlightedDescription.flatMap(htmlToPlainText)?.nilIfEmpty
                ?? item.highlightedDescription?
                    .replacingOccurrences(of: "<em>", with: "")
                    .replacingOccurrences(of: "</em>", with: "")
                    .nilIfEmpty
                ?? "No description"

            return SkillMarketplaceRepository(
                fullName: fullName,
                description: description,
                htmlURL: URL(string: "https://github.com/\(fullName)")!,
                cloneURL: URL(string: "https://github.com/\(fullName).git")!,
                stars: item.stars,
                updatedAt: item.repo.repository.updatedAt,
                language: item.language,
                topics: item.topics
            )
        }
    }
}
