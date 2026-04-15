import Foundation

// Hook installation routines are isolated here so public toggle APIs stay small and easier to verify.
extension ConfigInstaller {
    static func installClaudeHooks(cli: CLIConfig, fm: FileManager) -> Bool {
        let directory = cli.dirPath
        if !fm.fileExists(atPath: directory) {
            try? fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }

        var settings: [String: Any] = parseJSONFile(at: cli.fullPath, fm: fm) ?? [:]
        var hooks = settings[cli.configKey] as? [String: Any] ?? [:]
        let events = compatibleEvents(for: cli)

        let alreadyInstalled = events.allSatisfy { event, _, _ in
            guard let entries = hooks[event] as? [[String: Any]] else { return false }
            return entries.contains { entry in
                guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
                return hookList.contains { ($0["command"] as? String) == hookCommand }
            }
        }
        if alreadyInstalled && !hasStaleAsyncKey(hooks) { return true }

        // Remove every legacy copy first so version-gated reinstalls do not accumulate duplicate handlers.
        for key in hooks.keys {
            if var entries = hooks[key] as? [[String: Any]] {
                entries.removeAll { containsOurHook($0) }
                hooks[key] = entries.isEmpty ? nil : entries
            }
        }

        for (event, timeout, _) in events {
            var eventHooks = hooks[event] as? [[String: Any]] ?? []
            let hookEntry: [String: Any] = [
                "type": "command",
                "command": hookCommand,
                "timeout": timeout,
            ]
            eventHooks.append(["matcher": "", "hooks": [hookEntry]])
            hooks[event] = eventHooks
        }

        settings[cli.configKey] = hooks
        guard let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) else {
            return false
        }
        return fm.createFile(atPath: cli.fullPath, contents: data)
    }

    @discardableResult
    static func installExternalHooks(cli: CLIConfig, fm: FileManager) -> Bool {
        if cli.format == .copilot {
            let rootDirectory = NSHomeDirectory() + "/.copilot"
            guard fm.fileExists(atPath: rootDirectory) else { return true }
            if !fm.fileExists(atPath: cli.dirPath) {
                try? fm.createDirectory(atPath: cli.dirPath, withIntermediateDirectories: true)
            }
        } else {
            guard fm.fileExists(atPath: cli.dirPath) else { return true }
        }

        var root: [String: Any] = parseJSONFile(at: cli.fullPath, fm: fm) ?? [:]
        var hooks = root[cli.configKey] as? [String: Any] ?? [:]

        for (event, timeout, _) in cli.events {
            var eventEntries = hooks[event] as? [[String: Any]] ?? []
            eventEntries.removeAll { containsOurHook($0) }

            let entry: [String: Any]
            switch cli.format {
            case .claude:
                let command = externalHookCommand(for: cli, event: event)
                entry = ["matcher": "*", "hooks": [["type": "command", "command": command] as [String: Any]]]
            case .nested:
                let command = externalHookCommand(for: cli, event: event)
                entry = ["hooks": [["type": "command", "command": command, "timeout": timeout] as [String: Any]]]
            case .flat:
                let command = externalHookCommand(for: cli, event: event)
                entry = ["command": command]
            case .copilot:
                let copilotCommand = "\(externalBridgeBaseCommand(for: cli)) --event \(event)"
                entry = ["type": "command", "bash": copilotCommand, "timeoutSec": timeout]
            }

            eventEntries.append(entry)
            hooks[event] = eventEntries
        }

        root[cli.configKey] = hooks
        if cli.format == .copilot {
            root["version"] = 1
        }
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else {
            return false
        }
        return fm.createFile(atPath: cli.fullPath, contents: data)
    }

    @discardableResult
    static func enableCodexHooksConfig(fm: FileManager) -> Bool {
        let configPath = NSHomeDirectory() + "/.codex/config.toml"
        var contents = ""
        if fm.fileExists(atPath: configPath) {
            contents = (try? String(contentsOfFile: configPath, encoding: .utf8)) ?? ""
        }

        if contents.range(of: #"(?m)^\s*codex_hooks\s*=\s*true"#, options: .regularExpression) != nil {
            return true
        }

        if contents.range(of: #"(?m)^\s*codex_hooks\s*=\s*false"#, options: .regularExpression) != nil {
            contents = contents.replacingOccurrences(
                of: #"(?m)^\s*codex_hooks\s*=\s*false"#,
                with: "codex_hooks = true",
                options: .regularExpression
            )
            return fm.createFile(atPath: configPath, contents: contents.data(using: .utf8))
        }

        var lines = contents.components(separatedBy: "\n")
        if let featuresIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[features]" }) {
            lines.insert("codex_hooks = true", at: featuresIndex + 1)
        } else {
            if lines.last?.isEmpty == false {
                lines.append("")
            }
            lines.append("[features]")
            lines.append("codex_hooks = true")
        }
        let result = lines.joined(separator: "\n")
        return fm.createFile(atPath: configPath, contents: result.data(using: .utf8))
    }

    static func uninstallHooks(cli: CLIConfig, fm: FileManager) {
        guard var root = parseJSONFile(at: cli.fullPath, fm: fm),
              var hooks = root[cli.configKey] as? [String: Any] else { return }

        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            entries.removeAll { containsOurHook($0) }
            if entries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = entries
            }
        }

        root[cli.configKey] = hooks.isEmpty ? nil : hooks
        if let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) {
            _ = fm.createFile(atPath: cli.fullPath, contents: data)
        }
    }

    static func installHookScript(fm: FileManager) {
        let needsUpdate: Bool
        if fm.fileExists(atPath: hookScriptPath),
           let existing = fm.contents(atPath: hookScriptPath),
           let string = String(data: existing, encoding: .utf8) {
            let hasCurrentVersion = string.contains("# SuperIsland hook v\(hookScriptVersion)")
            needsUpdate = !hasCurrentVersion
        } else {
            needsUpdate = true
        }

        if needsUpdate {
            _ = fm.createFile(atPath: hookScriptPath, contents: Data(hookScript.utf8))
            chmod(hookScriptPath, 0o755)
        }
    }

    // Copy through a temp file first so upgrades stay atomic even when the bridge binary is in use.
    static func installBridgeBinary(fm: FileManager) {
        guard let executablePath = Bundle.main.executablePath else { return }
        let executableDirectory = (executablePath as NSString).deletingLastPathComponent
        let contentsDirectory = (executableDirectory as NSString).deletingLastPathComponent
        var sourcePath = contentsDirectory + "/Helpers/superisland-bridge"
        if !fm.fileExists(atPath: sourcePath) {
            sourcePath = executableDirectory + "/superisland-bridge"
        }
        guard fm.fileExists(atPath: sourcePath) else { return }

        let temporaryPath = bridgePath + ".tmp.\(ProcessInfo.processInfo.processIdentifier)"
        do {
            try? fm.removeItem(atPath: temporaryPath)
            try fm.copyItem(atPath: sourcePath, toPath: temporaryPath)
            chmod(temporaryPath, 0o755)
            stripQuarantine(temporaryPath)
            _ = try fm.replaceItemAt(URL(fileURLWithPath: bridgePath), withItemAt: URL(fileURLWithPath: temporaryPath))
        } catch {
            try? fm.moveItem(atPath: temporaryPath, toPath: bridgePath)
            chmod(bridgePath, 0o755)
        }

        stripQuarantine(bridgePath)
    }

    // Copied helper binaries inherit quarantine from the app bundle, so removing the xattr avoids Gatekeeper prompts.
    static func stripQuarantine(_ path: String) {
        removexattr(path, "com.apple.quarantine", 0)
    }
}
