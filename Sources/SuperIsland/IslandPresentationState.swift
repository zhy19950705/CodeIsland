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
    case shortcut
    case deeplink
    case boot
    case unknown
}

/// Separates "what is shown" from "how it is shown".
enum IslandContentType: Equatable {
    case sessions
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
        case .sessionList, .approvalCard, .questionCard:
            return .opened
        }
    }

    var contentType: IslandContentType {
        switch self {
        case .collapsed, .sessionList:
            return .sessions
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
        case .sessionList, .approvalCard, .questionCard:
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

    /// Centralize surface transitions so the open reason and restore target stay in sync.
    func presentSurface(
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

    func collapseIsland(
        reason: IslandOpenReason = .unknown,
        animation: Animation = NotchAnimation.close
    ) {
        presentSurface(.collapsed, reason: reason, animation: animation)
    }

    /// Reopen to the last meaningful surface when possible instead of always resetting to the session list.
    func openSessionList(
        reason: IslandOpenReason = .unknown,
        animation: Animation = NotchAnimation.open
    ) {
        presentSurface(restorableSurfaceForOpen(), reason: reason, animation: animation)
        cancelCompletionQueue()
        if activeSessionId == nil {
            activeSessionId = preferredSessionId
        }
    }

    /// Pending blocking interactions beat stale restore targets so the island reopens to the right card.
    private func restorableSurfaceForOpen() -> IslandSurface {
        switch lastRestorableSurface {
        case .approvalCard(let sessionId):
            return pendingPermission == nil ? .sessionList : .approvalCard(sessionId: sessionId)
        case .questionCard(let sessionId):
            return pendingQuestion == nil ? .sessionList : .questionCard(sessionId: sessionId)
        case .sessionList, .collapsed, .completionCard:
            return .sessionList
        }
    }
}
