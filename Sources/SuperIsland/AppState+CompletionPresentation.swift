extension AppState {
    /// Completion auto-collapse should only advance while the matching completion card is still the active surface.
    func shouldAutoCollapseCompletionCard(sessionId: String) -> Bool {
        guard case .completionCard(let activeCompletionSessionId) = surface else { return false }
        return activeCompletionSessionId == sessionId
    }
}
