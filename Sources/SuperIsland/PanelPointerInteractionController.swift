import AppKit

/// Global and local monitors are owned in one place so panel pointer handling has a
/// single lifecycle instead of being split across unrelated window/controller types.
final class PanelPointerInteractionController {
    private static let monitoredEvents: NSEvent.EventTypeMask = [
        .mouseMoved,
        .leftMouseDragged,
        .rightMouseDragged,
        .otherMouseDragged,
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown
    ]

    /// The window controller injects the concrete hover/click policy after its own initialization finishes.
    var handleEvent: (@MainActor (NSEvent?) -> Void)?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    deinit {
        stopObserving()
    }

    /// Replacing monitors on every start keeps recreation idempotent and avoids
    /// duplicate listeners after panel rebuilds or controller reinstantiation.
    func startObserving() {
        stopObserving()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.monitoredEvents) { [weak self] event in
            DispatchQueue.main.async { [weak self] in
                self?.handleEvent?(event)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.monitoredEvents) { [weak self] event in
            DispatchQueue.main.async { [weak self] in
                self?.handleEvent?(event)
            }
            return event
        }
    }

    /// Explicit cleanup prevents monitors from surviving panel/controller teardown.
    func stopObserving() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }
}
