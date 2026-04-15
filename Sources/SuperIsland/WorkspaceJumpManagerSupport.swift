import Foundation
import SuperIslandCore

// Workspace jump routing logic stays here so fallback decisions remain separate from platform execution details.
extension WorkspaceJumpManager {
    // Resolve the preferred app order from the host bundle first, then fall back to the session source.
    func fallbackChain(for session: SessionSnapshot) -> [JumpTarget] {
        if let bundleId = session.termBundleId,
           let hostChain = hostFallbackChain(for: bundleId) {
            return hostChain
        }

        switch session.source {
        case "cursor":
            return [.cursor, .visualStudioCode, .windsurf, .ghostty, .warp, .iTerm, .terminal, .finder]
        case "qoder":
            return [.qoder, .cursor, .visualStudioCode, .windsurf, .ghostty, .warp, .iTerm, .terminal, .finder]
        case "codebuddy":
            return [.codeBuddy, .cursor, .visualStudioCode, .windsurf, .ghostty, .warp, .iTerm, .terminal, .finder]
        case "droid":
            return [.factory, .cursor, .visualStudioCode, .windsurf, .ghostty, .warp, .iTerm, .terminal, .finder]
        case "codex":
            return [.codex, .finder]
        case "opencode":
            return [.openCode, .finder]
        default:
            if session.tmuxPane?.isEmpty == false {
                return [.cmux, .ghostty, .warp, .iTerm, .terminal, .finder]
            }
            return [.ghostty, .warp, .iTerm, .terminal, .cursor, .visualStudioCode, .windsurf, .finder]
        }
    }

    func hostFallbackChain(for bundleIdentifier: String) -> [JumpTarget]? {
        let normalized = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        switch normalized {
        case "com.cmuxterm.app":
            return [.cmux, .ghostty, .warp, .iTerm, .terminal, .finder]
        case "com.mitchellh.ghostty":
            return [.ghostty, .warp, .iTerm, .terminal, .finder]
        case "dev.warp.warp-stable":
            return [.warp, .ghostty, .iTerm, .terminal, .finder]
        case "com.googlecode.iterm2":
            return [.iTerm, .terminal, .ghostty, .warp, .finder]
        case "com.apple.terminal":
            return [.terminal, .ghostty, .iTerm, .warp, .finder]
        case "md.obsidian":
            return [.obsidian, .finder]
        case "com.openai.codex":
            return [.codex, .finder]
        case "ai.opencode.desktop":
            return [.openCode, .finder]
        case "com.todesktop.230313mzl4w4u92":
            return [.cursor, .visualStudioCode, .windsurf, .ghostty, .warp, .iTerm, .terminal, .finder]
        case "com.trae.app":
            return [.trae, .visualStudioCode, .cursor, .windsurf, .finder]
        case "com.qoder.ide":
            return [.qoder, .cursor, .visualStudioCode, .windsurf, .ghostty, .warp, .iTerm, .terminal, .finder]
        case "com.tencent.codebuddy":
            return [.codeBuddy, .cursor, .visualStudioCode, .windsurf, .ghostty, .warp, .iTerm, .terminal, .finder]
        case "com.factory.app":
            return [.factory, .cursor, .visualStudioCode, .windsurf, .ghostty, .warp, .iTerm, .terminal, .finder]
        case "com.exafunction.windsurf":
            return [.windsurf, .cursor, .visualStudioCode, .ghostty, .warp, .iTerm, .terminal, .finder]
        case "com.microsoft.vscode":
            return [.visualStudioCode, .cursor, .windsurf, .finder]
        case "com.microsoft.vscodeinsiders":
            return [.visualStudioCodeInsiders, .visualStudioCode, .cursor, .windsurf, .finder]
        case "com.vscodium":
            return [.vscodium, .visualStudioCode, .cursor, .windsurf, .finder]
        default:
            break
        }

        if normalized.contains("vscode") {
            return [.visualStudioCode, .cursor, .windsurf, .finder]
        }
        if normalized.contains("vscodium") {
            return [.vscodium, .visualStudioCode, .cursor, .windsurf, .finder]
        }
        if normalized.contains("trae") {
            return [.trae, .visualStudioCode, .cursor, .windsurf, .finder]
        }
        if normalized.contains("jetbrains")
            || normalized.contains("zed")
            || normalized.contains("xcode")
            || normalized == "com.apple.dt.xcode"
            || normalized.contains("panic.nova")
            || normalized.contains("android.studio")
            || normalized.contains("antigravity") {
            return [.finder]
        }

        return nil
    }

    func isTargetAvailable(_ target: JumpTarget) -> Bool {
        switch target {
        case .finder:
            return true
        default:
            if cliExecutable(for: target) != nil {
                return true
            }
            guard let descriptor = applicationDescriptors[target] else { return false }
            return workspace.urlForApplication(withBundleIdentifier: descriptor.bundleIdentifier) != nil
        }
    }

    // Native targets can bypass workspace path resolution and jump straight into app-specific deep links.
    func exactNativeTarget(for session: SessionSnapshot) -> JumpTarget? {
        switch session.termBundleId ?? "" {
        case "md.obsidian":
            return .obsidian
        case "com.openai.codex":
            return .codex
        case "ai.opencode.desktop":
            return .openCode
        default:
            return nil
        }
    }

    func openNativeTarget(_ target: JumpTarget, sessionId: String, session: SessionSnapshot) -> Bool {
        switch target {
        case .obsidian:
            return openInObsidian(sessionId: sessionId, vaultPath: session.cwd)
        case .codex:
            return openInCodex(sessionId: sessionId)
        case .openCode:
            return activateApplication(target: .openCode)
        default:
            return false
        }
    }
}
