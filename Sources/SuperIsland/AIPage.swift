import SwiftUI
import AppKit
import SuperIslandCore

// AIPage owns the state and async actions for usage monitoring and Codex account management.
struct AIPage: View {
    @ObservedObject var l10n = AppText.shared
    // Start from an empty snapshot so switching into the AI tab does not synchronously hit disk on the main thread.
    @State var usageSnapshot: UsageSnapshot = .empty
    @State var usageMonitorSnapshot = Self.loadingUsageMonitorSnapshot
    @State var usageStatusMessage = ""
    @State var usageStatusIsError = false
    @State var isTogglingUsageMonitor = false
    @State var isRefreshingUsage = false
    @State var codexStatus: CodexAccountManagerStatus?
    @State var codexAccounts: [CodexManagedAccount] = []
    @State var codexStatusMessage = ""
    @State var codexStatusIsError = false
    @State var isTogglingAutoSwitch = false
    @State var isRunningAutoSwitch = false
    @State var autoSwitchSnapshot = Self.loadingAutoSwitchSnapshot
    @State var autoSwitch5hThreshold = 10
    @State var autoSwitchWeeklyThreshold = 5
    @State var autoSwitchAPIUsageEnabled = true
    @State var hasActivatedContent = false
    @State private var hasScheduledInitialRefresh = false

    let usageMonitorManager = UsageMonitorLaunchAgentManager()
    let codexAccountManager = CodexAccountManager()
    let autoSwitchManager = CodexAutoSwitchLaunchAgentManager()

    static let loadingUsageMonitorSnapshot = UsageMonitorLaunchAgentSnapshot(
        state: .disabled,
        detail: "加载中…",
        plistPath: ""
    )

    static let loadingAutoSwitchSnapshot = CodexAutoSwitchLaunchAgentSnapshot(
        state: .disabled,
        detail: "加载中…",
        plistPath: ""
    )

    var body: some View {
        Group {
            if hasActivatedContent {
                aiForm
            } else {
                AIPageLoadingPlaceholder()
            }
        }
        .onAppear {
            guard !hasScheduledInitialRefresh else { return }
            hasScheduledInitialRefresh = true
            Task(priority: .utility) {
                await scheduleInitialRefresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UsageSnapshotStore.didUpdateNotification)) { _ in
            Task { await refreshUsageWithTimeout() }
        }
    }

    // Keep the heavy AI settings form behind a deferred activation step so tab switches stay responsive.
    private var aiForm: some View {
        Form {
            Section(l10n["usage_monitor_section"]) {
                AIUsageMonitorSection(
                    usageSnapshot: usageSnapshot,
                    usageMonitorSnapshot: usageMonitorSnapshot,
                    statusMessage: usageStatusMessage,
                    statusIsError: usageStatusIsError,
                    isTogglingUsageMonitor: isTogglingUsageMonitor,
                    isRefreshingUsage: isRefreshingUsage,
                    onToggleUsageMonitor: {
                        Task { await toggleUsageMonitor() }
                    },
                    onRefreshUsage: {
                        Task { await runUsageRefresh() }
                    }
                )
            }

            Section(l10n["codex_accounts_section"]) {
                AICodexAccountsSection(
                    codexStatus: codexStatus,
                    codexAccounts: codexAccounts,
                    statusMessage: codexStatusMessage,
                    statusIsError: codexStatusIsError,
                    onSyncCurrentAuth: {
                        Task {
                            do {
                                _ = try codexAccountManager.syncCurrentAuth()
                                await refreshCodexAccounts()
                                codexStatusMessage = l10n["codex_account_sync_complete"]
                                codexStatusIsError = false
                            } catch {
                                codexStatusMessage = error.localizedDescription
                                codexStatusIsError = true
                            }
                        }
                    },
                    onImportAccount: {
                        guard let selectedURL = chooseCodexImportPath() else { return }
                        Task {
                            do {
                                let summary = try codexAccountManager.importPath(selectedURL)
                                await refreshCodexAccounts()
                                codexStatusMessage = importSummary(summary)
                                codexStatusIsError = false
                            } catch {
                                codexStatusMessage = error.localizedDescription
                                codexStatusIsError = true
                            }
                        }
                    },
                    onLaunchLogin: {
                        do {
                            try codexAccountManager.launchCodexLoginInTerminal()
                            codexStatusMessage = l10n["codex_account_login_started"]
                            codexStatusIsError = false
                        } catch {
                            codexStatusMessage = error.localizedDescription
                            codexStatusIsError = true
                        }
                    },
                    onLaunchDeviceLogin: {
                        do {
                            try codexAccountManager.launchCodexLoginInTerminal(deviceAuth: true)
                            codexStatusMessage = l10n["codex_account_login_device_started"]
                            codexStatusIsError = false
                        } catch {
                            codexStatusMessage = error.localizedDescription
                            codexStatusIsError = true
                        }
                    },
                    onActivateAccount: { account in
                        Task {
                            do {
                                _ = try codexAccountManager.activateAccount(account.accountKey)
                                await refreshCodexAccounts()
                                codexStatusMessage = l10n["codex_account_activate_complete"]
                                codexStatusIsError = false
                            } catch {
                                codexStatusMessage = error.localizedDescription
                                codexStatusIsError = true
                            }
                        }
                    },
                    onRemoveAccount: { account in
                        Task {
                            do {
                                _ = try codexAccountManager.removeAccounts(accountKey: account.accountKey)
                                await refreshCodexAccounts()
                                codexStatusMessage = l10n["codex_account_remove_complete"]
                                codexStatusIsError = false
                            } catch {
                                codexStatusMessage = error.localizedDescription
                                codexStatusIsError = true
                            }
                        }
                    }
                )

                Divider()

                AIAutoSwitchSection(
                    autoSwitchSnapshot: autoSwitchSnapshot,
                    isTogglingAutoSwitch: isTogglingAutoSwitch,
                    isRunningAutoSwitch: isRunningAutoSwitch,
                    autoSwitch5hThreshold: autoSwitch5hThreshold,
                    autoSwitchWeeklyThreshold: autoSwitchWeeklyThreshold,
                    autoSwitchAPIUsageEnabled: autoSwitchAPIUsageEnabled,
                    onToggleAutoSwitch: {
                        Task { await toggleAutoSwitch() }
                    },
                    onRunAutoSwitch: {
                        Task { await runAutoSwitchNow() }
                    },
                    onUpdateThreshold5h: { newValue in
                        autoSwitch5hThreshold = newValue
                        updateAutoSwitchThresholds(fiveHour: newValue, weekly: nil)
                    },
                    onUpdateThresholdWeekly: { newValue in
                        autoSwitchWeeklyThreshold = newValue
                        updateAutoSwitchThresholds(fiveHour: nil, weekly: newValue)
                    },
                    onUpdateAPIUsage: { newValue in
                        autoSwitchAPIUsageEnabled = newValue
                        updateAutoSwitchAPIUsage(newValue)
                    }
                )
            }
        }
        .formStyle(.grouped)
    }
}
