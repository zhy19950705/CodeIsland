import AppKit
import Foundation

enum EditorBridgeHost: String, CaseIterable, Identifiable, Sendable {
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

    var systemName: String {
        switch self {
        case .visualStudioCode: return "square.and.pencil"
        case .cursor: return "cursorarrow.rays"
        case .windsurf: return "wind"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .visualStudioCode: return "com.microsoft.VSCode"
        case .cursor: return "com.todesktop.230313mzl4w4u92"
        case .windsurf: return "com.exafunction.windsurf"
        }
    }

    var extensionHost: IDEExtensionHost {
        switch self {
        case .visualStudioCode: return .visualStudioCode
        case .cursor: return .cursor
        case .windsurf: return .windsurf
        }
    }
}

enum EditorBridgeState: Sendable {
    case live
    case installed
    case unavailable

    var titleKey: String {
        switch self {
        case .live: return "editor_bridge_live"
        case .installed: return "editor_bridge_installed"
        case .unavailable: return "editor_bridge_unavailable"
        }
    }

    var detailKey: String {
        switch self {
        case .live: return "editor_bridge_live_detail"
        case .installed: return "editor_bridge_installed_detail"
        case .unavailable: return "editor_bridge_unavailable_detail"
        }
    }
}

struct EditorBridgeSnapshot: Identifiable, Sendable {
    var id: EditorBridgeHost { host }
    var host: EditorBridgeHost
    var state: EditorBridgeState
    var installPath: String?
    var extensionInstalled: Bool
}

final class EditorBridgeManager {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func snapshots() -> [EditorBridgeSnapshot] {
        EditorBridgeHost.allCases.map { host in
            let appURL = workspace.urlForApplication(withBundleIdentifier: host.bundleIdentifier)
            let isRunning = workspace.runningApplications.contains { application in
                application.bundleIdentifier == host.bundleIdentifier && !application.isTerminated
            }

            let state: EditorBridgeState
            if isRunning {
                state = .live
            } else if appURL != nil {
                state = .installed
            } else {
                state = .unavailable
            }

            return EditorBridgeSnapshot(
                host: host,
                state: state,
                installPath: appURL?.path,
                extensionInstalled: IDEExtensionInstaller.isInstalled(host.extensionHost)
            )
        }
    }

    func openInstallLocation(for host: EditorBridgeHost) {
        guard let appURL = workspace.urlForApplication(withBundleIdentifier: host.bundleIdentifier) else { return }
        workspace.open(appURL)
    }
}

enum CLIIntegrationID: String, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case gemini
    case cursor
    case qoder
    case droid
    case codebuddy
    case copilot
    case opencode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .gemini: return "Gemini CLI"
        case .cursor: return "Cursor Agent"
        case .qoder: return "Qoder"
        case .droid: return "Factory"
        case .codebuddy: return "CodeBuddy"
        case .copilot: return "Copilot CLI"
        case .opencode: return "OpenCode"
        }
    }

    var configPaths: [String] {
        switch self {
        case .opencode:
            return [
                "~/.config/opencode/plugins/superisland.js",
                "~/.config/opencode/plugins/codeisland.js",
                "~/.config/opencode/config.json",
            ]
        default:
            guard let cli = ConfigInstaller.allCLIs.first(where: { $0.source == rawValue }) else { return [] }
            return ["~/\(cli.configPath)"]
        }
    }

    var binaryCandidates: [String] {
        switch self {
        case .claude:
            return ["claude"]
        case .codex:
            return ["codex", "/Applications/Codex.app/Contents/Resources/codex"]
        case .gemini:
            return ["gemini"]
        case .cursor:
            return ["cursor", "/Applications/Cursor.app"]
        case .qoder:
            return ["qoder", "/Applications/Qoder.app"]
        case .droid:
            return ["droid", "/Applications/Factory.app"]
        case .codebuddy:
            return ["codebuddy", "/Applications/CodeBuddy.app"]
        case .copilot:
            return ["github-copilot", "copilot"]
        case .opencode:
            return ["opencode"]
        }
    }

    var installMarkers: [String] { ["superisland", "codeisland"] }
}

enum CLIIntegrationState: Sendable {
    case active
    case installed
    case notInstalled
    case cliNotFound
    case disabled

    var titleKey: String {
        switch self {
        case .active: return "cli_state_active"
        case .installed: return "cli_state_installed"
        case .notInstalled: return "cli_state_not_installed"
        case .cliNotFound: return "cli_state_cli_missing"
        case .disabled: return "cli_state_disabled"
        }
    }
}

struct CLIIntegrationSnapshot: Identifiable, Sendable {
    var id: CLIIntegrationID { integration }
    var integration: CLIIntegrationID
    var state: CLIIntegrationState
    var detail: String
    var configPath: String?
}

final class CLIIntegrationManager {
    private let fileManager: FileManager
    private let workspace: NSWorkspace

    init(fileManager: FileManager = .default, workspace: NSWorkspace = .shared) {
        self.fileManager = fileManager
        self.workspace = workspace
    }

    func snapshots() -> [CLIIntegrationSnapshot] {
        CLIIntegrationID.allCases.map(snapshot(for:))
    }

    func snapshot(for integration: CLIIntegrationID) -> CLIIntegrationSnapshot {
        let existingConfigPath = integration.configPaths
            .map(expandHome)
            .first(where: { fileManager.fileExists(atPath: $0) })

        let hasMarker = existingConfigPath.flatMap(readText).map { text in
            integration.installMarkers.contains { text.localizedCaseInsensitiveContains($0) }
        } ?? false

        let cliDetected = isCLIAvailable(for: integration)
        let enabled = ConfigInstaller.isEnabled(source: integration.rawValue)

        let state: CLIIntegrationState
        if !enabled {
            state = .disabled
        } else if hasMarker && cliDetected {
            state = .active
        } else if hasMarker {
            state = .installed
        } else if cliDetected {
            state = .notInstalled
        } else {
            state = .cliNotFound
        }

        let detail = existingConfigPath
            ?? integration.configPaths.map(expandHome).first
            ?? resolvedBinaryCandidate(for: integration)
            ?? integration.title

        return CLIIntegrationSnapshot(
            integration: integration,
            state: state,
            detail: detail,
            configPath: existingConfigPath
        )
    }

    func openConfig(for integration: CLIIntegrationID) {
        guard let path = integration.configPaths
            .map(expandHome)
            .first(where: { fileManager.fileExists(atPath: $0) }) else { return }

        workspace.open(URL(fileURLWithPath: path))
    }

    private func isCLIAvailable(for integration: CLIIntegrationID) -> Bool {
        resolvedBinaryCandidate(for: integration) != nil
    }

    private func resolvedBinaryCandidate(for integration: CLIIntegrationID) -> String? {
        for candidate in integration.binaryCandidates {
            if candidate.hasPrefix("/") {
                if fileManager.fileExists(atPath: candidate) {
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

    private func readText(at path: String) -> String? {
        try? String(contentsOfFile: path, encoding: .utf8)
    }

    private func expandHome(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }
}
