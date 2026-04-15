import AppKit
import Foundation

// Generic launch helpers live separately so workspace routing decisions stay small and easy to audit.
extension WorkspaceJumpManager {
    func openInWarp(_ url: URL) -> Bool {
        if let warpURL = warpURL(for: url), workspace.open(warpURL) {
            return true
        }
        return openWithApplication(url, target: .warp)
    }

    func openInITerm(_ url: URL) -> Bool {
        runAppleScript(scriptForITerm(path: url.path)) || openWithApplication(url, target: .iTerm)
    }

    func openInTerminal(_ url: URL) -> Bool {
        runAppleScript(scriptForTerminal(path: url.path)) || openWithApplication(url, target: .terminal)
    }

    func openInCodeCompatibleEditor(_ workspaceURL: URL, target: JumpTarget, sessionId: String?) -> Bool {
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

    func codeEditorURI(for target: JumpTarget, workspaceURL: URL, sessionId: String?) -> URL? {
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

    func warpURL(for directoryURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "warp"
        components.host = "action"
        components.path = "/new_tab"
        components.queryItems = [URLQueryItem(name: "path", value: directoryURL.path)]
        return components.url
    }

    func openInCodex(sessionId: String?) -> Bool {
        guard let url = codexThreadURL(sessionId: sessionId) else { return false }
        return workspace.open(url)
    }

    func openInObsidian(sessionId: String?, vaultPath: String?) -> Bool {
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

    func codexThreadURL(sessionId: String?) -> URL? {
        guard let sessionId else { return nil }
        let trimmed = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
        return URL(string: "codex://threads/\(encoded)")
    }

    // Obsidian automation uses `obsidian eval`, so JSON string escaping keeps session ids and paths script-safe.
    func obsidianEvalArguments(sessionId: String?, vaultPath: String?) -> [String]? {
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

    func obsidianVaultName(for vaultPath: String?) -> String? {
        guard let vaultPath else { return nil }
        let trimmed = vaultPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed).lastPathComponent
    }

    func javaScriptStringLiteral(_ value: String?) -> String? {
        guard let value else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
              var encoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        encoded.removeFirst()
        encoded.removeLast()
        return encoded
    }

    func openWithApplication(_ url: URL, target: JumpTarget) -> Bool {
        guard let descriptor = applicationDescriptors[target],
              let applicationURL = workspace.urlForApplication(withBundleIdentifier: descriptor.bundleIdentifier) else {
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.open([url], withApplicationAt: applicationURL, configuration: configuration) { _, _ in }
        return true
    }

    func activateApplication(target: JumpTarget) -> Bool {
        guard let descriptor = applicationDescriptors[target],
              let applicationURL = workspace.urlForApplication(withBundleIdentifier: descriptor.bundleIdentifier) else {
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: applicationURL, configuration: configuration) { _, _ in }
        return true
    }

    // CLI resolution prefers explicit bundled executables before falling back to PATH for better compatibility.
    func cliExecutable(for target: JumpTarget) -> String? {
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

    func which(_ name: String) -> String? {
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

    func runProcess(executable: String, arguments: [String], environment: [String: String]? = nil) -> Bool {
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

    func runProcessAndWait(executable: String, arguments: [String], environment: [String: String]? = nil) -> Bool {
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

    func captureProcessOutput(
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

    func runAppleScript(_ script: String) -> Bool {
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

    func scriptForITerm(path: String) -> String {
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

    func scriptForTerminal(path: String) -> String {
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

    func escapeAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // Walk upward until an existing directory is found so deleted nested paths still jump to a valid workspace root.
    func bestWorkspaceURL(for path: String) -> URL? {
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
