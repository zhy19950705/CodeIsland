import Foundation

// ConfigInstaller support helpers stay pure where possible so config-format refactors remain low risk.
extension ConfigInstaller {
    // Strip JSONC comments while preserving string contents so URL values and shell commands survive unchanged.
    static func stripJSONComments(_ input: String) -> String {
        var result = ""
        result.reserveCapacity(input.count)
        var i = input.startIndex
        let end = input.endIndex

        while i < end {
            let character = input[i]
            if character == "\"" {
                result.append(character)
                i = input.index(after: i)
                while i < end {
                    let stringCharacter = input[i]
                    result.append(stringCharacter)
                    if stringCharacter == "\\" {
                        i = input.index(after: i)
                        if i < end { result.append(input[i]) }
                    } else if stringCharacter == "\"" {
                        break
                    }
                    i = input.index(after: i)
                }
                if i < end { i = input.index(after: i) }
                continue
            }

            let next = input.index(after: i)
            if character == "/" && next < end {
                let nextCharacter = input[next]
                if nextCharacter == "/" {
                    i = input.index(after: next)
                    while i < end && input[i] != "\n" {
                        i = input.index(after: i)
                    }
                    continue
                }
                if nextCharacter == "*" {
                    i = input.index(after: next)
                    while i < end {
                        let blockNext = input.index(after: i)
                        if input[i] == "*" && blockNext < end && input[blockNext] == "/" {
                            i = input.index(after: blockNext)
                            break
                        }
                        i = input.index(after: i)
                    }
                    continue
                }
            }

            result.append(character)
            i = input.index(after: i)
        }

        return result
    }

    static func versionAtLeast(_ installed: String, _ required: String) -> Bool {
        let installedComponents = installed.split(separator: ".").compactMap { Int($0) }
        let requiredComponents = required.split(separator: ".").compactMap { Int($0) }

        for index in 0..<max(installedComponents.count, requiredComponents.count) {
            let installedValue = index < installedComponents.count ? installedComponents[index] : 0
            let requiredValue = index < requiredComponents.count ? requiredComponents[index] : 0
            if installedValue > requiredValue { return true }
            if installedValue < requiredValue { return false }
        }

        return true
    }

    static func parseJSONFile(at path: String, fm: FileManager) -> [String: Any]? {
        guard fm.fileExists(atPath: path),
              let data = fm.contents(atPath: path),
              let string = String(data: data, encoding: .utf8) else { return nil }
        let stripped = stripJSONComments(string)
        guard let strippedData = stripped.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: strippedData) as? [String: Any] else { return nil }
        return json
    }

    // GUI apps do not inherit an interactive shell PATH, so version lookup checks explicit install locations first.
    static func detectClaudeVersion() -> String? {
        if let cached = cachedClaudeVersion { return cached }

        let candidates = [
            NSHomeDirectory() + "/.local/bin/claude",
            "/usr/local/bin/claude",
        ]
        guard let claudePath = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let version = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: " ")
                    .first ?? ""
                if !version.isEmpty {
                    cachedClaudeVersion = version
                }
                return cachedClaudeVersion
            }
        } catch {}

        return nil
    }

    static func compatibleEvents(for cli: CLIConfig) -> [(String, Int, Bool)] {
        guard !cli.versionedEvents.isEmpty else { return cli.events }
        guard cli.source == "claude" else { return cli.events }

        let version = detectClaudeVersion()
        return cli.events.filter { event, _, _ in
            guard let minimumVersion = cli.versionedEvents[event] else { return true }
            guard let version else { return false }
            return versionAtLeast(version, minimumVersion)
        }
    }

    static func isHooksInstalled(for cli: CLIConfig, fm: FileManager) -> Bool {
        guard let root = parseJSONFile(at: cli.fullPath, fm: fm),
              let hooks = root[cli.configKey] as? [String: Any] else { return false }

        let allPresent = cli.events.allSatisfy { event, _, _ in
            guard let entries = hooks[event] as? [[String: Any]] else { return false }
            return entries.contains { containsOurHook($0) }
        }
        guard allPresent else { return false }
        return !hasStaleAsyncKey(hooks)
    }

    static func hasStaleAsyncKey(_ hooks: [String: Any]) -> Bool {
        for (_, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            for entry in entries where containsOurHook(entry) {
                if let hookList = entry["hooks"] as? [[String: Any]],
                   hookList.contains(where: { $0["async"] != nil }) {
                    return true
                }
            }
        }
        return false
    }

    static func containsOurHook(_ entry: [String: Any]) -> Bool {
        if let hookList = entry["hooks"] as? [[String: Any]] {
            return hookList.contains {
                let command = $0["command"] as? String ?? ""
                return HookId.isOurs(command)
            }
        }
        if let command = entry["command"] as? String, HookId.isOurs(command) {
            return true
        }
        if let command = entry["bash"] as? String, HookId.isOurs(command) {
            return true
        }
        return false
    }

    static func externalHookCommand(for cli: CLIConfig, event: String) -> String {
        if cli.source == "codex", let executablePath = currentExecutablePath() {
            return "\(shellQuote(executablePath)) --bridge-codex-hook --source codex --event \(event)"
        }
        return externalBridgeBaseCommand(for: cli)
    }

    static func externalBridgeBaseCommand(for cli: CLIConfig) -> String {
        let quotedBridge = bridgeCommand.contains(" ") ? "\"\(bridgeCommand)\"" : bridgeCommand
        return "\(quotedBridge) --source \(cli.source)"
    }

    static func currentExecutablePath() -> String? {
        AutomationCLI.executableURL()?.path
    }

    static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
