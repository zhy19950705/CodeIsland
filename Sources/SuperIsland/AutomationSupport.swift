import Foundation
import Darwin
import CommonCrypto
import SuperIslandCore

/// Small CLI surface embedded in the main app binary so Codex hooks can call
/// `SuperIsland` directly instead of depending on a separate helper executable.
enum AutomationCLI {
    static func runIfNeeded(arguments: [String] = CommandLine.arguments) -> Int32? {
        let commandArguments = Array(arguments.dropFirst())
        guard let command = commandArguments.first else { return nil }

        switch command {
        case "--install-codex-hooks":
            return ConfigInstaller.setEnabled(source: "codex", enabled: true) ? 0 : 1
        case "--bridge-codex-hook":
            return CodexHookBridgeCommand(arguments: Array(commandArguments.dropFirst())).run()
        case "--monitor-usage":
            return UsageMonitorCommand(arguments: Array(commandArguments.dropFirst())).run()
        case "--codex-auth":
            return CodexAccountCLICommand(arguments: Array(commandArguments.dropFirst())).run()
        default:
            return nil
        }
    }

    static func executableURL() -> URL? {
        if let executableURL = Bundle.main.executableURL {
            return executableURL.standardizedFileURL
        }

        guard let firstArgument = CommandLine.arguments.first, !firstArgument.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: firstArgument).standardizedFileURL
    }
}
