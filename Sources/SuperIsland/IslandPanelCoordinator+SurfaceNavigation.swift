import Foundation

/// UI-triggered surface navigation is deferred one main-queue turn so AppKit and
/// SwiftUI do not try to reconcile list/detail layout changes during the same click.
@MainActor
extension IslandPanelCoordinator {
    func handleDetailBackTap() {
        // Returning from detail should suppress hover reconciliation immediately,
        // but commit the surface swap on the next turn for a smoother transition.
        DispatchQueue.main.async { [weak self] in
            self?.showSessionListSurface()
        }
    }
}
