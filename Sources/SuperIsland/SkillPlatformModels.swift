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
    let cloneURL: String?
    let sourcePath: String
    let installedAt: Date
    let installedRevision: String?
    let cachedRemoteRevision: String?
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
    // Fall back to the legacy behavior when the app cannot compare revisions yet.
    var isUpdatable: Bool {
        guard hasUpdateSource else { return false }
        guard let metadata = sourceMetadata else { return false }
        guard let installedRevision = metadata.installedRevision?.nilIfEmpty,
              let cachedRemoteRevision = metadata.cachedRemoteRevision?.nilIfEmpty else { return true }
        return installedRevision != cachedRemoteRevision
    }
    var hasUpdateSource: Bool {
        sourceMetadata?.cloneURL?.nilIfEmpty != nil
            || sourceMetadata?.repoURL?.nilIfEmpty != nil
            || sourceMetadata?.repoFullName?.nilIfEmpty != nil
    }
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
    let bodyHTML: String?
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

struct SkillManifestMetadata {
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

struct SkillStorageRoot: Hashable {
    let kind: SkillStorageKind
    let rootURL: URL
}

struct SkillsShSearchResponse: Decodable {
    let skills: [SkillsShSearchSkill]
}

struct SkillsShSearchSkill: Decodable {
    let id: String
    let skillId: String
    let name: String
    let installs: Int
    let source: String
}

struct GitHubSearchEmbeddedData: Decodable {
    let payload: GitHubSearchEmbeddedPayload
}

struct GitHubSearchEmbeddedPayload: Decodable {
    let results: [GitHubSearchEmbeddedRepository]
}

struct GitHubSearchEmbeddedRepository: Decodable {
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

struct GitHubSearchEmbeddedRepoContainer: Decodable {
    let repository: GitHubSearchEmbeddedRepo
}

struct GitHubSearchEmbeddedRepo: Decodable {
    let name: String
    let ownerLogin: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case name
        case ownerLogin = "owner_login"
        case updatedAt = "updated_at"
    }
}

struct GitHubRepositoryItem: Decodable {
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

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
