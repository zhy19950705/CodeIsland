import Foundation

enum CodexAccountManagerError: LocalizedError {
    case unsupportedRegistryVersion(Int)
    case missingImportPath
    case invalidAuthSnapshot(String)
    case missingCodexCLI
    case missingCodeIslandExecutable
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
        case .missingCodeIslandExecutable:
            return "CodeIsland executable was not found on this Mac"
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

struct CodexAccountManager {
    let codexHomeURL: URL
    let fileManager: FileManager

    init(codexHomeURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.codexHomeURL = codexHomeURL ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }

    func status(syncCurrentAuth shouldSyncCurrentAuth: Bool = true) throws -> CodexAccountManagerStatus {
        var registry = try loadRegistry()
        if shouldSyncCurrentAuth, try syncCurrentAuth(into: &registry) {
            try saveRegistry(registry)
        }
        let currentAuth = try? CodexAuthStore.load(from: activeAuthURL())
        let activeAccount = activeAccount(in: registry)
        return CodexAccountManagerStatus(
            registry: registry,
            currentAuth: currentAuth,
            activeAccount: activeAccount,
            registryURL: registryURL(),
            activeAuthURL: activeAuthURL()
        )
    }

    func listAccounts(syncCurrentAuth shouldSyncCurrentAuth: Bool = true) throws -> [CodexManagedAccount] {
        let status = try status(syncCurrentAuth: shouldSyncCurrentAuth)
        return displayAccounts(from: status.registry)
    }

    @discardableResult
    func syncCurrentAuth() throws -> CodexManagedAccount? {
        var registry = try loadRegistry()
        let changed = try syncCurrentAuth(into: &registry)
        if changed {
            try saveRegistry(registry)
        }
        return activeAccount(in: registry)
    }

    func importPath(
        _ path: URL? = nil,
        alias: String? = nil,
        cpa: Bool = false,
        purge: Bool = false
    ) throws -> CodexImportSummary {
        var registry = purge ? try emptyRegistryPreservingConfig() : try loadRegistry()
        var results: [CodexImportResult] = []

        let sources = try importSources(for: path, cpa: cpa, purge: purge)
        let allowAlias = sources.count == 1 && sources.first?.isDirectory == false && !purge

        for source in sources {
            let result = try importSource(
                source,
                alias: allowAlias ? alias : nil,
                cpa: cpa,
                activate: false,
                registry: &registry
            )
            results.append(result)
        }

        if purge {
            if fileManager.fileExists(atPath: activeAuthURL().path) {
                let activeResult = try importSource(
                    ImportSource(url: activeAuthURL(), label: "auth.json (active)", isDirectory: false),
                    alias: nil,
                    cpa: false,
                    activate: true,
                    registry: &registry
                )
                results.append(activeResult)
            }

            if registry.activeAccountKey == nil, let first = displayAccounts(from: registry).first {
                try activateAccount(first.accountKey, in: &registry, backupCurrentAuth: true)
            }
        }

        sortAccounts(&registry.accounts)
        try saveRegistry(registry)
        return CodexImportSummary(results: results)
    }

    @discardableResult
    func activateAccount(_ accountKey: String) throws -> CodexManagedAccount {
        var registry = try loadRegistry()
        _ = try syncCurrentAuth(into: &registry)
        try activateAccount(accountKey, in: &registry, backupCurrentAuth: true)
        try saveRegistry(registry)
        return try requireAccount(accountKey, in: registry)
    }

    @discardableResult
    func switchAccount(matching query: String) throws -> CodexManagedAccount {
        var registry = try loadRegistry()
        _ = try syncCurrentAuth(into: &registry)
        let matches = matchingAccounts(query: query, in: registry)
        guard !matches.isEmpty else {
            throw CodexAccountManagerError.accountNotFound(query)
        }
        guard matches.count == 1, let match = matches.first else {
            throw CodexAccountManagerError.ambiguousAccountQuery(query, matches.map(\.displayName))
        }
        try activateAccount(match.accountKey, in: &registry, backupCurrentAuth: true)
        try saveRegistry(registry)
        return match
    }

    func removeAccounts(query: String? = nil, accountKey: String? = nil, removeAll: Bool = false) throws -> [CodexManagedAccount] {
        var registry = try loadRegistry()
        _ = try syncCurrentAuth(into: &registry)

        let toRemove: [CodexManagedAccount]
        if removeAll {
            toRemove = registry.accounts
        } else if let accountKey {
            toRemove = try [requireAccount(accountKey, in: registry)]
        } else if let query, !query.isEmpty {
            let matches = matchingAccounts(query: query, in: registry)
            guard !matches.isEmpty else {
                throw CodexAccountManagerError.accountNotFound(query)
            }
            guard matches.count == 1 else {
                throw CodexAccountManagerError.ambiguousAccountQuery(query, matches.map(\.displayName))
            }
            toRemove = matches
        } else {
            throw CodexAccountManagerError.accountNotFound("")
        }

        let removedKeys = Set(toRemove.map(\.accountKey))
        try deleteManagedSnapshots(for: removedKeys)
        try deleteMatchingAuthBackups(for: removedKeys)

        let currentAuthSnapshot = try? CodexAuthStore.load(from: activeAuthURL())
        registry.accounts.removeAll { removedKeys.contains($0.accountKey) }

        if registry.accounts.isEmpty {
            registry.activeAccountKey = nil
            registry.activeAccountActivatedAtMs = nil
            if let currentRecordKey = currentAuthSnapshot?.recordKey, removedKeys.contains(currentRecordKey) {
                try? fileManager.removeItem(at: activeAuthURL())
            }
        } else if registry.activeAccountKey.map(removedKeys.contains) == true || registry.activeAccountKey == nil {
            let replacement = selectBestReplacement(from: registry.accounts)
            try activateAccount(replacement.accountKey, in: &registry, backupCurrentAuth: true)
        }

        sortAccounts(&registry.accounts)
        try saveRegistry(registry)
        return toRemove
    }

    @discardableResult
    func runCodexLogin(deviceAuth: Bool = false) throws -> CodexManagedAccount? {
        guard let executable = findBinary("codex") else {
            throw CodexAccountManagerError.missingCodexCLI
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = deviceAuth ? ["login", "--device-auth"] : ["login"]

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CodexAccountManagerError.codexLoginFailed(process.terminationStatus)
        }
        return try syncCurrentAuth()
    }

    func launchCodexLoginInTerminal(deviceAuth: Bool = false) throws {
        guard let executableURL = AutomationCLI.executableURL() else {
            throw CodexAccountManagerError.missingCodeIslandExecutable
        }

        let command = shellQuoted(executableURL.path)
            + " --codex-auth login"
            + (deviceAuth ? " --device-auth" : "")
        let script = """
        set loginCommand to "\(escapeAppleScript(command))"
        tell application id "com.apple.Terminal"
            activate
            do script loginCommand
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = String(
                data: pipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw CodexAccountManagerError.terminalLaunchFailed(
                output.isEmpty ? "Failed to open Terminal for Codex login" : output
            )
        }
    }

    @discardableResult
    func updateConfiguration(
        autoSwitchEnabled: Bool? = nil,
        threshold5hPercent: Int? = nil,
        thresholdWeeklyPercent: Int? = nil,
        apiUsageEnabled: Bool? = nil
    ) throws -> CodexAccountManagerStatus {
        var registry = try loadRegistry()
        if let autoSwitchEnabled {
            registry.autoSwitch.enabled = autoSwitchEnabled
        }
        if let threshold5hPercent {
            registry.autoSwitch.threshold5hPercent = min(max(threshold5hPercent, 0), 100)
        }
        if let thresholdWeeklyPercent {
            registry.autoSwitch.thresholdWeeklyPercent = min(max(thresholdWeeklyPercent, 0), 100)
        }
        if let apiUsageEnabled {
            registry.api.usage = apiUsageEnabled
        }
        try saveRegistry(registry)
        return try status(syncCurrentAuth: false)
    }

    @discardableResult
    func updateUsage(
        for accountKey: String,
        snapshot: CodexRateLimitSnapshot?,
        lastLocalRollout: CodexRolloutSignature? = nil
    ) throws -> CodexManagedAccount {
        var registry = try loadRegistry()
        guard let index = registry.accounts.firstIndex(where: { $0.accountKey == accountKey }) else {
            throw CodexAccountManagerError.accountNotFound(accountKey)
        }

        if let snapshot {
            registry.accounts[index].lastUsage = snapshot
            registry.accounts[index].lastUsageAt = Int64(Date().timeIntervalSince1970)
        }
        if let lastLocalRollout {
            registry.accounts[index].lastLocalRollout = lastLocalRollout
        }

        try saveRegistry(registry)
        return registry.accounts[index]
    }

    func registryURL() -> URL {
        accountsDirectoryURL()
            .appendingPathComponent("registry.json", isDirectory: false)
    }

    func activeAuthURL() -> URL {
        codexHomeURL.appendingPathComponent("auth.json", isDirectory: false)
    }

    func accountsDirectoryURL() -> URL {
        codexHomeURL.appendingPathComponent("accounts", isDirectory: true)
    }

    func snapshotURL(for accountKey: String) -> URL {
        accountsDirectoryURL()
            .appendingPathComponent("\(snapshotFileKey(for: accountKey)).auth.json", isDirectory: false)
    }

    private func emptyRegistryPreservingConfig() throws -> CodexAccountRegistry {
        let current = try loadRegistry()
        var registry = CodexAccountRegistry()
        registry.autoSwitch = current.autoSwitch
        registry.api = current.api
        return registry
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private func escapeAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    func loadRegistry() throws -> CodexAccountRegistry {
        let url = registryURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return CodexAccountRegistry()
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let registry = try decoder.decode(CodexAccountRegistry.self, from: data)
        if registry.schemaVersion > CodexAccountRegistry.currentSchemaVersion {
            throw CodexAccountManagerError.unsupportedRegistryVersion(registry.schemaVersion)
        }
        return registry
    }

    func saveRegistry(_ registry: CodexAccountRegistry) throws {
        try fileManager.createDirectory(at: accountsDirectoryURL(), withIntermediateDirectories: true)
        var normalized = registry
        normalized.schemaVersion = CodexAccountRegistry.currentSchemaVersion
        sortAccounts(&normalized.accounts)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(normalized)
        data.append(0x0A)

        let url = registryURL()
        let currentData = try? Data(contentsOf: url)
        guard currentData != data else { return }

        try backupFileIfNeeded(at: url, basename: "registry.json", replacementData: data)
        try data.write(to: url, options: .atomic)
    }

    private func sortAccounts(_ accounts: inout [CodexManagedAccount]) {
        accounts.sort {
            let lhsEmail = $0.email.lowercased()
            let rhsEmail = $1.email.lowercased()
            if lhsEmail != rhsEmail { return lhsEmail < rhsEmail }
            return $0.accountKey < $1.accountKey
        }
    }

    private func displayAccounts(from registry: CodexAccountRegistry) -> [CodexManagedAccount] {
        registry.accounts.sorted { lhs, rhs in
            if lhs.accountKey == registry.activeAccountKey { return true }
            if rhs.accountKey == registry.activeAccountKey { return false }
            let lhsFresh = recordFreshness(lhs)
            let rhsFresh = recordFreshness(rhs)
            if lhsFresh != rhsFresh { return lhsFresh > rhsFresh }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func activeAccount(in registry: CodexAccountRegistry) -> CodexManagedAccount? {
        guard let key = registry.activeAccountKey else { return nil }
        return registry.accounts.first(where: { $0.accountKey == key })
    }

    private func requireAccount(_ accountKey: String, in registry: CodexAccountRegistry) throws -> CodexManagedAccount {
        guard let account = registry.accounts.first(where: { $0.accountKey == accountKey }) else {
            throw CodexAccountManagerError.accountNotFound(accountKey)
        }
        return account
    }

    @discardableResult
    private func syncCurrentAuth(into registry: inout CodexAccountRegistry) throws -> Bool {
        let authURL = activeAuthURL()
        guard fileManager.fileExists(atPath: authURL.path) else { return false }

        let data = try Data(contentsOf: authURL)
        let snapshot = try CodexAuthStore.parse(data: data)
        guard let account = validatedAccount(from: snapshot, alias: nil, createdAt: Int64(Date().timeIntervalSince1970)) else {
            return false
        }

        let snapshotURL = self.snapshotURL(for: account.accountKey)
        try fileManager.createDirectory(at: accountsDirectoryURL(), withIntermediateDirectories: true)
        let snapshotChanged = try writeSnapshotIfNeeded(data, to: snapshotURL)

        let existingIndex = registry.accounts.firstIndex(where: { $0.accountKey == account.accountKey })
        let previous = existingIndex.map { registry.accounts[$0] }
        if let existingIndex {
            registry.accounts[existingIndex] = merge(account: registry.accounts[existingIndex], with: account)
        } else {
            registry.accounts.append(account)
        }

        let activeChanged = registry.activeAccountKey != account.accountKey
        setActiveAccountKey(account.accountKey, in: &registry)

        return snapshotChanged || activeChanged || previous != account
    }

    private func importSources(for path: URL?, cpa: Bool, purge: Bool) throws -> [ImportSource] {
        if let path {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path.path, isDirectory: &isDirectory) else {
                throw CodexAccountManagerError.missingImportPath
            }
            if isDirectory.boolValue {
                return try directoryImportSources(for: path, cpa: cpa, purge: purge)
            }
            return [ImportSource(url: path, label: displayLabel(for: path), isDirectory: false)]
        }

        if cpa {
            let defaultCPAPath = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".cli-proxy-api", isDirectory: true)
            return try directoryImportSources(for: defaultCPAPath, cpa: true, purge: false)
        }

        if purge {
            return try purgeSources()
        }

        throw CodexAccountManagerError.missingImportPath
    }

    private func purgeSources() throws -> [ImportSource] {
        let accountsURL = accountsDirectoryURL()
        guard fileManager.fileExists(atPath: accountsURL.path) else { return [] }
        let contents = try fileManager.contentsOfDirectory(
            at: accountsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        return try contents
            .filter {
                let name = $0.lastPathComponent
                return name.hasSuffix(".auth.json") || name.hasPrefix("auth.json.bak.")
            }
            .sorted(by: fileFreshnessAscending)
            .map { ImportSource(url: $0, label: displayLabel(for: $0), isDirectory: false) }
    }

    private func directoryImportSources(for directory: URL, cpa: Bool, purge: Bool) throws -> [ImportSource] {
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let filtered = contents.filter {
            let name = $0.lastPathComponent
            if purge {
                return name.hasSuffix(".auth.json") || name.hasPrefix("auth.json.bak.")
            }
            return name.hasSuffix(".json")
        }
        return try filtered
            .sorted(by: fileFreshnessAscending)
            .map { ImportSource(url: $0, label: displayLabel(for: $0), isDirectory: false) }
    }

    private func fileFreshnessAscending(lhs: URL, rhs: URL) throws -> Bool {
        let left = try lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
        let right = try rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
        return left < right
    }

    private func importSource(
        _ source: ImportSource,
        alias: String?,
        cpa: Bool,
        activate: Bool,
        registry: inout CodexAccountRegistry
    ) throws -> CodexImportResult {
        let data = try Data(contentsOf: source.url)
        let normalizedData = cpa ? try convertCPAAuth(data: data) : data

        let snapshot: CodexAuthSnapshot
        do {
            snapshot = try CodexAuthStore.parse(data: normalizedData)
        } catch {
            return CodexImportResult(label: source.label, status: .skipped, reason: "MalformedJson", accountKey: nil)
        }

        guard let account = validatedAccount(
            from: snapshot,
            alias: alias,
            createdAt: source.createdAtUnix
        ) else {
            let reason = importValidationReason(for: snapshot)
            return CodexImportResult(label: source.label, status: .skipped, reason: reason, accountKey: nil)
        }

        let snapshotURL = self.snapshotURL(for: account.accountKey)
        try fileManager.createDirectory(at: accountsDirectoryURL(), withIntermediateDirectories: true)
        _ = try writeSnapshotIfNeeded(normalizedData, to: snapshotURL)

        let existingIndex = registry.accounts.firstIndex(where: { $0.accountKey == account.accountKey })
        if let existingIndex {
            registry.accounts[existingIndex] = merge(account: registry.accounts[existingIndex], with: account)
        } else {
            registry.accounts.append(account)
        }

        if activate {
            setActiveAccountKey(account.accountKey, in: &registry)
        }

        return CodexImportResult(
            label: source.label,
            status: existingIndex == nil ? .imported : .updated,
            reason: nil,
            accountKey: account.accountKey
        )
    }

    private func validatedAccount(
        from snapshot: CodexAuthSnapshot,
        alias: String?,
        createdAt: Int64
    ) -> CodexManagedAccount? {
        guard snapshot.authMode == .chatgpt else { return nil }
        guard let email = snapshot.email, !email.isEmpty else { return nil }
        guard let chatgptAccountId = snapshot.chatgptAccountId, !chatgptAccountId.isEmpty else { return nil }
        guard let chatgptUserId = snapshot.chatgptUserId, !chatgptUserId.isEmpty else { return nil }
        guard let recordKey = snapshot.recordKey, !recordKey.isEmpty, snapshot.isConsistentAccount else { return nil }

        return CodexManagedAccount(
            accountKey: recordKey,
            chatgptAccountId: chatgptAccountId,
            chatgptUserId: chatgptUserId,
            email: email,
            alias: (alias ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            accountName: nil,
            plan: snapshot.planType,
            authMode: snapshot.authMode.rawValue,
            createdAt: createdAt,
            lastUsedAt: nil,
            lastUsage: nil,
            lastUsageAt: nil,
            lastLocalRollout: nil
        )
    }

    private func importValidationReason(for snapshot: CodexAuthSnapshot) -> String {
        if snapshot.authMode == .apiKey { return "UnsupportedAuthMode" }
        if snapshot.email == nil { return "MissingEmail" }
        if snapshot.chatgptAccountId == nil { return "MissingAccountId" }
        if snapshot.chatgptUserId == nil { return "MissingChatgptUserId" }
        if !snapshot.isConsistentAccount { return "AccountIdMismatch" }
        if snapshot.recordKey == nil { return "MissingRecordKey" }
        return "InvalidAuth"
    }

    private func merge(account existing: CodexManagedAccount, with incoming: CodexManagedAccount) -> CodexManagedAccount {
        var merged = existing
        merged.chatgptAccountId = incoming.chatgptAccountId
        merged.chatgptUserId = incoming.chatgptUserId
        merged.email = incoming.email
        if !incoming.alias.isEmpty || merged.alias.isEmpty {
            merged.alias = incoming.alias
        }
        if merged.accountName == nil {
            merged.accountName = incoming.accountName
        }
        if incoming.plan != nil || merged.plan == nil {
            merged.plan = incoming.plan
        }
        if incoming.authMode != nil || merged.authMode == nil {
            merged.authMode = incoming.authMode
        }
        merged.createdAt = min(existing.createdAt, incoming.createdAt)
        merged.lastUsedAt = max(existing.lastUsedAt ?? .min, incoming.lastUsedAt ?? .min) == .min
            ? nil
            : max(existing.lastUsedAt ?? .min, incoming.lastUsedAt ?? .min)
        if let incomingUsage = incoming.lastUsage {
            merged.lastUsage = incomingUsage
        }
        if let incomingUsageAt = incoming.lastUsageAt, incomingUsageAt >= (merged.lastUsageAt ?? .min) {
            merged.lastUsageAt = incomingUsageAt
        }
        if let incomingRollout = incoming.lastLocalRollout {
            merged.lastLocalRollout = incomingRollout
        }
        return merged
    }

    private func setActiveAccountKey(_ accountKey: String, in registry: inout CodexAccountRegistry) {
        registry.activeAccountKey = accountKey
        registry.activeAccountActivatedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        if let index = registry.accounts.firstIndex(where: { $0.accountKey == accountKey }) {
            registry.accounts[index].lastUsedAt = Int64(Date().timeIntervalSince1970)
        }
    }

    func activateAccount(
        _ accountKey: String,
        in registry: inout CodexAccountRegistry,
        backupCurrentAuth: Bool
    ) throws {
        _ = try requireAccount(accountKey, in: registry)
        let sourceURL = snapshotURL(for: accountKey)
        let destinationURL = activeAuthURL()
        let sourceData = try Data(contentsOf: sourceURL)
        if backupCurrentAuth {
            try backupFileIfNeeded(at: destinationURL, basename: "auth.json", replacementData: sourceData)
        }
        try fileManager.createDirectory(at: codexHomeURL, withIntermediateDirectories: true)
        try sourceData.write(to: destinationURL, options: .atomic)
        setActiveAccountKey(accountKey, in: &registry)
    }

    private func deleteManagedSnapshots(for accountKeys: Set<String>) throws {
        for accountKey in accountKeys {
            let url = snapshotURL(for: accountKey)
            try? fileManager.removeItem(at: url)
        }
    }

    private func deleteMatchingAuthBackups(for accountKeys: Set<String>) throws {
        let directory = accountsDirectoryURL()
        guard fileManager.fileExists(atPath: directory.path) else { return }
        let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        for url in contents where url.lastPathComponent.hasPrefix("auth.json.bak.") {
            guard let snapshot = try? CodexAuthStore.load(from: url),
                  let recordKey = snapshot.recordKey,
                  accountKeys.contains(recordKey) else {
                continue
            }
            try? fileManager.removeItem(at: url)
        }
    }

    private func selectBestReplacement(from accounts: [CodexManagedAccount]) -> CodexManagedAccount {
        accounts.max { lhs, rhs in
            replacementScore(lhs) < replacementScore(rhs)
        } ?? accounts[0]
    }

    private func replacementScore(_ account: CodexManagedAccount) -> Int64 {
        if let usageScore = usageScore(for: account) {
            return usageScore * 1_000_000 + recordFreshness(account)
        }
        return recordFreshness(account)
    }

    private func usageScore(for account: CodexManagedAccount) -> Int64? {
        let now = Int64(Date().timeIntervalSince1970)
        let fiveHour = remainingPercentage(window: resolveWindow(from: account.lastUsage, minutes: 300, fallbackPrimary: true), now: now)
        let weekly = remainingPercentage(window: resolveWindow(from: account.lastUsage, minutes: 10080, fallbackPrimary: false), now: now)
        switch (fiveHour, weekly) {
        case let (lhs?, rhs?):
            return min(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }

    private func resolveWindow(
        from snapshot: CodexRateLimitSnapshot?,
        minutes: Int,
        fallbackPrimary: Bool
    ) -> CodexRateLimitWindow? {
        if snapshot?.primary?.windowMinutes == minutes {
            return snapshot?.primary
        }
        if snapshot?.secondary?.windowMinutes == minutes {
            return snapshot?.secondary
        }
        return fallbackPrimary ? snapshot?.primary : snapshot?.secondary
    }

    private func remainingPercentage(window: CodexRateLimitWindow?, now: Int64) -> Int64? {
        guard let window else { return nil }
        if let resetsAt = window.resetsAt, Int64(resetsAt) <= now {
            return 100
        }
        return Int64(max(0, min(100, Int(100 - window.usedPercent))))
    }

    private func recordFreshness(_ account: CodexManagedAccount) -> Int64 {
        max(account.createdAt, account.lastUsedAt ?? .min, account.lastUsageAt ?? .min)
    }

    private func matchingAccounts(query: String, in registry: CodexAccountRegistry) -> [CodexManagedAccount] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return displayAccounts(from: registry).filter { account in
            account.accountKey.lowercased() == normalized
                || account.accountKey.lowercased().contains(normalized)
                || account.email.lowercased().contains(normalized)
                || (!account.alias.isEmpty && account.alias.lowercased().contains(normalized))
                || ((account.accountName ?? "").lowercased().contains(normalized))
        }
    }

    private func displayLabel(for url: URL) -> String {
        let name = url.lastPathComponent
        if name.hasSuffix(".auth.json") {
            return String(name.dropLast(".auth.json".count))
        }
        if name.hasSuffix(".json") {
            return String(name.dropLast(".json".count))
        }
        return name
    }

    private func writeSnapshotIfNeeded(_ data: Data, to url: URL) throws -> Bool {
        let currentData = try? Data(contentsOf: url)
        guard currentData != data else { return false }
        try data.write(to: url, options: .atomic)
        return true
    }

    private func backupFileIfNeeded(at url: URL, basename: String, replacementData: Data) throws {
        guard let currentData = try? Data(contentsOf: url), currentData != replacementData else {
            return
        }
        try fileManager.createDirectory(at: accountsDirectoryURL(), withIntermediateDirectories: true)
        let backupURL = accountsDirectoryURL().appendingPathComponent("\(basename).bak.\(backupTimestamp())", isDirectory: false)
        try currentData.write(to: backupURL, options: .atomic)
        try pruneBackups(prefix: "\(basename).bak.", keep: 5)
    }

    private func pruneBackups(prefix: String, keep: Int) throws {
        let directory = accountsDirectoryURL()
        guard fileManager.fileExists(atPath: directory.path) else { return }
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let backups = try contents
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .sorted {
                let lhs = try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
                let rhs = try $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
                return lhs > rhs
            }
        for backup in backups.dropFirst(keep) {
            try? fileManager.removeItem(at: backup)
        }
    }

    private func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func snapshotFileKey(for accountKey: String) -> String {
        if accountKey.isEmpty || accountKey == "." || accountKey == ".." {
            return base64URLEncoded(accountKey)
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        if accountKey.unicodeScalars.allSatisfy(allowed.contains) {
            return accountKey
        }
        return base64URLEncoded(accountKey)
    }

    private func base64URLEncoded(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func convertCPAAuth(data: Data) throws -> Data {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexAccountManagerError.invalidAuthSnapshot("Malformed CPA auth")
        }

        guard let refreshToken = nonEmptyString(root["refresh_token"]) else {
            throw CodexAccountManagerError.invalidAuthSnapshot("MissingRefreshToken")
        }

        let normalized: [String: Any?] = [
            "auth_mode": "chatgpt",
            "OPENAI_API_KEY": nil,
            "tokens": [
                "id_token": nonEmptyString(root["id_token"]) ?? "",
                "access_token": nonEmptyString(root["access_token"]) ?? "",
                "refresh_token": refreshToken,
                "account_id": nonEmptyString(root["account_id"]) ?? "",
            ],
            "last_refresh": nonEmptyString(root["last_refresh"]) ?? "",
        ]

        let payload = normalized.compactMapValues { $0 }
        let json = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        return json + Data("\n".utf8)
    }

    private func findBinary(_ name: String) -> String? {
        let searchPaths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
        ]
        return searchPaths.first { access($0, X_OK) == 0 }
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct ImportSource {
    var url: URL
    var label: String
    var isDirectory: Bool

    var createdAtUnix: Int64 {
        let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
        return Int64((modifiedAt ?? Date()).timeIntervalSince1970)
    }
}
