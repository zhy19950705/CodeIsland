import AppKit
import Foundation

enum IDEExtensionHost: String, CaseIterable, Identifiable, Sendable {
    case visualStudioCode
    case cursor
    case windsurf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visualStudioCode: return "VS Code"
        case .cursor: return "Cursor"
        case .windsurf: return "Windsurf"
        }
    }

    var extensionRootURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .visualStudioCode:
            return home.appendingPathComponent(".vscode/extensions", isDirectory: true)
        case .cursor:
            return home.appendingPathComponent(".cursor/extensions", isDirectory: true)
        case .windsurf:
            return home.appendingPathComponent(".windsurf/extensions", isDirectory: true)
        }
    }

    var sourceTag: String {
        switch self {
        case .visualStudioCode: return "vscode"
        case .cursor: return "cursor"
        case .windsurf: return "windsurf"
        }
    }
}

struct IDEExtensionInstaller {
    private static let publisher = "codeisland"
    private static let name = "session-bridge"

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? AppVersion.fallback
    }

    static var identifier: String {
        "\(publisher).\(name)"
    }

    static func isInstalled(_ host: IDEExtensionHost) -> Bool {
        let manifestURL = extensionDirectoryURL(for: host).appendingPathComponent("package.json")
        return FileManager.default.fileExists(atPath: manifestURL.path)
    }

    static func install(_ host: IDEExtensionHost) throws {
        let fileManager = FileManager.default
        let rootURL = host.extensionRootURL
        let extensionURL = extensionDirectoryURL(for: host)

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        removeStaleExtensions(in: rootURL)
        try fileManager.createDirectory(at: extensionURL, withIntermediateDirectories: true)
        try Data(packageJSON(for: host).utf8).write(to: extensionURL.appendingPathComponent("package.json"), options: .atomic)
        try Data(extensionJS(for: host).utf8).write(to: extensionURL.appendingPathComponent("extension.js"), options: .atomic)
        try Data(readme(for: host).utf8).write(to: extensionURL.appendingPathComponent("README.md"), options: .atomic)
    }

    static func reinstall(_ host: IDEExtensionHost) throws {
        uninstall(host)
        try install(host)
    }

    static func uninstall(_ host: IDEExtensionHost) {
        try? FileManager.default.removeItem(at: extensionDirectoryURL(for: host))
    }

    private static func extensionDirectoryURL(for host: IDEExtensionHost) -> URL {
        host.extensionRootURL.appendingPathComponent("\(identifier)-\(version)", isDirectory: true)
    }

    private static func removeStaleExtensions(in rootURL: URL) {
        let prefix = "\(identifier)-"
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in items where item.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: item)
        }
    }

    private static func packageJSON(for host: IDEExtensionHost) -> String {
        """
        {
          "name": "\(name)",
          "displayName": "CodeIsland Session Bridge",
          "description": "Open CodeIsland settings and focus the active session for the current workspace.",
          "version": "\(version)",
          "publisher": "\(publisher)",
          "engines": {
            "vscode": "^1.85.0"
          },
          "categories": [
            "Other"
          ],
          "activationEvents": [
            "onStartupFinished"
          ],
          "main": "./extension.js",
          "contributes": {
            "commands": [
              {
                "command": "codeisland.openSettings",
                "title": "CodeIsland: Open Settings"
              },
              {
                "command": "codeisland.focusWorkspaceSession",
                "title": "CodeIsland: Focus Workspace Session"
              }
            ]
          }
        }
        """
    }

    private static func extensionJS(for host: IDEExtensionHost) -> String {
        """
        const vscode = require('vscode');

        function codeIslandURL(path, query) {
          const search = new URLSearchParams(query);
          const suffix = search.toString() ? `?${search.toString()}` : '';
          return vscode.Uri.parse(`codeisland://${path}${suffix}`);
        }

        async function focusWorkspaceSession() {
          const folder = vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders[0];
          if (!folder) {
            vscode.window.showInformationMessage('CodeIsland: no open workspace folder.');
            return;
          }

          await vscode.env.openExternal(codeIslandURL('session', {
            cwd: folder.uri.fsPath,
            source: '\(host.sourceTag)'
          }));
        }

        async function openSettings() {
          await vscode.env.openExternal(codeIslandURL('settings', {}));
        }

        function activate(context) {
          context.subscriptions.push(
            vscode.commands.registerCommand('codeisland.openSettings', openSettings),
            vscode.commands.registerCommand('codeisland.focusWorkspaceSession', focusWorkspaceSession)
          );
        }

        function deactivate() {}

        module.exports = { activate, deactivate };
        """
    }

    private static func readme(for host: IDEExtensionHost) -> String {
        """
        # CodeIsland Session Bridge

        Generated helper extension for \(host.title).

        Commands:
        - `CodeIsland: Open Settings`
        - `CodeIsland: Focus Workspace Session`
        """
    }
}
