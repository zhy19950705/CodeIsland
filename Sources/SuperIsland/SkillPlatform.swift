import AppKit
import Foundation

enum SkillAgentID: String, CaseIterable, Identifiable, Sendable {
    case codex
    case claude
    case cursor
    case gemini
    case copilot
    case opencode
    case qoder
    case droid
    case codebuddy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        case .cursor: return "Cursor"
        case .gemini: return "Gemini CLI"
        case .copilot: return "GitHub Copilot"
        case .opencode: return "OpenCode"
        case .qoder: return "Qoder"
        case .droid: return "Factory"
        case .codebuddy: return "CodeBuddy"
        }
    }

    var systemName: String {
        switch self {
        case .codex: return "sparkles.rectangle.stack"
        case .claude: return "bubble.left.and.bubble.right.fill"
        case .cursor: return "cursorarrow.rays"
        case .gemini: return "diamond.fill"
        case .copilot: return "paperplane.fill"
        case .opencode: return "chevron.left.forwardslash.chevron.right"
        case .qoder: return "q.circle.fill"
        case .droid: return "shippingbox.fill"
        case .codebuddy: return "person.crop.circle.badge.checkmark"
        }
    }

    func skillsURL(homeDirectory: URL) -> URL {
        switch self {
        case .codex:
            return homeDirectory
                .appendingPathComponent(".agents", isDirectory: true)
                .appendingPathComponent("skills", isDirectory: true)
        case .claude:
            return homeDirectory
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent("skills", isDirectory: true)
        case .cursor:
            return homeDirectory
                .appendingPathComponent(".cursor", isDirectory: true)
                .appendingPathComponent("skills", isDirectory: true)
        case .gemini:
            return homeDirectory
                .appendingPathComponent(".gemini", isDirectory: true)
                .appendingPathComponent("skills", isDirectory: true)
        case .copilot:
            return homeDirectory
                .appendingPathComponent(".copilot", isDirectory: true)
                .appendingPathComponent("skills", isDirectory: true)
        case .opencode:
            return homeDirectory
                .appendingPathComponent(".config", isDirectory: true)
                .appendingPathComponent("opencode", isDirectory: true)
                .appendingPathComponent("skills", isDirectory: true)
        case .qoder:
            return homeDirectory
                .appendingPathComponent(".qoder", isDirectory: true)
                .appendingPathComponent("skills", isDirectory: true)
        case .droid:
            return homeDirectory
                .appendingPathComponent(".factory", isDirectory: true)
                .appendingPathComponent("skills", isDirectory: true)
        case .codebuddy:
            return homeDirectory
                .appendingPathComponent(".codebuddy", isDirectory: true)
                .appendingPathComponent("skills", isDirectory: true)
        }
    }
}

enum SkillAgentLinkState: Sendable, Equatable {
    case native
    case linked
    case missing
    case conflict
}

struct SkillAgentLinkSnapshot: Identifiable, Sendable, Equatable {
    var id: SkillAgentID { agent }
    let agent: SkillAgentID
    let skillsURL: URL
    let state: SkillAgentLinkState
    let detail: String
}

struct SkillSourceMetadata: Codable, Hashable, Sendable {
    let repoFullName: String?
    let repoURL: String?
    let sourcePath: String
    let installedAt: Date
}

enum SkillStorageKind: Hashable, Sendable {
    case shared
    case legacyAgent
    case agent(SkillAgentID)
}

struct InstalledSkill: Identifiable, Hashable, Sendable {
    let directoryURL: URL
    let name: String
    let description: String
    let version: String?
    let author: String?
    let modifiedAt: Date?
    let sourceMetadata: SkillSourceMetadata?
    let storageKind: SkillStorageKind
    let isAdoptableToSharedLibrary: Bool

    var id: String { directoryURL.path }
    var folderName: String { directoryURL.lastPathComponent }
    var isUpdatable: Bool { sourceMetadata?.repoFullName?.isEmpty == false }
    var isSharedLibrarySkill: Bool {
        if case .shared = storageKind { return true }
        return false
    }
}

enum SkillMarketplaceSource: String, CaseIterable, Identifiable, Sendable {
    case all
    case github
    case skillsSh
    case mayidata

    var id: String { rawValue }
}

enum SkillsShLeaderboardKind: String, CaseIterable, Identifiable, Sendable {
    case hot
    case trending
    case allTime

    var id: String { rawValue }

    var path: String {
        switch self {
        case .hot:
            return "/hot"
        case .trending:
            return "/trending"
        case .allTime:
            return "/"
        }
    }
}

enum SkillMarketplaceItemSource: String, Sendable {
    case github
    case skillsSh
    case mayidata
}

struct SkillMarketplaceItem: Identifiable, Hashable, Sendable {
    let id: String
    let source: SkillMarketplaceItemSource
    let title: String
    let repoFullName: String
    let description: String
    let htmlURL: URL
    let installReference: String
    let stars: Int?
    let updatedAt: Date?
    let language: String?
    let topics: [String]
    let installsText: String?
    let rank: Int?
    let canInstallDirectly: Bool
}

struct SkillMarketplaceRepository: Identifiable, Hashable, Sendable {
    let fullName: String
    let description: String
    let htmlURL: URL
    let cloneURL: URL
    let stars: Int
    let updatedAt: Date
    let language: String?
    let topics: [String]

    var id: String { fullName }
}

struct SkillAdoptionSummary: Sendable {
    let imported: [InstalledSkill]
    let skipped: [InstalledSkill]

    var importedCount: Int { imported.count }
    var skippedCount: Int { skipped.count }
}

struct SkillLinkRepairSummary: Sendable {
    let linkedAgents: [SkillAgentID]
    let conflictAgents: [SkillAgentID]

    var linkedCount: Int { linkedAgents.count }
    var conflictCount: Int { conflictAgents.count }
}

struct SkillConflictResolutionSummary: Sendable {
    let agent: SkillAgentID
    let adoption: SkillAdoptionSummary

    var importedCount: Int { adoption.importedCount }
    var skippedCount: Int { adoption.skippedCount }
}

struct SkillBulkConflictResolutionSummary: Sendable {
    let resolutions: [SkillConflictResolutionSummary]

    var resolvedCount: Int { resolutions.count }
    var importedCount: Int { resolutions.reduce(0) { $0 + $1.importedCount } }
    var skippedCount: Int { resolutions.reduce(0) { $0 + $1.skippedCount } }
}

struct SkillPreviewDocument: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let body: String
    let sourceURL: URL?
    let metadata: [String]
}

enum SkillPlatformError: LocalizedError, Equatable {
    case invalidRepositoryReference
    case gitUnavailable
    case gitFailed(String)
    case noSkillsFound
    case skillAlreadyExists(String)
    case invalidSkillFolder(URL)
    case linkConflict(String)
    case noUpdateSource
    case projectScopedSkillCannotBeImported

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryReference:
            return "Invalid GitHub repository reference"
        case .gitUnavailable:
            return "Git is not available on this Mac"
        case let .gitFailed(message):
            return message
        case .noSkillsFound:
            return "No SKILL.md entries were found"
        case let .skillAlreadyExists(name):
            return "Skill already exists: \(name)"
        case let .invalidSkillFolder(url):
            return "Not a valid skill folder: \(url.lastPathComponent)"
        case let .linkConflict(path):
            return "Path is already occupied: \(path)"
        case .noUpdateSource:
            return "This skill was not installed from a GitHub source"
        case .projectScopedSkillCannotBeImported:
            return "Only global skills from ~/.agent/skills or ~/.<agent>/skills can be imported into the shared library"
        }
    }
}

private struct SkillManifestMetadata {
    let name: String
    let description: String
    let version: String?
    let author: String?
}

struct NormalizedRepositoryReference {
    let cloneURL: URL
    let htmlURL: URL
    let repoFullName: String
    let repoName: String
    let sourceRootPath: String?
    let preferredSkillName: String?
}

struct ParsedInstallReference {
    let reference: String
    let skillName: String?
}

private struct SkillStorageRoot: Hashable {
    let kind: SkillStorageKind
    let rootURL: URL
}

final class SkillManager {
    private static let sourceMetadataFileName = ".superisland-skill-source.json"
    private static let mayidataSkillHubURL = URL(string: "http://skillshub.mayidata.com")!
    private let fileManager: FileManager
    private let workspace: NSWorkspace
    private let session: URLSession
    private let homeDirectory: URL

    init(
        fileManager: FileManager = .default,
        workspace: NSWorkspace = .shared,
        session: URLSession = .shared,
        homeDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.workspace = workspace
        self.session = session
        self.homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
    }

    var sharedRootURL: URL {
        SkillAgentID.codex.skillsURL(homeDirectory: homeDirectory)
    }

    var legacyAgentRootURL: URL {
        homeDirectory
            .appendingPathComponent(".agent", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
    }

    func ensureSharedRootExists() throws {
        try fileManager.createDirectory(at: sharedRootURL, withIntermediateDirectories: true)
    }

    func openSharedRoot() {
        try? ensureSharedRootExists()
        workspace.open(sharedRootURL)
    }

    func reveal(_ url: URL) {
        workspace.activateFileViewerSelecting([url])
    }

    func discoverSkills() throws -> [InstalledSkill] {
        try ensureSharedRootExists()
        var discovered: [InstalledSkill] = []
        var seenResolvedDirectories = Set<String>()

        for storageRoot in skillStorageRoots() {
            let entries = (try? fileManager.contentsOfDirectory(
                at: storageRoot.rootURL,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for entry in entries where (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let resolvedPath = entry.resolvingSymlinksInPath().standardizedFileURL.path
                guard !seenResolvedDirectories.contains(resolvedPath) else { continue }
                guard let skill = loadSkill(
                    from: entry,
                    storageKind: storageRoot.kind,
                    isAdoptableToSharedLibrary: isGlobalSkillRoot(storageRoot.rootURL)
                ) else { continue }
                seenResolvedDirectories.insert(resolvedPath)
                discovered.append(skill)
            }
        }

        return discovered.sorted { lhs, rhs in
            if lhs.isSharedLibrarySkill != rhs.isSharedLibrarySkill {
                return lhs.isSharedLibrarySkill && !rhs.isSharedLibrarySkill
            }
            if lhs.name.localizedCaseInsensitiveCompare(rhs.name) != .orderedSame {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.directoryURL.path < rhs.directoryURL.path
        }
    }

    func importSkillToSharedLibrary(_ skill: InstalledSkill) throws -> InstalledSkill {
        try ensureSharedRootExists()
        guard skill.isAdoptableToSharedLibrary else {
            throw SkillPlatformError.projectScopedSkillCannotBeImported
        }
        return try installSkillDirectory(
            from: skill.directoryURL,
            preferredFolderName: skill.folderName,
            metadata: skill.sourceMetadata
        )
    }

    func importSkillsToSharedLibrary(_ skills: [InstalledSkill]) throws -> SkillAdoptionSummary {
        try ensureSharedRootExists()

        var imported: [InstalledSkill] = []
        var skipped: [InstalledSkill] = []

        for skill in skills where !skill.isSharedLibrarySkill {
            guard skill.isAdoptableToSharedLibrary else {
                skipped.append(skill)
                continue
            }
            do {
                imported.append(try importSkillToSharedLibrary(skill))
            } catch SkillPlatformError.skillAlreadyExists {
                skipped.append(skill)
            }
        }

        return SkillAdoptionSummary(imported: imported, skipped: skipped)
    }

    func agentSnapshots() -> [SkillAgentLinkSnapshot] {
        SkillAgentID.allCases.map(snapshot(for:))
    }

    func linkAllAgents() throws {
        for agent in SkillAgentID.allCases where agent != .codex {
            let snapshot = snapshot(for: agent)
            if snapshot.state == .missing {
                try link(agent)
            }
        }
    }

    func repairGlobalAgentLinks() -> SkillLinkRepairSummary {
        var linkedAgents: [SkillAgentID] = []
        var conflictAgents: [SkillAgentID] = []

        for agent in SkillAgentID.allCases where agent != .codex {
            let state = snapshot(for: agent).state
            switch state {
            case .missing:
                do {
                    try link(agent)
                    linkedAgents.append(agent)
                } catch {
                    conflictAgents.append(agent)
                }
            case .conflict:
                conflictAgents.append(agent)
            case .native, .linked:
                break
            }
        }

        return SkillLinkRepairSummary(
            linkedAgents: linkedAgents,
            conflictAgents: conflictAgents
        )
    }

    func resolveConflict(for agent: SkillAgentID) throws -> SkillConflictResolutionSummary {
        try ensureSharedRootExists()

        let snapshot = snapshot(for: agent)
        guard snapshot.state == .conflict else {
            throw SkillPlatformError.linkConflict(displayPath(snapshot.skillsURL))
        }

        let skillsToImport = discoverSkills(in: snapshot.skillsURL, storageKind: .agent(agent), isAdoptableToSharedLibrary: true)
        let adoption = try importSkillsToSharedLibrary(skillsToImport)
        try fileManager.removeItem(at: snapshot.skillsURL)
        try link(agent)

        return SkillConflictResolutionSummary(
            agent: agent,
            adoption: adoption
        )
    }

    func resolveAllConflicts() throws -> SkillBulkConflictResolutionSummary {
        let resolutions = try agentSnapshots()
            .filter { $0.state == .conflict }
            .map { try resolveConflict(for: $0.agent) }
        return SkillBulkConflictResolutionSummary(resolutions: resolutions)
    }

    func link(_ agent: SkillAgentID) throws {
        try ensureSharedRootExists()
        let destination = agent.skillsURL(homeDirectory: homeDirectory)
        if destination.standardizedFileURL == sharedRootURL.standardizedFileURL { return }

        if fileManager.fileExists(atPath: destination.path) || isDanglingSymlink(destination) {
            let snapshot = snapshot(for: agent)
            switch snapshot.state {
            case .linked:
                return
            case .missing:
                break
            case .native, .conflict:
                throw SkillPlatformError.linkConflict(displayPath(destination))
            }
        }

        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: destination, withDestinationURL: sharedRootURL)
    }

    func unlink(_ agent: SkillAgentID) throws {
        let destination = agent.skillsURL(homeDirectory: homeDirectory)
        if destination.standardizedFileURL == sharedRootURL.standardizedFileURL { return }

        let snapshot = snapshot(for: agent)
        guard snapshot.state == .linked else { return }
        try fileManager.removeItem(at: destination)
    }

    func importSkills(from sourceRoot: URL) throws -> [InstalledSkill] {
        try ensureSharedRootExists()
        let skillDirectories = try discoverSkillDirectories(in: sourceRoot)
        guard !skillDirectories.isEmpty else {
            throw SkillPlatformError.noSkillsFound
        }

        return try skillDirectories.map { sourceDirectory in
            try installSkillDirectory(
                from: sourceDirectory,
                preferredFolderName: sourceDirectory.lastPathComponent,
                metadata: nil
            )
        }
    }

    func installRepository(reference: String, preferredSkillName: String? = nil) async throws -> [InstalledSkill] {
        let normalizedReference = try normalizeRepositoryReference(reference, preferredSkillName: preferredSkillName)
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("SuperIsland-Skills-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        try await cloneRepository(reference: normalizedReference.cloneURL, to: temporaryRoot)
        let sourceRoot = normalizedReference.sourceRootPath.map {
            temporaryRoot.appendingPathComponent($0, isDirectory: true)
        } ?? temporaryRoot
        let discoveredSkills = try discoverSkillDirectories(in: sourceRoot, preferredSkillName: normalizedReference.preferredSkillName)
        guard !discoveredSkills.isEmpty else {
            throw SkillPlatformError.noSkillsFound
        }

        return try discoveredSkills.map { sourceDirectory in
            let relativePath = relativePath(from: temporaryRoot, to: sourceDirectory)
            let metadata = SkillSourceMetadata(
                repoFullName: normalizedReference.repoFullName,
                repoURL: normalizedReference.htmlURL.absoluteString,
                sourcePath: relativePath,
                installedAt: Date()
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

    func displayPath(_ url: URL) -> String {
        let path = url.path
        let homePath = homeDirectory.path
        guard path.hasPrefix(homePath) else { return path }
        return "~" + path.dropFirst(homePath.count)
    }

    func previewDocument(for skill: InstalledSkill) throws -> SkillPreviewDocument {
        let skillURL = skill.directoryURL.appendingPathComponent("SKILL.md", isDirectory: false)
        let contents = try String(contentsOf: skillURL, encoding: .utf8)
        return SkillPreviewDocument(
            id: "skill:\(skill.id)",
            title: skill.name,
            subtitle: displayPath(skillURL),
            body: contents,
            sourceURL: skill.sourceMetadata?.repoURL.flatMap(URL.init(string:)),
            metadata: [
                skill.version.map { "Version \($0)" },
                skill.author.map { "Author \($0)" },
                skill.sourceMetadata?.repoFullName.map { "Source \($0)" },
                "Storage \(storageLabel(for: skill.storageKind))",
            ].compactMap { $0 }
        )
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
            sourceURL: repository.htmlURL,
            metadata: [
                "Stars \(repository.stars)",
                repository.language.map { "Language \($0)" },
                !repository.topics.isEmpty ? "Topics \(repository.topics.prefix(5).joined(separator: ", "))" : nil,
                "Updated \(RelativeDateTimeFormatter().localizedString(for: repository.updatedAt, relativeTo: Date()))",
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

    func storageLabel(for kind: SkillStorageKind) -> String {
        switch kind {
        case .shared:
            return "Shared"
        case .legacyAgent:
            return "Legacy .agent"
        case .agent(let agent):
            return agent.title
        }
    }

    private func skillStorageRoots() -> [SkillStorageRoot] {
        var roots: [SkillStorageRoot] = [
            SkillStorageRoot(kind: .shared, rootURL: sharedRootURL)
        ]

        let legacyRoot = legacyAgentRootURL
        if fileManager.fileExists(atPath: legacyRoot.path), !resolves(toSharedRoot: legacyRoot) {
            roots.append(SkillStorageRoot(kind: .legacyAgent, rootURL: legacyRoot))
        }

        for agent in SkillAgentID.allCases where agent != .codex {
            let root = agent.skillsURL(homeDirectory: homeDirectory)
            guard fileManager.fileExists(atPath: root.path) || isDanglingSymlink(root) else { continue }
            guard !resolves(toSharedRoot: root) else { continue }
            guard root.standardizedFileURL != legacyRoot.standardizedFileURL else { continue }
            roots.append(SkillStorageRoot(kind: .agent(agent), rootURL: root))
        }

        return roots
    }

    private func resolves(toSharedRoot url: URL) -> Bool {
        url.resolvingSymlinksInPath().standardizedFileURL == sharedRootURL.standardizedFileURL
    }

    private func isGlobalSkillRoot(_ url: URL) -> Bool {
        let normalized = url.standardizedFileURL
        if normalized == sharedRootURL.standardizedFileURL { return false }
        if normalized == legacyAgentRootURL.standardizedFileURL { return true }
        return SkillAgentID.allCases
            .filter { $0 != .codex }
            .map { $0.skillsURL(homeDirectory: homeDirectory).standardizedFileURL }
            .contains(normalized)
    }

    private func snapshot(for agent: SkillAgentID) -> SkillAgentLinkSnapshot {
        let path = agent.skillsURL(homeDirectory: homeDirectory)
        if path.standardizedFileURL == sharedRootURL.standardizedFileURL {
            return SkillAgentLinkSnapshot(
                agent: agent,
                skillsURL: path,
                state: .native,
                detail: "Uses the shared library directly"
            )
        }

        guard fileManager.fileExists(atPath: path.path) || isDanglingSymlink(path) else {
            return SkillAgentLinkSnapshot(
                agent: agent,
                skillsURL: path,
                state: .missing,
                detail: "Not linked yet"
            )
        }

        do {
            let values = try path.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                let destination = try fileManager.destinationOfSymbolicLink(atPath: path.path)
                let resolvedURL = URL(fileURLWithPath: destination, relativeTo: path.deletingLastPathComponent())
                    .standardizedFileURL
                if resolvedURL == sharedRootURL.standardizedFileURL {
                    return SkillAgentLinkSnapshot(
                        agent: agent,
                        skillsURL: path,
                        state: .linked,
                        detail: "Linked to \(displayPath(sharedRootURL))"
                    )
                }
            }
        } catch {
            return SkillAgentLinkSnapshot(
                agent: agent,
                skillsURL: path,
                state: .conflict,
                detail: error.localizedDescription
            )
        }

        return SkillAgentLinkSnapshot(
            agent: agent,
            skillsURL: path,
            state: .conflict,
            detail: "Already exists but is not linked to the shared library"
        )
    }

    private func loadSkill(
        from directoryURL: URL,
        storageKind: SkillStorageKind,
        isAdoptableToSharedLibrary: Bool
    ) -> InstalledSkill? {
        let skillFileURL = directoryURL.appendingPathComponent("SKILL.md", isDirectory: false)
        guard fileManager.fileExists(atPath: skillFileURL.path) else { return nil }
        let contents = (try? String(contentsOf: skillFileURL, encoding: .utf8)) ?? ""
        let metadata = extractSkillMetadata(from: contents, fallbackName: directoryURL.lastPathComponent)
        let resourceValues = try? directoryURL.resourceValues(forKeys: [.contentModificationDateKey])
        return InstalledSkill(
            directoryURL: directoryURL,
            name: metadata.name,
            description: metadata.description,
            version: metadata.version,
            author: metadata.author,
            modifiedAt: resourceValues?.contentModificationDate,
            sourceMetadata: loadSourceMetadata(from: directoryURL),
            storageKind: storageKind,
            isAdoptableToSharedLibrary: isAdoptableToSharedLibrary
        )
    }

    private func discoverSkills(
        in rootURL: URL,
        storageKind: SkillStorageKind,
        isAdoptableToSharedLibrary: Bool
    ) -> [InstalledSkill] {
        let entries = (try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return entries.compactMap { entry in
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            return loadSkill(
                from: entry,
                storageKind: storageKind,
                isAdoptableToSharedLibrary: isAdoptableToSharedLibrary
            )
        }
    }

    private func discoverSkillDirectories(in sourceRoot: URL, preferredSkillName: String? = nil) throws -> [URL] {
        var discovered = Set<URL>()
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: []
        ) else {
            return []
        }

        let ignoredDirectoryNames = Set([".git", "node_modules", "dist", "build", ".next"])

        for case let url as URL in enumerator {
            if ignoredDirectoryNames.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard url.lastPathComponent == "SKILL.md" else { continue }
            discovered.insert(url.deletingLastPathComponent().standardizedFileURL)
        }

        let all = Array(discovered).sorted { $0.path < $1.path }
        let accepted = all.filter { candidate in
            let relative = relativePathComponents(from: sourceRoot, to: candidate)
            if relative.isEmpty {
                return all.count == 1
            }
            if relative.count == 1 {
                return true
            }
            return relative.contains("skills")
        }

        if accepted.isEmpty,
           fileManager.fileExists(atPath: sourceRoot.appendingPathComponent("SKILL.md", isDirectory: false).path) {
            let rootOnly = [sourceRoot]
            return filterSkillDirectories(rootOnly, preferredSkillName: preferredSkillName)
        }
        return filterSkillDirectories(accepted, preferredSkillName: preferredSkillName)
    }

    private func installSkillDirectory(
        from sourceDirectory: URL,
        preferredFolderName: String,
        metadata: SkillSourceMetadata?
    ) throws -> InstalledSkill {
        let skillFileURL = sourceDirectory.appendingPathComponent("SKILL.md", isDirectory: false)
        guard fileManager.fileExists(atPath: skillFileURL.path) else {
            throw SkillPlatformError.invalidSkillFolder(sourceDirectory)
        }

        let destinationURL = sharedRootURL.appendingPathComponent(preferredFolderName, isDirectory: true)
        if fileManager.fileExists(atPath: destinationURL.path) {
            if let existingMetadata = loadSourceMetadata(from: destinationURL),
               let metadata,
               existingMetadata.repoFullName == metadata.repoFullName,
               existingMetadata.sourcePath == metadata.sourcePath {
                try fileManager.removeItem(at: destinationURL)
            } else {
                throw SkillPlatformError.skillAlreadyExists(preferredFolderName)
            }
        }

        let temporaryURL = sharedRootURL.appendingPathComponent(".tmp-\(UUID().uuidString)", isDirectory: true)
        try copyDirectoryRecursively(from: sourceDirectory, to: temporaryURL)
        if let metadata {
            try writeSourceMetadata(metadata, to: temporaryURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)

        guard let installedSkill = loadSkill(
            from: destinationURL,
            storageKind: .shared,
            isAdoptableToSharedLibrary: false
        ) else {
            throw SkillPlatformError.invalidSkillFolder(destinationURL)
        }
        return installedSkill
    }

    private func filterSkillDirectories(_ directories: [URL], preferredSkillName: String?) -> [URL] {
        guard let preferredSkillName, !preferredSkillName.isEmpty else {
            return directories
        }

        let exactMatches = directories.filter { directory in
            if directory.lastPathComponent == preferredSkillName {
                return true
            }
            let skillFileURL = directory.appendingPathComponent("SKILL.md", isDirectory: false)
            guard let contents = try? String(contentsOf: skillFileURL, encoding: .utf8) else {
                return false
            }
            let metadata = extractSkillMetadata(from: contents, fallbackName: directory.lastPathComponent)
            return metadata.name == preferredSkillName
        }
        return exactMatches
    }

    private func extractSkillMetadata(from contents: String, fallbackName: String) -> SkillManifestMetadata {
        let normalized = contents.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var frontmatterLines: [String] = []
        var bodyLines = lines
        if lines.first == "---",
           let closingIndex = lines.dropFirst().firstIndex(of: "---") {
            frontmatterLines = Array(lines[1..<closingIndex])
            bodyLines = Array(lines[(closingIndex + 1)...])
        }

        let frontmatter = Dictionary(uniqueKeysWithValues: frontmatterLines.compactMap { line -> (String, String)? in
            guard let colonIndex = line.firstIndex(of: ":") else { return nil }
            let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return key.isEmpty ? nil : (key.lowercased(), value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))
        })

        let heading = bodyLines.first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }
        let summary = bodyLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { line in
                !line.isEmpty && !line.hasPrefix("#") && !line.hasPrefix("- ") && !line.hasPrefix("* ")
            }

        let rawName = frontmatter["name"] ?? heading ?? fallbackName
        let rawDescription = frontmatter["description"] ?? summary ?? "No description"
        let rawVersion = normalizedFrontmatterValue(frontmatter["version"])
        let rawAuthor = normalizedFrontmatterValue(frontmatter["author"])

        return SkillManifestMetadata(
            name: rawName,
            description: rawDescription,
            version: rawVersion,
            author: rawAuthor
        )
    }

    private func normalizedFrontmatterValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func loadSourceMetadata(from directoryURL: URL) -> SkillSourceMetadata? {
        let metadataURL = directoryURL.appendingPathComponent(Self.sourceMetadataFileName, isDirectory: false)
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SkillSourceMetadata.self, from: data)
    }

    private func writeSourceMetadata(_ metadata: SkillSourceMetadata, to directoryURL: URL) throws {
        let metadataURL = directoryURL.appendingPathComponent(Self.sourceMetadataFileName, isDirectory: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)
        try data.write(to: metadataURL, options: .atomic)
    }

    private func copyDirectoryRecursively(from source: URL, to destination: URL) throws {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )

        while let url = enumerator?.nextObject() as? URL {
            let relative = relativePath(from: source, to: url)
            if relative == ".git" || relative.hasPrefix(".git/") {
                enumerator?.skipDescendants()
                continue
            }

            let targetURL = destination.appendingPathComponent(relative, isDirectory: false)
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])

            if values.isDirectory == true {
                try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true)
            } else if values.isSymbolicLink == true {
                let linkDestination = try fileManager.destinationOfSymbolicLink(atPath: url.path)
                try fileManager.createSymbolicLink(atPath: targetURL.path, withDestinationPath: linkDestination)
            } else {
                try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: targetURL.path) {
                    try fileManager.removeItem(at: targetURL)
                }
                try fileManager.copyItem(at: url, to: targetURL)
            }
        }
    }

    func normalizeRepositoryReference(
        _ reference: String,
        preferredSkillName: String? = nil
    ) throws -> NormalizedRepositoryReference {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SkillPlatformError.invalidRepositoryReference
        }

        if let url = URL(string: trimmed), let host = url.host, host.contains("github.com") {
            let components = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            guard components.count >= 2 else {
                throw SkillPlatformError.invalidRepositoryReference
            }
            let owner = components[0]
            let repo = components[1].replacingOccurrences(of: ".git", with: "")
            guard let cloneURL = URL(string: "https://github.com/\(owner)/\(repo).git"),
                  let htmlURL = URL(string: "https://github.com/\(owner)/\(repo)") else {
                throw SkillPlatformError.invalidRepositoryReference
            }
            return NormalizedRepositoryReference(
                cloneURL: cloneURL,
                htmlURL: htmlURL,
                repoFullName: "\(owner)/\(repo)",
                repoName: repo,
                sourceRootPath: nil,
                preferredSkillName: preferredSkillName
            )
        }

        if let url = URL(string: trimmed), let host = url.host, host.contains("gitlab") {
            let parsedReference = try parseGitLabRepositoryReference(url: url, preferredSkillName: preferredSkillName)
            return parsedReference
        }

        let components = trimmed.split(separator: "/").map(String.init)
        guard components.count == 2 else {
            throw SkillPlatformError.invalidRepositoryReference
        }
        let owner = components[0]
        let repo = components[1].replacingOccurrences(of: ".git", with: "")
        guard let cloneURL = URL(string: "https://github.com/\(owner)/\(repo).git"),
              let htmlURL = URL(string: "https://github.com/\(owner)/\(repo)") else {
            throw SkillPlatformError.invalidRepositoryReference
        }
        return NormalizedRepositoryReference(
            cloneURL: cloneURL,
            htmlURL: htmlURL,
            repoFullName: "\(owner)/\(repo)",
            repoName: repo,
            sourceRootPath: nil,
            preferredSkillName: preferredSkillName
        )
    }

    private func parseGitLabRepositoryReference(
        url: URL,
        preferredSkillName: String?
    ) throws -> NormalizedRepositoryReference {
        let components = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard components.count >= 2 else {
            throw SkillPlatformError.invalidRepositoryReference
        }

        let treeMarkerIndex = components.firstIndex(of: "-")
        let repositoryComponents = Array(components.prefix(treeMarkerIndex ?? components.count))
        guard repositoryComponents.count >= 2 else {
            throw SkillPlatformError.invalidRepositoryReference
        }

        let repoName = repositoryComponents.last!
        let repoFullName = repositoryComponents.joined(separator: "/")
        let baseURL = URL(string: "\(url.scheme ?? "http")://\(url.host ?? "")")!
        let repositoryPath = repositoryComponents.joined(separator: "/")
        guard let cloneURL = URL(string: "\(baseURL.absoluteString)/\(repositoryPath).git"),
              let htmlURL = URL(string: "\(baseURL.absoluteString)/\(repositoryPath)") else {
            throw SkillPlatformError.invalidRepositoryReference
        }

        var sourceRootPath: String?
        if let treeMarkerIndex, components.count > treeMarkerIndex + 3 {
            sourceRootPath = components[(treeMarkerIndex + 3)...].joined(separator: "/")
        }

        return NormalizedRepositoryReference(
            cloneURL: cloneURL,
            htmlURL: htmlURL,
            repoFullName: repoFullName,
            repoName: repoName,
            sourceRootPath: sourceRootPath?.nilIfEmpty,
            preferredSkillName: preferredSkillName
        )
    }

    private func cloneRepository(reference cloneURL: URL, to destination: URL) async throws {
        guard fileManager.fileExists(atPath: "/usr/bin/git") else {
            throw SkillPlatformError.gitUnavailable
        }

        try? fileManager.removeItem(at: destination)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["clone", "--depth", "1", cloneURL.absoluteString, destination.path]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "git clone failed"
                throw SkillPlatformError.gitFailed(output)
            }
        }.value
    }

    private func fetchRepositories(query: String, limit: Int) async throws -> [SkillMarketplaceRepository] {
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

    private func fetchSkillsShItems(
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

        var items = parseSkillsShLeaderboardHTML(html)
        if !query.isEmpty {
            let needle = query.lowercased()
            items = items.filter { item in
                item.title.lowercased().contains(needle)
                    || item.repoFullName.lowercased().contains(needle)
                    || item.description.lowercased().contains(needle)
            }
        }
        return Array(items.prefix(limit))
    }

    private func searchSkillsShItems(
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

    private func fetchMayidataItems(
        query: String,
        limit: Int
    ) async throws -> [SkillMarketplaceItem] {
        var components = URLComponents(url: Self.mayidataSkillHubURL, resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
            ]
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

    private func previewDocumentFromSkillsSh(for item: SkillMarketplaceItem) async throws -> SkillPreviewDocument {
        var request = URLRequest(url: item.htmlURL)
        request.setValue("SuperIsland", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw SkillPlatformError.gitFailed("skills.sh detail page could not be loaded")
        }

        let summaryHTML = extractHTML(in: html, startMarker: "Summary</div>", endMarker: "<div class=\"bg-background\"><div class=\"flex items-center gap-2 text-sm font-mono text-white mb-4 pb-4 border-b border-border\"><span>SKILL.md</span></div>")
        let skillHTML = extractHTML(in: html, startMarker: "<span>SKILL.md</span></div>", endMarker: "<div class=\" lg:col-span-3\">")
        let body = [summaryHTML.flatMap(htmlToPlainText), skillHTML.flatMap(htmlToPlainText)]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        let metadata = [
            item.installsText.map { "Weekly installs \($0)" },
            "Source skills.sh",
            item.repoFullName.isEmpty ? nil : "Repository \(item.repoFullName)",
            item.stars.map { "GitHub stars \($0)" },
        ].compactMap { $0 }

        return SkillPreviewDocument(
            id: "skills-sh:\(item.id)",
            title: item.title,
            subtitle: item.repoFullName,
            body: body.isEmpty ? item.description : body,
            sourceURL: item.htmlURL,
            metadata: metadata
        )
    }

    private func previewDocumentFromMayidata(for item: SkillMarketplaceItem) async throws -> SkillPreviewDocument {
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
        let markdownBody = markdownHTML.flatMap(htmlToPlainText)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let installSection = installCommand.map { "Install\n\n\($0)" } ?? ""
        let body = [
            description.trimmingCharacters(in: .whitespacesAndNewlines),
            markdownBody,
            installSection,
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")

        let metadata = [
            "Source Guandata Skill Hub",
            repository.isEmpty ? nil : "Repository \(repository)",
            author.flatMap { $0.isEmpty ? nil : "Author \($0)" },
            updatedAt.flatMap { $0.isEmpty ? nil : "Updated \($0)" },
            createdAt.flatMap { $0.isEmpty ? nil : "Created \($0)" },
            !item.topics.isEmpty ? "Tags \(item.topics.joined(separator: ", "))" : nil,
        ].compactMap { $0 }

        return SkillPreviewDocument(
            id: "mayidata:\(item.id)",
            title: title,
            subtitle: repository,
            body: body.isEmpty ? item.description : body,
            sourceURL: item.htmlURL,
            metadata: metadata
        )
    }

    private func fetchMayidataInstallReference(for item: SkillMarketplaceItem) async throws -> ParsedInstallReference {
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

    private func marketplaceItem(from repository: SkillMarketplaceRepository) -> SkillMarketplaceItem {
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

    private func sortedMarketplaceItems(
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

    private func marketplaceSort(lhs: SkillMarketplaceItem, rhs: SkillMarketplaceItem) -> Bool {
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

    private func marketplaceRelevanceScore(for item: SkillMarketplaceItem, query: String) -> Int {
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

    private func normalizeMarketplaceSearchText(_ text: String) -> String {
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

    private func marketplaceSourceRank(_ source: SkillMarketplaceItemSource) -> Int {
        switch source {
        case .skillsSh:
            return 0
        case .mayidata:
            return 1
        case .github:
            return 2
        }
    }

    private func parseSkillsShLeaderboardHTML(_ html: String) -> [SkillMarketplaceItem] {
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
            let rank = Int(String(html[rankRange]))
            let installs = decodeHTML(String(html[installsRange]))

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
                installsText: installs,
                rank: rank,
                canInstallDirectly: true
            )
        } ?? []
    }

    private func parseMayidataListingHTML(_ html: String) -> [SkillMarketplaceItem] {
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
            let description = firstMatch(in: body, pattern: #"<h3>.*?</h3><p>(.*?)</p>"#, options: [.dotMatchesLineSeparators]).map(decodeHTML) ?? "No description"
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

    private func extractHTML(in html: String, startMarker: String, endMarker: String) -> String? {
        guard let start = html.range(of: startMarker)?.upperBound,
              let end = html.range(of: endMarker, range: start..<html.endIndex)?.lowerBound else {
            return nil
        }
        return String(html[start..<end])
    }

    private func htmlToPlainText(_ html: String) -> String? {
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

    private func decodeHTML(_ string: String) -> String {
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

    private func stripHTML(_ string: String) -> String {
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

        let reference = String(trimmed[referenceRange])
        let skillName: String?
        if match.range(at: 2).location != NSNotFound,
           let skillRange = Range(match.range(at: 2), in: trimmed) {
            skillName = String(trimmed[skillRange])
        } else {
            skillName = nil
        }

        return ParsedInstallReference(reference: reference, skillName: skillName)
    }

    private func firstMatch(
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

    private func allMatches(
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

    private func parseMayidataDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy/M/d"
        return formatter.date(from: string.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func updateReference(for metadata: SkillSourceMetadata?) -> String? {
        guard let metadata else { return nil }
        if let repoURL = metadata.repoURL?.trimmingCharacters(in: .whitespacesAndNewlines), !repoURL.isEmpty {
            return repoURL
        }
        if let repoFullName = metadata.repoFullName?.trimmingCharacters(in: .whitespacesAndNewlines), !repoFullName.isEmpty {
            return repoFullName
        }
        return nil
    }

    private func relativePath(from base: URL, to target: URL) -> String {
        let basePath = base.standardizedFileURL.path
        let targetPath = target.standardizedFileURL.path
        if targetPath == basePath {
            return "."
        }
        return String(targetPath.dropFirst(basePath.count + 1))
    }

    private func relativePathComponents(from base: URL, to target: URL) -> [String] {
        let relative = relativePath(from: base, to: target)
        if relative == "." {
            return []
        }
        return relative.split(separator: "/").map(String.init)
    }

    private func isDanglingSymlink(_ url: URL) -> Bool {
        ((try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false)
    }
}

private struct SkillsShSearchResponse: Decodable {
    let skills: [SkillsShSearchSkill]
}

private struct SkillsShSearchSkill: Decodable {
    let id: String
    let skillId: String
    let name: String
    let installs: Int
    let source: String
}

private struct GitHubSearchEmbeddedData: Decodable {
    let payload: GitHubSearchEmbeddedPayload
}

private struct GitHubSearchEmbeddedPayload: Decodable {
    let results: [GitHubSearchEmbeddedRepository]
}

private struct GitHubSearchEmbeddedRepository: Decodable {
    let highlightedDescription: String?
    let language: String?
    let repo: GitHubSearchEmbeddedRepoContainer
    let stars: Int
    let topics: [String]

    enum CodingKeys: String, CodingKey {
        case highlightedDescription = "hl_trunc_description"
        case language
        case repo
        case stars = "followers"
        case topics
    }
}

private struct GitHubSearchEmbeddedRepoContainer: Decodable {
    let repository: GitHubSearchEmbeddedRepo
}

private struct GitHubSearchEmbeddedRepo: Decodable {
    let name: String
    let ownerLogin: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case name
        case ownerLogin = "owner_login"
        case updatedAt = "updated_at"
    }
}

private struct GitHubRepositoryItem: Decodable {
    let fullName: String
    let htmlURL: URL
    let cloneURL: URL
    let description: String?
    let stars: Int
    let pushedAt: Date
    let language: String?
    let topics: [String]?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case htmlURL = "html_url"
        case cloneURL = "clone_url"
        case description
        case stars = "stargazers_count"
        case pushedAt = "pushed_at"
        case language
        case topics
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

@MainActor
final class SkillPlatformViewModel: ObservableObject {
    @Published private(set) var skills: [InstalledSkill] = []
    @Published private(set) var agentSnapshots: [SkillAgentLinkSnapshot] = []
    @Published private(set) var marketplaceItems: [SkillMarketplaceItem] = []
    @Published var installReference = ""
    @Published var marketplaceQuery = ""
    @Published var marketplaceSource: SkillMarketplaceSource = .all
    @Published var skillsShLeaderboard: SkillsShLeaderboardKind = .hot
    @Published var isRefreshingLocal = false
    @Published var isRefreshingMarketplace = false
    @Published var isInstallingReference = false
    @Published var isUpdatingSkills = false
    @Published var marketplaceHasLoaded = false
    @Published var isPreviewLoading = false
    @Published var previewDocument: SkillPreviewDocument?
    @Published var installingMarketplaceItemID: String?
    @Published var statusMessage = ""
    @Published var statusIsError = false
    @Published var statusIsBusy = false

    let manager: SkillManager
    private var didInitialLoad = false

    init(manager: SkillManager = SkillManager()) {
        self.manager = manager
    }

    func loadIfNeeded() {
        guard !didInitialLoad else { return }
        didInitialLoad = true
        refreshLocal()
        Task {
            await refreshMarketplace()
        }
    }

    func refreshLocal() {
        isRefreshingLocal = true
        defer { isRefreshingLocal = false }

        do {
            skills = try manager.discoverSkills()
            agentSnapshots = manager.agentSnapshots()
        } catch {
            publish(error)
        }
    }

    func refreshMarketplace() async {
        isRefreshingMarketplace = true
        defer {
            isRefreshingMarketplace = false
            marketplaceHasLoaded = true
        }

        do {
            marketplaceItems = try await manager.marketplaceItems(
                source: marketplaceSource,
                query: marketplaceQuery,
                leaderboard: skillsShLeaderboard
            )
        } catch {
            publish(error)
        }
    }

    func openSharedRoot() {
        manager.openSharedRoot()
    }

    func reveal(_ url: URL) {
        manager.reveal(url)
    }

    func importFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let installed = try manager.importSkills(from: url)
            let repair = manager.repairGlobalAgentLinks()
            refreshLocal()
            publishSuccess(successMessage("Imported \(installed.count) skill(s)", repair: repair))
        } catch {
            publish(error)
        }
    }

    func installFromReference() {
        let reference = installReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty else { return }

        isInstallingReference = true
        publishProgress("Installing \(reference)…")
        Task {
            do {
                let installed = try await manager.installRepository(reference: reference)
                await MainActor.run {
                    let repair = self.manager.repairGlobalAgentLinks()
                    self.installReference = ""
                    self.isInstallingReference = false
                    self.refreshLocal()
                    self.publishSuccess(self.successMessage("Installed \(installed.count) skill(s)", repair: repair))
                }
            } catch {
                await MainActor.run {
                    self.isInstallingReference = false
                    self.publish(error)
                }
            }
        }
    }

    func install(_ item: SkillMarketplaceItem) {
        guard item.canInstallDirectly else {
            publishSuccess("This source can be browsed and previewed, but direct install is not supported yet")
            return
        }
        isInstallingReference = true
        installingMarketplaceItemID = item.id
        publishProgress("Installing \(item.title)…")
        Task {
            do {
                let installed = try await manager.installMarketplaceItem(item)
                await MainActor.run {
                    let repair = self.manager.repairGlobalAgentLinks()
                    self.isInstallingReference = false
                    self.installingMarketplaceItemID = nil
                    self.refreshLocal()
                    self.publishSuccess(self.successMessage("Installed \(installed.count) skill(s)", repair: repair))
                }
            } catch {
                await MainActor.run {
                    self.isInstallingReference = false
                    self.installingMarketplaceItemID = nil
                    self.publish(error)
                }
            }
        }
    }

    func adopt(_ skill: InstalledSkill) {
        do {
            _ = try manager.importSkillToSharedLibrary(skill)
            let repair = manager.repairGlobalAgentLinks()
            refreshLocal()
            publishSuccess(successMessage("Imported \(skill.name) into the shared library", repair: repair))
        } catch {
            publish(error)
        }
    }

    func adoptAllExternalSkills() {
        let candidates = skills.filter { !$0.isSharedLibrarySkill && $0.isAdoptableToSharedLibrary }
        guard !candidates.isEmpty else { return }

        do {
            let summary = try manager.importSkillsToSharedLibrary(candidates)
            let repair = manager.repairGlobalAgentLinks()
            refreshLocal()
            if summary.skippedCount > 0 {
                publishSuccess(successMessage("Imported \(summary.importedCount) skill(s), skipped \(summary.skippedCount)", repair: repair))
            } else {
                publishSuccess(successMessage("Imported \(summary.importedCount) skill(s) into the shared library", repair: repair))
            }
        } catch {
            publish(error)
        }
    }

    func preview(_ skill: InstalledSkill) {
        do {
            previewDocument = try manager.previewDocument(for: skill)
        } catch {
            publish(error)
        }
    }

    func preview(_ item: SkillMarketplaceItem) {
        isPreviewLoading = true
        Task {
            do {
                let document = try await manager.previewDocument(for: item)
                await MainActor.run {
                    self.isPreviewLoading = false
                    self.previewDocument = document
                }
            } catch {
                await MainActor.run {
                    self.isPreviewLoading = false
                    self.publish(error)
                }
            }
        }
    }

    func updateAllSkills() {
        let updatableSkills = skills.filter(\.isUpdatable)
        guard !updatableSkills.isEmpty else {
            publish(SkillPlatformError.noUpdateSource)
            return
        }

        isUpdatingSkills = true
        Task {
            do {
                let updated = try await manager.updateAllSkills(updatableSkills)
                await MainActor.run {
                    let repair = self.manager.repairGlobalAgentLinks()
                    self.isUpdatingSkills = false
                    self.refreshLocal()
                    self.publishSuccess(self.successMessage("Updated \(updated.count) skill(s)", repair: repair))
                }
            } catch {
                await MainActor.run {
                    self.isUpdatingSkills = false
                    self.publish(error)
                }
            }
        }
    }

    func update(_ skill: InstalledSkill) {
        guard skill.isUpdatable else {
            publish(SkillPlatformError.noUpdateSource)
            return
        }

        isUpdatingSkills = true
        Task {
            do {
                let updated = try await manager.updateSkill(skill)
                await MainActor.run {
                    let repair = self.manager.repairGlobalAgentLinks()
                    self.isUpdatingSkills = false
                    self.refreshLocal()
                    self.publishSuccess(self.successMessage("Updated \(updated.count) skill(s)", repair: repair))
                }
            } catch {
                await MainActor.run {
                    self.isUpdatingSkills = false
                    self.publish(error)
                }
            }
        }
    }

    func linkAllAgents() {
        do {
            try manager.linkAllAgents()
            refreshLocal()
            publishSuccess("Linked supported agents")
        } catch {
            publish(error)
        }
    }

    func link(_ snapshot: SkillAgentLinkSnapshot) {
        do {
            try manager.link(snapshot.agent)
            refreshLocal()
            publishSuccess("Linked \(snapshot.agent.title)")
        } catch {
            publish(error)
        }
    }

    func unlink(_ snapshot: SkillAgentLinkSnapshot) {
        do {
            try manager.unlink(snapshot.agent)
            refreshLocal()
            publishSuccess("Unlinked \(snapshot.agent.title)")
        } catch {
            publish(error)
        }
    }

    func resolveConflict(_ snapshot: SkillAgentLinkSnapshot) {
        do {
            let summary = try manager.resolveConflict(for: snapshot.agent)
            refreshLocal()
            publishSuccess(conflictResolutionMessage(summary))
        } catch {
            publish(error)
        }
    }

    func resolveAllConflicts() {
        do {
            let summary = try manager.resolveAllConflicts()
            refreshLocal()
            publishSuccess(bulkConflictResolutionMessage(summary))
        } catch {
            publish(error)
        }
    }

    func remove(_ skill: InstalledSkill) {
        do {
            try manager.removeSkill(skill)
            refreshLocal()
            publishSuccess("Removed \(skill.name)")
        } catch {
            publish(error)
        }
    }

    private func publishProgress(_ message: String) {
        statusMessage = message
        statusIsError = false
        statusIsBusy = true
    }

    private func publishSuccess(_ message: String) {
        statusMessage = message
        statusIsError = false
        statusIsBusy = false
    }

    private func successMessage(_ base: String, repair: SkillLinkRepairSummary) -> String {
        guard repair.linkedCount > 0 || repair.conflictCount > 0 else { return base }
        if repair.conflictCount > 0 {
            return "\(base) · linked \(repair.linkedCount) agent(s), \(repair.conflictCount) conflict(s)"
        }
        return "\(base) · linked \(repair.linkedCount) agent(s)"
    }

    private func conflictResolutionMessage(_ summary: SkillConflictResolutionSummary) -> String {
        if summary.skippedCount > 0 {
            return "Resolved \(summary.agent.title) conflict · imported \(summary.importedCount), skipped \(summary.skippedCount)"
        }
        return "Resolved \(summary.agent.title) conflict · imported \(summary.importedCount) skill(s)"
    }

    private func bulkConflictResolutionMessage(_ summary: SkillBulkConflictResolutionSummary) -> String {
        guard summary.resolvedCount > 0 else {
            return "No conflicts were resolved"
        }
        if summary.skippedCount > 0 {
            return "Resolved \(summary.resolvedCount) conflict(s) · imported \(summary.importedCount), skipped \(summary.skippedCount)"
        }
        return "Resolved \(summary.resolvedCount) conflict(s) · imported \(summary.importedCount) skill(s)"
    }

    private func publish(_ error: Error) {
        statusMessage = error.localizedDescription
        statusIsError = true
        statusIsBusy = false
    }
}
