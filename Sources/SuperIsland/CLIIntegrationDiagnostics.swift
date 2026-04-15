import AppKit
import Foundation

// CLI integration diagnostics are split from editor bridge diagnostics because they inspect hook files and CLI availability.
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
                "~/.config/opencode/plugins/vibe-island.js",
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

    // Marker matching stays permissive so diagnostics still recognize legacy installs after upgrades.
    var installMarkers: [String] { ["superisland", "vibe-island"] }
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
