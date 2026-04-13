import Foundation

enum SessionFilter {
    private static let codexBarProbeSuffix = "/Library/Application Support/CodexBar/ClaudeProbe"
    private static let codexBarBundleID = "com.steipete.codexbar"

    static func shouldIgnoreSession(source: String?, cwd: String?, termBundleId: String?) -> Bool {
        let normalizedSource = source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedBundle = termBundleId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if let cwd, cwd.hasSuffix(codexBarProbeSuffix) {
            return true
        }

        if normalizedSource == "claude", normalizedBundle == codexBarBundleID {
            return true
        }

        return false
    }
}
