import SuperIslandCore

enum SessionJumpRouter {
    @MainActor
    static func jump(to session: SessionSnapshot, sessionId: String) {
        let jumpManager = WorkspaceJumpManager()

        if session.isNativeAppMode || session.isIDETerminal {
            if jumpManager.openWorkspace(for: session, sessionId: sessionId) {
                return
            }
            _ = TerminalActivator.activate(session: session, sessionId: sessionId)
            return
        }

        let didPreciseFocus = TerminalActivator.activate(session: session, sessionId: sessionId)
        if !didPreciseFocus {
            _ = jumpManager.openWorkspace(for: session, sessionId: sessionId)
        }
    }
}
