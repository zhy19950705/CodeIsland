import SwiftUI
import Observation

/// Centralizes notch hover and click policy so view rendering stays separate from interaction timing.
@MainActor
@Observable
final class IslandPanelCoordinator {
    private enum Timing {
        /// A longer collapse delay prevents the island from flashing shut when the
        /// pointer briefly slips outside the panel during normal movement.
        static let dismissDelay: TimeInterval = 1.25
        /// Explicit list/detail navigation should finish its spring animation before
        /// global hover tracking is allowed to reinterpret the same pointer movement.
        static let navigationHoverGuard: TimeInterval = 0.45
    }

    private unowned let appState: AppState
    private var hoverTimer: Timer?
    /// Records a short cooldown window after explicit surface navigation so hover
    /// monitors cannot immediately re-drive the panel mid-transition.
    private var hoverSuppressedUntil: Date = .distantPast
    /// Hover-opened surfaces should not dismiss until the pointer has actually
    /// entered the expanded surface once; this avoids flash-close during resize.
    private var hasEnteredExpandedSurfaceSinceOpen = false

    private(set) var interactionState: NotchInteractionState = .collapsed
    private(set) var isPointerInsideInteractiveRegion = false

    init(appState: AppState) {
        self.appState = appState
    }

    /// Keep coordinator state aligned with externally-driven surface changes such as blocking cards and notifications.
    func syncWithPresentationState() {
        cancelHoverTimer()
        interactionState = Self.interactionState(
            surface: appState.surface,
            reason: appState.lastOpenReason
        )
        syncExpandedSurfaceEntryGate(surface: appState.surface, reason: appState.lastOpenReason)
    }

    /// Release any pending hover work when the hosting view disappears or rebuilds.
    func cancelPendingInteraction() {
        cancelHoverTimer()
        isPointerInsideInteractiveRegion = false
        hoverSuppressedUntil = .distantPast
        hasEnteredExpandedSurfaceSinceOpen = false
    }

    /// Keep pointer-presence updates separate from transition timing so suppressed
    /// hover paths can still clear transient visual state without scheduling collapse.
    func setPointerInsideInteractiveRegion(_ inside: Bool) {
        isPointerInsideInteractiveRegion = inside
    }

    /// Convert raw hover-in / hover-out events into delayed panel transitions.
    func handleHover(
        inside: Bool,
        hoverActivationDelay: TimeInterval,
        collapseOnMouseLeave: Bool
    ) {
        isPointerInsideInteractiveRegion = inside
        notePointerInsideExpandedSurfaceIfNeeded(inside: inside)

        // Explicit surface switches can generate extra mouse-move events while the
        // panel is animating. Ignore those events briefly so detail/list transitions
        // are driven by the user's click, not by leftover hover state.
        if isHoverTransitionSuppressed {
            cancelHoverTimer()
            return
        }

        switch appState.surface {
        case .approvalCard, .questionCard:
            cancelHoverTimer()
            interactionState = .expanded
            return
        default:
            break
        }

        if inside {
            handleHoverEnter(hoverActivationDelay: hoverActivationDelay)
            return
        }

        handleHoverExit(collapseOnMouseLeave: collapseOnMouseLeave)
    }

    /// Row taps are explicit navigation intent, so they pin the panel and suppress hover-out collapse.
    func handleRowTap(sessionId: String) {
        // Defer to the next runloop tick to avoid NSHostingView layout re-entrancy
        // when AppKit event handling and SwiftUI animation overlap.
        DispatchQueue.main.async { [weak self] in
            self?.showSessionDetail(sessionId: sessionId, reason: .pinned)
        }
    }

    /// Dedicated detail presentation should pin the panel so pointer-out does not undo a deliberate navigation.
    func showSessionDetail(
        sessionId: String,
        reason: IslandOpenReason = .click
    ) {
        cancelHoverTimer()
        interactionState = reason == .pinned ? .pinned : .expanded
        guard appState.activateSession(sessionId) else { return }
        appState.setSurface(.sessionDetail(sessionId: sessionId), reason: reason, animation: NotchAnimation.open)
        syncExpandedSurfaceEntryGate(surface: .sessionDetail(sessionId: sessionId), reason: reason)
        appState.cancelCompletionQueue()
    }

    /// Session focus should keep the current list/detail restore semantics while routing the visual open through one coordinator.
    @discardableResult
    func focusSession(
        sessionId: String,
        reason: IslandOpenReason = .click
    ) -> Bool {
        guard appState.activateSession(sessionId) else { return false }
        openSessionList(reason: reason)
        return true
    }

    /// General surface presentation is centralized here so interaction state stays in sync with every transition source.
    func presentSurface(
        _ surface: IslandSurface,
        reason: IslandOpenReason = .unknown,
        animation: Animation? = nil
    ) {
        cancelHoverTimer()
        appState.setSurface(surface, reason: reason, animation: animation)
        interactionState = Self.interactionState(surface: surface, reason: reason)
        syncExpandedSurfaceEntryGate(surface: surface, reason: reason)
    }

    /// Explicit list expansion is not pinned; hover-out should still be allowed afterwards.
    func openSessionList(
        reason: IslandOpenReason,
        animation: Animation = NotchAnimation.open
    ) {
        cancelHoverTimer()
        let nextSurface = appState.resolvedSurfaceForOpen(reason: reason)
        appState.setSurface(nextSurface, reason: reason, animation: animation)
        appState.cancelCompletionQueue()
        appState.ensurePreferredActiveSession()
        interactionState = Self.interactionState(surface: nextSurface, reason: reason)
        syncExpandedSurfaceEntryGate(surface: nextSurface, reason: reason)
    }

    /// Returning from detail should land on the concrete list surface instead of re-restoring the pinned detail card.
    func showSessionListSurface(
        reason: IslandOpenReason = .click,
        animation: Animation = NotchAnimation.open
    ) {
        suppressHoverTransitions()
        presentSurface(.sessionList, reason: reason, animation: animation)
        appState.cancelCompletionQueue()
        if appState.activeSessionId == nil {
            appState.activeSessionId = appState.preferredSessionId
        }
    }

    /// Detail-surface actions can promote a blocking card without each view reimplementing the presentation policy.
    func presentBlockingCard(
        _ surface: IslandSurface,
        reason: IslandOpenReason = .click,
        animation: Animation? = nil
    ) {
        presentSurface(surface, reason: reason, animation: animation)
    }

    /// Completion cards are transient, but they still need coordinator-owned interaction state so hover dismissal remains deterministic.
    func presentCompletionCard(
        sessionId: String,
        reason: IslandOpenReason = .notification,
        animation: Animation? = nil
    ) {
        presentSurface(.completionCard(sessionId: sessionId), reason: reason, animation: animation)
    }

    /// Blocking queue transitions can move between cards, detail, and collapse; centralizing the branch keeps AppState data-focused.
    func applyBlockingPresentation(_ state: BlockingPresentationState?) {
        guard let state else { return }
        if let activeSessionId = state.activeSessionId {
            appState.activeSessionId = activeSessionId
        }

        switch state.surface {
        case .collapsed:
            collapse(reason: .notification)
        case .approvalCard, .questionCard, .sessionDetail, .sessionList, .completionCard:
            presentSurface(state.surface, reason: .notification)
        }
    }

    /// External click-away collapse should always win over transient hover work.
    func collapse(
        reason: IslandOpenReason,
        animation: Animation = NotchAnimation.close
    ) {
        cancelHoverTimer()
        interactionState = .collapsed
        hasEnteredExpandedSurfaceSinceOpen = false
        if reason == .click {
            appState.cancelCompletionQueue()
        }
        appState.setSurface(.collapsed, reason: reason, animation: animation)
    }

    /// External click-away collapse should always win over transient hover work.
    func collapseAfterOutsideClick() {
        isPointerInsideInteractiveRegion = false
        collapse(reason: .click)
    }

    /// The main toggle still powers menu-bar / notch mode switching through one coordinator entry point.
    func togglePrimarySurface() {
        if appState.surface.isExpanded {
            collapse(reason: .click)
        } else {
            openSessionList(reason: .click)
        }
    }

    /// Maps the current presentation into the coordinator state machine so tests can validate transitions without AppKit.
    nonisolated static func interactionState(
        surface: IslandSurface,
        reason: IslandOpenReason
    ) -> NotchInteractionState {
        switch surface {
        case .collapsed:
            return .collapsed
        case .sessionDetail:
            return .pinned
        case .completionCard:
            return reason == .pinned ? .pinned : .hovering
        case .approvalCard, .questionCard:
            return .expanded
        case .sessionList:
            return reason == .pinned ? .pinned : .expanded
        }
    }

    /// Tests use the shared timing source instead of re-encoding magic numbers.
    nonisolated static func hoverDismissDelay() -> TimeInterval {
        Timing.dismissDelay
    }

    /// Tests share the same transition guard constant so they stay aligned with the
    /// runtime gesture policy instead of hard-coding duplicate timing values.
    nonisolated static func navigationHoverGuardDelay() -> TimeInterval {
        Timing.navigationHoverGuard
    }

    private func handleHoverEnter(hoverActivationDelay: TimeInterval) {
        if interactionState == .pinned {
            cancelHoverTimer()
            return
        }

        switch appState.surface {
        case .completionCard:
            cancelHoverTimer()
            interactionState = .hovering
        case .collapsed:
            cancelHoverTimer()
            interactionState = .hovering
            hoverTimer = Timer.scheduledTimer(withTimeInterval: hoverActivationDelay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.openSessionList(reason: .hover)
                }
            }
        default:
            cancelHoverTimer()
            interactionState = .expanded
        }
    }

    private func handleHoverExit(collapseOnMouseLeave: Bool) {
        if interactionState == .pinned {
            cancelHoverTimer()
            return
        }

        switch appState.surface {
        case .completionCard:
            guard shouldAutoCollapseOnPointerExit(collapseOnMouseLeave: collapseOnMouseLeave) else {
                cancelHoverTimer()
                interactionState = .hovering
                return
            }
            scheduleDismiss {
                self.appState.cancelCompletionQueue()
                self.collapse(reason: .hover)
            }
        case .collapsed:
            cancelHoverTimer()
            interactionState = .collapsed
        default:
            guard shouldAutoCollapseOnPointerExit(collapseOnMouseLeave: collapseOnMouseLeave) else {
                cancelHoverTimer()
                interactionState = .expanded
                return
            }
            guard hasEnteredExpandedSurfaceSinceOpen || !requiresPriorExpandedSurfaceEntry else {
                cancelHoverTimer()
                interactionState = .expanded
                return
            }
            scheduleDismiss {
                self.collapse(reason: .hover)
            }
        }
    }

    private func scheduleDismiss(_ action: @escaping @MainActor () -> Void) {
        cancelHoverTimer()
        interactionState = .dismissing
        hoverTimer = Timer.scheduledTimer(withTimeInterval: Timing.dismissDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.interactionState != .pinned else { return }
                action()
                self.interactionState = .collapsed
            }
        }
    }

    private func cancelHoverTimer() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    /// Explicit navigation clicks should win over hover reconciliation until the
    /// surface swap animation has visually settled.
    private func suppressHoverTransitions(for delay: TimeInterval = Timing.navigationHoverGuard) {
        hoverSuppressedUntil = Date().addingTimeInterval(delay)
    }

    private var isHoverTransitionSuppressed: Bool {
        Date() < hoverSuppressedUntil
    }

    /// Hover-triggered surfaces should only auto-collapse if the user enabled the
    /// behavior. Notification completions keep the existing transient dismissal.
    private func shouldAutoCollapseOnPointerExit(collapseOnMouseLeave: Bool) -> Bool {
        switch appState.lastOpenReason {
        case .hover:
            return collapseOnMouseLeave
        case .notification:
            if case .completionCard = appState.surface {
                return true
            }
            return false
        case .click, .pinned, .shortcut, .deeplink, .boot, .unknown:
            return false
        }
    }

    /// Expanded surfaces opened by hover need one confirmed inside report before
    /// hover-out is allowed to dismiss them.
    private var requiresPriorExpandedSurfaceEntry: Bool {
        appState.lastOpenReason == .hover && appState.surface.isExpanded
    }

    private func notePointerInsideExpandedSurfaceIfNeeded(inside: Bool) {
        guard inside, appState.surface.isExpanded else { return }
        hasEnteredExpandedSurfaceSinceOpen = true
    }

    private func syncExpandedSurfaceEntryGate(surface: IslandSurface, reason: IslandOpenReason) {
        if !surface.isExpanded {
            hasEnteredExpandedSurfaceSinceOpen = false
            return
        }

        // Explicit openings are immediately stable. Hover openings must confirm
        // one real entry into the expanded frame before they can dismiss on exit.
        hasEnteredExpandedSurfaceSinceOpen = reason != .hover
    }
}
