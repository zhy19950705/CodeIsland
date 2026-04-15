import SwiftUI
import SuperIslandCore

// AIUsageMonitorSection renders the usage monitor controls and provider cards while the page owns the async actions.
struct AIUsageMonitorSection: View {
    @ObservedObject private var l10n = L10n.shared
    let usageSnapshot: UsageSnapshot
    let usageMonitorSnapshot: UsageMonitorLaunchAgentSnapshot
    let statusMessage: String
    let statusIsError: Bool
    let isTogglingUsageMonitor: Bool
    let isRefreshingUsage: Bool
    let onToggleUsageMonitor: () -> Void
    let onRefreshUsage: () -> Void

    private enum UsageMonitorToolSection: String, CaseIterable, Identifiable {
        case codex
        case claude
        case cursor

        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n["usage_monitor"])
                Text(usageMonitorSnapshot.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    onToggleUsageMonitor()
                } label: {
                    HStack(spacing: 8) {
                        if isTogglingUsageMonitor {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(usageMonitorSnapshot.state == .enabled ? l10n["disable_usage_monitor"] : l10n["enable_usage_monitor"])
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(usageMonitorSnapshot.state == .unavailable || isTogglingUsageMonitor || isRefreshingUsage)

                Button {
                    onRefreshUsage()
                } label: {
                    HStack(spacing: 8) {
                        if isRefreshingUsage {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(l10n["refresh_now"])
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(usageMonitorSnapshot.state == .unavailable || isRefreshingUsage || isTogglingUsageMonitor)
            }

            if !statusMessage.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: statusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(statusIsError ? .red : .green)
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(UsageMonitorToolSection.allCases) { tool in
                usageMonitorToolCard(tool)
            }
        }
    }

    @ViewBuilder
    private func usageMonitorToolCard(_ tool: UsageMonitorToolSection) -> some View {
        let provider = provider(for: tool)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(toolTitle(tool))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let provider, let updatedAtUnix = provider.updatedAtUnix {
                    Text(RelativeDateTimeFormatter().localizedString(for: Date(timeIntervalSince1970: updatedAtUnix), relativeTo: Date()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let provider {
                UsageProviderRow(provider: provider, showHeader: false)
            } else {
                Text(toolEmptyMessage(tool))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func provider(for tool: UsageMonitorToolSection) -> UsageProviderSnapshot? {
        let source: UsageProviderSource
        switch tool {
        case .codex:
            source = .codex
        case .claude:
            source = .claude
        case .cursor:
            source = .cursor
        }
        return usageSnapshot.providers.first(where: { $0.source == source })
    }

    private func toolTitle(_ tool: UsageMonitorToolSection) -> String {
        switch tool {
        case .codex:
            "Codex"
        case .claude:
            "Claude"
        case .cursor:
            "Cursor"
        }
    }

    private func toolEmptyMessage(_ tool: UsageMonitorToolSection) -> String {
        switch tool {
        case .codex, .claude:
            l10n["usage_snapshot_empty"]
        case .cursor:
            l10n["usage_cursor_unavailable"]
        }
    }
}
