import XCTest
@testable import SuperIsland

final class CodexAutoSwitchServiceTests: XCTestCase {
    private var temporaryRoot: URL!
    private var codexHome: URL!
    private var manager: CodexAccountManager!
    private var service: CodexAutoSwitchService!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexAutoSwitchServiceTests-\(UUID().uuidString)", isDirectory: true)
        codexHome = temporaryRoot.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        manager = CodexAccountManager(codexHomeURL: codexHome)
        service = CodexAutoSwitchService(codexHomeURL: codexHome, pollInterval: 0.1)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
    }

    func testRunOnceSwitchesToBetterStoredCandidateWhenActiveQuotaIsLow() throws {
        try writeAuth(
            to: manager.activeAuthURL(),
            email: "active@example.com",
            plan: "pro",
            userID: "user-active",
            accountID: "acct-active",
            accessToken: "access-active"
        )
        _ = try manager.syncCurrentAuth()

        let candidateAuth = temporaryRoot.appendingPathComponent("candidate.json", isDirectory: false)
        try writeAuth(
            to: candidateAuth,
            email: "candidate@example.com",
            plan: "pro",
            userID: "user-candidate",
            accountID: "acct-candidate",
            accessToken: "access-candidate"
        )
        _ = try manager.importPath(candidateAuth)
        _ = try manager.updateConfiguration(autoSwitchEnabled: true, apiUsageEnabled: false)

        _ = try manager.updateUsage(
            for: "user-active::acct-active",
            snapshot: makeUsage(primaryUsed: 95, weeklyUsed: 40)
        )
        _ = try manager.updateUsage(
            for: "user-candidate::acct-candidate",
            snapshot: makeUsage(primaryUsed: 30, weeklyUsed: 20)
        )

        let result = try service.runOnce()
        XCTAssertEqual(result.switchedAccount?.accountKey, "user-candidate::acct-candidate")

        let currentAuth = try XCTUnwrap(CodexAuthStore.load(from: manager.activeAuthURL()))
        XCTAssertEqual(currentAuth.email, "candidate@example.com")
    }

    func testRunOnceUsesLatestRolloutToRefreshActiveUsage() throws {
        try writeAuth(
            to: manager.activeAuthURL(),
            email: "active@example.com",
            plan: "pro",
            userID: "user-active",
            accountID: "acct-active",
            accessToken: "access-active"
        )
        _ = try manager.syncCurrentAuth()
        _ = try manager.updateConfiguration(autoSwitchEnabled: true, apiUsageEnabled: false)

        let sessionsDir = codexHome
            .appendingPathComponent("sessions/2026/04/09", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        let rolloutURL = sessionsDir.appendingPathComponent("rollout-2026-04-09T23-00-00-test.jsonl", isDirectory: false)
        let eventTimestamp = isoTimestamp(from: Date().addingTimeInterval(2))
        let line = """
        {"timestamp":"\(eventTimestamp)","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":55.0,"window_minutes":300,"resets_at":4070908800},"secondary":{"used_percent":10.0,"window_minutes":10080,"resets_at":4071513600},"plan_type":"pro"}}}
        """
        try Data((line + "\n").utf8).write(to: rolloutURL)

        let result = try service.runOnce()
        XCTAssertTrue(result.activeUsageUpdated)

        let status = try manager.status(syncCurrentAuth: false)
        let active = try XCTUnwrap(status.activeAccount)
        XCTAssertEqual(active.lastUsage?.primary?.usedPercent, 55.0)
        let recordedPath = try XCTUnwrap(active.lastLocalRollout?.path)
        XCTAssertTrue(recordedPath.contains("/.codex/sessions/2026/04/09/"))
        XCTAssertEqual(URL(fileURLWithPath: recordedPath).lastPathComponent, rolloutURL.lastPathComponent)
    }

    private func makeUsage(primaryUsed: Double, weeklyUsed: Double) -> CodexRateLimitSnapshot {
        CodexRateLimitSnapshot(
            primary: CodexRateLimitWindow(
                usedPercent: primaryUsed,
                windowMinutes: 300,
                resetsAt: Int(Date().timeIntervalSince1970) + 3600
            ),
            secondary: CodexRateLimitWindow(
                usedPercent: weeklyUsed,
                windowMinutes: 10080,
                resetsAt: Int(Date().timeIntervalSince1970) + 86_400
            ),
            credits: nil,
            planType: "pro"
        )
    }

    private func writeAuth(
        to url: URL,
        email: String,
        plan: String,
        userID: String,
        accountID: String,
        accessToken: String
    ) throws {
        let authJSON = """
        {
          "tokens": {
            "access_token": "\(accessToken)",
            "refresh_token": "refresh-\(accountID)",
            "account_id": "\(accountID)",
            "id_token": "\(makeJWT(payload: [
                "email": email,
                "https://api.openai.com/auth": [
                    "chatgpt_account_id": accountID,
                    "chatgpt_user_id": userID,
                    "chatgpt_plan_type": plan,
                ],
            ]))"
          },
          "last_refresh": "2026-04-09T08:00:00Z"
        }
        """
        try Data(authJSON.utf8).write(to: url)
    }

    private func makeJWT(payload: [String: Any]) -> String {
        let header = ["alg": "none", "typ": "JWT"]
        let headerData = try! JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
        let payloadData = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return "\(base64url(headerData)).\(base64url(payloadData)).sig"
    }

    private func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func isoTimestamp(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
