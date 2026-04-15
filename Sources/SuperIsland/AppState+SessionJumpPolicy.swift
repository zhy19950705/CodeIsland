import SuperIslandCore

extension AppState {
    func shouldAutoResumeOnJump(for session: SessionSnapshot, sessionId: String) -> Bool {
        guard SessionResumeSupport.resumeCommand(for: session, sessionId: sessionId) != nil else {
            return false
        }

        switch session.source {
        case "claude":
            // Offline Claude snapshots are more useful to resume than to reopen as a plain workspace.
            return session.status == .idle && processMonitors[sessionId] == nil
        default:
            return false
        }
    }

    func shouldAutoResumeOnJumpForTesting(sessionId: String) -> Bool {
        guard let session = sessions[sessionId] else { return false }
        return shouldAutoResumeOnJump(for: session, sessionId: sessionId)
    }

    func shouldValidateCodexJump(for session: SessionSnapshot) -> Bool {
        // Only Codex native-app sessions need thread validation. Terminal-hosted Codex
        // sessions should jump immediately so list-card clicks are never blocked on app-server IO.
        session.source == "codex" && session.isNativeAppMode
    }

    func shouldValidateCodexJumpForTesting(sessionId: String) -> Bool {
        guard let session = sessions[sessionId] else { return false }
        return shouldValidateCodexJump(for: session)
    }
}
