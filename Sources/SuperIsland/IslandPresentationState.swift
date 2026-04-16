import SwiftUI

/// Closed/opened/popping mirrors the Dynamic Island interaction model more directly
/// than the old single surface enum alone.
enum IslandPresentationStatus: Equatable {
    case closed
    case opened
    case popping
}

/// Tracks why the island opened so window activation and future heuristics can differ.
enum IslandOpenReason: Equatable {
    case click
    case hover
    case notification
    case pinned
    case shortcut
    case deeplink
    case boot
    case unknown
}

/// Tracks pointer-driven panel behavior separately from surface content so hover and tap can be coordinated deterministically.
enum NotchInteractionState: Equatable {
    case collapsed
    case hovering
    case expanded
    case dismissing
    case pinned
}

/// Separates "what is shown" from "how it is shown".
enum IslandContentType: Equatable {
    case sessions
    case detail(sessionId: String)
    case approval(sessionId: String)
    case question(sessionId: String)
    case completion(sessionId: String)
}

/// Snapshot of the current island presentation used by the window layer.
struct IslandPresentationState: Equatable {
    let status: IslandPresentationStatus
    let reason: IslandOpenReason
    let content: IslandContentType
}

extension IslandSurface {
    /// Completion cards animate like a pop; everything else is either open or closed.
    var presentationStatus: IslandPresentationStatus {
        switch self {
        case .collapsed:
            return .closed
        case .completionCard:
            return .popping
        case .sessionList, .sessionDetail, .approvalCard, .questionCard:
            return .opened
        }
    }

    var contentType: IslandContentType {
        switch self {
        case .collapsed, .sessionList:
            return .sessions
        case .sessionDetail(let sessionId):
            return .detail(sessionId: sessionId)
        case .approvalCard(let sessionId):
            return .approval(sessionId: sessionId)
        case .questionCard(let sessionId):
            return .question(sessionId: sessionId)
        case .completionCard(let sessionId):
            return .completion(sessionId: sessionId)
        }
    }

    /// Persist the last user-facing expanded content so re-open flows have a stable target.
    var canRestoreWhenReopened: Bool {
        switch self {
        case .sessionList, .sessionDetail, .approvalCard, .questionCard:
            return true
        case .collapsed, .completionCard:
            return false
        }
    }
}

extension AppState {
    /// Derived presentation model consumed by window coordination and tests.
    var presentationState: IslandPresentationState {
        IslandPresentationState(
            status: surface.presentationStatus,
            reason: lastOpenReason,
            content: surface.contentType
        )
    }

    /// Low-level surface mutation used by the panel coordinator once interaction policy has already been decided.
    func setSurface(
        _ nextSurface: IslandSurface,
        reason: IslandOpenReason = .unknown,
        animation: Animation? = nil
    ) {
        lastOpenReason = reason
        if nextSurface.canRestoreWhenReopened {
            lastRestorableSurface = nextSurface
        }

        if let animation {
            withAnimation(animation) {
                surface = nextSurface
            }
        } else {
            surface = nextSurface
        }
    }

    /// Keep the original presentation helper for compatibility in tests and incremental refactors.
    func presentSurface(
        _ nextSurface: IslandSurface,
        reason: IslandOpenReason = .unknown,
        animation: Animation? = nil
    ) {
        setSurface(nextSurface, reason: reason, animation: animation)
    }

    func collapseIsland(
        reason: IslandOpenReason = .unknown,
        animation: Animation = NotchAnimation.close
    ) {
        panelCoordinator.collapse(reason: reason, animation: animation)
    }

    /// Reopen to the last meaningful surface when possible instead of always resetting to the session list.
    func openSessionList(
        reason: IslandOpenReason = .unknown,
        animation: Animation = NotchAnimation.open
    ) {
        panelCoordinator.openSessionList(reason: reason, animation: animation)
    }

    /// Pending blocking interactions beat stale restore targets so the island reopens to the right card.
    func resolvedSurfaceForOpen(reason: IslandOpenReason) -> IslandSurface {
        switch lastRestorableSurface {
        case .approvalCard(let sessionId):
            return pendingPermission == nil ? .sessionList : .approvalCard(sessionId: sessionId)
        case .questionCard(let sessionId):
            return pendingQuestion == nil ? .sessionList : .questionCard(sessionId: sessionId)
        case .sessionDetail(let sessionId):
            // Hover reopen should stay lightweight and return to the list instead of jumping back into detail.
            guard reopensDetailSurface(for: reason), sessions[sessionId] != nil else {
                return .sessionList
            }
            return .sessionDetail(sessionId: sessionId)
        case .sessionList, .collapsed, .completionCard:
            return .sessionList
        }
    }

    /// Coordinator helpers still need a single source of truth for the "pick a sensible active session" fallback.
    func ensurePreferredActiveSession() {
        if activeSessionId == nil {
            activeSessionId = preferredSessionId
        }
    }

    /// Only explicit open actions should restore the dedicated detail surface after a collapse.
    private func reopensDetailSurface(for reason: IslandOpenReason) -> Bool {
        switch reason {
        case .click, .pinned, .shortcut, .deeplink:
            return true
        case .hover, .notification, .boot, .unknown:
            return false
        }
    }
}
