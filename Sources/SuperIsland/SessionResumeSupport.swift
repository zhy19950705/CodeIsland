import Foundation
import SuperIslandCore

// Resume command generation stays source-aware so stale session recovery does not leak CLI-specific syntax into views.
enum SessionResumeSupport {
    // Generate a shell-safe command that can be executed directly in a terminal tab.
    static func resumeCommand(for session: SessionSnapshot, sessionId: String) -> String? {
        let resolvedSessionId = nonEmpty(session.providerSessionId) ?? nonEmpty(sessionId)
        guard let resolvedSessionId else { return nil }

        let command: String
        switch session.source {
        case "codex":
            command = "codex resume \(shellQuoted(resolvedSessionId))"
        case "claude":
            command = "claude --resume \(shellQuoted(resolvedSessionId))"
        default:
            return nil
        }

        guard let cwd = nonEmpty(session.cwd) else { return command }
        return "cd \(shellQuoted(cwd)) && \(command)"
    }

    // Codex app-server returns human-readable errors, so matching well-known missing-thread phrases is the most stable fallback.
    static func isMissingCodexThreadError(_ error: Error) -> Bool {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !message.isEmpty else { return false }

        let missingSignals = [
            "not found",
            "no thread",
            "unknown thread",
            "missing thread",
            "archived",
        ]
        return missingSignals.contains(where: { message.contains($0) })
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // Single-quote escaping works across the default zsh/bash shells targeted by the app.
    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
