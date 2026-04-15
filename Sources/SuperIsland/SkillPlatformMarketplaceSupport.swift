import Foundation

// Ranking stays centralized so all marketplace sources use the same ordering and fuzzy-match behavior.
extension SkillManager {
    func marketplaceItem(from repository: SkillMarketplaceRepository) -> SkillMarketplaceItem {
        SkillMarketplaceItem(
            id: "github:\(repository.fullName)",
            source: .github,
            title: repository.fullName,
            repoFullName: repository.fullName,
            description: repository.description,
            htmlURL: repository.htmlURL,
            installReference: repository.fullName,
            stars: repository.stars,
            updatedAt: repository.updatedAt,
            language: repository.language,
            topics: repository.topics,
            installsText: nil,
            rank: nil,
            canInstallDirectly: true
        )
    }

    func sortedMarketplaceItems(
        _ items: [SkillMarketplaceItem],
        query: String,
        limit: Int
    ) -> [SkillMarketplaceItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sorted = items.sorted { lhs, rhs in
            if !trimmed.isEmpty {
                let leftScore = marketplaceRelevanceScore(for: lhs, query: trimmed)
                let rightScore = marketplaceRelevanceScore(for: rhs, query: trimmed)
                if leftScore != rightScore {
                    return leftScore > rightScore
                }
            }
            return marketplaceSort(lhs: lhs, rhs: rhs)
        }
        return Array(sorted.prefix(limit))
    }

    func marketplaceSort(lhs: SkillMarketplaceItem, rhs: SkillMarketplaceItem) -> Bool {
        if lhs.source != rhs.source {
            return marketplaceSourceRank(lhs.source) < marketplaceSourceRank(rhs.source)
        }
        if let leftRank = lhs.rank, let rightRank = rhs.rank, leftRank != rightRank {
            return leftRank < rightRank
        }
        if let leftStars = lhs.stars, let rightStars = rhs.stars, leftStars != rightStars {
            return leftStars > rightStars
        }
        if let leftDate = lhs.updatedAt, let rightDate = rhs.updatedAt, leftDate != rightDate {
            return leftDate > rightDate
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    func marketplaceRelevanceScore(for item: SkillMarketplaceItem, query: String) -> Int {
        let normalizedQuery = normalizeMarketplaceSearchText(query)
        guard !normalizedQuery.isEmpty else { return 0 }

        let title = normalizeMarketplaceSearchText(item.title)
        let repository = normalizeMarketplaceSearchText(item.repoFullName)
        let description = normalizeMarketplaceSearchText(item.description)
        let language = normalizeMarketplaceSearchText(item.language ?? "")
        let topics = item.topics.map(normalizeMarketplaceSearchText)
        let topicText = topics.joined(separator: " ")
        let tokens = Array(Set(normalizedQuery.split(separator: " ").map(String.init)))

        var score = 0
        if title == normalizedQuery { score += 1600 }
        if repository == normalizedQuery { score += 1600 }
        if title.hasPrefix(normalizedQuery) { score += 1100 }
        if repository.hasPrefix(normalizedQuery) { score += 1000 }
        if title.contains(normalizedQuery) { score += 850 }
        if repository.contains(normalizedQuery) { score += 750 }
        if description.contains(normalizedQuery) { score += 320 }
        if topics.contains(normalizedQuery) { score += 240 }
        if topicText.contains(normalizedQuery) { score += 180 }
        if language == normalizedQuery { score += 120 }

        var titleTokenMatches = 0
        var repositoryTokenMatches = 0
        var descriptionTokenMatches = 0
        var topicTokenMatches = 0

        for token in tokens {
            if title == token {
                score += 300
                titleTokenMatches += 1
            } else if title.hasPrefix(token) {
                score += 220
                titleTokenMatches += 1
            } else if title.contains(token) {
                score += 140
                titleTokenMatches += 1
            }

            if repository == token {
                score += 280
                repositoryTokenMatches += 1
            } else if repository.hasPrefix(token) {
                score += 200
                repositoryTokenMatches += 1
            } else if repository.contains(token) {
                score += 130
                repositoryTokenMatches += 1
            }

            if description.contains(token) {
                score += 60
                descriptionTokenMatches += 1
            }

            if topics.contains(where: { $0.contains(token) }) {
                score += 50
                topicTokenMatches += 1
            }

            if !language.isEmpty, language.contains(token) {
                score += 20
            }
        }

        score += titleTokenMatches * 120
        score += repositoryTokenMatches * 100
        score += descriptionTokenMatches * 20
        score += topicTokenMatches * 20

        let matchedPrimaryFields = [titleTokenMatches > 0, repositoryTokenMatches > 0].filter { $0 }.count
        if matchedPrimaryFields == 2 {
            score += 180
        }

        let totalMatchedTokens = titleTokenMatches + repositoryTokenMatches + descriptionTokenMatches + topicTokenMatches
        if totalMatchedTokens >= max(1, tokens.count) {
            score += 150
        }

        return score
    }

    func normalizeMarketplaceSearchText(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        var normalizedScalars: [UnicodeScalar] = []
        normalizedScalars.reserveCapacity(folded.unicodeScalars.count)
        let separator = UnicodeScalar(32)!

        var lastWasSeparator = true
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                normalizedScalars.append(scalar)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                normalizedScalars.append(separator)
                lastWasSeparator = true
            }
        }

        return String(String.UnicodeScalarView(normalizedScalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func marketplaceSourceRank(_ source: SkillMarketplaceItemSource) -> Int {
        switch source {
        case .skillsSh:
            return 0
        case .mayidata:
            return 1
        case .github:
            return 2
        }
    }
}
