import Foundation

extension AppState {
    // Keep session deeplink resolution in one place so notification entry points
    // and in-app cards consistently target the same backing session.
    func matchingSessionId(cwd: String?, source: String?) -> String? {
        let normalizedCwd = nonEmpty(cwd)
        let normalizedSource = nonEmpty(source)?.lowercased()

        return sessions
            .filter { _, session in
                let cwdMatches = normalizedCwd == nil || session.cwd == normalizedCwd
                let sourceMatches = normalizedSource == nil || session.source == normalizedSource
                return cwdMatches && sourceMatches
            }
            .max { lhs, rhs in
                lhs.value.lastActivity < rhs.value.lastActivity
            }?.key
    }

    @discardableResult
    func jumpToSession(cwd: String?, source: String?) -> String? {
        guard let match = matchingSessionId(cwd: cwd, source: source) else { return nil }
        jumpToSession(match)
        return match
    }
}
