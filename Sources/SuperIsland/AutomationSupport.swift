import Foundation
import Darwin
import CommonCrypto
import SuperIslandCore

/// Small CLI surface embedded in the main app binary so Codex hooks can call
/// `SuperIsland` directly instead of depending on a separate helper executable.
enum AutomationCLI {
    static func runIfNeeded(arguments: [String] = CommandLine.arguments) -> Int32? {
        let commandArguments = Array(arguments.dropFirst())
        guard let command = commandArguments.first else { return nil }

        switch command {
        case "--install-codex-hooks":
            return ConfigInstaller.setEnabled(source: "codex", enabled: true) ? 0 : 1
        case "--bridge-codex-hook":
            return CodexHookBridgeCommand(arguments: Array(commandArguments.dropFirst())).run()
        case "--monitor-usage":
            return UsageMonitorCommand(arguments: Array(commandArguments.dropFirst())).run()
        case "--codex-auth":
            return CodexAccountCLICommand(arguments: Array(commandArguments.dropFirst())).run()
        default:
            return nil
        }
    }

    static func executableURL() -> URL? {
        if let executableURL = Bundle.main.executableURL {
            return executableURL.standardizedFileURL
        }

        guard let firstArgument = CommandLine.arguments.first, !firstArgument.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: firstArgument).standardizedFileURL
    }
}

private struct CodexHookBridgeCommand {
    private let arguments: [String]

    init(arguments: [String]) {
        self.arguments = arguments
    }

    func run() -> Int32 {
        signal(SIGPIPE, SIG_IGN)
        signal(SIGALRM) { _ in
            _exit(0)
        }

        let env = ProcessInfo.processInfo.environment
        guard env["SUPERISLAND_SKIP"] == nil else { return 0 }

        let socketPath = SocketPath.path
        let sourceTag = argumentValue("--source")
        let eventTag = argumentValue("--event")
        let dryRun = arguments.contains("--dry-run")

        if !dryRun {
            var statBuf = stat()
            guard stat(socketPath, &statBuf) == 0, (statBuf.st_mode & S_IFMT) == S_IFSOCK else { return 0 }
        }

        alarm(5)
        let input = FileHandle.standardInput.readDataToEndOfFile()
        alarm(0)

        guard !input.isEmpty,
              var json = try? JSONSerialization.jsonObject(with: input) as? [String: Any] else {
            return 0
        }

        if json["hook_event_name"] == nil, let eventTag {
            json["hook_event_name"] = eventTag
        }
        if json["session_id"] == nil, let sessionId = nonEmptyString(json["sessionId"]) {
            json["session_id"] = sessionId
        }

        guard let sessionId = nonEmptyString(json["session_id"]) else {
            debugLog("no session_id, dropping codex hook")
            return 0
        }

        let eventName = nonEmptyString(json["hook_event_name"]) ?? ""
        let isPermission = eventName == "PermissionRequest"
        let isQuestion = (eventName == "Notification" || eventName == "afterAgentThought")
            && json["question"] as? String != nil
        let isBlocking = isPermission || isQuestion

        debugLog("event=\(eventName) session=\(sessionId) source=\(sourceTag ?? "codex")")

        alarm(8)
        enrichTerminalContext(&json, env: env, sourceTag: sourceTag)

        guard let enriched = try? JSONSerialization.data(withJSONObject: json, options: dryRun ? [.prettyPrinted, .sortedKeys] : []) else {
            return 1
        }

        if dryRun {
            FileHandle.standardOutput.write(enriched)
            if !enriched.isEmpty, enriched.last != 0x0A {
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            return 0
        }

        guard let sock = connectSocket(socketPath) else {
            debugLog("socket connect failed for codex hook")
            return 0
        }

        var sendTimeout = timeval(tv_sec: isBlocking ? 86400 : 3, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, socklen_t(MemoryLayout<timeval>.size))
        var recvTimeout = timeval(tv_sec: isBlocking ? 86400 : 3, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &recvTimeout, socklen_t(MemoryLayout<timeval>.size))

        sendAll(sock, data: enriched)
        shutdown(sock, SHUT_WR)

        if isBlocking {
            alarm(0)
        }

        let response = recvAll(sock)
        if isBlocking && !response.isEmpty {
            FileHandle.standardOutput.write(response)
        }

        close(sock)
        return 0
    }

    private func argumentValue(_ flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }
}

private func enrichTerminalContext(
    _ json: inout [String: Any],
    env: [String: String],
    sourceTag: String?
) {
    if let termApp = env["TERM_PROGRAM"], !termApp.isEmpty {
        json["_term_app"] = termApp
    }
    if let termBundle = env["__CFBundleIdentifier"], !termBundle.isEmpty {
        json["_term_bundle"] = termBundle
    }

    if let iterm = env["ITERM_SESSION_ID"], !iterm.isEmpty {
        if let colonIdx = iterm.firstIndex(of: ":") {
            json["_iterm_session"] = String(iterm[iterm.index(after: colonIdx)...])
        } else {
            json["_iterm_session"] = iterm
        }
    }

    if let kitty = env["KITTY_WINDOW_ID"], !kitty.isEmpty {
        json["_kitty_window"] = kitty
    }

    if let tmux = env["TMUX"], !tmux.isEmpty {
        json["_tmux"] = tmux
        if let pane = env["TMUX_PANE"], !pane.isEmpty {
            json["_tmux_pane"] = pane
            if let tmuxBin = findBinary("tmux"),
               let clientTTY = runCommand(tmuxBin, args: ["display-message", "-p", "-t", pane, "-F", "#{client_tty}"]) {
                json["_tmux_client_tty"] = clientTTY
            }
        }
    }

    let resolvedEnv = resolveCmuxEnvironment(env)
    if let workspaceRef = resolvedEnv["CMUX_WORKSPACE_REF"], !workspaceRef.isEmpty {
        json["_cmux_workspace_ref"] = workspaceRef
    }
    if let surfaceRef = resolvedEnv["CMUX_SURFACE_REF"], !surfaceRef.isEmpty {
        json["_cmux_surface_ref"] = surfaceRef
    }
    if let paneRef = resolvedEnv["CMUX_PANE_REF"], !paneRef.isEmpty {
        json["_cmux_pane_ref"] = paneRef
    }
    if let workspaceId = resolvedEnv["CMUX_WORKSPACE_ID"], !workspaceId.isEmpty {
        json["_cmux_workspace_id"] = workspaceId
    }
    if let surfaceId = resolvedEnv["CMUX_SURFACE_ID"], !surfaceId.isEmpty {
        json["_cmux_surface_id"] = surfaceId
    }
    if let socketPath = resolvedEnv["CMUX_SOCKET_PATH"], !socketPath.isEmpty {
        json["_cmux_socket_path"] = socketPath
    }

    let tty = detectTTY()
    if !tty.isEmpty {
        json["_tty"] = tty
    }

    if let sourceTag {
        json["_source"] = sourceTag
    }

    json["_ppid"] = getppid()
}

private func resolveCmuxEnvironment(_ env: [String: String]) -> [String: String] {
    var resolved = env

    let hasRef = [
        resolved["CMUX_WORKSPACE_REF"],
        resolved["CMUX_PANE_REF"],
    ].contains { !($0?.isEmpty ?? true) }

    if hasRef {
        return resolved
    }

    guard resolved["TERM_PROGRAM"] == "cmux" || resolved["__CFBundleIdentifier"] == "com.cmuxterm.app" else {
        return resolved
    }

    // `cmux identify --json` can trigger TCC/WindowServer checks on newer macOS
    // builds, which surfaces misleading screen-recording prompts. Prefer the
    // environment cmux already injected unless the user explicitly opts in.
    guard ProcessInfo.processInfo.environment["SUPERISLAND_ENABLE_CMUX_IDENTIFY"] == "1" else {
        return resolved
    }

    guard let executable = findBinary("cmux") ?? {
        let bundledPath = "/Applications/cmux.app/Contents/Resources/bin/cmux"
        return FileManager.default.isExecutableFile(atPath: bundledPath) ? bundledPath : nil
    }() else {
        return resolved
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = ["identify", "--json"]

    var processEnvironment = ProcessInfo.processInfo.environment
    if let socketPath = resolved["CMUX_SOCKET_PATH"], !socketPath.isEmpty {
        processEnvironment["CMUX_SOCKET_PATH"] = socketPath
    }
    process.environment = processEnvironment

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return resolved
    }

    guard process.terminationStatus == 0 else { return resolved }
    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return resolved
    }

    // Prefer caller (the pane running the hook) over focused (global focus)
    let source = (object["caller"] as? [String: Any]) ?? (object["focused"] as? [String: Any])
    if let source {
        if let workspaceRef = source["workspace_ref"] {
            resolved["CMUX_WORKSPACE_REF"] = String(describing: workspaceRef)
        }
        if let surfaceRef = source["surface_ref"] {
            resolved["CMUX_SURFACE_REF"] = String(describing: surfaceRef)
        }
        if let paneRef = source["pane_ref"] {
            resolved["CMUX_PANE_REF"] = String(describing: paneRef)
        }
        if let workspaceId = source["workspace_id"] {
            resolved["CMUX_WORKSPACE_ID"] = String(describing: workspaceId)
        }
        if let surfaceId = source["surface_id"] {
            resolved["CMUX_SURFACE_ID"] = String(describing: surfaceId)
        }
    }

    if let socketPath = object["socket_path"] as? String, !socketPath.isEmpty {
        resolved["CMUX_SOCKET_PATH"] = socketPath
    }

    return resolved
}

private func detectTTY() -> String {
    let fd = open("/dev/tty", O_RDONLY | O_NOCTTY)
    if fd >= 0 {
        if let name = ttyname(fd) {
            close(fd)
            return String(cString: name)
        }
        close(fd)
    }
    return ""
}

private func findBinary(_ name: String) -> String? {
    let searchPaths = [
        "/opt/homebrew/bin/\(name)",
        "/usr/local/bin/\(name)",
        "/usr/bin/\(name)",
    ]
    return searchPaths.first { access($0, X_OK) == 0 }
}

private func runCommand(_ path: String, args: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output?.isEmpty == false ? output : nil
    } catch {
        return nil
    }
}

private func nonEmptyString(_ value: Any?) -> String? {
    guard let raw = value as? String else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func debugLog(_ message: String) {
    guard ProcessInfo.processInfo.environment["SUPERISLAND_DEBUG"] != nil else { return }
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)\n"
    let path = "/tmp/superisland-bridge.log"
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        FileManager.default.createFile(atPath: path, contents: Data(line.utf8))
    }
}

private func connectSocket(_ path: String) -> Int32? {
    let sock = socket(AF_UNIX, SOCK_STREAM, 0)
    guard sock >= 0 else { return nil }

    var on: Int32 = 1
    setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
        path.withCString { _ = strcpy(ptr, $0) }
    }

    let originalFlags = fcntl(sock, F_GETFL)
    _ = fcntl(sock, F_SETFL, originalFlags | O_NONBLOCK)

    let result = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(sock, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }

    if result != 0 && errno != EINPROGRESS {
        close(sock)
        return nil
    }

    if result != 0 {
        var pfd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
        let ready = poll(&pfd, 1, 3000)
        if ready <= 0 {
            close(sock)
            return nil
        }
        var socketError: Int32 = 0
        var errorLength = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(sock, SOL_SOCKET, SO_ERROR, &socketError, &errorLength)
        if socketError != 0 {
            close(sock)
            return nil
        }
    }

    _ = fcntl(sock, F_SETFL, originalFlags)
    return sock
}

private func sendAll(_ sock: Int32, data: Data) {
    data.withUnsafeBytes { buffer in
        guard let base = buffer.baseAddress else { return }
        var sent = 0
        while sent < buffer.count {
            let count = send(sock, base + sent, buffer.count - sent, 0)
            if count < 0 {
                if errno == EINTR { continue }
                break
            }
            if count == 0 { break }
            sent += count
        }
    }
}

private func recvAll(_ sock: Int32) -> Data {
    var response = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        let count = recv(sock, &buffer, buffer.count, 0)
        if count < 0 {
            if errno == EINTR { continue }
            break
        }
        if count == 0 { break }
        response.append(contentsOf: buffer[..<count])
    }
    return response
}

private struct UsageMonitorCommand {
    private let providers: [String]
    private let explicitSocketPath: String?
    private let isDryRun: Bool
    private let isVerbose: Bool

    init(arguments: [String]) {
        let rawProviders = Self.value(after: "--providers", in: arguments) ?? "claude,codex,cursor"
        self.providers = rawProviders
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        self.explicitSocketPath = Self.value(after: "--socket", in: arguments)
        self.isDryRun = arguments.contains("--dry-run")
        self.isVerbose = arguments.contains("--verbose")
    }

    func run() -> Int32 {
        let usageSnapshot = buildUsageSnapshot()
        let envelope = UsageUpdateEnvelope(usage: usageSnapshot)
        let encoder = JSONEncoder()

        guard let payload = try? encoder.encode(envelope) else {
            FileHandle.standardError.write(Data("Failed to encode usage snapshot.\n".utf8))
            return 1
        }

        guard isDryRun || UsageSnapshotStore.save(usageSnapshot) else {
            FileHandle.standardError.write(Data("Failed to persist usage snapshot.\n".utf8))
            return 1
        }

        if isDryRun {
            if let object = try? JSONSerialization.jsonObject(with: payload),
               let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
                FileHandle.standardOutput.write(pretty)
                if pretty.last != 0x0A {
                    FileHandle.standardOutput.write(Data("\n".utf8))
                }
            }
            return 0
        }

        if let socketPath = sendToSocket(payload) {
            debug("sent usage_update to \(socketPath)")
        } else {
            debug("no active SuperIsland socket found, cache updated only")
        }

        return 0
    }

    private func buildUsageSnapshot() -> UsageSnapshot {
        var snapshots: [UsageProviderSnapshot] = []
        let now = Date().timeIntervalSince1970
        let previousSnapshot = UsageSnapshotStore.load()
        let previousClaudeSnapshot = previousSnapshot.providers.first(where: { $0.source == .claude })
        let previousCursorSnapshot = previousSnapshot.providers.first(where: { $0.source == .cursor })
        let claudeUsageHistory = ClaudeMonthlyUsageCalculator.loadUsageHistory()

        if providers.contains("claude"),
           let snapshot = buildClaudeSnapshot(
            now: now,
            previousSnapshot: previousClaudeSnapshot,
            history: claudeUsageHistory
           ) {
            snapshots.append(snapshot)
        }

        if providers.contains("codex"), let quota = fetchCodexQuota() {
            let primaryRemaining = clampPercentage(100 - quota.primary.usedPercent)
            let secondaryRemaining = clampPercentage(100 - quota.secondary.usedPercent)
            let usageHistory = CodexMonthlyUsageCalculator.loadUsageHistory()
            snapshots.append(
                UsageProviderSnapshot(
                    source: .codex,
                    primary: UsageWindowStat(
                        label: "5h",
                        percentage: primaryRemaining,
                        detail: codexWindowDetail(resetAtUnix: quota.primary.resetAtUnix, resetAfterSeconds: quota.primary.resetAfterSeconds),
                        tintHex: tintHex(forRemainingPercentage: primaryRemaining)
                    ),
                    secondary: UsageWindowStat(
                        label: "7d",
                        percentage: secondaryRemaining,
                        detail: codexWindowDetail(resetAtUnix: quota.secondary.resetAtUnix, resetAfterSeconds: quota.secondary.resetAfterSeconds),
                        tintHex: tintHex(forRemainingPercentage: secondaryRemaining)
                    ),
                    updatedAtUnix: now,
                    summary: quota.summary,
                    monthly: usageHistory.monthly,
                    history: usageHistory.history.isEmpty ? nil : usageHistory.history
                )
            )
        }

        if providers.contains("cursor"),
           let snapshot = buildCursorSnapshot(now: now, previousSnapshot: previousCursorSnapshot) {
            snapshots.append(snapshot)
        }

        return UsageSnapshot(providers: snapshots.sorted { $0.source.sortOrder < $1.source.sortOrder })
    }

    private func buildClaudeSnapshot(
        now: TimeInterval,
        previousSnapshot: UsageProviderSnapshot?,
        history: (monthly: UsageMonthlyStat?, history: [UsageHistoryRangeSnapshot])
    ) -> UsageProviderSnapshot? {
        if let quota = fetchClaudeQuota() {
            let primaryUsed = clampPercentage(Int((quota.primary.utilization * 100).rounded()))
            let secondaryUsed = clampPercentage(Int((quota.secondary.utilization * 100).rounded()))
            return UsageProviderSnapshot(
                source: .claude,
                primary: UsageWindowStat(
                    label: "5h",
                    percentage: primaryUsed,
                    detail: claudeWindowDetail(resetAt: quota.primary.resetAt),
                    tintHex: tintHex(forUsedPercentage: primaryUsed)
                ),
                secondary: UsageWindowStat(
                    label: "7d",
                    percentage: secondaryUsed,
                    detail: claudeWindowDetail(resetAt: quota.secondary.resetAt),
                    tintHex: tintHex(forUsedPercentage: secondaryUsed)
                ),
                updatedAtUnix: now,
                summary: claudeQuotaSummary(sourceLabel: quota.sourceLabel, hasLocalHistory: history.monthly != nil),
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
                detail: history.monthly.map { formatTokenCount($0.totalTokens) } ?? "--",
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

    private func buildCursorSnapshot(
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
                    tintHex: tintHex(forUsedPercentage: quota.primary.usedPercent)
                ),
                secondary: UsageWindowStat(
                    label: quota.secondary.label,
                    percentage: quota.secondary.usedPercent,
                    detail: quota.secondary.detail,
                    tintHex: tintHex(forUsedPercentage: quota.secondary.usedPercent)
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
                summary: "Using cached Cursor quota",
                monthly: nil,
                history: nil,
                showsQuotaBadge: true
            )
        }

        return nil
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
                primary: ClaudeWindow(utilization: normalizedClaudeUtilization(fiveHour["utilization"]), resetAt: parseTimestamp(fiveHour["resets_at"])),
                secondary: ClaudeWindow(utilization: normalizedClaudeUtilization(sevenDay["utilization"]), resetAt: parseTimestamp(sevenDay["resets_at"])),
                sourceLabel: "Claude Code OAuth"
            )
        }

        return fetchClaudeWebQuota()
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
                usedPercent: integerValue(primaryWindow["used_percent"]),
                resetAtUnix: integerValue(primaryWindow["reset_at"]),
                resetAfterSeconds: integerValue(primaryWindow["reset_after_seconds"])
            ),
            secondary: CodexWindow(
                usedPercent: integerValue(secondaryWindow["used_percent"]),
                resetAtUnix: integerValue(secondaryWindow["reset_at"]),
                resetAfterSeconds: integerValue(secondaryWindow["reset_after_seconds"])
            ),
            summary: codexUsageSummary(payload: payload)
        )
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

    private func loadCodexAccessToken() -> String? {
        CodexAuthStore.load()?.accessToken
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
            primary: ClaudeWindow(utilization: normalizedClaudeUtilization(fiveHour["utilization"]), resetAt: parseTimestamp(fiveHour["resets_at"])),
            secondary: ClaudeWindow(utilization: normalizedClaudeUtilization(sevenDay["utilization"]), resetAt: parseTimestamp(sevenDay["resets_at"])),
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
            url: URL(string: "https://cursor.com/api/usage?user=\(userID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userID)")!,
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

        let autoPercent = normalizedCursorPercent(plan?["autoPercentUsed"])
        let apiPercent = normalizedCursorPercent(plan?["apiPercentUsed"])
        let totalPercent = resolvedCursorTotalPercent(plan: plan, autoPercent: autoPercent, apiPercent: apiPercent)
        let billingCycleEnd = parseTimestamp(payload["billingCycleEnd"])
        let resetDetail = cursorResetDetail(resetAt: billingCycleEnd)

        var primary = CursorWindow(
            label: "Total",
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

        let summary = cursorUsageSummary(
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

    private func fetchJSON(url: URL, headers: [String: String]) -> [String: Any]? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let semaphore = DispatchSemaphore(value: 0)
        var result: [String: Any]?

        URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            result = object
        }.resume()

        _ = semaphore.wait(timeout: .now() + 35)
        return result
    }

    private func fetchJSONResponse(url: URL, headers: [String: String]) -> (statusCode: Int, object: [String: Any]?)? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let semaphore = DispatchSemaphore(value: 0)
        var statusCode = 0
        var result: [String: Any]?

        URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let httpResponse = response as? HTTPURLResponse else {
                return
            }

            statusCode = httpResponse.statusCode
            guard let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            result = object
        }.resume()

        _ = semaphore.wait(timeout: .now() + 35)
        guard statusCode > 0 else { return nil }
        return (statusCode, result)
    }

    private func fetchJSONArray(url: URL, headers: [String: String]) -> [[String: Any]]? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let semaphore = DispatchSemaphore(value: 0)
        var result: [[String: Any]]?

        URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return
            }
            result = object
        }.resume()

        _ = semaphore.wait(timeout: .now() + 35)
        return result
    }

    private func codexWindowDetail(resetAtUnix: Int, resetAfterSeconds: Int) -> String {
        if resetAtUnix > 0 {
            return formatResetDeadline(timestamp: resetAtUnix)
        }
        if resetAfterSeconds > 0 {
            return formatResetDeadline(timestamp: Int(Date().timeIntervalSince1970) + resetAfterSeconds)
        }
        return "--"
    }

    private func claudeWindowDetail(resetAt: TimeInterval?) -> String {
        guard let resetAt else { return "--" }
        return formatDuration(seconds: Int(resetAt - Date().timeIntervalSince1970))
    }

    private func formatDuration(seconds: Int) -> String {
        let clamped = max(seconds, 0)
        let days = clamped / (24 * 60 * 60)
        let hours = (clamped % (24 * 60 * 60)) / (60 * 60)
        let minutes = (clamped % (60 * 60)) / 60

        if days > 0 { return "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h\(String(format: "%02d", minutes))m" : "\(hours)h" }
        return "\(max(minutes, 0))m"
    }

    private func formatResetDeadline(timestamp: Int) -> String {
        guard timestamp > 0 else { return "--" }

        let formatter = DateFormatter()
        let target = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let calendar = Calendar.current

        if calendar.isDateInToday(target) {
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: target)
        }

        let currentYear = calendar.component(.year, from: Date())
        let targetYear = calendar.component(.year, from: target)
        formatter.dateFormat = currentYear == targetYear ? "M/d" : "yyyy-MM-dd"
        return formatter.string(from: target)
    }

    private func parseTimestamp(_ raw: Any?) -> TimeInterval? {
        if let value = raw as? NSNumber {
            return value.doubleValue
        }
        guard var stringValue = raw as? String else { return nil }
        stringValue = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stringValue.isEmpty else { return nil }

        if let unix = TimeInterval(stringValue) {
            return unix
        }

        if stringValue.hasSuffix("Z") {
            stringValue = String(stringValue.dropLast()) + "+00:00"
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: stringValue) {
            return date.timeIntervalSince1970
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: stringValue)?.timeIntervalSince1970
    }

    private func integerValue(_ raw: Any?) -> Int {
        if let value = raw as? NSNumber { return value.intValue }
        if let stringValue = raw as? String, let value = Int(stringValue) { return value }
        return 0
    }

    private func doubleValue(_ raw: Any?) -> Double {
        if let value = raw as? NSNumber { return value.doubleValue }
        if let stringValue = raw as? String, let value = Double(stringValue) { return value }
        return 0
    }

    private func normalizedClaudeUtilization(_ raw: Any?) -> Double {
        let value = doubleValue(raw)
        guard value > 1 else { return value }
        return value / 100
    }

    private func clampPercentage(_ value: Int) -> Int {
        min(max(value, 0), 100)
    }

    private func tintHex(forUsedPercentage value: Int) -> String {
        if value >= 90 { return "#FF6F61" }
        if value >= 70 { return "#FFAC3B" }
        return "#2FD86D"
    }

    private func tintHex(forRemainingPercentage value: Int) -> String {
        if value <= 10 { return "#FF6F61" }
        if value <= 30 { return "#FFAC3B" }
        return "#2FD86D"
    }

    private func formatTokenCount(_ totalTokens: Int) -> String {
        if totalTokens >= 1_000_000 {
            return String(format: "%.1fM tokens", Double(totalTokens) / 1_000_000)
        }
        if totalTokens >= 1_000 {
            return String(format: "%.1fK tokens", Double(totalTokens) / 1_000)
        }
        return "\(totalTokens) tokens"
    }

    private func codexUsageSummary(payload: [String: Any]) -> String? {
        var parts: [String] = []

        if let planType = nonEmptyString(payload["plan_type"]) {
            parts.append(planType.uppercased())
        }

        if let credits = payload["credits"] as? [String: Any] {
            let balance = nonEmptyString(credits["balance"])
            let hasCredits = (credits["has_credits"] as? Bool) == true
            let unlimited = (credits["unlimited"] as? Bool) == true

            if unlimited {
                parts.append("Credits unlimited")
            } else if hasCredits, let balance {
                parts.append("Credits \(balance)")
            }
        }

        if let spendControl = payload["spend_control"] as? [String: Any],
           let reached = spendControl["reached"] as? Bool {
            parts.append(reached ? "Spend blocked" : "Spend OK")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func sendToSocket(_ data: Data) -> String? {
        for candidate in socketCandidates() where UnixSocketSender.send(data, to: candidate) {
            return candidate
        }
        return nil
    }

    private func socketCandidates() -> [String] {
        var candidates: [String] = []
        if let explicitSocketPath, !explicitSocketPath.isEmpty {
            candidates.append(explicitSocketPath)
        }
        let defaultPath = SocketPath.path
        if !candidates.contains(defaultPath) {
            candidates.append(defaultPath)
        }
        return candidates
    }

    private func runProcess(executable: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func debug(_ message: String) {
        guard isVerbose else { return }
        FileHandle.standardError.write(Data("[usage-monitor] \(message)\n".utf8))
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static let cursorSessionCookieNames: Set<String> = [
        "WorkosCursorSessionToken",
        "__Secure-next-auth.session-token",
        "next-auth.session-token",
        "wos-session",
        "__Secure-wos-session",
        "authjs.session-token",
        "__Secure-authjs.session-token",
    ]

    private struct ClaudeWindow {
        var utilization: Double
        var resetAt: TimeInterval?
    }

    private struct ClaudeQuota {
        var primary: ClaudeWindow
        var secondary: ClaudeWindow
        var sourceLabel: String
    }

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

    private func loadSafeStorageKey(serviceName: String) -> Data? {
        guard let secret = runProcess(
            executable: "/usr/bin/security",
            arguments: ["find-generic-password", "-s", serviceName, "-w"]
        ), !secret.isEmpty else {
            return nil
        }

        return deriveClaudeDesktopKey(secret: secret)
    }

    private func normalizedCursorPercent(_ raw: Any?) -> Int? {
        guard let raw else { return nil }
        return clampPercentage(Int(doubleValue(raw).rounded()))
    }

    private func resolvedCursorTotalPercent(
        plan: [String: Any]?,
        autoPercent: Int?,
        apiPercent: Int?
    ) -> Int {
        if let total = normalizedCursorPercent(plan?["totalPercentUsed"]) {
            return total
        }

        if let autoPercent, let apiPercent {
            return clampPercentage(Int((Double(autoPercent + apiPercent) / 2).rounded()))
        }

        if let apiPercent { return apiPercent }
        if let autoPercent { return autoPercent }

        let used = doubleValue(plan?["used"])
        let limit = doubleValue(plan?["limit"])
        guard limit > 0 else { return 0 }
        return clampPercentage(Int(((used / limit) * 100).rounded()))
    }

    private func parseCursorRequestWindow(_ payload: [String: Any]?, resetDetail: String) -> CursorWindow? {
        guard let payload,
              let requestFamily = payload["gpt-4"] as? [String: Any] else {
            return nil
        }

        let limit = integerValue(requestFamily["maxRequestUsage"])
        guard limit > 0 else { return nil }

        let used = max(integerValue(requestFamily["numRequestsTotal"]), integerValue(requestFamily["numRequests"]))
        let percentage = clampPercentage(Int((Double(used) / Double(limit) * 100).rounded()))
        let requestDetail = "\(used)/\(limit) req"

        return CursorWindow(
            label: "Req",
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
            return CursorWindow(label: "Auto", usedPercent: autoPercent, detail: resetDetail)
        }

        if let apiPercent {
            return CursorWindow(label: "API", usedPercent: apiPercent, detail: resetDetail)
        }

        return CursorWindow(label: "Plan", usedPercent: fallbackPercent, detail: resetDetail)
    }

    private func cursorResetDetail(resetAt: TimeInterval?) -> String {
        guard let resetAt else { return "--" }
        return "Resets \(formatResetDeadline(timestamp: Int(resetAt)))"
    }

    private func cursorUsageSummary(
        payload: [String: Any],
        plan: [String: Any]?,
        individualOnDemand: [String: Any]?,
        teamOnDemand: [String: Any]?,
        userInfo: [String: Any]?,
        sourceLabel: String,
        apiPercent: Int?
    ) -> String? {
        var parts: [String] = ["Cursor Web API via \(sourceLabel)"]

        if let membershipType = nonEmptyString(payload["membershipType"]) {
            parts.append("Plan \(membershipType.capitalized)")
        }

        if let apiPercent {
            parts.append("API \(apiPercent)%")
        }

        let planUsed = doubleValue(plan?["used"]) / 100
        let planLimit = doubleValue(plan?["limit"]) / 100
        if planUsed > 0 || planLimit > 0 {
            parts.append("Included \(formatUSD(planUsed))/\(formatUSD(planLimit))")
        }

        let onDemandUsed = doubleValue(individualOnDemand?["used"]) / 100
        let onDemandLimit = doubleValue(individualOnDemand?["limit"]) / 100
        if onDemandUsed > 0 || onDemandLimit > 0 {
            let suffix = onDemandLimit > 0 ? "/\(formatUSD(onDemandLimit))" : ""
            parts.append("On-demand \(formatUSD(onDemandUsed))\(suffix)")
        }

        let teamOnDemandUsed = doubleValue(teamOnDemand?["used"]) / 100
        let teamOnDemandLimit = doubleValue(teamOnDemand?["limit"]) / 100
        if teamOnDemandUsed > 0 || teamOnDemandLimit > 0 {
            let suffix = teamOnDemandLimit > 0 ? "/\(formatUSD(teamOnDemandLimit))" : ""
            parts.append("Team \(formatUSD(teamOnDemandUsed))\(suffix)")
        }

        if let email = nonEmptyString(userInfo?["email"]) {
            parts.append(email)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func formatUSD(_ amount: Double) -> String {
        String(format: "$%.2f", amount)
    }

    private func deriveClaudeDesktopKey(secret: String) -> Data? {
        let password = Array(secret.utf8)
        let salt = Array("saltysalt".utf8)
        var derived = [UInt8](repeating: 0, count: kCCKeySizeAES128)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            String(decoding: password, as: UTF8.self),
            password.count,
            salt,
            salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
            1003,
            &derived,
            derived.count
        )
        guard status == kCCSuccess else { return nil }
        return Data(derived)
    }

    private func dataFromHexString(_ hex: String) -> Data? {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count.isMultiple(of: 2) else { return nil }

        var data = Data(capacity: trimmed.count / 2)
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let nextIndex = trimmed.index(index, offsetBy: 2)
            guard let byte = UInt8(trimmed[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        return data
    }

    private func stringFromHexString(_ hex: String) -> String? {
        guard let data = dataFromHexString(hex) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func decryptClaudeDesktopCache(encryptedData: Data, key: Data) -> Data? {
        decryptChromiumCookieValue(encryptedData: encryptedData, key: key)
    }

    private func decryptChromiumCookieValue(encryptedData: Data, key: Data) -> Data? {
        let prefix = Data("v10".utf8)
        let ciphertext: Data
        if encryptedData.starts(with: prefix) {
            ciphertext = encryptedData.dropFirst(prefix.count)
        } else {
            ciphertext = encryptedData
        }

        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var output = Data(count: ciphertext.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var decryptedLength = 0

        let status = output.withUnsafeMutableBytes { outputBytes in
            ciphertext.withUnsafeBytes { cipherBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            cipherBytes.baseAddress,
                            ciphertext.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &decryptedLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        output.removeSubrange(decryptedLength..<output.count)
        return output
    }

    private func extractClaudeSessionKey(from decrypted: Data) -> String? {
        let decoded = String(decoding: decrypted, as: UTF8.self)
        guard let range = decoded.range(of: #"sk-ant-[A-Za-z0-9_-]+"#, options: .regularExpression) else {
            return nil
        }
        return String(decoded[range])
    }

    private func claudeQuotaSummary(sourceLabel: String, hasLocalHistory: Bool) -> String? {
        guard hasLocalHistory else { return sourceLabel == "Claude Code OAuth" ? nil : sourceLabel }
        if sourceLabel == "Claude Code OAuth" {
            return "Quota + local token history"
        }
        return "\(sourceLabel) + local token history"
    }
}

private enum UnixSocketSender {
    static func send(_ data: Data, to path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.stride)
        address.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = path.utf8CString
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count <= capacity else { return false }

        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            let rawPointer = UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self)
            for (index, byte) in pathBytes.enumerated() {
                rawPointer[index] = byte
            }
        }

        let addressLength = socklen_t(MemoryLayout.offset(of: \sockaddr_un.sun_path)! + pathBytes.count)
        let didConnect = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketPointer in
                connect(fd, socketPointer, addressLength)
            }
        }
        guard didConnect == 0 else { return false }

        let didWrite = data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return -1 }
            return write(fd, baseAddress, rawBuffer.count)
        }
        return didWrite >= 0
    }
}
