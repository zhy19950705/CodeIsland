import SuperIslandCore

enum SessionVisibilityPolicy {
    static func shouldHideWhenNoSession(
        hideWhenNoSession: Bool,
        sessions: [String: SessionSnapshot]
    ) -> Bool {
        hideWhenNoSession && sessions.isEmpty
    }
}
