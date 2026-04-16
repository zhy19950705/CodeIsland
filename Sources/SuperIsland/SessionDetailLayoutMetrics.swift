import CoreGraphics
import SuperIslandCore

/// Shared sizing rules keep the notch detail panel and menu bar popover aligned.
enum SessionDetailLayoutMetrics {
    /// Detail views can grow past the old half-screen cap, but should still stay tighter than full list surfaces.
    static let detailPanelMaxScreenRatio: CGFloat = 0.64
    /// Menu bar detail should stay compact even when the transcript grows quickly.
    static let detailPopoverMaxHeight: CGFloat = 620

    /// Estimate how many conversation rows are worth reserving space for before the inner scroll view takes over.
    static func estimatedTimelineItemCount(
        session: SessionSnapshot?,
        conversationState: SessionConversationState?
    ) -> Int {
        let parsedCount = conversationState?.items.count ?? 0
        let recentPreviewCount = session?.recentMessages.count ?? 0
        let toolPreviewCount = min(session?.toolHistory.count ?? 0, 4)
        let liveBonus = isLiveStatus(session?.status) ? 1 : 0
        return max(parsedCount, recentPreviewCount, toolPreviewCount) + liveBonus
    }

    /// Detail timelines should size to a few rows of content, then cap so lazy rendering keeps working.
    static func timelineViewportHeight(
        itemCount: Int,
        showsProcessingIndicator: Bool,
        prefersCompactLayout: Bool
    ) -> CGFloat {
        let renderedCount = max(1, itemCount + (showsProcessingIndicator ? 1 : 0))
        let clampedCount = min(renderedCount, 6)
        let baseHeight: CGFloat = prefersCompactLayout ? 116 : 128
        let rowHeight: CGFloat = prefersCompactLayout ? 52 : 62
        let estimatedHeight = baseHeight + CGFloat(clampedCount) * rowHeight
        return min(max(180, estimatedHeight), 360)
    }

    /// The outer panel estimate combines the measured transcript viewport with the fixed header and footer chrome.
    static func estimatedPanelHeight(
        session: SessionSnapshot?,
        conversationState: SessionConversationState?
    ) -> CGFloat {
        let showsProcessingIndicator = isLiveStatus(session?.status)
        let prefersCompactLayout = session?.source == "claude"
        let itemCount = estimatedTimelineItemCount(session: session, conversationState: conversationState)
        let timelineHeight = timelineViewportHeight(
            itemCount: itemCount,
            showsProcessingIndicator: showsProcessingIndicator,
            prefersCompactLayout: prefersCompactLayout
        )
        let headerHeight: CGFloat = 108
        let footerHeight: CGFloat = session?.source == "codex" ? 120 : 78
        return headerHeight + timelineHeight + footerHeight
    }

    /// Menu bar detail keeps the same transcript budget, with a little extra room for the popover chrome.
    static func estimatedPopoverHeight(
        session: SessionSnapshot?,
        conversationState: SessionConversationState?
    ) -> CGFloat {
        let estimatedHeight = estimatedPanelHeight(session: session, conversationState: conversationState) + 22
        return min(detailPopoverMaxHeight, max(400, estimatedHeight))
    }

    /// Session detail should respect the user's global cap without falling back to the old half-screen ceiling.
    static func maxDetailPanelHeight(maxPanelHeight: CGFloat, screenHeight: CGFloat) -> CGFloat {
        min(maxPanelHeight, screenHeight * detailPanelMaxScreenRatio)
    }

    /// Processing and running states both imply that another row can appear immediately.
    private static func isLiveStatus(_ status: AgentStatus?) -> Bool {
        status == .processing || status == .running
    }
}
