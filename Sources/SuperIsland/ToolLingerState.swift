import SwiftUI
import Observation

@MainActor
@Observable
final class ToolLingerState {
    private(set) var shownTool: String?

    private var hideTask: Task<Void, Never>?

    func update(
        liveTool: String?,
        linger: Duration = .seconds(2),
        revealAnimation: Animation = .easeInOut(duration: 0.2),
        hideAnimation: Animation = .easeOut(duration: 0.3)
    ) {
        hideTask?.cancel()

        guard let liveTool else {
            hideTask = Task { @MainActor in
                try? await Task.sleep(for: linger)
                guard !Task.isCancelled else { return }
                withAnimation(hideAnimation) {
                    shownTool = nil
                }
            }
            return
        }

        withAnimation(revealAnimation) {
            shownTool = liveTool
        }
    }

    func reset(to liveTool: String?, animation: Animation = .easeInOut(duration: 0.2)) {
        hideTask?.cancel()
        withAnimation(animation) {
            shownTool = liveTool
        }
    }

    func cancelPendingHide() {
        hideTask?.cancel()
        hideTask = nil
    }

    deinit {}
}
