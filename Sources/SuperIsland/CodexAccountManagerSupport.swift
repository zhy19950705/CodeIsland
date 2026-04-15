import Foundation

// CodexAccountManagerSupport isolates persistence, import normalization, and ranking helpers from the user-facing operations.
extension CodexAccountManager {
    func emptyRegistryPreservingConfig() throws -> CodexAccountRegistry {
        let current = try loadRegistry()
        var registry = CodexAccountRegistry()
        registry.autoSwitch = current.autoSwitch
        registry.api = current.api
        return registry
    }

    func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    func escapeAppleScript(_ value: String) -> String {
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

    func sortAccounts(_ accounts: inout [CodexManagedAccount]) {
        accounts.sort {
            let lhsEmail = $0.email.lowercased()
            let rhsEmail = $1.email.lowercased()
            if lhsEmail != rhsEmail { return lhsEmail < rhsEmail }
            return $0.accountKey < $1.accountKey
        }
    }

    func displayAccounts(from registry: CodexAccountRegistry) -> [CodexManagedAccount] {
        registry.accounts.sorted { lhs, rhs in
            if lhs.accountKey == registry.activeAccountKey { return true }
            if rhs.accountKey == registry.activeAccountKey { return false }
            let lhsFresh = recordFreshness(lhs)
            let rhsFresh = recordFreshness(rhs)
            if lhsFresh != rhsFresh { return lhsFresh > rhsFresh }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    func activeAccount(in registry: CodexAccountRegistry) -> CodexManagedAccount? {
        guard let key = registry.activeAccountKey else { return nil }
        return registry.accounts.first(where: { $0.accountKey == key })
    }

    func requireAccount(_ accountKey: String, in registry: CodexAccountRegistry) throws -> CodexManagedAccount {
        guard let account = registry.accounts.first(where: { $0.accountKey == accountKey }) else {
            throw CodexAccountManagerError.accountNotFound(accountKey)
        }
        return account
    }

    @discardableResult
    func syncCurrentAuth(into registry: inout CodexAccountRegistry) throws -> Bool {
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

    func importSources(for path: URL?, cpa: Bool, purge: Bool) throws -> [ImportSource] {
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

    func purgeSources() throws -> [ImportSource] {
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

    func directoryImportSources(for directory: URL, cpa: Bool, purge: Bool) throws -> [ImportSource] {
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

    func fileFreshnessAscending(lhs: URL, rhs: URL) throws -> Bool {
        let left = try lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
        let right = try rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
        return left < right
    }

    func importSource(
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

    func validatedAccount(
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

    func importValidationReason(for snapshot: CodexAuthSnapshot) -> String {
        if snapshot.authMode == .apiKey { return "UnsupportedAuthMode" }
        if snapshot.email == nil { return "MissingEmail" }
        if snapshot.chatgptAccountId == nil { return "MissingAccountId" }
        if snapshot.chatgptUserId == nil { return "MissingChatgptUserId" }
        if !snapshot.isConsistentAccount { return "AccountIdMismatch" }
        if snapshot.recordKey == nil { return "MissingRecordKey" }
        return "InvalidAuth"
    }

    func merge(account existing: CodexManagedAccount, with incoming: CodexManagedAccount) -> CodexManagedAccount {
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

    func setActiveAccountKey(_ accountKey: String, in registry: inout CodexAccountRegistry) {
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

    func deleteManagedSnapshots(for accountKeys: Set<String>) throws {
        for accountKey in accountKeys {
            let url = snapshotURL(for: accountKey)
            try? fileManager.removeItem(at: url)
        }
    }

    func deleteMatchingAuthBackups(for accountKeys: Set<String>) throws {
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

    func selectBestReplacement(from accounts: [CodexManagedAccount]) -> CodexManagedAccount {
        accounts.max { lhs, rhs in
            replacementScore(lhs) < replacementScore(rhs)
        } ?? accounts[0]
    }

    func replacementScore(_ account: CodexManagedAccount) -> Int64 {
        if let usageScore = usageScore(for: account) {
            return usageScore * 1_000_000 + recordFreshness(account)
        }
        return recordFreshness(account)
    }

    func usageScore(for account: CodexManagedAccount) -> Int64? {
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

    func resolveWindow(
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

    func remainingPercentage(window: CodexRateLimitWindow?, now: Int64) -> Int64? {
        guard let window else { return nil }
        if let resetsAt = window.resetsAt, Int64(resetsAt) <= now {
            return 100
        }
        return Int64(max(0, min(100, Int(100 - window.usedPercent))))
    }

    func recordFreshness(_ account: CodexManagedAccount) -> Int64 {
        max(account.createdAt, account.lastUsedAt ?? .min, account.lastUsageAt ?? .min)
    }

    func matchingAccounts(query: String, in registry: CodexAccountRegistry) -> [CodexManagedAccount] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return displayAccounts(from: registry).filter { account in
            account.accountKey.lowercased() == normalized
                || account.accountKey.lowercased().contains(normalized)
                || account.email.lowercased().contains(normalized)
                || (!account.alias.isEmpty && account.alias.lowercased().contains(normalized))
                || ((account.accountName ?? "").lowercased().contains(normalized))
        }
    }

    func displayLabel(for url: URL) -> String {
        let name = url.lastPathComponent
        if name.hasSuffix(".auth.json") {
            return String(name.dropLast(".auth.json".count))
        }
        if name.hasSuffix(".json") {
            return String(name.dropLast(".json".count))
        }
        return name
    }

    func writeSnapshotIfNeeded(_ data: Data, to url: URL) throws -> Bool {
        let currentData = try? Data(contentsOf: url)
        guard currentData != data else { return false }
        try data.write(to: url, options: .atomic)
        return true
    }

    func backupFileIfNeeded(at url: URL, basename: String, replacementData: Data) throws {
        guard let currentData = try? Data(contentsOf: url), currentData != replacementData else {
            return
        }
        try fileManager.createDirectory(at: accountsDirectoryURL(), withIntermediateDirectories: true)
        let backupURL = accountsDirectoryURL().appendingPathComponent("\(basename).bak.\(backupTimestamp())", isDirectory: false)
        try currentData.write(to: backupURL, options: .atomic)
        try pruneBackups(prefix: "\(basename).bak.", keep: 5)
    }

    func pruneBackups(prefix: String, keep: Int) throws {
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

    func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    func snapshotFileKey(for accountKey: String) -> String {
        if accountKey.isEmpty || accountKey == "." || accountKey == ".." {
            return base64URLEncoded(accountKey)
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        if accountKey.unicodeScalars.allSatisfy(allowed.contains) {
            return accountKey
        }
        return base64URLEncoded(accountKey)
    }

    func base64URLEncoded(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func convertCPAAuth(data: Data) throws -> Data {
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

    func findBinary(_ name: String) -> String? {
        let searchPaths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
        ]
        return searchPaths.first { access($0, X_OK) == 0 }
    }

    func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// ImportSource keeps file metadata attached to import jobs so purge/import ordering stays deterministic.
struct ImportSource {
    var url: URL
    var label: String
    var isDirectory: Bool

    var createdAtUnix: Int64 {
        let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
        return Int64((modifiedAt ?? Date()).timeIntervalSince1970)
    }
}
