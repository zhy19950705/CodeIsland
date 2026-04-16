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

    // Accept a few known field variants so quota parsing survives minor API shape changes.
    private func parseClaudeWindow(_ payload: [String: Any]) -> ClaudeWindow {
        let utilization = firstClaudeUtilization(in: payload)
        let resetAt = firstClaudeResetAt(in: payload)
        return ClaudeWindow(utilization: utilization, resetAt: resetAt)
    }

    // Treat "all zero + no reset" as invalid so the UI falls back to local history instead of fake 0% badges.
    private func isMeaningfulClaudeQuota(_ quota: ClaudeQuota) -> Bool {
        let windows = [quota.primary, quota.secondary]
        return windows.contains { $0.utilization > 0 || $0.resetAt != nil }
    }

    // Reuse the same validity rule for cached UI snapshots so stale fake-zero badges do not stick around.
    private func isMeaningfulClaudeSnapshot(_ snapshot: UsageProviderSnapshot) -> Bool {
        let windows = [snapshot.primary, snapshot.secondary]
        return windows.contains { $0.percentage > 0 || $0.detail != "--" }
    }

    // Keep utilization parsing centralized because OAuth and web payloads may use slightly different keys.
    private func firstClaudeUtilization(in payload: [String: Any]) -> Double {
        let candidates: [Any?] = [
            payload["utilization"],
            payload["usage_ratio"],
            payload["ratio"],
            payload["used_ratio"],
            payload["used_percent"],
            payload["percent_used"],
            payload["percentage"],
            payload["value"],
        ]

        for candidate in candidates {
            let value = AutomationUsageMonitorSupport.normalizedClaudeUtilization(candidate)
            if value > 0 {
                return value
            }
        }

        // If the API explicitly reports 0, keep that signal only when a reset timestamp exists elsewhere.
        return AutomationUsageMonitorSupport.normalizedClaudeUtilization(payload["utilization"])
    }

    // Support common timestamp aliases used by web and desktop APIs.
    private func firstClaudeResetAt(in payload: [String: Any]) -> TimeInterval? {
        let candidates: [Any?] = [
            payload["resets_at"],
            payload["reset_at"],
            payload["resetsAt"],
            payload["resetAt"],
            payload["window_reset_at"],
            payload["windowResetAt"],
        ]

        for candidate in candidates {
            if let value = AutomationUsageMonitorSupport.parseTimestamp(candidate) {
                return value
            }
        }
        return nil
    }

    func buildClaudeSnapshot(
        now: TimeInterval,
        previousSnapshot: UsageProviderSnapshot?,
        history: (monthly: UsageMonthlyStat?, history: [UsageHistoryRangeSnapshot])
    ) -> UsageProviderSnapshot? {
        if let quota = fetchClaudeQuota(), isMeaningfulClaudeQuota(quota) {
            let primaryUsed = AutomationUsageMonitorSupport.clampPercentage(Int((quota.primary.utilization * 100).rounded()))
            let secondaryUsed = AutomationUsageMonitorSupport.clampPercentage(Int((quota.secondary.utilization * 100).rounded()))
            return UsageProviderSnapshot(
                source: .claude,
                primary: UsageWindowStat(
                    label: "5小时",
                    percentage: primaryUsed,
                    detail: AutomationUsageMonitorSupport.claudeWindowDetail(resetAt: quota.primary.resetAt),
                    refreshAtUnix: quota.primary.resetAt,
                    tintHex: AutomationUsageMonitorSupport.tintHex(forUsedPercentage: primaryUsed)
                ),
                secondary: UsageWindowStat(
                    label: "7天",
                    percentage: secondaryUsed,
                    detail: AutomationUsageMonitorSupport.claudeWindowDetail(resetAt: quota.secondary.resetAt),
                    refreshAtUnix: quota.secondary.resetAt,
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
           isMeaningfulClaudeSnapshot(previousSnapshot),
           let updatedAtUnix = previousSnapshot.updatedAtUnix,
           now - updatedAtUnix <= 6 * 60 * 60 {
            return UsageProviderSnapshot(
                source: .claude,
                primary: previousSnapshot.primary,
                secondary: previousSnapshot.secondary,
                updatedAtUnix: updatedAtUnix,
                summary: history.monthly == nil ? "使用缓存额度" : "使用缓存额度与本地 token 历史",
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
                label: "30天",
                percentage: 0,
                detail: history.monthly.map { AutomationUsageMonitorSupport.formatTokenCount($0.totalTokens) } ?? "--",
                tintHex: "#7A7A7A"
            ),
            secondary: UsageWindowStat(
                label: "日志",
                percentage: 0,
                detail: "本地历史",
                tintHex: "#7A7A7A"
            ),
            updatedAtUnix: now,
            summary: "额度不可用，当前展示本地 Claude 令牌历史",
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
                primary: parseClaudeWindow(fiveHour),
                secondary: parseClaudeWindow(sevenDay),
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
            primary: parseClaudeWindow(fiveHour),
            secondary: parseClaudeWindow(sevenDay),
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
