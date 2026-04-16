import AppKit
import SwiftUI
import SuperIslandCore

/// Detail timelines use a chat-style layout so the dedicated surface feels closer to a full conversation view.
struct DetailConversationTimeline: View {
    let sessionId: String
    let session: SessionSnapshot
    let state: SessionConversationState

    @ObservedObject private var l10n = L10n.shared
    @State private var isAutoscrollPaused = false
    @State private var newMessageCount = 0
    @State private var lastInitialScrollSessionId: String?

    private var bottomAnchorID: String { "detail-conversation-bottom-\(sessionId)" }

    /// Treat the processing indicator as part of the visible timeline so auto-scroll follows live agent work too.
    private var renderedItemCount: Int {
        state.items.count + (showsProcessingIndicator ? 1 : 0)
    }

    private var showsProcessingIndicator: Bool {
        session.status == .processing || session.status == .running
    }

    private var processingLabel: String {
        let value = session.toolDescription ?? session.currentTool ?? l10n["status_processing"]
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? l10n["status_processing"] : value
    }

    /// Claude detail should match MioIsland's denser chat mode instead of expanding
    /// every thinking block and tool result by default.
    private var prefersCompactClaudeLayout: Bool {
        session.source == "claude"
    }

    /// A fixed transcript viewport keeps LazyVStack lazy while still allowing short conversations to stay compact.
    private var timelineHeight: CGFloat {
        SessionDetailLayoutMetrics.timelineViewportHeight(
            itemCount: state.items.count,
            showsProcessingIndicator: showsProcessingIndicator,
            prefersCompactLayout: prefersCompactClaudeLayout
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 16) {
                    // Keep the transcript in natural order and scroll to a bottom anchor.
                    // This avoids the inverted-scroll layout trick, which is fragile on newer macOS SwiftUI builds.
                    if state.items.isEmpty && !showsProcessingIndicator {
                        Text(l10n["session_detail_no_history"])
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.42))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(state.items) { item in
                            DetailConversationRow(
                                item: item,
                                linkContext: linkContext,
                                prefersCompactClaudeLayout: prefersCompactClaudeLayout
                            )
                        }

                        if showsProcessingIndicator {
                            DetailProcessingIndicator(text: processingLabel)
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorID)
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 12)
            }
            .frame(height: timelineHeight, alignment: .top)
            .modifier(
                DetailScrollBottomTrackingModifier(threshold: 50) { isNearBottom in
                    if isNearBottom {
                        isAutoscrollPaused = false
                        newMessageCount = 0
                    } else {
                        isAutoscrollPaused = true
                    }
                }
            )
            .onAppear {
                if Self.shouldPerformInitialScroll(
                    sessionId: sessionId,
                    lastInitialScrollSessionId: lastInitialScrollSessionId
                ) {
                    lastInitialScrollSessionId = sessionId
                    scrollToBottom(proxy, animated: false)
                }
            }
            .onChange(of: sessionId) { _, _ in
                // Switching to a different session should opt the new timeline back into its first bottom alignment.
                lastInitialScrollSessionId = nil
            }
            .onChange(of: renderedItemCount) { oldCount, newCount in
                guard newCount > oldCount else { return }
                if isAutoscrollPaused {
                    newMessageCount += newCount - oldCount
                } else {
                    scrollToBottom(proxy)
                }
            }
            .overlay(alignment: .bottom) {
                if newMessageCount > 0 {
                    Button {
                        scrollToBottom(proxy)
                        isAutoscrollPaused = false
                        newMessageCount = 0
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 12, weight: .medium))
                            Text(String(format: l10n["session_detail_new_messages"], newMessageCount))
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.14))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeOut(duration: 0.2), value: newMessageCount)
        }
    }

    /// Detail-mode markdown links should resolve against the same workspace as the inline transcript.
    private var linkContext: EditorLinkContext {
        EditorLinkContext(sessionId: sessionId, session: session)
    }

    /// Reappearing after an external-file jump should not reset the reader back to the bottom for the same session.
    static func shouldPerformInitialScroll(
        sessionId: String,
        lastInitialScrollSessionId: String?
    ) -> Bool {
        lastInitialScrollSessionId != sessionId
    }

    /// Bottom anchoring keeps the latest turn visible during live agent activity.
    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let action = {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.22), action)
        } else {
            action()
        }
    }
}

/// Use a single AppKit-backed tracking path for transcript scrolling so behavior stays stable across macOS releases.
private struct DetailScrollBottomTrackingModifier: ViewModifier {
    let threshold: CGFloat
    let onNearBottomChange: (Bool) -> Void

    func body(content: Content) -> some View {
        // Always use the AppKit observer here. It is less fancy than SwiftUI's native
        // geometry callback, but it is more stable across macOS releases for this transcript view.
        content.background(
            DetailScrollBottomObserver(threshold: threshold, onNearBottomChange: onNearBottomChange)
        )
    }
}

/// Observing the backing NSScrollView keeps bottom-tracking independent from SwiftUI's scroll layout internals.
private struct DetailScrollBottomObserver: NSViewRepresentable {
    let threshold: CGFloat
    let onNearBottomChange: (Bool) -> Void

    func makeNSView(context: Context) -> DetailScrollBottomObserverView {
        let view = DetailScrollBottomObserverView()
        view.threshold = threshold
        view.onNearBottomChange = onNearBottomChange
        return view
    }

    func updateNSView(_ nsView: DetailScrollBottomObserverView, context: Context) {
        nsView.threshold = threshold
        nsView.onNearBottomChange = onNearBottomChange
        nsView.attachIfNeeded()
        // Bounce the visibility report to the next run-loop turn so SwiftUI state
        // is not mutated while AppKit is still reconciling this representable.
        nsView.scheduleScrollPositionReport()
    }
}

/// AppKit observation keeps the auto-scroll pause heuristic compatible with older macOS targets.
private final class DetailScrollBottomObserverView: NSView {
    var threshold: CGFloat = 80
    var onNearBottomChange: ((Bool) -> Void)?

    private var boundsObserver: NSObjectProtocol?
    private var hasScheduledReport = false
    private var lastReportedNearBottom: Bool?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachIfNeeded()
        scheduleScrollPositionReport()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        attachIfNeeded()
        scheduleScrollPositionReport()
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    func attachIfNeeded() {
        guard boundsObserver == nil,
              let scrollView = enclosingScrollView else {
            return
        }

        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleScrollPositionReport()
        }
    }

    func scheduleScrollPositionReport() {
        guard !hasScheduledReport else { return }
        hasScheduledReport = true
        // Coalesce repeated layout/scroll callbacks into one main-queue report so
        // the detail timeline does not thrash SwiftUI state during transitions.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hasScheduledReport = false
            self.reportScrollPosition()
        }
    }

    func reportScrollPosition() {
        guard let scrollView = enclosingScrollView,
              let documentView = scrollView.documentView else {
            return
        }

        let visibleRect = scrollView.contentView.bounds
        let isNearBottom = visibleRect.maxY >= documentView.bounds.height - threshold
        guard lastReportedNearBottom != isNearBottom else { return }
        lastReportedNearBottom = isNearBottom
        onNearBottomChange?(isNearBottom)
    }
}

/// Detail rows switch from timeline prefixes to chat-like bubbles so long messages scan more naturally.
private struct DetailConversationRow: View {
    let item: ConversationHistoryItem
    let linkContext: EditorLinkContext
    let prefersCompactClaudeLayout: Bool

    var body: some View {
        switch item.kind {
        case .user(let text):
            HStack {
                Spacer(minLength: 56)
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.94))
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                    )
            }
        case .assistant(let text):
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 6, height: 6)
                    .padding(.top, 6)
                MarkdownText(text, color: .white.opacity(0.9), fontSize: 13, linkContext: linkContext)
                    .textSelection(.enabled)
                Spacer(minLength: 56)
            }
        case .thinking(let text):
            DetailThinkingRow(text: text, compactByDefault: prefersCompactClaudeLayout)
        case .interrupted(let text):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.86))
                    .padding(.top, 2)
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.orange.opacity(0.84))
                    .textSelection(.enabled)
                Spacer(minLength: 56)
            }
        case .toolCall(let tool):
            DetailToolConversationRow(
                tool: tool,
                linkContext: linkContext,
                compactByDefault: prefersCompactClaudeLayout
            )
        }
    }
}

/// Processing rows make live sessions feel active even before the next structured transcript event lands.
private struct DetailProcessingIndicator: View {
    let text: String

    @State private var pulse = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(Color(red: 0.92, green: 0.55, blue: 0.34))
                .frame(width: 8, height: 8)
                .scaleEffect(pulse ? 1.0 : 0.72)
                .opacity(pulse ? 0.92 : 0.45)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
            Text(text)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(2)
            Spacer(minLength: 56)
        }
        .onAppear {
            pulse = true
        }
    }
}
