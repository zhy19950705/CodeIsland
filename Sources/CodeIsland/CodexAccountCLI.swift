import Foundation

struct CodexAccountCLICommand {
    let arguments: [String]

    func run() -> Int32 {
        do {
            return try execute()
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    private func execute() throws -> Int32 {
        guard let subcommand = arguments.first else {
            printHelp()
            return 0
        }

        let manager = CodexAccountManager()
        let autoSwitchManager = CodexAutoSwitchLaunchAgentManager()

        switch subcommand {
        case "help", "--help", "-h":
            printHelp()
            return 0

        case "status":
            let status = try manager.status()
            let serviceSnapshot = autoSwitchManager.snapshot()
            if arguments.contains("--json") {
                try printJSON(CLIStatusPayload(status: status, serviceSnapshot: serviceSnapshot))
            } else {
                printStatus(status, serviceSnapshot: serviceSnapshot)
            }
            return 0

        case "list":
            let status = try manager.status()
            let accounts = try manager.listAccounts(syncCurrentAuth: false)
            if arguments.contains("--json") {
                try printJSON(CLIListPayload(activeAccountKey: status.registry.activeAccountKey, accounts: accounts))
            } else {
                printAccounts(accounts, activeAccountKey: status.registry.activeAccountKey)
            }
            return 0

        case "sync":
            if let active = try manager.syncCurrentAuth() {
                print("Synced active auth: \(active.displayName) (\(active.accountKey))")
            } else {
                print("Current auth could not be imported into managed accounts.")
            }
            return 0

        case "import":
            let path = positionalArgument(after: subcommand)
            let alias = optionValue("--alias")
            let summary = try manager.importPath(path.map(URL.init(fileURLWithPath:)), alias: alias, cpa: arguments.contains("--cpa"), purge: arguments.contains("--purge"))
            printImportSummary(summary)
            return summary.skippedCount > 0 && (summary.importedCount + summary.updatedCount == 0) ? 1 : 0

        case "switch":
            guard let query = positionalArgument(after: subcommand) else {
                throw CodexAccountManagerError.accountNotFound("")
            }
            let account = try manager.switchAccount(matching: query)
            print("Activated: \(account.displayName) (\(account.accountKey))")
            return 0

        case "activate":
            guard let accountKey = positionalArgument(after: subcommand) else {
                throw CodexAccountManagerError.accountNotFound("")
            }
            let account = try manager.activateAccount(accountKey)
            print("Activated: \(account.displayName) (\(account.accountKey))")
            return 0

        case "remove":
            let accountKey = optionValue("--account-key")
            let query = positionalArgument(after: subcommand)
            let removed = try manager.removeAccounts(
                query: query,
                accountKey: accountKey,
                removeAll: arguments.contains("--all")
            )
            if removed.isEmpty {
                print("No accounts removed.")
            } else {
                print("Removed \(removed.count) account(s): \(removed.map(\.displayName).joined(separator: ", "))")
            }
            return 0

        case "login":
            let account = try manager.runCodexLogin(deviceAuth: arguments.contains("--device-auth"))
            if let account {
                print("Logged in and synced: \(account.displayName) (\(account.accountKey))")
            } else {
                print("Login completed, but current auth could not be imported.")
            }
            return 0

        case "config":
            return try handleConfig(manager: manager, autoSwitchManager: autoSwitchManager)

        case "daemon":
            let daemon = CodexAutoSwitchService()
            if arguments.contains("--watch") {
                try daemon.runWatch(log: logLine)
                return 0
            }
            let result = try daemon.runOnce(log: logLine)
            if let switched = result.switchedAccount {
                print("Switched to \(switched.displayName) (\(switched.accountKey))")
            } else {
                print(result.activeUsageUpdated ? "Auto-switch check complete; usage updated." : "Auto-switch check complete; no switch needed.")
            }
            return 0

        default:
            printHelp()
            return 1
        }
    }

    private func optionValue(_ flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    private func positionalArgument(after subcommand: String) -> String? {
        guard let start = arguments.firstIndex(of: subcommand) else { return nil }
        var index = arguments.index(after: start)
        while index < arguments.endIndex {
            let value = arguments[index]
            if value.hasPrefix("--") {
                if ["--alias", "--account-key"].contains(value) {
                    index = arguments.index(index, offsetBy: 2, limitedBy: arguments.endIndex) ?? arguments.endIndex
                    continue
                }
                index = arguments.index(after: index)
                continue
            }
            return value
        }
        return nil
    }

    private func printStatus(_ status: CodexAccountManagerStatus, serviceSnapshot: CodexAutoSwitchLaunchAgentSnapshot) {
        let active = status.activeAccount.map { "\($0.displayName) · \($0.subtitle)" } ?? "None"
        let currentAuth = status.currentAuth.map { snapshot in
            ([snapshot.email, snapshot.planType?.uppercased()].compactMap { $0 }).joined(separator: " · ")
        } ?? "Unavailable"

        print("Active account: \(active)")
        print("Managed accounts: \(status.registry.accounts.count)")
        print("Current auth: \(currentAuth)")
        print("Auto-switch: \(status.registry.autoSwitch.enabled ? "enabled" : "disabled") · 5h<\(status.registry.autoSwitch.threshold5hPercent)% · weekly<\(status.registry.autoSwitch.thresholdWeeklyPercent)%")
        print("Usage API: \(status.registry.api.usage ? "enabled" : "disabled")")
        print("Watcher service: \(serviceSnapshot.state.rawValue) · \(serviceSnapshot.detail)")
        print("Registry: \(status.registryURL.path)")
        print("Active auth: \(status.activeAuthURL.path)")
    }

    private func printAccounts(_ accounts: [CodexManagedAccount], activeAccountKey: String?) {
        if accounts.isEmpty {
            print("No managed Codex accounts.")
            return
        }

        for account in accounts {
            let marker = account.accountKey == activeAccountKey ? "*" : "-"
            print("\(marker) \(account.displayName) · \(account.subtitle) · \(account.accountKey)")
        }
    }

    private func printImportSummary(_ summary: CodexImportSummary) {
        for result in summary.results {
            switch result.status {
            case .imported:
                print("✓ imported  \(result.label)")
            case .updated:
                print("✓ updated   \(result.label)")
            case .skipped:
                let reason = result.reason ?? "Skipped"
                print("✗ skipped   \(result.label) (\(reason))")
            }
        }
        print("Import Summary: \(summary.importedCount) imported, \(summary.updatedCount) updated, \(summary.skippedCount) skipped")
    }

    private func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(value)
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }

    private func printHelp() {
        let help = """
        CodeIsland Codex account commands

        Usage:
          CodeIsland --codex-auth status [--json]
          CodeIsland --codex-auth list [--json]
          CodeIsland --codex-auth sync
          CodeIsland --codex-auth import <path> [--alias <alias>] [--cpa] [--purge]
          CodeIsland --codex-auth switch <query>
          CodeIsland --codex-auth activate <account-key>
          CodeIsland --codex-auth remove <query>
          CodeIsland --codex-auth remove --account-key <account-key>
          CodeIsland --codex-auth remove --all
          CodeIsland --codex-auth login [--device-auth]
          CodeIsland --codex-auth config auto enable|disable
          CodeIsland --codex-auth config auto [--5h <percent>] [--weekly <percent>]
          CodeIsland --codex-auth config api enable|disable
          CodeIsland --codex-auth daemon --once|--watch
        """
        print(help)
    }

    private func handleConfig(
        manager: CodexAccountManager,
        autoSwitchManager: CodexAutoSwitchLaunchAgentManager
    ) throws -> Int32 {
        guard arguments.count >= 2 else {
            printHelp()
            return 1
        }

        switch arguments[1] {
        case "auto":
            if arguments.contains("enable") {
                _ = try manager.updateConfiguration(autoSwitchEnabled: true)
                try autoSwitchManager.setEnabled(true)
                let status = try manager.status(syncCurrentAuth: false)
                print("Auto-switch enabled (\(status.registry.api.usage ? "API mode" : "local-only mode"))")
                return 0
            }
            if arguments.contains("disable") {
                _ = try manager.updateConfiguration(autoSwitchEnabled: false)
                try autoSwitchManager.setEnabled(false)
                print("Auto-switch disabled")
                return 0
            }

            let fiveHour = optionValue("--5h").flatMap(Int.init)
            let weekly = optionValue("--weekly").flatMap(Int.init)
            let status = try manager.updateConfiguration(
                threshold5hPercent: fiveHour,
                thresholdWeeklyPercent: weekly
            )
            print("Auto-switch thresholds: 5h<\(status.registry.autoSwitch.threshold5hPercent)% · weekly<\(status.registry.autoSwitch.thresholdWeeklyPercent)%")
            return 0

        case "api":
            if arguments.contains("enable") {
                _ = try manager.updateConfiguration(apiUsageEnabled: true)
                print("Usage API enabled")
                return 0
            }
            if arguments.contains("disable") {
                _ = try manager.updateConfiguration(apiUsageEnabled: false)
                print("Usage API disabled")
                return 0
            }
            printHelp()
            return 1

        default:
            printHelp()
            return 1
        }
    }

    private func logLine(_ line: String) {
        FileHandle.standardOutput.write(Data("\(line)\n".utf8))
    }
}

private struct CLIStatusPayload: Encodable {
    var activeAccountKey: String?
    var currentAuth: CodexAuthSnapshot?
    var activeAccount: CodexManagedAccount?
    var registryURL: String
    var activeAuthURL: String
    var accountCount: Int
    var autoSwitchEnabled: Bool
    var autoSwitchThreshold5h: Int
    var autoSwitchThresholdWeekly: Int
    var usageAPIEnabled: Bool
    var watcherServiceState: String
    var watcherServiceDetail: String

    init(status: CodexAccountManagerStatus, serviceSnapshot: CodexAutoSwitchLaunchAgentSnapshot) {
        self.activeAccountKey = status.registry.activeAccountKey
        self.currentAuth = status.currentAuth
        self.activeAccount = status.activeAccount
        self.registryURL = status.registryURL.path
        self.activeAuthURL = status.activeAuthURL.path
        self.accountCount = status.registry.accounts.count
        self.autoSwitchEnabled = status.registry.autoSwitch.enabled
        self.autoSwitchThreshold5h = status.registry.autoSwitch.threshold5hPercent
        self.autoSwitchThresholdWeekly = status.registry.autoSwitch.thresholdWeeklyPercent
        self.usageAPIEnabled = status.registry.api.usage
        self.watcherServiceState = serviceSnapshot.state.rawValue
        self.watcherServiceDetail = serviceSnapshot.detail
    }
}

private struct CLIListPayload: Encodable {
    var activeAccountKey: String?
    var accounts: [CodexManagedAccount]
}
