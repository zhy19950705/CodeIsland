import AppKit
import Foundation
import SuperIslandCore

@MainActor
final class WorkspaceJumpManager {
    private struct CmuxTreeSnapshot: Decodable {
        var windows: [CmuxWindow]
    }

    private struct CmuxWindow: Decodable {
        var workspaces: [CmuxWorkspace]
    }

    private struct CmuxWorkspace: Decodable {
        var ref: String
        var panes: [CmuxPane]
    }

    private struct CmuxPane: Decodable {
        var ref: String
        var surfaceRefs: [String]
        var selectedSurfaceRef: String?

        private enum CodingKeys: String, CodingKey {
            case ref
            case surfaceRefs = "surface_refs"
            case selectedSurfaceRef = "selected_surface_ref"
        }
    }

    private enum JumpTarget {
        case cmux
        case ghostty
        case warp
        case iTerm
        case terminal
        case obsidian
        case codex
        case openCode
        case cursor
        case trae
        case qoder
        case codeBuddy
        case factory
        case windsurf
        case visualStudioCode
        case visualStudioCodeInsiders
        case vscodium
        case finder

        var title: String {
            switch self {
            case .cmux: return "cmux"
            case .ghostty: return "Ghostty"
            case .warp: return "Warp"
            case .iTerm: return "iTerm2"
            case .terminal: return "Terminal"
            case .obsidian: return "Obsidian"
            case .codex: return "Codex"
            case .openCode: return "OpenCode"
            case .cursor: return "Cursor"
            case .trae: return "Trae"
            case .qoder: return "Qoder"
            case .codeBuddy: return "CodeBuddy"
            case .factory: return "Factory"
            case .windsurf: return "Windsurf"
            case .visualStudioCode: return "VS Code"
            case .visualStudioCodeInsiders: return "VS Code Insiders"
            case .vscodium: return "VSCodium"
            case .finder: return "Finder"
            }
        }
    }

    private struct ApplicationDescriptor {
        let bundleIdentifier: String
        let cliCandidates: [String]
        let uriScheme: String?
    }

    private let fileManager: FileManager
    private let workspace: NSWorkspace

    private let applicationDescriptors: [JumpTarget: ApplicationDescriptor] = [
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

    func canResolveWorkspace(for session: SessionSnapshot) -> Bool {
        guard let cwd = session.cwd else { return false }
        return bestWorkspaceURL(for: cwd) != nil
    }

    func resolvedApplicationName(for session: SessionSnapshot) -> String {
        fallbackChain(for: session).first(where: isTargetAvailable)?.title ?? JumpTarget.finder.title
    }

    private func fallbackChain(for session: SessionSnapshot) -> [JumpTarget] {
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

    func fallbackTitles(for session: SessionSnapshot) -> [String] {
        fallbackChain(for: session).map(\.title)
    }

    private func hostFallbackChain(for bundleIdentifier: String) -> [JumpTarget]? {
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

    private func isTargetAvailable(_ target: JumpTarget) -> Bool {
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

    private func openInCmux(_ workspaceURL: URL, session: SessionSnapshot) -> Bool {
        let workspaceReference = normalizedCmuxReference(session.cmuxWorkspaceRef)
            ?? normalizedCmuxReference(session.cmuxWorkspaceId)
        let surfaceReference = normalizedCmuxReference(session.cmuxSurfaceRef)
            ?? normalizedCmuxReference(session.cmuxSurfaceId)
        let paneReference = normalizedCmuxReference(session.cmuxPaneRef)

        if focusInCmuxViaCLI(
            workspaceReference: workspaceReference,
            surfaceReference: surfaceReference,
            paneReference: paneReference,
            socketPath: session.cmuxSocketPath
        ) {
            return true
        }

        if let executable = cliExecutable(for: .cmux),
           runProcess(executable: executable, arguments: [workspaceURL.path], environment: cmuxEnvironment(socketPath: session.cmuxSocketPath)) {
            return true
        }
        return openWithApplication(workspaceURL, target: .cmux)
    }

    private func openInWarp(_ url: URL) -> Bool {
        if let warpURL = warpURL(for: url), workspace.open(warpURL) {
            return true
        }
        return openWithApplication(url, target: .warp)
    }

    private func openInITerm(_ url: URL) -> Bool {
        runAppleScript(scriptForITerm(path: url.path)) || openWithApplication(url, target: .iTerm)
    }

    private func openInTerminal(_ url: URL) -> Bool {
        runAppleScript(scriptForTerminal(path: url.path)) || openWithApplication(url, target: .terminal)
    }

    private func openInCodeCompatibleEditor(_ workspaceURL: URL, target: JumpTarget, sessionId: String?) -> Bool {
        if let uri = codeEditorURI(for: target, workspaceURL: workspaceURL, sessionId: sessionId),
           workspace.open(uri) {
            return true
        }

        if let executable = cliExecutable(for: target),
           runProcess(executable: executable, arguments: ["--reuse-window", workspaceURL.path]) {
            return true
        }

        return openWithApplication(workspaceURL, target: target)
    }

    private func codeEditorURI(for target: JumpTarget, workspaceURL: URL, sessionId: String?) -> URL? {
        if target == .codex {
            return codexThreadURL(sessionId: sessionId)
        }
        guard let descriptor = applicationDescriptors[target],
              let scheme = descriptor.uriScheme else { return nil }

        var components = URLComponents()
        components.scheme = scheme
        components.host = "file"
        components.path = workspaceURL.path
        return components.url
    }

    private func warpURL(for directoryURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "warp"
        components.host = "action"
        components.path = "/new_tab"
        components.queryItems = [URLQueryItem(name: "path", value: directoryURL.path)]
        return components.url
    }

    private func focusInCmuxViaCLI(
        workspaceReference: String?,
        surfaceReference: String?,
        paneReference: String?,
        socketPath: String?
    ) -> Bool {
        guard let executable = cliExecutable(for: .cmux) else { return false }
        let environment = cmuxEnvironment(socketPath: socketPath)

        if let workspaceReference,
           let paneReference,
           runProcessAndWait(
               executable: executable,
               arguments: ["focus-pane", "--workspace", workspaceReference, "--pane", paneReference],
               environment: environment
           ) {
            triggerCmuxFlash(executable: executable, workspaceReference: workspaceReference, surfaceReference: surfaceReference, environment: environment)
            _ = activateApplication(target: .cmux)
            return true
        }

        if let surfaceReference,
           let focusTarget = cmuxFocusTarget(
               surfaceReference: surfaceReference,
               workspaceReference: workspaceReference,
               executable: executable,
               environment: environment
           ),
           runProcessAndWait(
               executable: executable,
               arguments: ["focus-pane", "--workspace", focusTarget.workspaceReference, "--pane", focusTarget.paneReference],
               environment: environment
           ) {
            triggerCmuxFlash(executable: executable, workspaceReference: focusTarget.workspaceReference, surfaceReference: surfaceReference, environment: environment)
            _ = activateApplication(target: .cmux)
            return true
        }

        if let workspaceReference,
           runProcessAndWait(
               executable: executable,
               arguments: ["select-workspace", "--workspace", workspaceReference],
               environment: environment
           ) {
            triggerCmuxFlash(executable: executable, workspaceReference: workspaceReference, surfaceReference: surfaceReference, environment: environment)
            _ = activateApplication(target: .cmux)
            return true
        }

        return false
    }

    private func triggerCmuxFlash(executable: String, workspaceReference: String?, surfaceReference: String?, environment: [String: String]) {
        var arguments = ["trigger-flash"]
        if let workspaceReference {
            arguments.append(contentsOf: ["--workspace", workspaceReference])
        }
        if let surfaceReference {
            arguments.append(contentsOf: ["--surface", surfaceReference])
        }
        _ = runProcessAndWait(executable: executable, arguments: arguments, environment: environment)
    }

    private func cmuxFocusTarget(
        surfaceReference: String,
        workspaceReference: String?,
        executable: String,
        environment: [String: String]
    ) -> (workspaceReference: String, paneReference: String)? {
        guard let snapshot = loadCmuxTreeSnapshot(
            workspaceReference: workspaceReference,
            executable: executable,
            environment: environment
        ) else {
            return nil
        }

        for window in snapshot.windows {
            for workspace in window.workspaces {
                for pane in workspace.panes where pane.surfaceRefs.contains(surfaceReference) || pane.selectedSurfaceRef == surfaceReference {
                    return (workspace.ref, pane.ref)
                }
            }
        }

        return nil
    }

    private func loadCmuxTreeSnapshot(
        workspaceReference: String?,
        executable: String,
        environment: [String: String]
    ) -> CmuxTreeSnapshot? {
        var arguments = ["tree", "--json"]
        if let workspaceReference {
            arguments.append(contentsOf: ["--workspace", workspaceReference])
        } else {
            arguments.insert("--all", at: 1)
        }

        guard let output = captureProcessOutput(executable: executable, arguments: arguments, environment: environment),
              let data = output.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(CmuxTreeSnapshot.self, from: data)
    }

    private func normalizedCmuxReference(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func cmuxEnvironment(socketPath: String?) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        if let socketPath = socketPath?.trimmingCharacters(in: .whitespacesAndNewlines), !socketPath.isEmpty {
            environment["CMUX_SOCKET_PATH"] = socketPath
        }
        return environment
    }

    private func exactNativeTarget(for session: SessionSnapshot) -> JumpTarget? {
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

    private func openNativeTarget(_ target: JumpTarget, sessionId: String, session: SessionSnapshot) -> Bool {
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

    private func openInCodex(sessionId: String?) -> Bool {
        guard let url = codexThreadURL(sessionId: sessionId) else { return false }
        return workspace.open(url)
    }

    private func openInObsidian(sessionId: String?, vaultPath: String?) -> Bool {
        let didActivate = activateApplication(target: .obsidian)

        guard let executable = cliExecutable(for: .obsidian),
              let commandArguments = obsidianEvalArguments(sessionId: sessionId, vaultPath: vaultPath) else {
            return didActivate
        }

        if runProcessAndWait(executable: executable, arguments: commandArguments) {
            _ = activateApplication(target: .obsidian)
            return true
        }

        return didActivate
    }

    private func codexThreadURL(sessionId: String?) -> URL? {
        guard let sessionId else { return nil }
        let trimmed = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
        return URL(string: "codex://threads/\(encoded)")
    }

    private func obsidianEvalArguments(sessionId: String?, vaultPath: String?) -> [String]? {
        guard let escapedSessionId = javaScriptStringLiteral(sessionId),
              let escapedViewType = javaScriptStringLiteral("claudian-view"),
              let escapedPluginId = javaScriptStringLiteral("claudian") else {
            return nil
        }

        let escapedVaultPath = javaScriptStringLiteral(vaultPath)
        let vaultName = obsidianVaultName(for: vaultPath)

        let code = """
        (async () => {
          const plugin = app?.plugins?.plugins?.[\(escapedPluginId)];
          if (!plugin) {
            return 'missing-plugin';
          }

          const sessionId = \(escapedSessionId);
          const expectedVaultPath = \(escapedVaultPath ?? "null");
          const currentVaultPath = app?.vault?.adapter?.basePath ?? null;
          if (expectedVaultPath && currentVaultPath && expectedVaultPath !== currentVaultPath) {
            return 'wrong-vault';
          }

          const conversations = (plugin.getConversationList?.() ?? [])
            .map(meta => plugin.getConversationSync?.(meta.id))
            .filter(Boolean);

          const conversation = conversations.find(conv => {
            const providerSessionId = conv?.providerState?.providerSessionId ?? null;
            return conv?.id === sessionId || conv?.sessionId === sessionId || providerSessionId === sessionId;
          }) ?? null;

          await plugin.activateView?.();

          const leaves = app.workspace.getLeavesOfType(\(escapedViewType));
          if (conversation && leaves.length > 0) {
            const view = leaves[0]?.view;
            await view?.getTabManager?.()?.openConversation?.(conversation.id);
          }

          const notePath = conversation?.currentNote ?? null;
          if (notePath) {
            const file = app.vault.getFileByPath(notePath);
            if (file) {
              const mostRecentLeaf = app.workspace.getMostRecentLeaf?.();
              const noteLeaf = mostRecentLeaf?.view?.getViewType?.() === \(escapedViewType)
                ? app.workspace.getLeaf('tab')
                : (mostRecentLeaf ?? app.workspace.getLeaf('tab'));
              await noteLeaf?.openFile?.(file);
            }
          }

          return notePath ?? (conversation ? 'conversation-opened' : 'view-opened');
        })()
        """

        var arguments: [String] = []
        if let vaultName, !vaultName.isEmpty {
            arguments.append("vault=\(vaultName)")
        }
        arguments.append("eval")
        arguments.append("code=\(code)")
        return arguments
    }

    private func obsidianVaultName(for vaultPath: String?) -> String? {
        guard let vaultPath else { return nil }
        let trimmed = vaultPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed).lastPathComponent
    }

    private func javaScriptStringLiteral(_ value: String?) -> String? {
        guard let value else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
              var encoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        encoded.removeFirst()
        encoded.removeLast()
        return encoded
    }

    private func openWithApplication(_ url: URL, target: JumpTarget) -> Bool {
        guard let descriptor = applicationDescriptors[target],
              let applicationURL = workspace.urlForApplication(withBundleIdentifier: descriptor.bundleIdentifier) else {
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.open([url], withApplicationAt: applicationURL, configuration: configuration) { _, _ in }
        return true
    }

    private func activateApplication(target: JumpTarget) -> Bool {
        guard let descriptor = applicationDescriptors[target],
              let applicationURL = workspace.urlForApplication(withBundleIdentifier: descriptor.bundleIdentifier) else {
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: applicationURL, configuration: configuration) { _, _ in }
        return true
    }

    private func cliExecutable(for target: JumpTarget) -> String? {
        guard let descriptor = applicationDescriptors[target] else { return nil }

        for candidate in descriptor.cliCandidates {
            if candidate.hasPrefix("/") {
                if fileManager.isExecutableFile(atPath: candidate) {
                    return candidate
                }
                continue
            }
            if let resolved = which(candidate) {
                return resolved
            }
        }

        return nil
    }

    private func which(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output?.isEmpty == false ? output : nil
    }

    private func runProcess(executable: String, arguments: [String], environment: [String: String]? = nil) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    private func runProcessAndWait(executable: String, arguments: [String], environment: [String: String]? = nil) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func captureProcessOutput(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private func runAppleScript(_ script: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func scriptForITerm(path: String) -> String {
        """
        set targetPath to "\(escapeAppleScript(path))"
        tell application id "com.googlecode.iterm2"
            activate
            if (count of windows) is 0 then
                set newWindow to (create window with default profile)
                tell current session of current tab of newWindow
                    write text ("cd " & quoted form of targetPath)
                end tell
            else
                tell current session of current window
                    write text ("cd " & quoted form of targetPath)
                    select
                end tell
            end if
        end tell
        """
    }

    private func scriptForTerminal(path: String) -> String {
        """
        set targetPath to "\(escapeAppleScript(path))"
        tell application id "com.apple.Terminal"
            activate
            if (count of windows) is 0 then
                do script ("cd " & quoted form of targetPath)
            else
                set frontTab to selected tab of front window
                if busy of frontTab is false then
                    do script ("cd " & quoted form of targetPath) in frontTab
                else
                    do script ("cd " & quoted form of targetPath)
                end if
            end if
        end tell
        """
    }

    private func escapeAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func bestWorkspaceURL(for path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var currentURL = URL(fileURLWithPath: trimmed, isDirectory: true)
        while true {
            if fileManager.fileExists(atPath: currentURL.path) {
                return currentURL
            }

            let parentURL = currentURL.deletingLastPathComponent()
            if parentURL.path == currentURL.path || parentURL.path.isEmpty {
                return nil
            }
            currentURL = parentURL
        }
    }
}
