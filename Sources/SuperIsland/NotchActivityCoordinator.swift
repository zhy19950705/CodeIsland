import SwiftUI
import SuperIslandCore

/// Side-expansion variants used by the compact notch state.
enum NotchActivityType: Equatable {
    case none
    case processing
    case blocking
    case boot
}

/// Small render model for the collapsed island's temporary side growth.
struct ExpandingActivity: Equatable {
    var show = false
    var type: NotchActivityType = .none
    var extraWidth: CGFloat = 0

    static let empty = ExpandingActivity()
}

/// Keeps side-expansion logic out of the view so width changes have one source of truth.
@MainActor
final class NotchActivityCoordinator: ObservableObject {
    static let shared = NotchActivityCoordinator()

    @Published private(set) var expandingActivity: ExpandingActivity = .empty

    private var autoHideTask: Task<Void, Never>?

    /// View code only needs the final width delta, not the full activity payload.
    var currentExtraWidth: CGFloat {
        expandingActivity.show ? expandingActivity.extraWidth : 0
    }

    /// Keep expansion behavior deterministic across collapsed, blocking, and running states.
    func sync(status: AgentStatus, isExpanded: Bool, hasBlockingCard: Bool) {
        guard !isExpanded else {
            hideActivity()
            return
        }

        if hasBlockingCard {
            showActivity(type: .blocking, extraWidth: 28)
            return
        }

        if status != .idle {
            showActivity(type: .processing, extraWidth: 20)
            return
        }

        hideActivity()
    }

    /// Short startup pulse helps users discover the island without keeping it open.
    func showBootPulse() {
        showActivity(type: .boot, extraWidth: 24, duration: 0.9)
    }

    /// Optional duration supports transient activities such as boot or future notifications.
    func showActivity(
        type: NotchActivityType,
        extraWidth: CGFloat,
        duration: TimeInterval = 0
    ) {
        autoHideTask?.cancel()

        withAnimation(.smooth(duration: 0.24)) {
            expandingActivity = ExpandingActivity(
                show: true,
                type: type,
                extraWidth: extraWidth
            )
        }

        guard duration > 0 else { return }
        autoHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled else { return }
            hideActivity()
        }
    }

    /// Cancel any pending auto-hide before retracting so repeated updates do not fight each other.
    func hideActivity() {
        autoHideTask?.cancel()
        autoHideTask = nil

        guard expandingActivity != .empty else { return }
        withAnimation(.smooth(duration: 0.24)) {
            expandingActivity = .empty
        }
    }
}
