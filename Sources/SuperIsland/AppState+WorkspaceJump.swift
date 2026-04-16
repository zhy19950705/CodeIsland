import AppKit
import Foundation
import SuperIslandCore

extension AppState {
    /// Editor jumps intentionally bypass terminal focus so the detail footer can expose a dedicated workspace action.
    @MainActor
    func openSessionEditor(_ sessionId: String) {
        guard let session = sessions[sessionId] else { return }
        acknowledgePendingCompletionReview(for: sessionId)
        _ = WorkspaceJumpManager().openEditor(for: session, sessionId: sessionId)
    }

    /// Detail surfaces resolve their secondary action through the lightweight path so view rendering never blocks on CLI probes.
    @MainActor
    func resolvedSessionEditorTarget(_ sessionId: String) -> WorkspaceJumpManager.JumpTarget? {
        guard let session = sessions[sessionId] else { return nil }
        return WorkspaceJumpManager().resolvedPresentationEditorTarget(for: session)
    }

    /// The detail footer reuses the resolved editor target icon so users can distinguish app handoffs at a glance.
    @MainActor
    func resolvedSessionEditorIcon(_ target: WorkspaceJumpManager.JumpTarget) -> NSImage? {
        WorkspaceJumpManager().applicationIcon(for: target)
    }
}
