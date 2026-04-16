import Foundation

/// Surface motion is described separately from rendering so transitions stay testable
/// without depending on SwiftUI's opaque animation types.
enum IslandSurfaceMotionProfile: Equatable {
    case list
    case detail
    case blockingCard
    case completion
    case collapsed
}

extension IslandSurface {
    /// Different surfaces should move differently so list/detail navigation reads as
    /// navigation, while approvals and completions still feel like transient overlays.
    var motionProfile: IslandSurfaceMotionProfile {
        switch self {
        case .collapsed:
            return .collapsed
        case .sessionList:
            return .list
        case .sessionDetail:
            return .detail
        case .approvalCard, .questionCard:
            return .blockingCard
        case .completionCard:
            return .completion
        }
    }

    /// A concrete identity prevents SwiftUI from recycling the previous expanded
    /// surface subtree when the content type actually changed.
    var transitionIdentity: String {
        switch self {
        case .collapsed:
            return "surface-collapsed"
        case .sessionList:
            return "surface-session-list"
        case .sessionDetail(let sessionId):
            return "surface-session-detail-\(sessionId)"
        case .approvalCard(let sessionId):
            return "surface-approval-\(sessionId)"
        case .questionCard(let sessionId):
            return "surface-question-\(sessionId)"
        case .completionCard(let sessionId):
            return "surface-completion-\(sessionId)"
        }
    }
}
