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

    @AppStorage(SettingsKey.smartSuppress) private var smartSuppress = SettingsDefaults.smartSuppress
    @AppStorage(SettingsKey.hideWhenNoSession) private var hideWhenNoSession = SettingsDefaults.hideWhenNoSession
    @AppStorage(SettingsKey.showToolStatus) private var showToolStatus = SettingsDefaults.showToolStatus

    /// Delayed hover: prevents accidental expansion when mouse passes through
    @State private var hoverTimer: Timer?
    @State private var idleHovered = false
    /// Track fullscreen state for adaptive hover behavior
    @State private var isFullscreenActive = false
    /// Track if mouse is in fullscreen reveal zone (top edge when hidden)
    @State private var isInFullscreenRevealZone = false
    @State private var lastFullscreenStateRefreshAt: Date = .distantPast
    @State private var toolStatusCurtainPhase: ToolStatusCurtainPhase = .visible
    @State private var displayedToolStatus: Bool = SettingsDefaults.showToolStatus
    @State private var completionHasBeenEntered = false
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
    private var compactUsageProvider: UsageProviderSnapshot? {
        Self.compactUsageProvider(
            from: appState.usageSnapshot,
            sessions: appState.sessions,
            rotatingSessionId: appState.rotatingSessionId,
            activeSessionId: appState.activeSessionId,
            primarySource: appState.primarySource
        )
    }
    private var showCompactUsageBadge: Bool {
        !shouldShowExpanded && compactUsageProvider != nil
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
        if showIdleIndicator { return idleHovered ? notchW + compactWingWidth * 2 + 80 : notchW + compactWingWidth * 2 }
        if !isActive { return hasNotch ? notchW - 20 : notchW }
        if shouldShowExpanded { return min(max(notchW + 200, 580), maxWidth) }
        let wing = compactWingWidth
        let activityExtra = activityCoordinator.currentExtraWidth
        // Reserve space for tool status — proportional to screen width
        let toolExtra: CGFloat = displayedToolStatus ? (hasNotch ? screenWidth * 0.03 : screenWidth * 0.04) : 0
        let usageExtra: CGFloat = showCompactUsageBadge ? (hasNotch ? 76 : 90) : 0
        return notchW + wing * 2 + activityExtra + toolExtra + usageExtra
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
                    idleHovered: idleHovered,
                    showToolStatus: showToolStatus
                )

                // Below-notch expanded content
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
                updateFullscreenState(force: true)
                syncActivityState()
            }
            .onDisappear {
                toolStatusTransitionTask?.cancel()
                cancelHoverTimer()
            }
            .onChange(of: appState.surface) { _, newValue in
                _ = newValue
                completionHasBeenEntered = false
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
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let point):
                    handleActiveHover(at: point)
                case .ended:
                    handleHoverEnded()
                }
            }

            Spacer()
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(NotchAnimation.open, value: appState.surface)
    }

    private func handleActiveHover(at point: CGPoint) {
        // Update fullscreen state for adaptive hover behavior
        updateFullscreenState()

        if shouldIgnoreCollapsedNotchHover(localPoint: point) {
            cancelHoverTimer()
            return
        }
        handleHoverChange(true)
    }

    /// Update fullscreen state by checking with panel controller
    private func updateFullscreenState(force: Bool = false) {
        let now = Date()
        if !force, now.timeIntervalSince(lastFullscreenStateRefreshAt) < 0.08 {
            return
        }
        lastFullscreenStateRefreshAt = now

        guard let delegate = NSApp.delegate as? AppDelegate,
              let panelController = delegate.panelController else { return }

        _ = isFullscreenActive
        isFullscreenActive = panelController.isFullscreenEdgeRevealActive

        // Check if mouse is in fullscreen reveal zone
        let wasInRevealZone = isInFullscreenRevealZone
        isInFullscreenRevealZone = panelController.isMouseInFullscreenRevealZone(
            panelWidth: panelWidth,
            notchWidth: notchW,
            hasNotch: hasNotch
        )

        // If entering reveal zone, trigger hover immediately
        if isInFullscreenRevealZone && !wasInRevealZone && !appState.surface.isExpanded {
            handleHoverChange(true)
        }
    }

    private func handleHoverChange(_ hovering: Bool) {
        if !hovering, shouldIgnoreCollapsedNotchHover(localPoint: nil) {
            cancelHoverTimer()
            return
        }

        // Idle indicator hover
        if showIdleIndicator {
            withAnimation(NotchAnimation.micro) { idleHovered = hovering }
            return
        }
        switch appState.surface {
        case .approvalCard, .questionCard: return
        case .completionCard:
            // Completion card: mark entered on hover-in, block collapse until entered
            if hovering {
                completionHasBeenEntered = true
            } else if completionHasBeenEntered {
                // Mouse entered then left — allow collapse
                cancelHoverTimer()
                appState.cancelCompletionQueue()
                appState.collapseIsland(reason: .hover)
                }
            return
        default: break
        }
        // Respect collapseOnMouseLeave setting
        if !hovering && !SettingsManager.shared.collapseOnMouseLeave { return }
        // Smart suppress: don't auto-expand when active session's terminal is foreground
        if hovering && smartSuppress {
            if let delegate = NSApp.delegate as? AppDelegate,
               let pc = delegate.panelController,
               pc.isActiveTerminalForeground() {
                return
            }
        }

        if hovering {
            if appState.surface.isExpanded {
                cancelHoverTimer()
                return
            }
            // Delay expansion to avoid accidental triggers (adaptive based on fullscreen state)
            cancelHoverTimer()
            let delay = hoverActivationDelay
            hoverTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak appState] _ in
                Task { @MainActor in
                    appState?.openSessionList(reason: .hover)
                }
            }
        } else {
            // Collapse with brief delay to prevent flicker on accidental mouse-out
            cancelHoverTimer()
            hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak appState] _ in
                Task { @MainActor in
                    appState?.collapseIsland(reason: .hover)
                }
            }
        }
    }

    private func handleHoverEnded() {
        if shouldIgnoreExpandedHoverEnded() {
            cancelHoverTimer()
            return
        }
        handleHoverChange(false)
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

    /// Adaptive hover activation delay based on fullscreen state
    private var hoverActivationDelay: TimeInterval {
        let settings = SettingsManager.shared
        return isFullscreenActive
            ? settings.fullscreenHoverActivationDelay
            : settings.hoverActivationDelay
    }

    private func cancelHoverTimer() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    private func syncActivityState() {
        // Keep transient side expansion logic centralized and deterministic.
        activityCoordinator.sync(
            status: appState.status,
            isExpanded: shouldShowExpanded,
            hasBlockingCard: appState.pendingPermission != nil || appState.pendingQuestion != nil
        )
    }

    private func shouldIgnoreCollapsedNotchHover(localPoint: CGPoint?) -> Bool {
        // Check fullscreen reveal zone first - if in zone, don't ignore
        if isInFullscreenRevealZone {
            return false
        }

        let ignoresHover = !shouldShowExpanded
        if let localPoint,
           Self.isInCollapsedNotchDeadZone(
               point: localPoint,
               panelWidth: panelWidth,
               notchWidth: notchW,
               hasNotch: hasNotch,
               ignoresHover: ignoresHover
           ) {
            return true
        }

        guard let delegate = NSApp.delegate as? AppDelegate,
              let panelController = delegate.panelController else { return false }

        // Check fullscreen reveal zone via panel controller
        if panelController.isMouseInFullscreenRevealZone(
            panelWidth: panelWidth,
            notchWidth: notchW,
            hasNotch: hasNotch
        ) {
            return false
        }

        return panelController.isMouseInsideCollapsedNotchDeadZone(
            panelWidth: panelWidth,
            notchWidth: notchW,
            notchHeight: notchHeight,
            hasNotch: hasNotch,
            ignoresHover: ignoresHover
        )
    }

    private func shouldIgnoreExpandedHoverEnded() -> Bool {
        guard appState.surface.isExpanded,
              let delegate = NSApp.delegate as? AppDelegate,
              let panelController = delegate.panelController else { return false }
        return panelController.isMouseInsidePanelFrame()
    }
}
