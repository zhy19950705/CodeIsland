import AppKit
import Foundation
import UniformTypeIdentifiers
import SuperIslandCore

// Workspace jump entry points and target dispatch stay here; platform-specific helpers live in support files.
@MainActor
final class WorkspaceJumpManager {
    let fileManager: FileManager
    let workspace: NSWorkspace

    // Keeping app metadata centralized avoids repeated bundle-id and CLI resolution logic across targets.
    let applicationDescriptors: [JumpTarget: ApplicationDescriptor] = [
        .cmux: ApplicationDescriptor(
            bundleIdentifier: "com.cmuxterm.app",
            cliCandidates: ["cmux", "/Applications/cmux.app/Contents/Resources/bin/cmux"],
            uriScheme: nil
        ),
        .ghostty: ApplicationDescriptor(
            bundleIdentifier: "com.mitchellh.ghostty",
            cliCandidates: [],
            uriScheme: nil
        ),
        .warp: ApplicationDescriptor(
            bundleIdentifier: "dev.warp.Warp-Stable",
            cliCandidates: [],
            uriScheme: "warp"
        ),
        .iTerm: ApplicationDescriptor(
            bundleIdentifier: "com.googlecode.iterm2",
            cliCandidates: [],
            uriScheme: nil
        ),
        .terminal: ApplicationDescriptor(
            bundleIdentifier: "com.apple.Terminal",
            cliCandidates: [],
            uriScheme: nil
        ),
        .obsidian: ApplicationDescriptor(
            bundleIdentifier: "md.obsidian",
            cliCandidates: ["obsidian"],
            uriScheme: nil
        ),
        .codex: ApplicationDescriptor(
            bundleIdentifier: "com.openai.codex",
            cliCandidates: [],
            uriScheme: "codex"
        ),
        .openCode: ApplicationDescriptor(
            bundleIdentifier: "ai.opencode.desktop",
            cliCandidates: [],
            uriScheme: nil
        ),
        .cursor: ApplicationDescriptor(
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            cliCandidates: [
                "cursor",
                "/Applications/Cursor.app/Contents/Resources/app/bin/cursor",
                "/Applications/Cursor.app/Contents/Resources/app/bin/code",
            ],
            uriScheme: "cursor"
        ),
        .trae: ApplicationDescriptor(
            bundleIdentifier: "com.trae.app",
            cliCandidates: [
                "trae",
            ],
            uriScheme: "trae"
        ),
        .qoder: ApplicationDescriptor(
            bundleIdentifier: "com.qoder.ide",
            cliCandidates: ["qoder"],
            uriScheme: "qoder"
        ),
        .codeBuddy: ApplicationDescriptor(
            bundleIdentifier: "com.tencent.codebuddy",
            cliCandidates: [],
            uriScheme: "codebuddy"
        ),
        .factory: ApplicationDescriptor(
            bundleIdentifier: "com.factory.app",
            cliCandidates: [],
            uriScheme: nil
        ),
        .windsurf: ApplicationDescriptor(
            bundleIdentifier: "com.exafunction.windsurf",
            cliCandidates: [
                "windsurf",
                "/Applications/Windsurf.app/Contents/Resources/app/bin/windsurf",
                "/Applications/Windsurf.app/Contents/Resources/app/bin/code",
            ],
            uriScheme: "windsurf"
        ),
        .visualStudioCode: ApplicationDescriptor(
            bundleIdentifier: "com.microsoft.VSCode",
            cliCandidates: [
                "code",
                "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
            ],
            uriScheme: "vscode"
        ),
        .visualStudioCodeInsiders: ApplicationDescriptor(
            bundleIdentifier: "com.microsoft.VSCodeInsiders",
            cliCandidates: [
                "code-insiders",
                "/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code-insiders",
            ],
            uriScheme: "vscode-insiders"
        ),
        .vscodium: ApplicationDescriptor(
            bundleIdentifier: "com.vscodium",
            cliCandidates: [
                "codium",
                "/Applications/VSCodium.app/Contents/Resources/app/bin/codium",
            ],
            uriScheme: "vscodium"
        ),
    ]

    init(fileManager: FileManager = .default, workspace: NSWorkspace = .shared) {
        self.fileManager = fileManager
        self.workspace = workspace
    }

    @discardableResult
    func openWorkspace(for session: SessionSnapshot, sessionId: String? = nil) -> Bool {
        if let sessionId,
           let nativeTarget = exactNativeTarget(for: session),
           isTargetAvailable(nativeTarget),
           openNativeTarget(nativeTarget, sessionId: sessionId, session: session) {
            return true
        }

        guard let cwd = session.cwd,
              let workspaceURL = bestWorkspaceURL(for: cwd) else { return false }

        for target in fallbackChain(for: session) {
            guard isTargetAvailable(target) else { continue }
            if open(workspaceURL, using: target, sessionId: sessionId, session: session) {
                return true
            }
        }

        return workspace.open(workspaceURL)
    }

    @discardableResult
    func openResumeSession(for session: SessionSnapshot, sessionId: String) -> Bool {
        guard let command = SessionResumeSupport.resumeCommand(for: session, sessionId: sessionId) else {
            return openWorkspace(for: session, sessionId: sessionId)
        }

        // Resume commands need a scriptable terminal, so prefer iTerm when available and fall back to Terminal.app.
        if isTargetAvailable(.iTerm), openShellCommandInITerm(command) {
            return true
        }
        return openShellCommandInTerminal(command)
    }

    func canResolveWorkspace(for session: SessionSnapshot) -> Bool {
        guard let cwd = session.cwd else { return false }
        return bestWorkspaceURL(for: cwd) != nil
    }

    func resolvedApplicationName(for session: SessionSnapshot) -> String {
        fallbackChain(for: session).first(where: isTargetAvailable)?.title ?? JumpTarget.finder.title
    }

    func fallbackTitles(for session: SessionSnapshot) -> [String] {
        fallbackChain(for: session).map { $0.title }
    }

    // Detail footer buttons use app icons so the workspace handoff target stays immediately recognizable.
    func applicationIcon(for target: JumpTarget) -> NSImage? {
        switch target {
        case .finder:
            return NSWorkspace.shared.icon(for: .folder)
        default:
            guard let descriptor = applicationDescriptors[target],
                  let applicationURL = workspace.urlForApplication(withBundleIdentifier: descriptor.bundleIdentifier) else {
                return nil
            }
            return workspace.icon(forFile: applicationURL.path)
        }
    }

    // Resolve the icon from the same target selection used by editor jumps so button copy and icon never diverge.
    func resolvedEditorIcon(for session: SessionSnapshot) -> NSImage? {
        guard let target = resolvedEditorTarget(for: session) else { return nil }
        return applicationIcon(for: target)
    }

    // Dispatch stays centralized here so target-specific behavior remains easy to audit.
    private func open(_ workspaceURL: URL, using target: JumpTarget, sessionId: String?, session: SessionSnapshot) -> Bool {
        switch target {
        case .cmux:
            return openInCmux(workspaceURL, session: session)
        case .ghostty:
            return openWithApplication(workspaceURL, target: .ghostty)
        case .warp:
            return openInWarp(workspaceURL)
        case .iTerm:
            return openInITerm(workspaceURL)
        case .terminal:
            return openInTerminal(workspaceURL)
        case .obsidian:
            return openInObsidian(sessionId: sessionId, vaultPath: workspaceURL.path)
                || openWithApplication(workspaceURL, target: .obsidian)
        case .codex:
            return openInCodex(sessionId: sessionId) || openWithApplication(workspaceURL, target: .codex)
        case .openCode:
            return openWithApplication(workspaceURL, target: .openCode)
        case .cursor, .trae, .qoder, .codeBuddy, .windsurf, .visualStudioCode, .visualStudioCodeInsiders, .vscodium:
            return openInCodeCompatibleEditor(workspaceURL, target: target, sessionId: sessionId)
        case .factory:
            return openWithApplication(workspaceURL, target: .factory)
        case .finder:
            return workspace.open(workspaceURL)
        }
    }
}
