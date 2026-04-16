import Foundation
import SuperIslandCore

extension UsageMonitorCommand {
    // Codex quota is a single API source, so keep the transport and snapshot assembly adjacent.
    private struct CodexWindow {
        var usedPercent: Int
        var resetAtUnix: Int
        var resetAfterSeconds: Int
    }

    private struct CodexQuota {
        var primary: CodexWindow
        var secondary: CodexWindow
        var summary: String?
    }

    func buildCodexSnapshot(now: TimeInterval) -> UsageProviderSnapshot? {
        guard let quota = fetchCodexQuota() else {
            return nil
        }

        let referenceDate = Date(timeIntervalSince1970: now)
        let primaryRemaining = AutomationUsageMonitorSupport.clampPercentage(100 - quota.primary.usedPercent)
        let secondaryRemaining = AutomationUsageMonitorSupport.clampPercentage(100 - quota.secondary.usedPercent)
        let usageHistory = CodexMonthlyUsageCalculator.loadUsageHistory()
        return UsageProviderSnapshot(
            source: .codex,
            primary: UsageWindowStat(
                label: "5h",
                percentage: primaryRemaining,
                detail: AutomationUsageMonitorSupport.codexWindowDetail(
                    resetAtUnix: quota.primary.resetAtUnix,
                    resetAfterSeconds: quota.primary.resetAfterSeconds,
                    now: referenceDate
                ),
                refreshAtUnix: AutomationUsageMonitorSupport.codexResetAtUnix(
                    resetAtUnix: quota.primary.resetAtUnix,
                    resetAfterSeconds: quota.primary.resetAfterSeconds,
                    now: referenceDate
                ),
                tintHex: AutomationUsageMonitorSupport.tintHex(forRemainingPercentage: primaryRemaining)
            ),
            secondary: UsageWindowStat(
                label: "7d",
                percentage: secondaryRemaining,
                detail: AutomationUsageMonitorSupport.codexWindowDetail(
                    resetAtUnix: quota.secondary.resetAtUnix,
                    resetAfterSeconds: quota.secondary.resetAfterSeconds,
                    now: referenceDate
                ),
                refreshAtUnix: AutomationUsageMonitorSupport.codexResetAtUnix(
                    resetAtUnix: quota.secondary.resetAtUnix,
                    resetAfterSeconds: quota.secondary.resetAfterSeconds,
                    now: referenceDate
                ),
                tintHex: AutomationUsageMonitorSupport.tintHex(forRemainingPercentage: secondaryRemaining)
            ),
            updatedAtUnix: now,
            summary: quota.summary,
            monthly: usageHistory.monthly,
            history: usageHistory.history.isEmpty ? nil : usageHistory.history
        )
    }

    private func fetchCodexQuota() -> CodexQuota? {
        guard let token = loadCodexAccessToken(),
              let payload = fetchJSON(
                url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
                headers: [
                    "Authorization": "Bearer \(token)",
                    "Accept": "application/json",
                ]
              ),
              let rateLimit = payload["rate_limit"] as? [String: Any],
              let primaryWindow = rateLimit["primary_window"] as? [String: Any],
              let secondaryWindow = rateLimit["secondary_window"] as? [String: Any] else {
            return nil
        }

        return CodexQuota(
            primary: CodexWindow(
                usedPercent: AutomationUsageMonitorSupport.integerValue(primaryWindow["used_percent"]),
                resetAtUnix: AutomationUsageMonitorSupport.integerValue(primaryWindow["reset_at"]),
                resetAfterSeconds: AutomationUsageMonitorSupport.integerValue(primaryWindow["reset_after_seconds"])
            ),
            secondary: CodexWindow(
                usedPercent: AutomationUsageMonitorSupport.integerValue(secondaryWindow["used_percent"]),
                resetAtUnix: AutomationUsageMonitorSupport.integerValue(secondaryWindow["reset_at"]),
                resetAfterSeconds: AutomationUsageMonitorSupport.integerValue(secondaryWindow["reset_after_seconds"])
            ),
            summary: AutomationUsageMonitorSupport.codexUsageSummary(payload: payload)
        )
    }

    private func loadCodexAccessToken() -> String? {
        CodexAuthStore.load()?.accessToken
    }
}
