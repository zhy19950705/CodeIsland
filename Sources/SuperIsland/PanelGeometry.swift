import AppKit

enum PanelGeometry {
    static let dragThreshold: CGFloat = 5

    nonisolated static func centeredX(
        panelWidth: CGFloat,
        screenFrame: CGRect
    ) -> CGFloat {
        screenFrame.midX - panelWidth / 2
    }

    nonisolated static func clampedX(
        desiredX: CGFloat,
        panelWidth: CGFloat,
        screenFrame: CGRect
    ) -> CGFloat {
        min(max(desiredX, screenFrame.minX), screenFrame.maxX - panelWidth)
    }

    nonisolated static func panelFrame(
        panelSize: NSSize,
        screenFrame: CGRect,
        allowHorizontalDrag: Bool,
        storedHorizontalOffset: CGFloat
    ) -> NSRect {
        let centeredX = centeredX(panelWidth: panelSize.width, screenFrame: screenFrame)
        let dragOffset = allowHorizontalDrag ? storedHorizontalOffset : 0
        let x = clampedX(
            desiredX: centeredX + dragOffset,
            panelWidth: panelSize.width,
            screenFrame: screenFrame
        )
        let y = screenFrame.maxY - panelSize.height
        return NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height)
    }

    nonisolated static func approximatelyEqual(
        _ lhs: NSRect,
        _ rhs: NSRect,
        tolerance: CGFloat = 0.5
    ) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < tolerance
            && abs(lhs.origin.y - rhs.origin.y) < tolerance
            && abs(lhs.size.width - rhs.size.width) < tolerance
            && abs(lhs.size.height - rhs.size.height) < tolerance
    }

    nonisolated static func shouldStartDrag(
        deltaX: CGFloat,
        threshold: CGFloat = dragThreshold
    ) -> Bool {
        abs(deltaX) > threshold
    }

    nonisolated static func draggedFrameOrigin(
        startPanelX: CGFloat,
        mouseDeltaX: CGFloat,
        panelSize: NSSize,
        screenFrame: CGRect
    ) -> NSPoint {
        let x = clampedX(
            desiredX: startPanelX + mouseDeltaX,
            panelWidth: panelSize.width,
            screenFrame: screenFrame
        )
        let y = screenFrame.maxY - panelSize.height
        return NSPoint(x: x, y: y)
    }

    nonisolated static func persistedHorizontalOffset(
        panelOriginX: CGFloat,
        panelWidth: CGFloat,
        screenFrame: CGRect
    ) -> CGFloat {
        panelOriginX - centeredX(panelWidth: panelWidth, screenFrame: screenFrame)
    }
}
