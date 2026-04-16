import Foundation
import SuperIslandCore

extension UsageMonitorCommand {
    // Cursor quota collection depends on browser cookie discovery, so keep the scan and API parsing together.
    private static let cursorSessionCookieNames: Set<String> = [
        "WorkosCursorSessionToken",
        "__Secure-next-auth.session-token",
        "next-auth.session-token",
        "wos-session",
        "__Secure-wos-session",
        "authjs.session-token",
        "__Secure-authjs.session-token",
    ]

    private struct CursorWindow {
        var label: String
        var usedPercent: Int
        var detail: String
    }

    private struct CursorQuota {
        var primary: CursorWindow
        var secondary: CursorWindow
        var summary: String?
    }

    private struct ChromiumBrowserSource {
        var label: String
        var baseDirectory: URL
        var safeStorageService: String
    }

    private struct ChromiumCookie {
        var name: String
        var value: String
    }

    private struct CursorCookieCandidate {
        var cookieHeader: String
        var sourceLabel: String
    }

    func buildCursorSnapshot(
        now: TimeInterval,
        previousSnapshot: UsageProviderSnapshot?
    ) -> UsageProviderSnapshot? {
        if let quota = fetchCursorQuota() {
            return UsageProviderSnapshot(
                source: .cursor,
                primary: UsageWindowStat(
                    label: quota.primary.label,
                    percentage: quota.primary.usedPercent,
                    detail: quota.primary.detail,
                    tintHex: AutomationUsageMonitorSupport.tintHex(forUsedPercentage: quota.primary.usedPercent)
                ),
                secondary: UsageWindowStat(
                    label: quota.secondary.label,
                    percentage: quota.secondary.usedPercent,
                    detail: quota.secondary.detail,
                    tintHex: AutomationUsageMonitorSupport.tintHex(forUsedPercentage: quota.secondary.usedPercent)
                ),
                updatedAtUnix: now,
                summary: quota.summary,
                monthly: nil,
                history: nil,
                showsQuotaBadge: true
            )
        }

        if let previousSnapshot,
           previousSnapshot.hasQuotaMetrics,
           let updatedAtUnix = previousSnapshot.updatedAtUnix,
           now - updatedAtUnix <= 6 * 60 * 60 {
            return UsageProviderSnapshot(
                source: .cursor,
                primary: previousSnapshot.primary,
                secondary: previousSnapshot.secondary,
                updatedAtUnix: updatedAtUnix,
                summary: "使用缓存的 Cursor 配额",
                monthly: nil,
                history: nil,
                showsQuotaBadge: true
            )
        }

        return nil
    }

    private func fetchCursorQuota() -> CursorQuota? {
        for candidate in loadCursorCookieCandidates(requireKnownSessionName: true) {
            if let quota = fetchCursorQuota(cookieHeader: candidate.cookieHeader, sourceLabel: candidate.sourceLabel) {
                return quota
            }
        }

        for candidate in loadCursorCookieCandidates(requireKnownSessionName: false) {
            if let quota = fetchCursorQuota(cookieHeader: candidate.cookieHeader, sourceLabel: candidate.sourceLabel) {
                return quota
            }
        }

        return nil
    }

    private func fetchCursorQuota(cookieHeader: String, sourceLabel: String) -> CursorQuota? {
        guard let usageResponse = fetchJSONResponse(
            url: URL(string: "https://cursor.com/api/usage-summary")!,
            headers: [
                "Cookie": cookieHeader,
                "Accept": "application/json",
            ]
        ), usageResponse.statusCode == 200,
        let payload = usageResponse.object else {
            return nil
        }

        let userPayload = fetchJSONResponse(
            url: URL(string: "https://cursor.com/api/auth/me")!,
            headers: [
                "Cookie": cookieHeader,
                "Accept": "application/json",
            ]
        )
        let userInfo = userPayload?.statusCode == 200 ? userPayload?.object : nil
        let userID = nonEmptyString(userInfo?["sub"])

        var requestUsage: [String: Any]?
        if let userID,
           let requestUsageResponse = fetchJSONResponse(
            url: URL(string: "https://cursor.com/api/usage?user=\(userID.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? userID)")!,
            headers: [
                "Cookie": cookieHeader,
                "Accept": "application/json",
            ]
           ),
           requestUsageResponse.statusCode == 200 {
            requestUsage = requestUsageResponse.object
        }

        let individualUsage = payload["individualUsage"] as? [String: Any]
        let plan = individualUsage?["plan"] as? [String: Any]
        let individualOnDemand = individualUsage?["onDemand"] as? [String: Any]
        let teamUsage = payload["teamUsage"] as? [String: Any]
        let teamOnDemand = teamUsage?["onDemand"] as? [String: Any]

        let autoPercent = AutomationUsageMonitorSupport.normalizedCursorPercent(plan?["autoPercentUsed"])
        let apiPercent = AutomationUsageMonitorSupport.normalizedCursorPercent(plan?["apiPercentUsed"])
        let totalPercent = AutomationUsageMonitorSupport.resolvedCursorTotalPercent(
            plan: plan,
            autoPercent: autoPercent,
            apiPercent: apiPercent
        )
        let billingCycleEnd = AutomationUsageMonitorSupport.parseTimestamp(payload["billingCycleEnd"])
        let resetDetail = AutomationUsageMonitorSupport.cursorResetDetail(resetAt: billingCycleEnd)

        var primary = CursorWindow(
            label: "总览",
            usedPercent: totalPercent,
            detail: resetDetail
        )

        if let requestWindow = parseCursorRequestWindow(requestUsage, resetDetail: resetDetail) {
            primary = requestWindow
        }

        let secondary = resolvedCursorSecondaryWindow(
            autoPercent: autoPercent,
            apiPercent: apiPercent,
            fallbackPercent: totalPercent,
            resetDetail: resetDetail
        )

        let summary = AutomationUsageMonitorSupport.cursorUsageSummary(
            payload: payload,
            plan: plan,
            individualOnDemand: individualOnDemand,
            teamOnDemand: teamOnDemand,
            userInfo: userInfo,
            sourceLabel: sourceLabel,
            apiPercent: apiPercent
        )

        return CursorQuota(primary: primary, secondary: secondary, summary: summary)
    }

    private func loadCursorCookieCandidates(requireKnownSessionName: Bool) -> [CursorCookieCandidate] {
        var candidates: [CursorCookieCandidate] = []
        for source in chromiumBrowserSources() {
            guard let safeStorageKey = loadSafeStorageKey(serviceName: source.safeStorageService) else {
                continue
            }

            for profileURL in chromiumProfileDirectories(baseDirectory: source.baseDirectory) {
                guard let cookies = loadChromiumCookies(
                    cookieStoreURL: profileURL.appendingPathComponent("Cookies", isDirectory: false),
                    key: safeStorageKey
                ), !cookies.isEmpty else {
                    continue
                }

                let hasKnownSessionName = cookies.contains { Self.cursorSessionCookieNames.contains($0.name) }
                guard requireKnownSessionName ? hasKnownSessionName : !hasKnownSessionName else { continue }

                let sourceLabel = sourceLabel(browser: source.label, profileURL: profileURL, domainCookiesOnly: !hasKnownSessionName)
                let cookieHeader = cookies
                    .map { "\($0.name)=\($0.value)" }
                    .joined(separator: "; ")
                guard !cookieHeader.isEmpty else { continue }

                candidates.append(
                    CursorCookieCandidate(
                        cookieHeader: cookieHeader,
                        sourceLabel: sourceLabel
                    )
                )
            }
        }

        return candidates
    }

    private func chromiumBrowserSources() -> [ChromiumBrowserSource] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            ChromiumBrowserSource(
                label: "Arc",
                baseDirectory: home.appendingPathComponent("Library/Application Support/Arc/User Data", isDirectory: true),
                safeStorageService: "Arc Safe Storage"
            ),
            ChromiumBrowserSource(
                label: "Chrome",
                baseDirectory: home.appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true),
                safeStorageService: "Chrome Safe Storage"
            ),
            ChromiumBrowserSource(
                label: "Brave",
                baseDirectory: home.appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser", isDirectory: true),
                safeStorageService: "Brave Safe Storage"
            ),
            ChromiumBrowserSource(
                label: "Edge",
                baseDirectory: home.appendingPathComponent("Library/Application Support/Microsoft Edge", isDirectory: true),
                safeStorageService: "Microsoft Edge Safe Storage"
            ),
            ChromiumBrowserSource(
                label: "Chromium",
                baseDirectory: home.appendingPathComponent("Library/Application Support/Chromium", isDirectory: true),
                safeStorageService: "Chromium Safe Storage"
            ),
        ]
    }

    private func chromiumProfileDirectories(baseDirectory: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents
            .filter { url in
                let name = url.lastPathComponent
                guard name == "Default" || name.hasPrefix("Profile ") || name == "Guest Profile" else {
                    return false
                }
                return FileManager.default.fileExists(atPath: url.appendingPathComponent("Cookies", isDirectory: false).path)
            }
            .sorted { lhs, rhs in
                if lhs.lastPathComponent == rhs.lastPathComponent { return lhs.path < rhs.path }
                if lhs.lastPathComponent == "Default" { return true }
                if rhs.lastPathComponent == "Default" { return false }
                return lhs.lastPathComponent < rhs.lastPathComponent
            }
    }

    private func loadChromiumCookies(cookieStoreURL: URL, key: Data) -> [ChromiumCookie]? {
        let query = """
        select name || char(31) || hex(value) || char(31) || hex(encrypted_value)
        from cookies
        where host_key in ('cursor.com','.cursor.com','www.cursor.com','.www.cursor.com','cursor.sh','.cursor.sh','authenticator.cursor.sh','.authenticator.cursor.sh')
           or host_key like '%.cursor.com'
           or host_key like '%.cursor.sh'
        order by host_key, name;
        """

        guard let raw = runProcess(
            executable: "/usr/bin/sqlite3",
            arguments: [
                "-readonly",
                cookieStoreURL.path,
                query
            ]
        ), !raw.isEmpty else {
            return nil
        }

        return raw
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: "\u{1F}", omittingEmptySubsequences: false)
                guard parts.count == 3 else { return nil }

                let name = String(parts[0])
                let valueHex = String(parts[1])
                let encryptedHex = String(parts[2])

                if let value = stringFromHexString(valueHex), !value.isEmpty {
                    return ChromiumCookie(name: name, value: value)
                }

                guard let encryptedData = dataFromHexString(encryptedHex),
                      let decryptedData = decryptChromiumCookieValue(encryptedData: encryptedData, key: key),
                      let decryptedValue = String(data: decryptedData, encoding: .utf8),
                      !decryptedValue.isEmpty else {
                    return nil
                }

                return ChromiumCookie(name: name, value: decryptedValue)
            }
    }

    private func sourceLabel(browser: String, profileURL: URL, domainCookiesOnly: Bool) -> String {
        let profileName = profileURL.lastPathComponent
        let base = profileName == "Default" ? browser : "\(browser) \(profileName)"
        return domainCookiesOnly ? "\(base) domain cookies" : base
    }

    private func loadSafeStorageKey(serviceName: String) -> Data? {
        guard let secret = runProcess(
            executable: "/usr/bin/security",
            arguments: ["find-generic-password", "-s", serviceName, "-w"]
        ), !secret.isEmpty else {
            return nil
        }

        return deriveClaudeDesktopKey(secret: secret)
    }

    private func parseCursorRequestWindow(_ payload: [String: Any]?, resetDetail: String) -> CursorWindow? {
        guard let payload,
              let requestFamily = payload["gpt-4"] as? [String: Any] else {
            return nil
        }

        let limit = AutomationUsageMonitorSupport.integerValue(requestFamily["maxRequestUsage"])
        guard limit > 0 else { return nil }

        let used = max(
            AutomationUsageMonitorSupport.integerValue(requestFamily["numRequestsTotal"]),
            AutomationUsageMonitorSupport.integerValue(requestFamily["numRequests"])
        )
        let percentage = AutomationUsageMonitorSupport.clampPercentage(
            Int((Double(used) / Double(limit) * 100).rounded())
        )
        let requestDetail = "\(used)/\(limit) req"

        return CursorWindow(
            label: "请求",
            usedPercent: percentage,
            detail: resetDetail == "--" ? requestDetail : "\(requestDetail) · \(resetDetail)"
        )
    }

    private func resolvedCursorSecondaryWindow(
        autoPercent: Int?,
        apiPercent: Int?,
        fallbackPercent: Int,
        resetDetail: String
    ) -> CursorWindow {
        if let autoPercent {
            return CursorWindow(label: "自动", usedPercent: autoPercent, detail: resetDetail)
        }

        if let apiPercent {
            return CursorWindow(label: "API", usedPercent: apiPercent, detail: resetDetail)
        }

        return CursorWindow(label: "套餐", usedPercent: fallbackPercent, detail: resetDetail)
    }
}
