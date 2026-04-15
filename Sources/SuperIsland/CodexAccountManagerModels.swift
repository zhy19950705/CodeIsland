import Foundation

// CodexAccountManagerModels keeps the registry and account value types separate from the manager workflow code.
enum CodexAccountManagerError: LocalizedError {
    case unsupportedRegistryVersion(Int)
    case missingImportPath
    case invalidAuthSnapshot(String)
    case missingCodexCLI
    case missingSuperIslandExecutable
    case codexLoginFailed(Int32)
    case terminalLaunchFailed(String)
    case accountNotFound(String)
    case ambiguousAccountQuery(String, [String])

    var errorDescription: String? {
        switch self {
        case let .unsupportedRegistryVersion(version):
            return "Unsupported registry schema_version \(version)"
        case .missingImportPath:
            return "Import path is required"
        case let .invalidAuthSnapshot(reason):
            return "Invalid auth snapshot: \(reason)"
        case .missingCodexCLI:
            return "Codex CLI was not found on this Mac"
        case .missingSuperIslandExecutable:
            return "SuperIsland executable was not found on this Mac"
        case let .codexLoginFailed(status):
            return "codex login exited with status \(status)"
        case let .terminalLaunchFailed(message):
            return message
        case let .accountNotFound(query):
            return "No account matched '\(query)'"
        case let .ambiguousAccountQuery(query, matches):
            let suffix = matches.isEmpty ? "" : ": \(matches.joined(separator: ", "))"
            return "Multiple accounts matched '\(query)'\(suffix)"
        }
    }
}

struct CodexAutoSwitchConfig: Codable, Hashable, Sendable {
    var enabled: Bool = false
    var threshold5hPercent: Int = 10
    var thresholdWeeklyPercent: Int = 5

    enum CodingKeys: String, CodingKey {
        case enabled
        case threshold5hPercent = "threshold_5h_percent"
        case thresholdWeeklyPercent = "threshold_weekly_percent"
    }
}

struct CodexAPIConfig: Codable, Hashable, Sendable {
    var usage: Bool = true
    var account: Bool = true
}

struct CodexRateLimitWindow: Codable, Hashable, Sendable {
    var usedPercent: Double
    var windowMinutes: Int?
    var resetsAt: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }
}

struct CodexCreditsSnapshot: Codable, Hashable, Sendable {
    var hasCredits: Bool
    var unlimited: Bool
    var balance: String?

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }
}

struct CodexRateLimitSnapshot: Codable, Hashable, Sendable {
    var primary: CodexRateLimitWindow?
    var secondary: CodexRateLimitWindow?
    var credits: CodexCreditsSnapshot?
    var planType: String?

    enum CodingKeys: String, CodingKey {
        case primary
        case secondary
        case credits
        case planType = "plan_type"
    }
}

struct CodexRolloutSignature: Codable, Hashable, Sendable {
    var path: String
    var eventTimestampMs: Int64

    enum CodingKeys: String, CodingKey {
        case path
        case eventTimestampMs = "event_timestamp_ms"
    }
}

struct CodexManagedAccount: Codable, Hashable, Sendable, Identifiable {
    var accountKey: String
    var chatgptAccountId: String
    var chatgptUserId: String
    var email: String
    var alias: String
    var accountName: String?
    var plan: String?
    var authMode: String?
    var createdAt: Int64
    var lastUsedAt: Int64?
    var lastUsage: CodexRateLimitSnapshot?
    var lastUsageAt: Int64?
    var lastLocalRollout: CodexRolloutSignature?

    enum CodingKeys: String, CodingKey {
        case accountKey = "account_key"
        case chatgptAccountId = "chatgpt_account_id"
        case chatgptUserId = "chatgpt_user_id"
        case email
        case alias
        case accountName = "account_name"
        case plan
        case authMode = "auth_mode"
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
        case lastUsage = "last_usage"
        case lastUsageAt = "last_usage_at"
        case lastLocalRollout = "last_local_rollout"
    }

    var id: String { accountKey }

    var displayName: String {
        if let accountName, !accountName.isEmpty {
            return accountName
        }
        if !alias.isEmpty {
            return alias
        }
        return email
    }

    var subtitle: String {
        var parts: [String] = [email]
        if let plan, !plan.isEmpty {
            parts.append(plan.uppercased())
        }
        return parts.joined(separator: " · ")
    }
}

struct CodexAccountRegistry: Codable, Sendable {
    static let currentSchemaVersion = 3

    var schemaVersion: Int = currentSchemaVersion
    var activeAccountKey: String?
    var activeAccountActivatedAtMs: Int64?
    var autoSwitch: CodexAutoSwitchConfig = .init()
    var api: CodexAPIConfig = .init()
    var accounts: [CodexManagedAccount] = []

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case legacyVersion = "version"
        case activeAccountKey = "active_account_key"
        case activeAccountActivatedAtMs = "active_account_activated_at_ms"
        case autoSwitch = "auto_switch"
        case api
        case accounts
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? container.decodeIfPresent(Int.self, forKey: .legacyVersion)
            ?? Self.currentSchemaVersion
        self.schemaVersion = schemaVersion
        self.activeAccountKey = try container.decodeIfPresent(String.self, forKey: .activeAccountKey)
        self.activeAccountActivatedAtMs = try container.decodeIfPresent(Int64.self, forKey: .activeAccountActivatedAtMs)
        self.autoSwitch = try container.decodeIfPresent(CodexAutoSwitchConfig.self, forKey: .autoSwitch) ?? .init()
        self.api = try container.decodeIfPresent(CodexAPIConfig.self, forKey: .api) ?? .init()
        self.accounts = try container.decodeIfPresent([CodexManagedAccount].self, forKey: .accounts) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encodeIfPresent(activeAccountKey, forKey: .activeAccountKey)
        try container.encodeIfPresent(activeAccountActivatedAtMs, forKey: .activeAccountActivatedAtMs)
        try container.encode(autoSwitch, forKey: .autoSwitch)
        try container.encode(api, forKey: .api)
        try container.encode(accounts, forKey: .accounts)
    }
}

struct CodexAccountManagerStatus: Sendable {
    var registry: CodexAccountRegistry
    var currentAuth: CodexAuthSnapshot?
    var activeAccount: CodexManagedAccount?
    var registryURL: URL
    var activeAuthURL: URL
}

enum CodexImportStatus: String, Sendable {
    case imported
    case updated
    case skipped
}

struct CodexImportResult: Sendable {
    var label: String
    var status: CodexImportStatus
    var reason: String?
    var accountKey: String?
}

struct CodexImportSummary: Sendable {
    var results: [CodexImportResult]

    var importedCount: Int { results.filter { $0.status == .imported }.count }
    var updatedCount: Int { results.filter { $0.status == .updated }.count }
    var skippedCount: Int { results.filter { $0.status == .skipped }.count }
}
