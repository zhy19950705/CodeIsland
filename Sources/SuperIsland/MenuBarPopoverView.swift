import SwiftUI

struct MenuBarPopoverView: View {
    enum Mode: Equatable {
        case contextual
        case sessionListOnly
    }

    var appState: AppState
    var mode: Mode = .contextual

    private var visibleSurface: IslandSurface {
        if mode == .sessionListOnly {
            return .sessionList
        }

        if let pendingPermission = appState.pendingPermission,
           let sessionId = pendingPermission.event.sessionId {
            return .approvalCard(sessionId: sessionId)
        }

        if let pendingQuestion = appState.pendingQuestion,
           let sessionId = pendingQuestion.event.sessionId {
            return .questionCard(sessionId: sessionId)
        }

        switch appState.surface {
        case .collapsed:
            return .sessionList
        default:
            return appState.surface
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .overlay(Color.white.opacity(0.08))
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 430, height: 560)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if let icon = cliIcon(source: headerSource, size: 16) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "menubar.rectangle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }

                Text("SuperIsland")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    SettingsWindowController.shared.show()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .center, spacing: 8) {
                Text(headerSubtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                if !usageProviders.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(usageProviders) { provider in
                            MenuBarUsageBadge(provider: provider)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.02))
    }

    private var usageProviders: [UsageProviderSnapshot] {
        guard let source = UsageProviderSource(rawValue: headerSource) else { return [] }
        return appState.usageSnapshot.providers.filter { $0.source == source }
    }

    @ViewBuilder
    private var content: some View {
        switch visibleSurface {
        case .approvalCard:
            if let pendingPermission = appState.pendingPermission {
                ApprovalBar(
                    tool: pendingPermission.event.toolName ?? "Unknown",
                    toolInput: pendingPermission.event.toolInput,
                    queuePosition: 1,
                    queueTotal: appState.permissionQueue.count,
                    onAllow: { appState.approvePermission(always: false) },
                    onAlwaysAllow: { appState.approvePermission(always: true) },
                    onDeny: { appState.denyPermission() }
                )
                .padding(.top, 12)
            } else {
                fallbackSessionList
            }

        case .questionCard(let sessionId):
            if let pendingQuestion = appState.pendingQuestion {
                QuestionBar(
                    question: pendingQuestion.question.question,
                    options: pendingQuestion.question.options,
                    descriptions: pendingQuestion.question.descriptions,
                    sessionSource: appState.sessions[sessionId]?.source,
                    sessionContext: appState.sessions[sessionId]?.cwd,
                    queuePosition: 1,
                    queueTotal: appState.questionQueue.count,
                    onAnswer: { appState.answerQuestion($0) },
                    onSkip: { appState.skipQuestion() }
                )
                .padding(.top, 12)
            } else {
                fallbackSessionList
            }

        case .completionCard:
            SessionListView(
                appState: appState,
                onlySessionId: appState.justCompletedSessionId,
                presentation: .menuBar
            )

        case .collapsed, .sessionList:
            fallbackSessionList
        }
    }

    private var fallbackSessionList: some View {
        SessionListView(appState: appState, onlySessionId: nil, presentation: .menuBar)
    }

    private var headerSubtitle: String {
        let sessionCount = appState.sessions.count
        if let activeSessionId = appState.activeSessionId,
           let session = appState.sessions[activeSessionId] {
            return "\(session.sourceLabel) · \(session.projectDisplayName) · \(sessionCount) \(L10n.shared["n_sessions"])"
        }
        return "\(sessionCount) \(L10n.shared["n_sessions"])"
    }

    private var headerSource: String {
        if let activeSessionId = appState.activeSessionId,
           let session = appState.sessions[activeSessionId] {
            return session.source
        }
        return appState.primarySource
    }
}

private struct MenuBarUsageBadge: View {
    let provider: UsageProviderSnapshot

    var body: some View {
        HStack(spacing: 6) {
            MenuBarUsageWindowBadge(
                title: provider.primary.label,
                remainingPercentage: provider.remainingPercentage(for: provider.primary),
                tintHex: provider.primary.tintHex
            )
            MenuBarUsageWindowBadge(
                title: provider.secondary.label,
                remainingPercentage: provider.remainingPercentage(for: provider.secondary),
                tintHex: provider.secondary.tintHex
            )
        }
        .help(helpText)
    }

    private var helpText: String {
        var lines = [
            line(for: provider.primary),
            line(for: provider.secondary),
        ]
        if let summary = provider.summary, !summary.isEmpty {
            lines.append(summary)
        }
        return lines.joined(separator: "\n")
    }

    private func line(for window: UsageWindowStat) -> String {
        "\(provider.source.title) \(window.label) \(L10n.shared["usage_remaining"]): \(provider.remainingPercentage(for: window))% · \(window.detail)"
    }
}

private struct MenuBarUsageWindowBadge: View {
    let title: String
    let remainingPercentage: Int
    let tintHex: String

    private var tint: Color { menuBarColor(hex: tintHex) }

    var body: some View {
        HStack(spacing: 3) {
            Text(title.uppercased())
                .foregroundStyle(.white.opacity(0.55))
            Text(L10n.shared["usage_remaining"].uppercased())
                .foregroundStyle(.white.opacity(0.75))
            Text("\(remainingPercentage)%")
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
    }
}

private func menuBarColor(hex: String) -> Color {
    let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: cleaned).scanHexInt64(&int)

    let r, g, b: UInt64
    switch cleaned.count {
    case 3:
        (r, g, b) = ((int >> 8) * 17, ((int >> 4) & 0xF) * 17, (int & 0xF) * 17)
    case 6:
        (r, g, b) = (int >> 16, (int >> 8) & 0xFF, int & 0xFF)
    default:
        (r, g, b) = (255, 255, 255)
    }

    return Color(
        red: Double(r) / 255.0,
        green: Double(g) / 255.0,
        blue: Double(b) / 255.0
    )
}
