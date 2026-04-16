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

    // Editor jumps intentionally avoid terminal-first chains so the detail footer can offer a true workspace/editor handoff.
    func editorFallbackChain(for session: SessionSnapshot) -> [JumpTarget] {
        var targets: [JumpTarget] = []

        if let bundleId = session.termBundleId,
           let hostChain = hostFallbackChain(for: bundleId) {
            targets.append(contentsOf: hostChain.filter { isEditorLikeTarget($0) && $0 != .finder })
        }

        if let nativeTarget = exactNativeTarget(for: session) {
            targets.append(nativeTarget)
        }

        switch session.source {
        case "cursor":
            targets.append(contentsOf: [.cursor, .visualStudioCode, .windsurf])
        case "trae":
            targets.append(contentsOf: [.trae, .visualStudioCode, .cursor, .windsurf])
        case "qoder":
            targets.append(contentsOf: [.qoder, .cursor, .visualStudioCode, .windsurf])
        case "codebuddy":
            targets.append(contentsOf: [.codeBuddy, .cursor, .visualStudioCode, .windsurf])
        case "droid":
            targets.append(contentsOf: [.factory, .cursor, .visualStudioCode, .windsurf])
        case "codex":
            targets.append(contentsOf: [.codex, .cursor, .visualStudioCode, .windsurf])
        case "opencode":
            targets.append(contentsOf: [.openCode, .cursor, .visualStudioCode, .windsurf])
        default:
            break
        }

        targets.append(contentsOf: [
            .cursor,
            .trae,
            .qoder,
            .codeBuddy,
            .factory,
            .windsurf,
            .visualStudioCodeInsiders,
            .visualStudioCode,
            .vscodium,
        ])

        // Finder stays last so unsupported IDE hosts do not hide a usable editor that is installed locally.
        return deduplicatedJumpTargets(targets + [.finder])
    }

    // Detail views need a stable label even when the actual launch falls back from an app to Finder.
    func resolvedEditorTarget(for session: SessionSnapshot) -> JumpTarget? {
        if let nativeTarget = exactNativeTarget(for: session),
           isTargetAvailable(nativeTarget) {
            return nativeTarget
        }

        guard let cwd = session.cwd,
              bestWorkspaceURL(for: cwd) != nil else {
            return nil
        }

        return editorFallbackChain(for: session).first(where: isTargetAvailable)
    }

    // Detail surfaces cannot block SwiftUI layout on PATH probing, so render-time resolution only checks
    // bundle registration and bundled absolute executables that are cheap to inspect synchronously.
    func resolvedPresentationEditorTarget(for session: SessionSnapshot) -> JumpTarget? {
        if let nativeTarget = exactNativeTarget(for: session),
           isPresentationTargetAvailable(nativeTarget) {
            return nativeTarget
        }

        guard let cwd = session.cwd,
              bestWorkspaceURL(for: cwd) != nil else {
            return nil
        }

        return editorFallbackChain(for: session).first(where: isPresentationTargetAvailable)
    }

    func canResolveEditor(for session: SessionSnapshot) -> Bool {
        resolvedEditorTarget(for: session) != nil
    }

    func resolvedEditorApplicationName(for session: SessionSnapshot) -> String? {
        resolvedEditorTarget(for: session)?.title
    }

    // Render-time labels should stay aligned with the lightweight target selection used by the detail footer.
    func resolvedPresentationEditorApplicationName(for session: SessionSnapshot) -> String? {
        resolvedPresentationEditorTarget(for: session)?.title
    }

    @discardableResult
    func openEditor(for session: SessionSnapshot, sessionId: String? = nil) -> Bool {
        guard let target = resolvedEditorTarget(for: session) else { return false }

        switch target {
        case .obsidian:
            return openInObsidian(sessionId: sessionId, vaultPath: session.cwd)
        case .codex:
            if let sessionId, openInCodex(sessionId: sessionId) {
                return true
            }
        case .openCode:
            if activateApplication(target: .openCode) {
                return true
            }
        case .cursor,
             .trae,
             .qoder,
             .codeBuddy,
             .factory,
             .windsurf,
             .visualStudioCode,
             .visualStudioCodeInsiders,
             .vscodium,
             .finder:
            break
        default:
            return false
        }

        guard let cwd = session.cwd,
              let workspaceURL = bestWorkspaceURL(for: cwd) else { return false }

        switch target {
        case .cursor,
             .trae,
             .qoder,
             .codeBuddy,
             .factory,
             .windsurf,
             .visualStudioCode,
             .visualStudioCodeInsiders,
             .vscodium:
            return openInCodeCompatibleEditor(workspaceURL, target: target, sessionId: sessionId)
        case .finder:
            return workspace.open(workspaceURL)
        case .codex:
            return openWithApplication(workspaceURL, target: .codex)
        case .openCode:
            return openWithApplication(workspaceURL, target: .openCode)
        case .obsidian:
            return openWithApplication(workspaceURL, target: .obsidian)
        default:
            return false
        }
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

    // The lightweight availability path intentionally avoids `which` so SwiftUI body evaluation never launches subprocesses.
    func isPresentationTargetAvailable(_ target: JumpTarget) -> Bool {
        switch target {
        case .finder:
            return true
        default:
            guard let descriptor = applicationDescriptors[target] else { return false }
            if workspace.urlForApplication(withBundleIdentifier: descriptor.bundleIdentifier) != nil {
                return true
            }
            return descriptor.cliCandidates.contains { candidate in
                candidate.hasPrefix("/") && fileManager.isExecutableFile(atPath: candidate)
            }
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

    // Keep editor-only ranking explicit so footer actions never regress back to terminal-oriented ordering.
    private func isEditorLikeTarget(_ target: JumpTarget) -> Bool {
        switch target {
        case .obsidian,
             .codex,
             .openCode,
             .cursor,
             .trae,
             .qoder,
             .codeBuddy,
             .factory,
             .windsurf,
             .visualStudioCode,
             .visualStudioCodeInsiders,
             .vscodium,
             .finder:
            return true
        case .cmux, .ghostty, .warp, .iTerm, .terminal:
            return false
        }
    }

    private func deduplicatedJumpTargets(_ targets: [JumpTarget]) -> [JumpTarget] {
        var seen: Set<String> = []
        return targets.filter { target in
            let key = target.title
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }
}
