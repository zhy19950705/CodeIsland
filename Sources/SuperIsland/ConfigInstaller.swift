import Foundation

// Hook identifier matching stays centralized so installs can clean up legacy entries consistently.
enum HookId {
    static let current = "superisland"
    static let legacy = ["superisland", "vibenotch", "vibe-island"]

    static func isOurs(_ s: String) -> Bool {
        let lowered = s.lowercased()
        return lowered.contains(current)
            || legacy.contains(where: lowered.contains)
            || lowered.contains("--bridge-codex-hook")
    }
}

// Hook entry format variants stay explicit because each CLI expects a slightly different JSON shape.
enum HookFormat {
    case claude
    case nested
    case flat
    case copilot
}

// CLI integration metadata is shared by install, repair and detection paths.
struct CLIConfig {
    let name: String
    let source: String
    let configPath: String
    let configKey: String
    let format: HookFormat
    let events: [(String, Int, Bool)]
    /// Events that require a minimum CLI version (eventName → minVersion like "2.1.89").
    var versionedEvents: [String: String] = [:]

    var fullPath: String { NSHomeDirectory() + "/\(configPath)" }
    var dirPath: String { (fullPath as NSString).deletingLastPathComponent }
}

// ConfigInstaller keeps public install/repair entry points, while file-format helpers live in support files.
struct ConfigInstaller {
    static let bridgePath = NSHomeDirectory() + "/.claude/hooks/superisland-bridge"
    static let hookScriptPath = NSHomeDirectory() + "/.claude/hooks/superisland-hook.sh"
    static let hookCommand = "~/.claude/hooks/superisland-hook.sh"
    /// Absolute path for external CLI hooks avoids tilde expansion issues in IDE-launched processes.
    static let bridgeCommand = NSHomeDirectory() + "/.claude/hooks/superisland-bridge"

    // MARK: - Supported CLIs

    static let allCLIs: [CLIConfig] = [
        CLIConfig(
            name: "Claude Code", source: "claude",
            configPath: ".claude/settings.json", configKey: "hooks",
            format: .claude,
            events: [
                ("UserPromptSubmit", 5, true),
                ("PreToolUse", 5, false),
                ("PostToolUse", 5, true),
                ("PostToolUseFailure", 5, true),
                ("PermissionRequest", 86400, false),
                ("PermissionDenied", 5, true),
                ("Stop", 5, true),
                ("SubagentStart", 5, true),
                ("SubagentStop", 5, true),
                ("SessionStart", 5, false),
                ("SessionEnd", 5, true),
                ("Notification", 86400, false),
                ("PreCompact", 5, true),
            ],
            versionedEvents: [
                "PermissionDenied": "2.1.89",
                "PostToolUseFailure": "2.1.89",
            ]
        ),
        CLIConfig(
            name: "Codex", source: "codex",
            configPath: ".codex/hooks.json", configKey: "hooks",
            format: .nested,
            events: [
                ("SessionStart", 5, false),
                ("UserPromptSubmit", 5, false),
                ("PreToolUse", 5, false),
                ("PostToolUse", 5, false),
                ("Stop", 5, false),
            ]
        ),
        CLIConfig(
            name: "Gemini", source: "gemini",
            configPath: ".gemini/settings.json", configKey: "hooks",
            format: .nested,
            events: [
                ("SessionStart", 5000, false),
                ("SessionEnd", 5000, false),
                ("BeforeTool", 5000, false),
                ("AfterTool", 5000, false),
                ("BeforeAgent", 5000, false),
                ("AfterAgent", 5000, false),
            ]
        ),
        CLIConfig(
            name: "Cursor", source: "cursor",
            configPath: ".cursor/hooks.json", configKey: "hooks",
            format: .flat,
            events: [
                ("beforeSubmitPrompt", 5, false),
                ("beforeShellExecution", 5, false),
                ("afterShellExecution", 5, false),
                ("beforeReadFile", 5, false),
                ("afterFileEdit", 5, false),
                ("beforeMCPExecution", 5, false),
                ("afterMCPExecution", 5, false),
                ("afterAgentThought", 5, false),
                ("afterAgentResponse", 5, false),
                ("stop", 5, false),
            ]
        ),
        CLIConfig(
            name: "Qoder", source: "qoder",
            configPath: ".qoder/settings.json", configKey: "hooks",
            format: .claude,
            events: [
                ("UserPromptSubmit", 5, true),
                ("PreToolUse", 5, false),
                ("PostToolUse", 5, true),
                ("SessionStart", 5, false),
                ("SessionEnd", 5, true),
                ("Stop", 5, true),
                ("SubagentStart", 5, true),
                ("SubagentStop", 5, true),
                ("Notification", 86400, false),
                ("PreCompact", 5, true),
            ]
        ),
        CLIConfig(
            name: "Factory", source: "droid",
            configPath: ".factory/settings.json", configKey: "hooks",
            format: .claude,
            events: [
                ("UserPromptSubmit", 5, true),
                ("PreToolUse", 5, false),
                ("PostToolUse", 5, true),
                ("SessionStart", 5, false),
                ("SessionEnd", 5, true),
                ("Stop", 5, true),
                ("SubagentStart", 5, true),
                ("SubagentStop", 5, true),
                ("Notification", 86400, false),
                ("PreCompact", 5, true),
            ]
        ),
        CLIConfig(
            name: "CodeBuddy", source: "codebuddy",
            configPath: ".codebuddy/settings.json", configKey: "hooks",
            format: .claude,
            events: [
                ("UserPromptSubmit", 5, true),
                ("PreToolUse", 5, false),
                ("PostToolUse", 5, true),
                ("SessionStart", 5, false),
                ("SessionEnd", 5, true),
                ("Stop", 5, true),
                ("SubagentStart", 5, true),
                ("SubagentStop", 5, true),
                ("Notification", 86400, false),
                ("PreCompact", 5, true),
            ]
        ),
        CLIConfig(
            name: "Copilot", source: "copilot",
            configPath: ".copilot/hooks/superisland.json", configKey: "hooks",
            format: .copilot,
            events: [
                ("sessionStart", 5, false),
                ("sessionEnd", 5, true),
                ("userPromptSubmitted", 5, false),
                ("preToolUse", 5, false),
                ("postToolUse", 5, true),
                ("errorOccurred", 5, true),
            ]
        ),
    ]

    /// Hook script version should bump whenever the embedded template changes.
    static let hookScriptVersion = 4

    /// Claude Code uses the shell hook as a dispatcher so the bridge binary can update independently.
    static let hookScript = """
        #!/bin/bash
        # SuperIsland hook v\(hookScriptVersion) — native bridge with shell fallback
        BRIDGE="$HOME/.claude/hooks/superisland-bridge"
        if [ -x "$BRIDGE" ]; then
          "$BRIDGE" "$@"
          exit $?
        fi
        SOCK="/tmp/superisland-$(id -u).sock"
        [ -S "$SOCK" ] || exit 0
        INPUT=$(cat)
        _ITERM_GUID="${ITERM_SESSION_ID##*:}"
        TERM_INFO="\\"_term_app\\":\\"${TERM_PROGRAM:-}\\",\\"_iterm_session\\":\\"${_ITERM_GUID:-}\\",\\"_tty\\":\\"$(tty 2>/dev/null || true)\\",\\"_ppid\\":$PPID"
        PATCHED="${INPUT%\\}},${TERM_INFO}}"
        if echo "$INPUT" | grep -q '"PermissionRequest"'; then
          echo "$PATCHED" | nc -U -w 120 "$SOCK" 2>/dev/null || true
        else
          echo "$PATCHED" | nc -U -w 2 "$SOCK" 2>/dev/null || true
        fi
        """

    // MARK: - OpenCode plugin

    static let opencodePluginDir = NSHomeDirectory() + "/.config/opencode/plugins"
    static let opencodePluginPath = NSHomeDirectory() + "/.config/opencode/plugins/superisland.js"
    static let opencodeConfigPath = NSHomeDirectory() + "/.config/opencode/config.json"
    static let opencodePluginVersion = "v2"

    // MARK: - Version detection cache

    static var cachedClaudeVersion: String?

    // MARK: - Install / Uninstall

    static func install() -> Bool {
        let fm = FileManager.default
        let hookDir = (hookScriptPath as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: hookDir, withIntermediateDirectories: true)

        installHookScript(fm: fm)
        installBridgeBinary(fm: fm)

        var ok = true
        for cli in allCLIs {
            guard isEnabled(source: cli.source) else { continue }
            if cli.source == "claude" {
                if !installClaudeHooks(cli: cli, fm: fm) { ok = false }
            } else if !installExternalHooks(cli: cli, fm: fm) {
                ok = false
            }
        }

        if isEnabled(source: "codex"),
           fm.fileExists(atPath: NSHomeDirectory() + "/.codex") {
            enableCodexHooksConfig(fm: fm)
        }

        if isEnabled(source: "opencode"),
           !installOpencodePlugin(fm: fm) {
            ok = false
        }

        return ok
    }

    static func uninstall() {
        let fm = FileManager.default
        try? fm.removeItem(atPath: hookScriptPath)
        try? fm.removeItem(atPath: bridgePath)

        for cli in allCLIs {
            uninstallHooks(cli: cli, fm: fm)
        }

        uninstallOpencodePlugin(fm: fm)
    }

    static func isInstalled() -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: hookScriptPath) else { return false }
        guard let claude = allCLIs.first else { return false }
        return isHooksInstalled(for: claude, fm: fm)
    }

    static func isInstalled(source: String) -> Bool {
        if source == "opencode" {
            return isOpencodePluginInstalled(fm: FileManager.default)
        }
        guard let cli = allCLIs.first(where: { $0.source == source }) else { return false }
        return isHooksInstalled(for: cli, fm: FileManager.default)
    }

    static func cliExists(source: String) -> Bool {
        if source == "opencode" {
            return FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.config/opencode")
        }
        if source == "copilot" {
            return FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.copilot")
        }
        guard let cli = allCLIs.first(where: { $0.source == source }) else { return false }
        return FileManager.default.fileExists(atPath: cli.dirPath)
    }

    static func isCodexInstalled() -> Bool { isInstalled(source: "codex") }

    static func isEnabled(source: String) -> Bool {
        let key = "cli_enabled_\(source)"
        if UserDefaults.standard.object(forKey: key) == nil { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    @discardableResult
    static func setEnabled(source: String, enabled: Bool) -> Bool {
        UserDefaults.standard.set(enabled, forKey: "cli_enabled_\(source)")
        let fm = FileManager.default

        if enabled {
            installHookScript(fm: fm)
            installBridgeBinary(fm: fm)

            if source == "opencode" {
                return installOpencodePlugin(fm: fm)
            }

            guard let cli = allCLIs.first(where: { $0.source == source }) else { return false }
            if cli.source == "claude" {
                return installClaudeHooks(cli: cli, fm: fm)
            }

            installExternalHooks(cli: cli, fm: fm)
            if cli.source == "codex" {
                enableCodexHooksConfig(fm: fm)
            }
            return isHooksInstalled(for: cli, fm: fm)
        }

        if source == "opencode" {
            uninstallOpencodePlugin(fm: fm)
        } else if let cli = allCLIs.first(where: { $0.source == source }) {
            uninstallHooks(cli: cli, fm: fm)
        }
        return true
    }

    static func verifyAndRepair() -> [String] {
        let fm = FileManager.default
        installBridgeBinary(fm: fm)
        installHookScript(fm: fm)

        var repaired: [String] = []
        for cli in allCLIs {
            guard isEnabled(source: cli.source) else { continue }
            let dirExists = cli.format == .copilot
                ? fm.fileExists(atPath: NSHomeDirectory() + "/.copilot")
                : fm.fileExists(atPath: cli.dirPath)
            guard dirExists else { continue }
            guard !isHooksInstalled(for: cli, fm: fm) else { continue }

            if cli.source == "claude" {
                if installClaudeHooks(cli: cli, fm: fm) {
                    repaired.append(cli.name)
                }
                continue
            }

            installExternalHooks(cli: cli, fm: fm)
            if cli.source == "codex" {
                enableCodexHooksConfig(fm: fm)
            }
            if isHooksInstalled(for: cli, fm: fm) {
                repaired.append(cli.name)
            }
        }

        if isEnabled(source: "codex"),
           fm.fileExists(atPath: NSHomeDirectory() + "/.codex") {
            enableCodexHooksConfig(fm: fm)
        }

        if isEnabled(source: "opencode"),
           fm.fileExists(atPath: (opencodeConfigPath as NSString).deletingLastPathComponent),
           !isOpencodePluginInstalled(fm: fm),
           installOpencodePlugin(fm: fm) {
            repaired.append("OpenCode")
        }

        return repaired
    }
}
