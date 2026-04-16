import AppKit

/// Pointer-specific behavior stays in its own extension so the main interaction file
/// remains readable and within the repository's single-file size constraint.
@MainActor
extension PanelWindowController {
    /// Pointer activity from global/local monitors is funneled through one method so
    /// hover, click-away collapse, and suppression logic stay ordered consistently.
    func handlePointerEvent(_ event: NSEvent?) {
        let mouseLocation = event.map(pointerLocation(for:)) ?? NSEvent.mouseLocation

        if let event, Self.isMouseDownEvent(event.type) {
            handleOutsidePointerDownIfNeeded(at: mouseLocation)
        }

        reconcilePointerHoverState(at: mouseLocation)
    }

    /// Hover tracking is skipped when the panel is hidden, but transient state is still
    /// cleared so collapsed visuals do not get stuck in a hovered appearance.
    func reconcilePointerHoverState(at mouseLocation: CGPoint = NSEvent.mouseLocation) {
        guard shouldTrackPointerHover else {
            appState.panelCoordinator.cancelPendingInteraction()
            return
        }

        let insideInteractiveRegion = isPointerInsideInteractiveRegion(mouseLocation: mouseLocation)
        appState.panelCoordinator.handleHover(
            inside: insideInteractiveRegion,
            hoverActivationDelay: currentHoverActivationDelay(),
            collapseOnMouseLeave: SettingsManager.shared.collapseOnMouseLeave
        )
    }

    /// Hidden or menu-bar-only modes should never schedule hover transitions from the
    /// background pointer monitors.
    private var shouldTrackPointerHover: Bool {
        guard let panel, panel.isVisible else { return false }
        guard shouldShowPanel(on: chosenScreen()) else { return false }
        return !isDraggingPanel
    }

    /// Collapsed state uses an expanded hot zone, while fullscreen reveal remains an
    /// explicit separate zone for displays without a physical notch.
    private func isPointerInsideInteractiveRegion(mouseLocation: CGPoint) -> Bool {
        guard let panel else { return false }
        let metrics = renderMetrics(for: chosenScreen())

        if isMouseInFullscreenRevealZone(
            panelWidth: panel.frame.width,
            notchWidth: metrics.notchWidth,
            hasNotch: metrics.hasNotch
        ) {
            return true
        }

        return PanelPointerGeometry.containsPointer(
            panelFrame: panel.frame,
            mouseLocation: mouseLocation,
            isExpanded: appState.surface.isExpanded
        )
    }

    /// Click-away collapse now shares the same input stream as hover tracking, which
    /// removes the old split between global monitors, window reposting, and coordinator calls.
    private func handleOutsidePointerDownIfNeeded(at mouseLocation: CGPoint) {
        guard appState.surface.isExpanded else { return }

        switch appState.surface {
        case .approvalCard, .questionCard:
            return
        default:
            break
        }

        guard let panel, !panel.frame.contains(mouseLocation) else { return }
        appState.panelCoordinator.collapseAfterOutsideClick()
    }

    /// The current screen-space pointer location is used for both local and global monitors.
    private func pointerLocation(for event: NSEvent) -> CGPoint {
        guard let window = event.window else { return NSEvent.mouseLocation }
        return window.convertPoint(toScreen: event.locationInWindow)
    }

    /// Mouse-down events are the only pointer events that can trigger click-away collapse.
    private nonisolated static func isMouseDownEvent(_ type: NSEvent.EventType) -> Bool {
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return true
        default:
            return false
        }
    }

    /// Fullscreen edge reveal keeps its own hover delay so top-edge activation stays controlled.
    private func currentHoverActivationDelay() -> TimeInterval {
        let settings = SettingsManager.shared
        return isFullscreenEdgeRevealActive
            ? settings.fullscreenHoverActivationDelay
            : settings.hoverActivationDelay
    }
}
