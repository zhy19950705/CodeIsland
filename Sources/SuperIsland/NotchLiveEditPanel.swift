import AppKit

/// Pass clicks through unless a concrete live-edit control wants them.
final class NotchLiveEditContentView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        for subview in subviews where subview.frame.contains(point) {
            if let target = subview.hitTest(convert(point, to: subview)) {
                return target
            }
        }
        return nil
    }
}

/// Floating panel that hosts the live notch editing controls near the menu bar.
final class NotchLiveEditPanel: NSPanel {
    init(screen: NSScreen) {
        let panelHeight: CGFloat = 170
        let screenFrame = screen.frame
        let frame = NSRect(
            x: screenFrame.minX,
            y: screenFrame.maxY - panelHeight,
            width: screenFrame.width,
            height: panelHeight
        )

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        isMovableByWindowBackground = false
        hasShadow = false
        isOpaque = false
        backgroundColor = .clear
        level = .mainMenu + 4
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        contentView = NotchLiveEditContentView(frame: NSRect(origin: .zero, size: frame.size))
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
