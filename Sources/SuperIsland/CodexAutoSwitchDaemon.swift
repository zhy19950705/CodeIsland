import Foundation
import AppKit
#if canImport(Darwin)
import Darwin
#endif

struct CodexAutoSwitchRunResult: Sendable {
    var switchedAccount: CodexManagedAccount?
    var activeUsageUpdated: Bool
}

final class CodexAutoSwitchService {
    private let accountManager: CodexAccountManager
    private let usageClient: CodexUsageAPIClient
    private let sessionsScanner: CodexSessionsUsageScanner
    private let pollInterval: TimeInterval
    private var lastAPIRefreshAt: [String: Date] = [:]

    init(
        codexHomeURL: URL? = nil,
        fileManager: FileManager = .default,
        pollInterval: TimeInterval = 15
    ) {
        self.accountManager = CodexAccountManager(codexHomeURL: codexHomeURL, fileManager: fileManager)
        self.usageClient = CodexUsageAPIClient()
        self.sessionsScanner = CodexSessionsUsageScanner(fileManager: fileManager)
        self.pollInterval = pollInterval
    }

    func runOnce(log: @escaping (String) -> Void = { _ in }) throws -> CodexAutoSwitchRunResult {
        let status = try accountManager.status()
        var registry = status.registry

        guard registry.autoSwitch.enabled else {
            log("[switch] auto-switch disabled")
            return CodexAutoSwitchRunResult(switchedAccount: nil, activeUsageUpdated: false)
        }

        guard let activeAccountKey = registry.activeAccountKey,
              let activeIndex = registry.accounts.firstIndex(where: { $0.accountKey == activeAccountKey }) else {
            log("[switch] no active managed account")
            return CodexAutoSwitchRunResult(switchedAccount: nil, activeUsageUpdated: false)
        }

        var changed = false
        var activeUsageUpdated = false
        var activeAccount = registry.accounts[activeIndex]

        let rolloutScan = sessionsScanner.scanLatestUsage(
            codexHomeURL: accountManager.codexHomeURL,
            activatedAfterMs: registry.activeAccountActivatedAtMs ?? 0
        )
        if let rolloutScan,
           let usableSnapshot = rolloutScan.latestUsableSnapshot,
           let usableSignature = rolloutScan.latestUsableSignature,
           activeAccount.lastLocalRollout != usableSignature
        {
            activeAccount.lastUsage = usableSnapshot
            activeAccount.lastUsageAt = Int64(Date().timeIntervalSince1970)
            activeAccount.lastLocalRollout = usableSignature
            registry.accounts[activeIndex] = activeAccount
            changed = true
            activeUsageUpdated = true
            log("[local] refreshed usage from \(URL(fileURLWithPath: usableSignature.path).lastPathComponent)")
        }

        let latestLocalEventWasUnusable = rolloutScan?.latestEventSignature != nil
            && rolloutScan?.latestEventSignature != rolloutScan?.latestUsableSignature
        if shouldRefreshActiveUsageViaAPI(
            registry: registry,
            activeAccount: activeAccount,
            rolloutScan: rolloutScan,
            activeUsageUpdated: activeUsageUpdated,
            latestLocalEventWasUnusable: latestLocalEventWasUnusable
        ) {
            if let refreshed = try refreshUsage(
                accountKey: activeAccount.accountKey,
                authURL: accountManager.activeAuthURL(),
                reason: "active",
                log: log
            ) {
                activeAccount.lastUsage = refreshed
                activeAccount.lastUsageAt = Int64(Date().timeIntervalSince1970)
                registry.accounts[activeIndex] = activeAccount
                changed = true
                activeUsageUpdated = true
            }
        }

        let currentScore = score(for: activeAccount)
        if shouldSwitch(activeAccount: activeAccount, config: registry.autoSwitch) {
            var bestCandidate: CodexManagedAccount?
            var bestScore: Int = currentScore

            for index in registry.accounts.indices where registry.accounts[index].accountKey != activeAccount.accountKey {
                var candidate = registry.accounts[index]
                if registry.api.usage,
                   let refreshed = try refreshUsage(
                    accountKey: candidate.accountKey,
                    authURL: accountManager.snapshotURL(for: candidate.accountKey),
                    reason: candidate.email,
                    log: log,
                    force: true
                   )
                {
                    candidate.lastUsage = refreshed
                    candidate.lastUsageAt = Int64(Date().timeIntervalSince1970)
                    registry.accounts[index] = candidate
                    changed = true
                }

                let candidateScore = score(for: candidate)
                if candidateScore > bestScore {
                    bestScore = candidateScore
                    bestCandidate = candidate
                }
            }

            if let bestCandidate, bestScore > currentScore {
                try accountManager.activateAccount(bestCandidate.accountKey, in: &registry, backupCurrentAuth: true)
                changed = true
                log("[switch] activated \(bestCandidate.displayName) (\(bestCandidate.accountKey))")
                try accountManager.saveRegistry(registry)
                return CodexAutoSwitchRunResult(switchedAccount: bestCandidate, activeUsageUpdated: activeUsageUpdated)
            }
        }

        if changed {
            try accountManager.saveRegistry(registry)
        }
        return CodexAutoSwitchRunResult(switchedAccount: nil, activeUsageUpdated: activeUsageUpdated)
    }

    func runWatch(log: @escaping (String) -> Void = { _ in }) throws {
        let stop = ManagedAtomicStopSignal()
        stop.install()
        while !stop.shouldStop {
            do {
                _ = try runOnce(log: log)
            } catch {
                log("[switch] cycle failed: \(error.localizedDescription)")
            }

            let deadline = Date().addingTimeInterval(pollInterval)
            while Date() < deadline {
                if stop.shouldStop { break }
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
    }

    private func shouldRefreshActiveUsageViaAPI(
        registry: CodexAccountRegistry,
        activeAccount: CodexManagedAccount,
        rolloutScan: CodexRolloutScanResult?,
        activeUsageUpdated: Bool,
        latestLocalEventWasUnusable: Bool
    ) -> Bool {
        guard registry.api.usage else { return false }
        if activeUsageUpdated { return false }
        if latestLocalEventWasUnusable {
            return canCallAPI(for: activeAccount.accountKey)
        }
        if rolloutScan?.latestEventSignature == nil {
            return canCallAPI(for: activeAccount.accountKey)
        }
        return activeAccount.lastUsage == nil && canCallAPI(for: activeAccount.accountKey)
    }

    private func refreshUsage(
        accountKey: String,
        authURL: URL,
        reason: String,
        log: @escaping (String) -> Void,
        force: Bool = false
    ) throws -> CodexRateLimitSnapshot? {
        guard force || canCallAPI(for: accountKey) else { return nil }
        guard let auth = try? CodexAuthStore.load(from: authURL),
              let accessToken = auth.accessToken,
              let accountId = auth.chatgptAccountId else {
            log("[api] refresh usage | status=MissingAuth (\(reason))")
            return nil
        }

        let snapshot = try usageClient.fetchUsage(accessToken: accessToken, chatgptAccountId: accountId)
        lastAPIRefreshAt[accountKey] = Date()
        log("[api] refresh usage | status=OK (\(reason))")
        return snapshot
    }

    private func canCallAPI(for accountKey: String) -> Bool {
        guard let lastRefreshAt = lastAPIRefreshAt[accountKey] else { return true }
        return Date().timeIntervalSince(lastRefreshAt) >= 60
    }

    private func shouldSwitch(activeAccount: CodexManagedAccount, config: CodexAutoSwitchConfig) -> Bool {
        let thresholds = effectiveThresholds(for: activeAccount, config: config)
        if let remaining5h = remainingPercentage(resolveWindow(from: activeAccount.lastUsage, minutes: 300, fallbackPrimary: true)),
           remaining5h < thresholds.fiveHour {
            return true
        }
        if let remainingWeekly = remainingPercentage(resolveWindow(from: activeAccount.lastUsage, minutes: 10080, fallbackPrimary: false)),
           remainingWeekly < thresholds.weekly {
            return true
        }
        return false
    }

    private func effectiveThresholds(for account: CodexManagedAccount, config: CodexAutoSwitchConfig) -> (fiveHour: Int, weekly: Int) {
        let isFree = account.plan?.lowercased() == "free"
        let fiveHourWindow = resolveWindow(from: account.lastUsage, minutes: 300, fallbackPrimary: true)
        let qualifiesForFreeFloor = isFree && (fiveHourWindow?.windowMinutes == 300 || fiveHourWindow?.windowMinutes == nil)
        return (
            qualifiesForFreeFloor ? max(config.threshold5hPercent, 35) : config.threshold5hPercent,
            config.thresholdWeeklyPercent
        )
    }

    private func score(for account: CodexManagedAccount) -> Int {
        let fiveHour = remainingPercentage(resolveWindow(from: account.lastUsage, minutes: 300, fallbackPrimary: true))
        let weekly = remainingPercentage(resolveWindow(from: account.lastUsage, minutes: 10080, fallbackPrimary: false))
        switch (fiveHour, weekly) {
        case let (lhs?, rhs?):
            return min(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return 100
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

    private func remainingPercentage(_ window: CodexRateLimitWindow?) -> Int? {
        guard let window else { return nil }
        if let resetsAt = window.resetsAt, TimeInterval(resetsAt) <= Date().timeIntervalSince1970 {
            return 100
        }
        return max(0, min(100, Int((100 - window.usedPercent).rounded())))
    }
}

private final class ManagedAtomicStopSignal {
    func install() {
        codexAutoSwitchStopRequested = false
        signal(SIGINT, codexAutoSwitchSignalHandler)
        signal(SIGTERM, codexAutoSwitchSignalHandler)
    }

    var shouldStop: Bool { codexAutoSwitchStopRequested }
}

private var codexAutoSwitchStopRequested = false

private func codexAutoSwitchSignalHandler(_: Int32) {
    codexAutoSwitchStopRequested = true
}

private struct CodexRolloutScanResult: Sendable {
    var latestEventSignature: CodexRolloutSignature?
    var latestUsableSignature: CodexRolloutSignature?
    var latestUsableSnapshot: CodexRateLimitSnapshot?
}

private struct CodexSessionsUsageScanner {
    let fileManager: FileManager

    func scanLatestUsage(codexHomeURL: URL, activatedAfterMs: Int64) -> CodexRolloutScanResult? {
        let sessionsURL = codexHomeURL.appendingPathComponent("sessions", isDirectory: true)
        guard fileManager.fileExists(atPath: sessionsURL.path) else { return nil }
        guard let latestFile = latestRolloutFile(in: sessionsURL) else { return nil }
        return parseLatestUsage(from: latestFile, activatedAfterMs: activatedAfterMs)
    }

    private func latestRolloutFile(in sessionsURL: URL) -> URL? {
        guard let enumerator = fileManager.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var best: (url: URL, modifiedAt: Date)?
        for case let url as URL in enumerator where url.pathExtension == "jsonl" && url.lastPathComponent.hasPrefix("rollout-") {
            let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if best == nil || modifiedAt > best!.modifiedAt {
                best = (url, modifiedAt)
            }
        }
        return best?.url
    }

    private func parseLatestUsage(from fileURL: URL, activatedAfterMs: Int64) -> CodexRolloutScanResult? {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }

        var latestEventSignature: CodexRolloutSignature?
        var latestUsableSignature: CodexRolloutSignature?
        var latestUsableSnapshot: CodexRateLimitSnapshot?

        for line in content.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let timestampRaw = object["timestamp"] as? String,
                  let timestamp = parseTimestamp(timestampRaw) else {
                continue
            }

            let timestampMs = Int64(timestamp.timeIntervalSince1970 * 1000)
            guard timestampMs >= activatedAfterMs else { continue }

            let signature = CodexRolloutSignature(path: fileURL.path, eventTimestampMs: timestampMs)
            latestEventSignature = signature

            guard let rateLimits = payload["rate_limits"] as? [String: Any],
                  let snapshot = parseRateLimits(rateLimits) else {
                continue
            }
            latestUsableSignature = signature
            latestUsableSnapshot = snapshot
        }

        guard latestEventSignature != nil || latestUsableSignature != nil else { return nil }
        return CodexRolloutScanResult(
            latestEventSignature: latestEventSignature,
            latestUsableSignature: latestUsableSignature,
            latestUsableSnapshot: latestUsableSnapshot
        )
    }

    private func parseRateLimits(_ rateLimits: [String: Any]) -> CodexRateLimitSnapshot? {
        let primary = parseWindow(rateLimits["primary"])
        let secondary = parseWindow(rateLimits["secondary"])
        let credits = parseCredits(rateLimits["credits"])
        let planType = nonEmptyString(rateLimits["plan_type"])
        guard primary != nil || secondary != nil || credits != nil else { return nil }
        return CodexRateLimitSnapshot(primary: primary, secondary: secondary, credits: credits, planType: planType)
    }

    private func parseWindow(_ raw: Any?) -> CodexRateLimitWindow? {
        guard let object = raw as? [String: Any] else { return nil }
        guard let usedPercent = doubleValue(object["used_percent"]) else { return nil }
        return CodexRateLimitWindow(
            usedPercent: usedPercent,
            windowMinutes: intValue(object["window_minutes"]),
            resetsAt: intValue(object["resets_at"])
        )
    }

    private func parseCredits(_ raw: Any?) -> CodexCreditsSnapshot? {
        guard let object = raw as? [String: Any] else { return nil }
        return CodexCreditsSnapshot(
            hasCredits: boolValue(object["has_credits"]),
            unlimited: boolValue(object["unlimited"]),
            balance: nonEmptyString(object["balance"])
        )
    }

    private func parseTimestamp(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    private func nonEmptyString(_ raw: Any?) -> String? {
        guard let raw = raw as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func intValue(_ raw: Any?) -> Int? {
        if let raw = raw as? NSNumber { return raw.intValue }
        if let raw = raw as? String { return Int(raw) }
        return nil
    }

    private func doubleValue(_ raw: Any?) -> Double? {
        if let raw = raw as? NSNumber { return raw.doubleValue }
        if let raw = raw as? String { return Double(raw) }
        return nil
    }

    private func boolValue(_ raw: Any?) -> Bool {
        if let raw = raw as? Bool { return raw }
        if let raw = raw as? NSNumber { return raw.boolValue }
        if let raw = raw as? String {
            return ["1", "true", "yes"].contains(raw.lowercased())
        }
        return false
    }
}

private struct CodexUsageAPIClient {
    func fetchUsage(accessToken: String, chatgptAccountId: String) throws -> CodexRateLimitSnapshot? {
        var request = URLRequest(
            url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 5
        )
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(chatgptAccountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36 SuperIsland/1.0",
            forHTTPHeaderField: "User-Agent"
        )

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseError: Error?

        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                responseError = error
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let data else {
                return
            }
            responseData = data
        }.resume()

        _ = semaphore.wait(timeout: .now() + 6)
        if let responseError { throw responseError }
        guard let responseData,
              let payload = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let rateLimit = payload["rate_limit"] as? [String: Any] else {
            return nil
        }

        let primary = parseWindow(rateLimit["primary_window"])
        let secondary = parseWindow(rateLimit["secondary_window"])
        let credits = parseCredits(payload["credits"])
        let planType = nonEmptyString(payload["plan_type"])
        guard primary != nil || secondary != nil || credits != nil else { return nil }
        return CodexRateLimitSnapshot(primary: primary, secondary: secondary, credits: credits, planType: planType)
    }

    private func parseWindow(_ raw: Any?) -> CodexRateLimitWindow? {
        guard let object = raw as? [String: Any],
              let usedPercent = doubleValue(object["used_percent"]) else {
            return nil
        }
        let resetAt = intValue(object["reset_at"])
            ?? intValue(object["resets_at"])
            ?? {
                if let seconds = intValue(object["reset_after_seconds"]) {
                    return Int(Date().timeIntervalSince1970) + seconds
                }
                return nil
            }()

        return CodexRateLimitWindow(
            usedPercent: usedPercent,
            windowMinutes: intValue(object["window_minutes"]),
            resetsAt: resetAt
        )
    }

    private func parseCredits(_ raw: Any?) -> CodexCreditsSnapshot? {
        guard let object = raw as? [String: Any] else { return nil }
        return CodexCreditsSnapshot(
            hasCredits: boolValue(object["has_credits"]),
            unlimited: boolValue(object["unlimited"]),
            balance: nonEmptyString(object["balance"])
        )
    }

    private func nonEmptyString(_ raw: Any?) -> String? {
        guard let raw = raw as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func intValue(_ raw: Any?) -> Int? {
        if let raw = raw as? NSNumber { return raw.intValue }
        if let raw = raw as? String { return Int(raw) }
        return nil
    }

    private func doubleValue(_ raw: Any?) -> Double? {
        if let raw = raw as? NSNumber { return raw.doubleValue }
        if let raw = raw as? String { return Double(raw) }
        return nil
    }

    private func boolValue(_ raw: Any?) -> Bool {
        if let raw = raw as? Bool { return raw }
        if let raw = raw as? NSNumber { return raw.boolValue }
        if let raw = raw as? String {
            return ["1", "true", "yes"].contains(raw.lowercased())
        }
        return false
    }
}

enum CodexAutoSwitchLaunchAgentState: String, Sendable {
    case enabled
    case disabled
    case unavailable

    var title: String {
        switch self {
        case .enabled: "Enabled"
        case .disabled: "Disabled"
        case .unavailable: "Unavailable"
        }
    }
}

struct CodexAutoSwitchLaunchAgentSnapshot: Sendable {
    var state: CodexAutoSwitchLaunchAgentState
    var detail: String
    var plistPath: String
    var needsRepair: Bool = false
}

enum CodexAutoSwitchLaunchAgentError: LocalizedError {
    case executableMissing
    case launchctlFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableMissing:
            "缺少可执行文件"
        case let .launchctlFailed(message):
            message
        }
    }
}

final class CodexAutoSwitchLaunchAgentManager {
    private let fileManager: FileManager
    private let label = "com.superisland.codex-auto-switch"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func snapshot() -> CodexAutoSwitchLaunchAgentSnapshot {
        let plistURL = launchAgentPlistURL()
        guard let executableURL = AutomationCLI.executableURL(),
              fileManager.fileExists(atPath: executableURL.path) else {
            return CodexAutoSwitchLaunchAgentSnapshot(
                state: .unavailable,
                detail: "SuperIsland 可执行文件不可用",
                plistPath: plistURL.path
            )
        }

        if let installedExecutablePath = installedExecutablePath(plistURL: plistURL),
           installedExecutablePath != executableURL.path {
            return CodexAutoSwitchLaunchAgentSnapshot(
                state: .disabled,
                detail: "当前安装记录指向旧构建路径，请重新启用以修复",
                plistPath: plistURL.path,
                needsRepair: true
            )
        }

        if let service = serviceStatus() {
            if service.jobState == "spawn failed" {
                return CodexAutoSwitchLaunchAgentSnapshot(
                    state: .disabled,
                    detail: "自动切号守护进程启动失败，请重新启用以修复",
                    plistPath: plistURL.path,
                    needsRepair: true
                )
            }
            if service.isLoaded {
                return CodexAutoSwitchLaunchAgentSnapshot(
                    state: .enabled,
                    detail: "监控 Codex 额度并自动切换账号",
                    plistPath: plistURL.path
                )
            }
        }

        let detail = fileManager.fileExists(atPath: plistURL.path)
            ? "已安装但未加载"
            : "未安装 LaunchAgent"
        return CodexAutoSwitchLaunchAgentSnapshot(state: .disabled, detail: detail, plistPath: plistURL.path)
    }

    @discardableResult
    func repairIfNeeded() throws -> Bool {
        let current = snapshot()
        guard current.needsRepair else { return false }
        try setEnabled(true)
        return true
    }

    func setEnabled(_ enabled: Bool) throws {
        let plistURL = launchAgentPlistURL()
        guard let executableURL = AutomationCLI.executableURL(),
              fileManager.fileExists(atPath: executableURL.path) else {
            throw CodexAutoSwitchLaunchAgentError.executableMissing
        }

        if enabled {
            try writePlist(at: plistURL, executableURL: executableURL)
            bootoutIfPresent(plistURL: plistURL)
            try runLaunchctl(["bootstrap", launchDomain(), plistURL.path])
            try runLaunchctl(["enable", "\(launchDomain())/\(label)"])
            try runLaunchctl(["kickstart", "-k", "\(launchDomain())/\(label)"])
        } else {
            _ = try? runLaunchctl(["disable", "\(launchDomain())/\(label)"])
            bootoutIfPresent(plistURL: plistURL)
            waitForServiceRemoval()
            if fileManager.fileExists(atPath: plistURL.path) {
                try fileManager.removeItem(at: plistURL)
            }
        }
    }

    func runNow() async throws {
        guard let executableURL = AutomationCLI.executableURL(),
              fileManager.fileExists(atPath: executableURL.path) else {
            throw CodexAutoSwitchLaunchAgentError.executableMissing
        }

        let stderr = Pipe()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--codex-auth", "daemon", "--once"]
        process.standardOutput = Pipe()
        process.standardError = stderr

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { process in
                guard process.terminationStatus != 0 else {
                    continuation.resume()
                    return
                }

                let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(throwing: CodexAutoSwitchLaunchAgentError.launchctlFailed(
                    message.isEmpty ? "Auto-switch check failed" : message
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func launchAgentPlistURL() -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist", isDirectory: false)
    }

    private func launchDomain() -> String {
        "gui/\(getuid())"
    }

    private func isLoaded() -> Bool {
        (try? runLaunchctl(["print", "\(launchDomain())/\(label)"])) != nil
    }

    private func installedExecutablePath(plistURL: URL) -> String? {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String],
              let executablePath = arguments.first,
              !executablePath.isEmpty else {
            return nil
        }
        return executablePath
    }

    private func serviceStatus() -> CodexLaunchServiceStatus? {
        guard let output = try? runLaunchctl(["print", "\(launchDomain())/\(label)"]) else {
            return nil
        }
        return CodexLaunchServiceStatus(output: output)
    }

    private func bootoutIfPresent(plistURL: URL) {
        _ = try? runLaunchctl(["bootout", launchDomain(), label])
        _ = try? runLaunchctl(["bootout", launchDomain(), plistURL.path])
    }

    private func waitForServiceRemoval() {
        for _ in 0..<20 {
            guard isLoaded() else { return }
            usleep(100_000)
        }
    }

    private func writePlist(at plistURL: URL, executableURL: URL) throws {
        let logsDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".superisland", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
        try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [
                executableURL.path,
                "--codex-auth",
                "daemon",
                "--watch",
            ],
            "WorkingDirectory": fileManager.homeDirectoryForCurrentUser.path,
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardOutPath": logsDirectory.appendingPathComponent("codex-auto-switch.log").path,
            "StandardErrorPath": logsDirectory.appendingPathComponent("codex-auto-switch.error.log").path,
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL)
    }

    @discardableResult
    private func runLaunchctl(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            throw CodexAutoSwitchLaunchAgentError.launchctlFailed(output.isEmpty ? "launchctl failed" : output)
        }
        return output
    }
}

private struct CodexLaunchServiceStatus {
    let output: String

    var isLoaded: Bool {
        output.contains("state =")
    }

    var jobState: String? {
        extractValue(after: "job state = ")
    }

    private func extractValue(after prefix: String) -> String? {
        output
            .split(separator: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix(prefix) else { return nil }
                return String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .first
    }
}
