import AppKit

/// Pure geometry helpers keep pointer hit-testing deterministic and easy to unit test.
enum PanelPointerGeometry {
    /// Collapsed mode needs a slightly larger catchment area so the pointer does not
    /// have to land on an exact pixel-perfect notch boundary to trigger expansion.
    private enum HoverInsets {
        static let collapsedHorizontal: CGFloat = 12
        static let collapsedVertical: CGFloat = 6
        static let expandedHorizontal: CGFloat = 4
        static let expandedVertical: CGFloat = 4
    }

    /// Expanded panels should stay close to their actual frame, while collapsed panels
    /// intentionally feel a bit more forgiving around the physical notch area.
    nonisolated static func hoverHotZone(
        panelFrame: CGRect,
        isExpanded: Bool
    ) -> CGRect {
        let horizontalInset = isExpanded
            ? HoverInsets.expandedHorizontal
            : HoverInsets.collapsedHorizontal
        let verticalInset = isExpanded
            ? HoverInsets.expandedVertical
            : HoverInsets.collapsedVertical
        return panelFrame.insetBy(dx: -horizontalInset, dy: -verticalInset)
    }

    /// Keeping the point containment logic here lets tests assert the hot-zone policy
    /// without needing a real AppKit panel or SwiftUI hosting hierarchy.
    nonisolated static func containsPointer(
        panelFrame: CGRect,
        mouseLocation: CGPoint,
        isExpanded: Bool
    ) -> Bool {
        hoverHotZone(panelFrame: panelFrame, isExpanded: isExpanded).contains(mouseLocation)
    }
}
