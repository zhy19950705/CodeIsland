import SwiftUI
import SuperIslandCore

struct CompactRightWing: View {
    var appState: AppState
    let expanded: Bool
    let hasNotch: Bool
    @AppStorage(SettingsKey.showToolStatus) private var showToolStatus = SettingsDefaults.showToolStatus

    private var displaySessionId: String? {
        appState.rotatingSessionId ?? appState.activeSessionId ?? appState.sessions.keys.sorted().first
    }
    private var displaySource: String {
        guard let sid = displaySessionId else { return appState.primarySource }
        return appState.sessions[sid]?.source ?? appState.primarySource
    }
    private var displaySession: SessionSnapshot? {
        guard let sid = displaySessionId else { return nil }
        return appState.sessions[sid]
    }
    private var usageProvider: UsageProviderSnapshot? {
        NotchPanelView.compactUsageProvider(
            from: appState.usageSnapshot,
            sessions: appState.sessions,
            rotatingSessionId: appState.rotatingSessionId,
            activeSessionId: appState.activeSessionId,
            primarySource: displaySource
        )
    }
    // Prefer Claude's live transcript context badge over the quota badge when a Claude session is frontmost.
    private var claudeContextLabel: String? {
        guard displaySource == "claude" else { return nil }
        return displaySession?.claudeContextBadgeText
    }

    var body: some View {
        HStack(spacing: 6) {
            if expanded {
                // Reuse the shared notch controls so every surface keeps the same spacing and hover behavior.
                NotchControlButtonGroup(showsSoundToggle: true, trailingAction: .quitApp)
            } else {
                if appState.status == .waitingApproval || appState.status == .waitingQuestion {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.7, blue: 0.28))
                        .symbolEffect(.pulse, options: .repeating)
                }

                if let claudeContextLabel, let displaySession {
                    CompactClaudeContextBadge(session: displaySession, label: claudeContextLabel)
                } else if let usageProvider {
                    CompactUsageBadge(provider: usageProvider)
                }

                HStack(spacing: 1) {
                    let active = appState.activeSessionCount
                    let total = appState.totalSessionCount
                    if active > 0 {
                        Text("\(active)")
                            .foregroundStyle(Color(red: 0.4, green: 1.0, blue: 0.5))
                        Text("/")
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Text("\(total)")
                        .foregroundStyle(.white.opacity(0.9))
                }
                .font(.system(size: showToolStatus ? 12 : 13, weight: showToolStatus ? .semibold : .bold, design: .monospaced))
            }
        }
        .padding(.trailing, 6)
    }
}

struct CompactUsageBadge: View {
    @ObservedObject private var l10n = L10n.shared
    let provider: UsageProviderSnapshot

    private var primary: UsageWindowStat { provider.primary }
    private var tint: Color { Color(hex: primary.tintHex) }
    private var label: String { provider.source.displaysUsedPercentage ? l10n["usage_used"] : l10n["usage_remaining"] }
    private var displayedPercentage: Int {
        provider.source.displaysUsedPercentage
            ? provider.usedPercentage(for: primary)
            : provider.remainingPercentage(for: primary)
    }
    private var helpText: String {
        let usedPercentage = provider.usedPercentage(for: primary)
        let remainingPercentage = provider.remainingPercentage(for: primary)
        let headline = "\(provider.source.title) \(primary.label) \(l10n["usage_used"]): \(usedPercentage)% · \(l10n["usage_remaining"]): \(remainingPercentage)%"
        var lines = [headline, primary.detail]
        if let summary = provider.summary, !summary.isEmpty {
            lines.append(summary)
        }
        if let monthly = provider.monthly {
            var monthlyLine = "\(l10n["usage_recent_30_days"]) \(monthly.label): \(compactTokenSummary(monthly.totalTokens))"
            if let costUSD = monthly.costUSD {
                monthlyLine += " · \(String(format: "$%.2f", costUSD))"
            }
            lines.append(monthlyLine)
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        HStack(spacing: 3) {
            Text(primary.label.uppercased())
                .foregroundStyle(.white.opacity(0.55))
            Text(label.uppercased())
                .foregroundStyle(.white.opacity(0.75))
            Text("\(displayedPercentage)%")
                .foregroundStyle(tint)
        }
        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(.white.opacity(0.08))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
        .help(helpText)
    }

    private func compactTokenSummary(_ totalTokens: Int) -> String {
        if totalTokens >= 1_000_000 {
            return String(format: "%.1fM", Double(totalTokens) / 1_000_000)
        }
        if totalTokens >= 1_000 {
            return String(format: "%.1fK", Double(totalTokens) / 1_000)
        }
        return "\(totalTokens)"
    }
}

// Keep the Claude realtime badge visually aligned with the existing quota badge so provider-specific status lands in one place.
struct CompactClaudeContextBadge: View {
    let session: SessionSnapshot
    let label: String

    private var tint: Color {
        guard let percent = session.claudeContextUsagePercent else {
            return .white.opacity(0.72)
        }
        if percent >= 85 {
            return Color(red: 1.0, green: 0.45, blue: 0.35)
        }
        if percent >= 65 {
            return Color(red: 1.0, green: 0.7, blue: 0.2)
        }
        return Color(red: 0.3, green: 0.85, blue: 0.4)
    }
    private var helpText: String {
        var lines = ["Claude live context: \(label)"]
        if let detail = session.claudeTokenDetailText, detail != label {
            lines.append(detail)
        }
        if let transcriptPath = session.claudeTranscriptPath, !transcriptPath.isEmpty {
            lines.append(transcriptPath)
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        HStack(spacing: 3) {
            Text("CLAUDE")
                .foregroundStyle(.white.opacity(0.55))
            Text(label.uppercased())
                .foregroundStyle(tint)
        }
        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(.white.opacity(0.08))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
        .help(helpText)
    }
}

// MARK: - Tool Status Helpers
