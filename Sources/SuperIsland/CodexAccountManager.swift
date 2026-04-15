import Foundation

// CodexAccountManager keeps the public account operations together while storage and import helpers live in a support file.
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
            throw CodexAccountManagerError.missingSuperIslandExecutable
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
}
