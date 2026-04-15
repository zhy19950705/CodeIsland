import CoreGraphics
import SuperIslandCore

extension NotchPanelView {
    static func compactUsageProvider(
        from snapshot: UsageSnapshot,
        sessions: [String: SessionSnapshot],
        rotatingSessionId: String?,
        activeSessionId: String?,
        primarySource: String
    ) -> UsageProviderSnapshot? {
        let sessionId = rotatingSessionId ?? activeSessionId ?? sessions.keys.sorted().first
        let source = sessionId.flatMap { sessions[$0]?.source } ?? primarySource
        guard let usageSource = UsageProviderSource(rawValue: source) else { return nil }
        return snapshot.providers.first(where: { $0.source == usageSource && $0.hasQuotaMetrics })
    }

    /// The physical notch should not auto-expand from hover when the pointer is only crossing the cutout.
    static func isInCollapsedNotchDeadZone(
        point: CGPoint,
        panelWidth: CGFloat,
        notchWidth: CGFloat,
        hasNotch: Bool,
        ignoresHover: Bool
    ) -> Bool {
        guard hasNotch, ignoresHover, notchWidth > 0, panelWidth > notchWidth else { return false }
        let notchMinX = (panelWidth - notchWidth) / 2
        let notchMaxX = notchMinX + notchWidth
        return point.x >= notchMinX && point.x <= notchMaxX
    }

    /// `onContinuousHover` can emit `.ended` while the pointer is still within the panel during resize.
    static func shouldIgnoreExpandedHoverEnded(
        mouseLocation: CGPoint,
        panelFrame: CGRect?,
        isExpanded: Bool
    ) -> Bool {
        guard isExpanded, let panelFrame else { return false }
        return panelFrame.contains(mouseLocation)
    }
}
