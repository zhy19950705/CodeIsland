import SwiftUI
import AppKit
import SuperIslandCore

struct CompactRightWing: View {
    var appState: AppState
    let expanded: Bool
    let hasNotch: Bool
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.soundEnabled) private var soundEnabled = SettingsDefaults.soundEnabled
    @AppStorage(SettingsKey.showToolStatus) private var showToolStatus = SettingsDefaults.showToolStatus

    private var displaySessionId: String? {
        appState.rotatingSessionId ?? appState.activeSessionId ?? appState.sessions.keys.sorted().first
    }
    private var displaySource: String {
        guard let sid = displaySessionId else { return appState.primarySource }
        return appState.sessions[sid]?.source ?? appState.primarySource
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

    var body: some View {
        HStack(spacing: 6) {
            if expanded {
                NotchIconButton(icon: soundEnabled ? "speaker.wave.2" : "speaker.slash", tooltip: soundEnabled ? l10n["mute"] : l10n["enable_sound_tooltip"]) {
                    soundEnabled.toggle()
                }
                NotchIconButton(icon: "gearshape", tooltip: l10n["settings"]) {
                    SettingsWindowController.shared.show()
                }
                NotchIconButton(icon: "power", tint: Color(red: 1.0, green: 0.4, blue: 0.4), tooltip: l10n["quit"]) {
                    NSApplication.shared.terminate(nil)
                }
            } else {
                if appState.status == .waitingApproval || appState.status == .waitingQuestion {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.7, blue: 0.28))
                        .symbolEffect(.pulse, options: .repeating)
                }

                if let usageProvider {
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

// MARK: - Tool Status Helpers
