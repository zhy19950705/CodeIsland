import SwiftUI
import AppKit
import SuperIslandCore

// AIPageActions keeps async refresh and mutation logic separate from the page layout while preserving the same behavior.
extension AIPage {
    struct TimeoutError: Error {}

    @MainActor
    func scheduleInitialRefresh() async {
        // Let the AI tab paint once before kicking off background refresh work.
        await Task.yield()
        hasActivatedContent = true
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await refreshUsageWithTimeout()
            }
            group.addTask {
                await refreshCodexAccountsWithTimeout()
            }
        }
    }

    func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // Run the requested operation and a timeout race in parallel so the settings UI never stalls indefinitely.
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    @MainActor
    func refreshUsage() async {
        await refreshUsageWithTimeout()
    }

    @MainActor
    func refreshUsageWithTimeout(timeout: TimeInterval = 5.0) async {
        do {
            let payload = try await withTimeout(seconds: timeout) {
                await Task.detached(priority: .utility) {
                    // Load snapshots off the main actor because these calls can touch disk and launchd state.
                    let usageSnapshot = UsageSnapshotStore.load()
                    let monitorSnapshot = UsageMonitorLaunchAgentManager().snapshot()
                    return (usageSnapshot, monitorSnapshot)
                }.value
            }
            usageSnapshot = payload.0
            usageMonitorSnapshot = payload.1
        } catch is TimeoutError {
            usageStatusMessage = "加载超时，请检查文件访问权限"
            usageStatusIsError = true
        } catch {
            usageStatusMessage = error.localizedDescription
            usageStatusIsError = true
        }
    }

    @MainActor
    func refreshCodexAccounts() async {
        await refreshCodexAccountsWithTimeout()
    }

    @MainActor
    func refreshCodexAccountsWithTimeout(timeout: TimeInterval = 5.0) async {
        do {
            let payload = try await withTimeout(seconds: timeout) {
                await Task.detached(priority: .utility) {
                    let accountManager = CodexAccountManager()

                    // Fetch status and accounts independently so one failure does not blank out the entire section.
                    let status: CodexAccountManagerStatus?
                    do {
                        status = try accountManager.status()
                    } catch {
                        status = nil
                    }

                    let accounts: [CodexManagedAccount]
                    do {
                        accounts = try accountManager.listAccounts(syncCurrentAuth: false)
                    } catch {
                        accounts = []
                    }

                    let autoSwitchSnapshot = CodexAutoSwitchLaunchAgentManager().snapshot()
                    return (status, accounts, autoSwitchSnapshot)
                }.value
            }

            codexStatus = payload.0
            codexAccounts = payload.1
            autoSwitchSnapshot = payload.2

            if let status = payload.0 {
                autoSwitch5hThreshold = status.registry.autoSwitch.threshold5hPercent
                autoSwitchWeeklyThreshold = status.registry.autoSwitch.thresholdWeeklyPercent
                autoSwitchAPIUsageEnabled = status.registry.api.usage
            }
        } catch is TimeoutError {
            codexStatusMessage = "加载超时，请检查文件访问权限或 Codex 配置"
            codexStatusIsError = true
            autoSwitchSnapshot = CodexAutoSwitchLaunchAgentSnapshot(
                state: .disabled,
                detail: "加载超时",
                plistPath: ""
            )
        } catch {
            codexStatusMessage = error.localizedDescription
            codexStatusIsError = true
        }
    }

    @MainActor
    func toggleUsageMonitor() async {
        isTogglingUsageMonitor = true
        defer { isTogglingUsageMonitor = false }

        do {
            let shouldEnable = usageMonitorSnapshot.state != .enabled
            try await Task.detached(priority: .userInitiated) {
                try UsageMonitorLaunchAgentManager().setEnabled(shouldEnable)
            }.value
            await refreshUsage()
            usageStatusMessage = shouldEnable
                ? l10n["usage_monitor_enabled"]
                : l10n["usage_monitor_disabled"]
            usageStatusIsError = false
        } catch {
            usageStatusMessage = error.localizedDescription
            usageStatusIsError = true
            await refreshUsage()
        }
    }

    @MainActor
    func runUsageRefresh() async {
        isRefreshingUsage = true
        defer { isRefreshingUsage = false }

        do {
            try await usageMonitorManager.runNow()
            await refreshUsage()
            usageStatusMessage = l10n["usage_refresh_complete"]
            usageStatusIsError = false
        } catch {
            usageStatusMessage = error.localizedDescription
            usageStatusIsError = true
        }
    }

    @MainActor
    func toggleAutoSwitch() async {
        isTogglingAutoSwitch = true
        defer { isTogglingAutoSwitch = false }

        do {
            let shouldEnable = autoSwitchSnapshot.state != .enabled
            try await Task.detached(priority: .userInitiated) {
                let accountManager = CodexAccountManager()
                let autoSwitchManager = CodexAutoSwitchLaunchAgentManager()
                _ = try accountManager.updateConfiguration(autoSwitchEnabled: shouldEnable)
                try autoSwitchManager.setEnabled(shouldEnable)
            }.value
            await refreshCodexAccounts()
            codexStatusMessage = shouldEnable
                ? l10n["codex_auto_switch_enabled"]
                : l10n["codex_auto_switch_disabled"]
            codexStatusIsError = false
        } catch {
            codexStatusMessage = error.localizedDescription
            codexStatusIsError = true
            await refreshCodexAccounts()
        }
    }

    @MainActor
    func runAutoSwitchNow() async {
        isRunningAutoSwitch = true
        defer { isRunningAutoSwitch = false }

        do {
            try await autoSwitchManager.runNow()
            await refreshCodexAccounts()
            codexStatusMessage = l10n["codex_auto_switch_run_complete"]
            codexStatusIsError = false
        } catch {
            codexStatusMessage = error.localizedDescription
            codexStatusIsError = true
        }
    }

    func updateAutoSwitchThresholds(fiveHour: Int?, weekly: Int?) {
        Task {
            do {
                _ = try codexAccountManager.updateConfiguration(
                    threshold5hPercent: fiveHour,
                    thresholdWeeklyPercent: weekly
                )
                await refreshCodexAccounts()
            } catch {
                codexStatusMessage = error.localizedDescription
                codexStatusIsError = true
            }
        }
    }

    func chooseCodexImportPath() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    func importSummary(_ summary: CodexImportSummary) -> String {
        "\(summary.importedCount) \(l10n["codex_account_imported"]) · \(summary.updatedCount) \(l10n["codex_account_updated"]) · \(summary.skippedCount) \(l10n["codex_account_skipped"])"
    }

    func updateAutoSwitchAPIUsage(_ enabled: Bool) {
        Task {
            do {
                _ = try codexAccountManager.updateConfiguration(apiUsageEnabled: enabled)
                await refreshCodexAccounts()
            } catch {
                codexStatusMessage = error.localizedDescription
                codexStatusIsError = true
            }
        }
    }
}
