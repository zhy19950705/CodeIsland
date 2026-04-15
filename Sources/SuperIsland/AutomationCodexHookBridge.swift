import Foundation
import Darwin
import CommonCrypto
import SuperIslandCore

struct CodexHookBridgeCommand {
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

func nonEmptyString(_ value: Any?) -> String? {
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
