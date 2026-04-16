import SwiftUI
import SuperIslandCore

struct NotchPanelView: View {
    private enum ToolStatusCurtainPhase {
        case visible
        case concealed
    }

    private enum ToolStatusTransition {
        static let concealDuration = 0.2
        static let revealDuration = 0.25
        static let concealDelay: Duration = .milliseconds(250)
        static let revealDelay: Duration = .milliseconds(100)
    }

    var appState: AppState
    let hasNotch: Bool
    let notchHeight: CGFloat
    let notchW: CGFloat
    let screenWidth: CGFloat

    @AppStorage(SettingsKey.hideWhenNoSession) private var hideWhenNoSession = SettingsDefaults.hideWhenNoSession
    @AppStorage(SettingsKey.showToolStatus) private var showToolStatus = SettingsDefaults.showToolStatus

    @State private var toolStatusCurtainPhase: ToolStatusCurtainPhase = .visible
    @State private var displayedToolStatus: Bool = SettingsDefaults.showToolStatus
    @State private var toolStatusTransitionTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var activityCoordinator = NotchActivityCoordinator.shared

    private var isActive: Bool { !appState.sessions.isEmpty }
    /// First launch / no-session state should still render a visible marker so the app
    /// doesn't disappear completely behind the physical notch.
    private var showIdleIndicator: Bool {
        !isActive && !hideWhenNoSession
    }
    /// Whether the bar content should be visible (respects hideWhenNoSession)
    private var showBar: Bool {
        isActive && !SessionVisibilityPolicy.shouldHideWhenNoSession(
            hideWhenNoSession: hideWhenNoSession,
            sessions: appState.sessions
        )
    }
    private var shouldShowExpanded: Bool {
        showBar && appState.surface.isExpanded
    }
    private var curtainOffset: CGFloat {
        toolStatusCurtainPhase == .concealed ? -notchHeight : 0
    }
    private var curtainOpacity: Double {
        toolStatusCurtainPhase == .concealed ? 0 : 1
    }

    /// Mascot size — fits within the menu bar height
    private var mascotSize: CGFloat { min(27, notchHeight - 6) }

    /// Minimum wing width needed to display compact bar content
    private var compactWingWidth: CGFloat { mascotSize + 14 }

    /// Total panel width — adapts based on state and screen geometry
    private var panelWidth: CGFloat {
        let maxWidth = min(620, screenWidth - 40)
        if showIdleIndicator {
            return appState.panelCoordinator.isPointerInsideInteractiveRegion
                ? notchW + compactWingWidth * 2 + 80
                : notchW + compactWingWidth * 2
        }
        if !isActive { return hasNotch ? notchW - 20 : notchW }
        if shouldShowExpanded { return min(max(notchW + 200, 580), maxWidth) }
        return Self.collapsedPanelWidth(
            notchWidth: notchW,
            compactWingWidth: compactWingWidth,
            screenWidth: screenWidth,
            hasNotch: hasNotch,
            displayedToolStatus: displayedToolStatus,
            activityExtraWidth: activityCoordinator.currentExtraWidth
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                NotchPrimaryBarView(
                    appState: appState,
                    showBar: showBar,
                    showIdleIndicator: showIdleIndicator,
                    shouldShowExpanded: shouldShowExpanded,
                    mascotSize: mascotSize,
                    compactWingWidth: compactWingWidth,
                    notchW: notchW,
                    notchHeight: notchHeight,
                    hasNotch: hasNotch,
                    idleHovered: appState.panelCoordinator.isPointerInsideInteractiveRegion,
                    showToolStatus: showToolStatus
                )

                // Match MioIsland's "bounded but content-led" behavior:
                // expanded content can grow up to the panel height, but it does not
                // need to occupy all of it when the transcript is short.
                if shouldShowExpanded {
                    NotchExpandedContentView(appState: appState)
                }
            }
            .frame(width: panelWidth)
            .clipped()
            .background(
                NotchPanelShape(
                    shoulderExtension: shouldShowExpanded ? 14 : 3,
                    topCornerRadius: shouldShowExpanded ? 18 : 6,
                    bottomCornerRadius: shouldShowExpanded ? 24 : 12,
                    minHeight: notchHeight
                )
                .fill(.black)
            )
            .offset(y: curtainOffset)
            .opacity(curtainOpacity)
            .onChange(of: showToolStatus) { _, newValue in
                animateToolStatusTransition(to: newValue)
            }
            .onAppear {
                displayedToolStatus = showToolStatus
                appState.panelCoordinator.syncWithPresentationState()
                syncActivityState()
            }
            .onDisappear {
                toolStatusTransitionTask?.cancel()
                appState.panelCoordinator.cancelPendingInteraction()
            }
            .onChange(of: appState.surface) { _, _ in
                appState.panelCoordinator.syncWithPresentationState()
                syncActivityState()
                NotificationCenter.default.post(name: .superIslandSurfaceDidChange, object: nil)
            }
            .onChange(of: appState.lastOpenReason) { _, _ in
                appState.panelCoordinator.syncWithPresentationState()
                syncActivityState()
            }
            .onChange(of: appState.status) { _, _ in
                syncActivityState()
            }
            .onChange(of: appState.pendingPermission != nil) { _, _ in
                syncActivityState()
            }
            .onChange(of: appState.pendingQuestion != nil) { _, _ in
                syncActivityState()
            }

            Spacer()
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(NotchAnimation.open, value: appState.surface)
        .animation(NotchAnimation.micro, value: appState.panelCoordinator.isPointerInsideInteractiveRegion)
    }

    private func animateToolStatusTransition(to newValue: Bool) {
        toolStatusTransitionTask?.cancel()

        guard !reduceMotion else {
            displayedToolStatus = newValue
            toolStatusCurtainPhase = .visible
            return
        }

        toolStatusTransitionTask = Task { @MainActor in
            withAnimation(.easeIn(duration: ToolStatusTransition.concealDuration)) {
                toolStatusCurtainPhase = .concealed
            }

            try? await Task.sleep(for: ToolStatusTransition.concealDelay)
            guard !Task.isCancelled else { return }
            displayedToolStatus = newValue

            try? await Task.sleep(for: ToolStatusTransition.revealDelay)
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: ToolStatusTransition.revealDuration)) {
                toolStatusCurtainPhase = .visible
            }
        }
    }

    private func syncActivityState() {
        // Keep transient side expansion logic centralized and deterministic.
        activityCoordinator.sync(
            status: appState.status,
            isExpanded: shouldShowExpanded,
            hasBlockingCard: appState.pendingPermission != nil || appState.pendingQuestion != nil
        )
    }
}
