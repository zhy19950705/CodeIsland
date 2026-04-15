import SwiftUI
import SuperIslandCore

// MARK: - Session List

enum SessionListPresentation {
    case notch
    case menuBar
}

struct SessionListContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private enum SessionListRowStyle {
    case fullCard
    case compactRow
}

struct SessionListView: View {
    var appState: AppState
    /// When set, only show this session (auto-expand on completion)
    var onlySessionId: String? = nil
    var presentation: SessionListPresentation = .notch
    @AppStorage(SettingsKey.sessionGroupingMode) private var groupingMode = SettingsDefaults.sessionGroupingMode
    @AppStorage(SettingsKey.maxVisibleSessions) private var maxVisibleSessions = SettingsDefaults.maxVisibleSessions
    @State private var codexInput = ""

    private var activeCodexSessionId: String? {
        guard let sessionId = appState.activeSessionId,
              let session = appState.sessions[sessionId],
              session.source == "codex",
              appState.canContinueActiveCodexSession else { return nil }
        return sessionId
    }

    static func needsScroll(
        totalSessionCount: Int,
        groupHeaderCount: Int,
        hasComposer: Bool,
        maxVisibleSessions: Int,
        onlySessionId: String?,
        presentation: SessionListPresentation = .notch
    ) -> Bool {
        guard onlySessionId == nil else { return false }

        // Menu bar popover has a fixed outer height and its own scroller —
        // always let the list scroll inside it so overflow never gets
        // silently clipped when cards, headers, or the composer combine to
        // exceed the popover's content area.
        if presentation == .menuBar {
            return totalSessionCount > 0
        }

        let estimatedVisibleUnits = Double(totalSessionCount)
            + (Double(groupHeaderCount) * 0.3)
            + (hasComposer ? 0.9 : 0)

        return estimatedVisibleUnits > Double(maxVisibleSessions)
    }

    static func usesCompactRow(
        status: AgentStatus,
        needsCompletionReview: Bool,
        sessionId: String,
        activeSessionId: String?,
        onlySessionId: String?
    ) -> Bool {
        guard onlySessionId == nil else { return false }
        guard !needsCompletionReview else { return false }
        guard sessionId != activeSessionId else { return false }

        switch status {
        case .idle:
            return true
        case .processing, .running, .waitingApproval, .waitingQuestion:
            return false
        }
    }

    var body: some View {
        let snapshot = appState.sessionListPresentation(
            groupingMode: groupingMode,
            onlySessionId: onlySessionId
        )
        let needsScroll = Self.needsScroll(
            totalSessionCount: snapshot.totalSessionCount,
            groupHeaderCount: snapshot.groupHeaderCount,
            hasComposer: activeCodexSessionId != nil,
            maxVisibleSessions: maxVisibleSessions,
            onlySessionId: onlySessionId,
            presentation: presentation
        )
        let notchScrollMaxHeight = CGFloat(maxVisibleSessions) * 90

        Group {
            if presentation == .menuBar {
                ScrollView(.vertical) {
                    sessionRows(lazy: true, groups: snapshot.groups)
                }
                .scrollIndicators(.automatic)
            } else if needsScroll {
                AutoHeightSessionScrollView(maxHeight: notchScrollMaxHeight) {
                    sessionRows(lazy: false, groups: snapshot.groups)
                } scrollContent: {
                    sessionRows(lazy: true, groups: snapshot.groups)
                }
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0, bottomLeadingRadius: 20,
                        bottomTrailingRadius: 20, topTrailingRadius: 0,
                        style: .continuous
                    )
                )
            } else {
                sessionRows(lazy: false, groups: snapshot.groups)
            }
        }
    }

    @ViewBuilder
    private func sessionRows(lazy: Bool, groups: [SessionListGroupPresentation]) -> some View {
        if lazy {
            LazyVStack(spacing: 6) {
                sessionRowSections(groups: groups)
            }
            .padding(.vertical, 4)
        } else {
            VStack(spacing: 6) {
                sessionRowSections(groups: groups)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func sessionRowSections(groups: [SessionListGroupPresentation]) -> some View {
        ForEach(groups) { group in
            if !group.header.isEmpty {
                HStack(spacing: 6) {
                    if let src = group.source, let icon = cliIcon(source: src) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 14, height: 14)
                    }
                    Text(group.header)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 2)
            }

            ForEach(group.ids, id: \.self) { sessionId in
                if let session = appState.sessions[sessionId] {
                    let style = rowStyle(for: sessionId, session: session)
                    let needsCompletionReview = appState.needsCompletionReview(sessionId: sessionId)
                    switch style {
                    case .fullCard:
                        SessionCard(
                            appState: appState,
                            sessionId: sessionId,
                            session: session,
                            isCompletion: onlySessionId != nil || needsCompletionReview,
                            isSelected: sessionId == appState.activeSessionId,
                            needsCompletionReview: needsCompletionReview
                        )
                    case .compactRow:
                        CompactSessionRow(
                            appState: appState,
                            sessionId: sessionId,
                            session: session,
                            isSelected: sessionId == appState.activeSessionId,
                            needsCompletionReview: needsCompletionReview
                        )
                        .equatable()
                    }
                }
            }
        }

        if onlySessionId != nil && appState.sessions.count > 1 {
            SessionsExpandLink(count: appState.sessions.count) {
                withAnimation(NotchAnimation.open) {
                    appState.surface = .sessionList
                    appState.cancelCompletionQueue()
                }
            }
        }

        if let sessionId = activeCodexSessionId,
           let session = appState.sessions[sessionId] {
            CodexComposerBar(
                projectName: session.projectDisplayName,
                text: $codexInput,
                onSubmit: {
                    let value = codexInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { return }
                    appState.sendPromptToSession(sessionId, text: value)
                    codexInput = ""
                }
            )
        }
    }

    private func rowStyle(for sessionId: String, session: SessionSnapshot) -> SessionListRowStyle {
        let needsCompletionReview = appState.needsCompletionReview(sessionId: sessionId)
        if Self.usesCompactRow(
            status: session.status,
            needsCompletionReview: needsCompletionReview,
            sessionId: sessionId,
            activeSessionId: appState.activeSessionId,
            onlySessionId: onlySessionId
        ) {
            return .compactRow
        }
        return .fullCard
    }
}
