import Foundation
import SuperIslandCore

extension UsageMonitorCommand {
    // Claude quota fetches have two transport paths, so keep the desktop and web fallbacks together.
    private struct ClaudeWindow {
        var utilization: Double
        var resetAt: TimeInterval?
    }

    private struct ClaudeQuota {
        var primary: ClaudeWindow
        var secondary: ClaudeWindow
        var sourceLabel: String
    }

    func buildClaudeSnapshot(
        now: TimeInterval,
        previousSnapshot: UsageProviderSnapshot?,
        history: (monthly: UsageMonthlyStat?, history: [UsageHistoryRangeSnapshot])
    ) -> UsageProviderSnapshot? {
        if let quota = fetchClaudeQuota() {
            let primaryUsed = AutomationUsageMonitorSupport.clampPercentage(Int((quota.primary.utilization * 100).rounded()))
            let secondaryUsed = AutomationUsageMonitorSupport.clampPercentage(Int((quota.secondary.utilization * 100).rounded()))
            return UsageProviderSnapshot(
                source: .claude,
                primary: UsageWindowStat(
                    label: "5h",
                    percentage: primaryUsed,
                    detail: AutomationUsageMonitorSupport.claudeWindowDetail(resetAt: quota.primary.resetAt),
                    tintHex: AutomationUsageMonitorSupport.tintHex(forUsedPercentage: primaryUsed)
                ),
                secondary: UsageWindowStat(
                    label: "7d",
                    percentage: secondaryUsed,
                    detail: AutomationUsageMonitorSupport.claudeWindowDetail(resetAt: quota.secondary.resetAt),
                    tintHex: AutomationUsageMonitorSupport.tintHex(forUsedPercentage: secondaryUsed)
                ),
                updatedAtUnix: now,
                summary: AutomationUsageMonitorSupport.claudeQuotaSummary(
                    sourceLabel: quota.sourceLabel,
                    hasLocalHistory: history.monthly != nil
                ),
                monthly: history.monthly,
                history: history.history.isEmpty ? nil : history.history,
                showsQuotaBadge: true
            )
        }

        if let previousSnapshot,
           previousSnapshot.hasQuotaMetrics,
           let updatedAtUnix = previousSnapshot.updatedAtUnix,
           now - updatedAtUnix <= 6 * 60 * 60 {
            return UsageProviderSnapshot(
                source: .claude,
                primary: previousSnapshot.primary,
                secondary: previousSnapshot.secondary,
                updatedAtUnix: updatedAtUnix,
                summary: history.monthly == nil ? "Using cached quota" : "Using cached quota + local token history",
                monthly: history.monthly,
                history: history.history.isEmpty ? nil : history.history,
                showsQuotaBadge: true
            )
        }

        guard history.monthly != nil || !history.history.isEmpty else {
            return nil
        }

        return UsageProviderSnapshot(
            source: .claude,
            primary: UsageWindowStat(
                label: "30d",
                percentage: 0,
                detail: history.monthly.map { AutomationUsageMonitorSupport.formatTokenCount($0.totalTokens) } ?? "--",
                tintHex: "#7A7A7A"
            ),
            secondary: UsageWindowStat(
                label: "log",
                percentage: 0,
                detail: "Local history",
                tintHex: "#7A7A7A"
            ),
            updatedAtUnix: now,
            summary: "Quota unavailable; showing local Claude token history",
            monthly: history.monthly,
            history: history.history.isEmpty ? nil : history.history,
            showsQuotaBadge: false
        )
    }

    private func fetchClaudeQuota() -> ClaudeQuota? {
        let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        if let accessToken = loadClaudeCodeAccessToken(),
           let payload = fetchJSON(
                url: endpoint,
                headers: [
                    "Authorization": "Bearer \(accessToken)",
                    "Accept": "application/json",
                    "anthropic-beta": "oauth-2025-04-20",
                ]
           ),
           let fiveHour = payload["five_hour"] as? [String: Any],
           let sevenDay = payload["seven_day"] as? [String: Any] {
            return ClaudeQuota(
                primary: ClaudeWindow(
                    utilization: AutomationUsageMonitorSupport.normalizedClaudeUtilization(fiveHour["utilization"]),
                    resetAt: AutomationUsageMonitorSupport.parseTimestamp(fiveHour["resets_at"])
                ),
                secondary: ClaudeWindow(
                    utilization: AutomationUsageMonitorSupport.normalizedClaudeUtilization(sevenDay["utilization"]),
                    resetAt: AutomationUsageMonitorSupport.parseTimestamp(sevenDay["resets_at"])
                ),
                sourceLabel: "Claude Code OAuth"
            )
        }

        return fetchClaudeWebQuota()
    }

    private func loadClaudeCodeAccessToken() -> String? {
        if let keychainPayload = runProcess(executable: "/usr/bin/security", arguments: [
            "find-generic-password",
            "-s", "Claude Code-credentials",
            "-w",
        ]),
           let data = keychainPayload.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let nested = object["claudeAiOauth"] as? [String: Any],
           let accessToken = (nested["accessToken"] as? String) ?? (nested["access_token"] as? String),
           !accessToken.isEmpty {
            return accessToken
        }

        let credentialsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent(".credentials.json", isDirectory: false)
        guard let data = try? Data(contentsOf: credentialsURL),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let nested = payload["claudeAiOauth"] as? [String: Any],
           let accessToken = (nested["accessToken"] as? String) ?? (nested["access_token"] as? String),
           !accessToken.isEmpty {
            return accessToken
        }

        for key in ["accessToken", "access_token", "token"] {
            if let accessToken = payload[key] as? String, !accessToken.isEmpty {
                return accessToken
            }
        }
        return nil
    }

    private func fetchClaudeWebQuota() -> ClaudeQuota? {
        guard let sessionKey = loadClaudeWebSessionKey(),
              let organizationID = fetchClaudeWebOrganizationID(sessionKey: sessionKey),
              let payload = fetchJSON(
                url: URL(string: "https://claude.ai/api/organizations/\(organizationID)/usage")!,
                headers: [
                    "Cookie": "sessionKey=\(sessionKey)",
                    "Accept": "application/json",
                ]
              ),
              let fiveHour = payload["five_hour"] as? [String: Any],
              let sevenDay = payload["seven_day"] as? [String: Any] else {
            return nil
        }

        return ClaudeQuota(
            primary: ClaudeWindow(
                utilization: AutomationUsageMonitorSupport.normalizedClaudeUtilization(fiveHour["utilization"]),
                resetAt: AutomationUsageMonitorSupport.parseTimestamp(fiveHour["resets_at"])
            ),
            secondary: ClaudeWindow(
                utilization: AutomationUsageMonitorSupport.normalizedClaudeUtilization(sevenDay["utilization"]),
                resetAt: AutomationUsageMonitorSupport.parseTimestamp(sevenDay["resets_at"])
            ),
            sourceLabel: "Claude Web API"
        )
    }

    private func loadClaudeWebSessionKey() -> String? {
        let cookiesPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/Cookies", isDirectory: false)
            .path

        guard let encryptedHex = runProcess(
            executable: "/usr/bin/sqlite3",
            arguments: [
                "-readonly",
                cookiesPath,
                "select hex(encrypted_value) from cookies where host_key in ('claude.ai','.claude.ai') and name='sessionKey' order by host_key limit 1;"
            ]
        ),
        let encryptedData = dataFromHexString(encryptedHex),
        let safeStorageSecret = runProcess(
            executable: "/usr/bin/security",
            arguments: ["find-generic-password", "-s", "Claude Safe Storage", "-w"]
        ),
        let key = deriveClaudeDesktopKey(secret: safeStorageSecret),
        let decrypted = decryptClaudeDesktopCache(encryptedData: encryptedData, key: key) else {
            return nil
        }

        return extractClaudeSessionKey(from: decrypted)
    }

    private func fetchClaudeWebOrganizationID(sessionKey: String) -> String? {
        guard let payload = fetchJSONArray(
            url: URL(string: "https://claude.ai/api/organizations")!,
            headers: [
                "Cookie": "sessionKey=\(sessionKey)",
                "Accept": "application/json",
            ]
        ) else {
            return nil
        }

        let selected = payload.first(where: { organization in
            let capabilities = (organization["capabilities"] as? [String])?.map { $0.lowercased() } ?? []
            return capabilities.contains("chat")
        }) ?? payload.first(where: { organization in
            let capabilities = Set((organization["capabilities"] as? [String])?.map { $0.lowercased() } ?? [])
            return !(capabilities.count == 1 && capabilities.contains("api"))
        }) ?? payload.first

        return nonEmptyString(selected?["uuid"] ?? selected?["id"])
    }
}
