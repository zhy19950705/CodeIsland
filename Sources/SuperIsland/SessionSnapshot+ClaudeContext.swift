import Foundation
import SuperIslandCore

// Claude-specific context helpers stay outside the core model so the UI can evolve without touching shared types.
extension SessionSnapshot {
    // Show a compact usage badge only when we have both usage and a usable context window size.
    var claudeContextUsagePercent: Int? {
        guard source == "claude",
              let contextTokens,
              let contextWindowSize,
              contextTokens > 0,
              contextWindowSize > 0 else {
            return nil
        }

        let ratio = min(max(Double(contextTokens) / Double(contextWindowSize), 0), 1)
        return Int((ratio * 100).rounded())
    }

    // Prefer percentage for quick scanning, but fall back to the raw context token count if needed.
    var claudeContextBadgeText: String? {
        if let percent = claudeContextUsagePercent {
            return "ctx \(percent)%"
        }
        guard source == "claude", let contextTokens, contextTokens > 0 else { return nil }
        return "ctx \(abbreviatedTokenCount(contextTokens))"
    }

    // The tooltip-style detail is useful in compact center status when the session is idle.
    var claudeTokenDetailText: String? {
        guard let contextText = claudeContextBadgeText else { return nil }
        guard let outputTokens, outputTokens > 0 else { return contextText }
        return "\(contextText) · out \(abbreviatedTokenCount(outputTokens))"
    }

    // Format large token counts without taking much horizontal space in the notch UI.
    private func abbreviatedTokenCount(_ count: Int) -> String {
        let value = Double(count)
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return "\(count)"
    }
}
