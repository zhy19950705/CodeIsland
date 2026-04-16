import CoreGraphics

extension NotchPanelView {
    /// Compact notch mode now reserves width only for the wing content, live activity, and session counters.
    static func collapsedPanelWidth(
        notchWidth: CGFloat,
        compactWingWidth: CGFloat,
        screenWidth: CGFloat,
        hasNotch: Bool,
        displayedToolStatus: Bool,
        activityExtraWidth: CGFloat
    ) -> CGFloat {
        let maxWidth = min(620, screenWidth - 40)
        let statusReserve: CGFloat
        if displayedToolStatus {
            statusReserve = hasNotch ? 68 : 112
        } else {
            statusReserve = 0
        }

        let calculatedWidth = notchWidth
            + compactWingWidth * 2
            + activityExtraWidth
            + statusReserve
        let minimumCompactWidth = hasNotch ? min(maxWidth, 460) : min(maxWidth, 360)
        return min(max(calculatedWidth, minimumCompactWidth), maxWidth)
    }
}
