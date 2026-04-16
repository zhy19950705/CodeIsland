import SwiftUI
import AppKit
import SuperIslandCore

/// Dedicated session detail surface keeps the list layout stable while still exposing full conversation history.
struct SessionDetailView: View {
    var appState: AppState
    let sessionId: String
    let session: SessionSnapshot

    @State private var codexInput = ""
    @State private var isHeaderHovered = false
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(spacing: 0) {
            detailHeader

            SessionConversationView(
                sessionId: sessionId,
                session: session,
                style: .detail
            )
            .frame(maxWidth: .infinity, alignment: .top)

            detailFooter
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var isCompletionPresentation: Bool {
        appState.surface == .completionCard(sessionId: sessionId)
    }

    /// Header mirrors MioIsland's dedicated chat surface: back to the list, keep session identity visible.
    private var detailHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                detailBackButton

                SessionJumpButton(session: session) {
                    appState.jumpToSession(sessionId)
                }
            }

            detailStatusBar
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color.white.opacity(0.03))
    }

    /// Match MioIsland's broader back affordance so users can click the header strip, not just the text itself.
    private var detailBackButton: some View {
        Button {
            if isCompletionPresentation {
                // Completion detail acts like a transient notification surface, so
                // "back" should advance the queue instead of dumping the user into the list.
                appState.showNextCompletionOrCollapse()
            } else {
                // Route the back tap through the coordinator's staged navigation entry
                // so the list/detail swap does not fight the current click layout pass.
                appState.panelCoordinator.handleDetailBackTap()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(isHeaderHovered ? 0.94 : 0.82))

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.projectDisplayName)
                        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(isHeaderHovered ? 0.98 : 0.9))
                        .lineLimit(1)
                    Text(session.displayTitle(sessionId: session.displaySessionId(sessionId: sessionId)))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(isHeaderHovered ? 0.6 : 0.48))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHeaderHovered ? Color.white.opacity(0.08) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(NotchAnimation.micro) {
                isHeaderHovered = hovering
            }
        }
    }

    /// Compact status chips make the dedicated detail surface easier to parse without reopening the list.
    private var detailStatusBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                DetailStatusChip(statusLabel, tint: statusColor)
                DetailStatusChip(session.sourceLabel, tint: .white.opacity(0.6))

                if let terminalName = session.terminalName {
                    DetailStatusChip(terminalName, tint: Color(red: 0.3, green: 0.85, blue: 0.4))
                }

                if let model = session.shortModelName {
                    DetailStatusChip(model, tint: Color(red: 0.4, green: 0.7, blue: 1.0))
                }

                DetailStatusChip(timeAgoText(session.lastActivity), tint: .white.opacity(0.45))

                if hasPendingApproval {
                    Button(l10n["session_detail_review_approval"]) {
                        // Route detail-surface card promotions through the panel coordinator so UI policy stays centralized.
                        appState.panelCoordinator.presentBlockingCard(.approvalCard(sessionId: sessionId))
                    }
                    .buttonStyle(.plain)
                    .modifier(DetailActionChipModifier(tint: .orange.opacity(0.9)))
                }

                if hasPendingQuestion {
                    Button(l10n["session_detail_answer_question"]) {
                        // Route detail-surface card promotions through the panel coordinator so UI policy stays centralized.
                        appState.panelCoordinator.presentBlockingCard(.questionCard(sessionId: sessionId))
                    }
                    .buttonStyle(.plain)
                    .modifier(DetailActionChipModifier(tint: Color(red: 0.4, green: 0.7, blue: 1.0)))
                }
            }
        }
    }

    @ViewBuilder
    private var detailFooter: some View {
        VStack(spacing: 0) {
            detailActionBar

            // Codex keeps the lightweight inline composer so the dedicated detail view remains actionable.
            if session.source == "codex", appState.canContinueActiveCodexSession {
                CodexComposerBar(
                    projectName: session.projectDisplayName,
                    text: $codexInput,
                    onSubmit: submitCodexPrompt
                )
            }
        }
    }

    /// Bottom actions keep the primary terminal jump obvious while still exposing any pending blocking interaction.
    private var detailActionBar: some View {
        let editorTarget = appState.resolvedSessionEditorTarget(sessionId)
        let editorAppIcon = resolvedEditorActionIcon(for: editorTarget)

        return HStack(spacing: 10) {
            detailPrimaryActionButton(
                title: l10n["session_detail_go_to_terminal"],
                systemImage: "terminal"
            ) {
                appState.jumpToSession(sessionId)
            }

            if let editorTarget {
                detailPrimaryActionButton(
                    title: editorActionTitle(for: editorTarget),
                    systemImage: editorActionSystemImage(for: editorTarget),
                    appIcon: editorAppIcon
                ) {
                    appState.openSessionEditor(sessionId)
                }
            }

            if hasPendingApproval {
                Button(l10n["session_detail_approval_short"]) {
                    // Route detail-surface card promotions through the panel coordinator so UI policy stays centralized.
                    appState.panelCoordinator.presentBlockingCard(.approvalCard(sessionId: sessionId))
                }
                .buttonStyle(.plain)
                .modifier(DetailActionChipModifier(tint: .orange.opacity(0.9)))
            } else if hasPendingQuestion {
                Button(l10n["session_detail_question_short"]) {
                    // Route detail-surface card promotions through the panel coordinator so UI policy stays centralized.
                    appState.panelCoordinator.presentBlockingCard(.questionCard(sessionId: sessionId))
                }
                .buttonStyle(.plain)
                .modifier(DetailActionChipModifier(tint: Color(red: 0.4, green: 0.7, blue: 1.0)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.04))
    }

    /// Share the same footer button chrome so terminal and editor actions feel like a single action group.
    private func detailPrimaryActionButton(
        title: String,
        systemImage: String,
        appIcon: NSImage? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 13, height: 13)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var hasPendingApproval: Bool {
        appState.pendingPermission?.event.sessionId == sessionId
    }

    private var hasPendingQuestion: Bool {
        appState.pendingQuestion?.event.sessionId == sessionId
    }

    // Footer copy is derived from the already-resolved target so SwiftUI does not repeat any availability work.
    private func editorActionTitle(for target: WorkspaceJumpManager.JumpTarget) -> String {
        if target == .finder {
            return l10n["open_folder"]
        }
        return String(format: l10n["session_detail_open_in_format"], target.title)
    }

    // Finder keeps the familiar folder glyph while real editors preserve the code-oriented affordance.
    private func editorActionSystemImage(for target: WorkspaceJumpManager.JumpTarget) -> String {
        if target == .finder {
            return "folder"
        }
        return "chevron.left.forwardslash.chevron.right"
    }

    // App icons are only shown for concrete applications; Finder already reads clearly from the folder glyph.
    private func resolvedEditorActionIcon(for target: WorkspaceJumpManager.JumpTarget?) -> NSImage? {
        guard let target,
              target != .finder else {
            return nil
        }
        return appState.resolvedSessionEditorIcon(target)
    }

    private var statusLabel: String {
        switch session.status {
        case .idle:
            return session.interrupted ? l10n["session_detail_status_interrupted"] : l10n["status_idle"]
        case .processing:
            return l10n["status_processing"]
        case .running:
            return l10n["status_running"]
        case .waitingApproval:
            return l10n["session_detail_status_waiting_approval"]
        case .waitingQuestion:
            return l10n["session_detail_status_waiting_question"]
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .idle:
            return session.interrupted ? .orange.opacity(0.86) : .white.opacity(0.5)
        case .processing, .running:
            return Color(red: 0.3, green: 0.85, blue: 0.4)
        case .waitingApproval:
            return .orange.opacity(0.9)
        case .waitingQuestion:
            return Color(red: 0.4, green: 0.7, blue: 1.0)
        }
    }

    private func submitCodexPrompt() {
        let value = codexInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        appState.sendPromptToSession(sessionId, text: value)
        codexInput = ""
    }
}

private struct DetailStatusChip: View {
    let text: String
    let tint: Color

    init(_ text: String, tint: Color) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }
}

private struct DetailActionChipModifier: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        content
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(tint.opacity(0.18), lineWidth: 1)
                    )
            )
    }
}
