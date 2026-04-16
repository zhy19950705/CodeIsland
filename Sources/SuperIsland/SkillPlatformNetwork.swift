import AppKit
import Foundation

// Keep the high-level Skill marketplace flows together; move protocol- or source-specific helpers into focused files.
extension SkillManager {
    func installRepository(reference: String, preferredSkillName: String? = nil) async throws -> [InstalledSkill] {
        let normalizedReference = try normalizeRepositoryReference(reference, preferredSkillName: preferredSkillName)
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("SuperIsland-Skills-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        try await cloneRepository(reference: normalizedReference.cloneURL, to: temporaryRoot)
        let installedRevision = try currentRepositoryRevision(at: temporaryRoot)
        let sourceRoot = normalizedReference.sourceRootPath.map {
            temporaryRoot.appendingPathComponent($0, isDirectory: true)
        } ?? temporaryRoot
        let discoveredSkills = try discoverSkillDirectories(in: sourceRoot, preferredSkillName: normalizedReference.preferredSkillName)
        guard !discoveredSkills.isEmpty else {
            throw SkillPlatformError.noSkillsFound
        }

        return try discoveredSkills.map { sourceDirectory in
            let sourcePath = relativePath(from: temporaryRoot, to: sourceDirectory)
            let metadata = SkillSourceMetadata(
                repoFullName: normalizedReference.repoFullName,
                repoURL: normalizedReference.htmlURL.absoluteString,
                cloneURL: normalizedReference.cloneURL.absoluteString,
                sourcePath: sourcePath,
                installedAt: Date(),
                installedRevision: installedRevision,
                cachedRemoteRevision: installedRevision
            )
            let preferredFolderName = sourceDirectory == temporaryRoot
                ? normalizedReference.repoName
                : sourceDirectory.lastPathComponent

            return try installSkillDirectory(
                from: sourceDirectory,
                preferredFolderName: preferredFolderName,
                metadata: metadata
            )
        }
    }

    func installMarketplaceItem(_ item: SkillMarketplaceItem) async throws -> [InstalledSkill] {
        switch item.source {
        case .github, .skillsSh:
            return try await installRepository(reference: item.installReference)
        case .mayidata:
            let parsedReference = try await fetchMayidataInstallReference(for: item)
            return try await installRepository(reference: parsedReference.reference, preferredSkillName: parsedReference.skillName)
        }
    }

    func removeSkill(_ skill: InstalledSkill) throws {
        let standardizedTarget = skill.directoryURL.standardizedFileURL.path
        let managedRoots = skillStorageRoots().map { $0.rootURL.standardizedFileURL.path }
        guard managedRoots.contains(where: { root in
            standardizedTarget == root || standardizedTarget.hasPrefix(root + "/")
        }) else {
            throw SkillPlatformError.invalidSkillFolder(skill.directoryURL)
        }
        try fileManager.removeItem(at: skill.directoryURL)
    }

    func updateSkill(_ skill: InstalledSkill) async throws -> [InstalledSkill] {
        guard let reference = updateReference(for: skill.sourceMetadata) else {
            throw SkillPlatformError.noUpdateSource
        }
        return try await installRepository(reference: reference)
    }

    func updateAllSkills(_ skills: [InstalledSkill]) async throws -> [InstalledSkill] {
        let references = Array(Set(skills.compactMap { updateReference(for: $0.sourceMetadata) })).sorted()
        guard !references.isEmpty else {
            throw SkillPlatformError.noUpdateSource
        }

        var updated: [InstalledSkill] = []
        for reference in references {
            updated.append(contentsOf: try await installRepository(reference: reference))
        }
        return updated
    }

    func fetchHotRepositories(limit: Int = 12) async throws -> [SkillMarketplaceRepository] {
        let queries = [
            "topic:agent-skills",
            "topic:claude-code-skills",
            "\"agent skills\" in:name,description,readme",
            "\"claude code skills\" in:name,description,readme",
            "\"codex skills\" in:name,description,readme",
        ]

        var merged: [String: SkillMarketplaceRepository] = [:]
        for query in queries {
            let repositories = try await fetchRepositories(query: query, limit: max(6, limit))
            for repository in repositories {
                if let current = merged[repository.fullName], current.stars >= repository.stars {
                    continue
                }
                merged[repository.fullName] = repository
            }
        }

        return merged.values
            .sorted { lhs, rhs in
                if lhs.stars != rhs.stars {
                    return lhs.stars > rhs.stars
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            .prefix(limit)
            .map { $0 }
    }

    func marketplaceItems(
        source: SkillMarketplaceSource,
        query: String,
        leaderboard: SkillsShLeaderboardKind,
        limit: Int = 18
    ) async throws -> [SkillMarketplaceItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        switch source {
        case .github:
            return []
        case .skillsSh:
            return sortedMarketplaceItems(
                try await fetchSkillsShItems(query: trimmed, leaderboard: leaderboard, limit: limit),
                query: trimmed,
                limit: limit
            )
        case .mayidata:
            return sortedMarketplaceItems(
                try await fetchMayidataItems(query: trimmed, limit: limit),
                query: trimmed,
                limit: limit
            )
        case .all:
            async let skillsShItemsTask = fetchSkillsShItems(
                query: trimmed,
                leaderboard: leaderboard,
                limit: max(10, limit / 2)
            )

            async let mayidataItemsTask = fetchMayidataItems(
                query: trimmed,
                limit: max(10, limit / 2)
            )

            var merged: [String: SkillMarketplaceItem] = [:]
            for item in try await skillsShItemsTask + mayidataItemsTask {
                merged[item.id] = item
            }
            return sortedMarketplaceItems(Array(merged.values), query: trimmed, limit: limit)
        }
    }

    func searchRepositories(query: String, limit: Int = 20) async throws -> [SkillMarketplaceRepository] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try await fetchHotRepositories(limit: limit)
        }

        let queries = [
            "\(trimmed) \"agent skills\" in:name,description,readme",
            "\(trimmed) \"claude code skills\" in:name,description,readme",
            "\(trimmed) \"codex skills\" in:name,description,readme",
            "\(trimmed) topic:agent-skills",
            "\(trimmed) topic:claude-code-skills",
            "\(trimmed) topic:codex-skills",
            "\(trimmed) topic:cursor-skills",
        ]

        var merged: [String: SkillMarketplaceRepository] = [:]
        for query in queries {
            let repositories = try await fetchRepositories(query: query, limit: max(8, limit))
            for repository in repositories {
                if let current = merged[repository.fullName], current.stars >= repository.stars {
                    continue
                }
                merged[repository.fullName] = repository
            }
        }

        return merged.values
            .sorted { lhs, rhs in
                if lhs.stars != rhs.stars {
                    return lhs.stars > rhs.stars
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            .prefix(limit)
            .map { $0 }
    }

    func previewDocument(for repository: SkillMarketplaceRepository) async throws -> SkillPreviewDocument {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository.fullName)/readme")!)
        request.setValue("application/vnd.github.raw+json", forHTTPHeaderField: "Accept")
        request.setValue("SuperIsland", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let body = String(data: data, encoding: .utf8),
              !body.isEmpty else {
            throw SkillPlatformError.gitFailed("Repository README could not be loaded")
        }

        return SkillPreviewDocument(
            id: "repo:\(repository.fullName)",
            title: repository.fullName,
            subtitle: repository.description,
            body: body,
            bodyHTML: nil,
            sourceURL: repository.htmlURL,
            metadata: [
                "Stars \(repository.stars)",
                repository.language.map { "语言 \($0)" },
                !repository.topics.isEmpty ? "Topics \(repository.topics.prefix(5).joined(separator: ", "))" : nil,
                {
                    let formatter = RelativeDateTimeFormatter()
                    formatter.locale = AppLocale.chinese
                    return "更新于 \(formatter.localizedString(for: repository.updatedAt, relativeTo: Date()))"
                }(),
            ].compactMap { $0 }
        )
    }

    func previewDocument(for item: SkillMarketplaceItem) async throws -> SkillPreviewDocument {
        switch item.source {
        case .github:
            let repository = SkillMarketplaceRepository(
                fullName: item.repoFullName,
                description: item.description,
                htmlURL: item.htmlURL,
                cloneURL: URL(string: "https://github.com/\(item.repoFullName).git")!,
                stars: item.stars ?? 0,
                updatedAt: item.updatedAt ?? Date(),
                language: item.language,
                topics: item.topics
            )
            return try await previewDocument(for: repository)
        case .skillsSh:
            return try await previewDocumentFromSkillsSh(for: item)
        case .mayidata:
            return try await previewDocumentFromMayidata(for: item)
        }
    }
}
