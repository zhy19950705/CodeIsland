import XCTest
@testable import SuperIsland

final class CodexAccountManagerTests: XCTestCase {
    private var temporaryRoot: URL!
    private var codexHome: URL!
    private var manager: CodexAccountManager!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexAccountManagerTests-\(UUID().uuidString)", isDirectory: true)
        codexHome = temporaryRoot.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        manager = CodexAccountManager(codexHomeURL: codexHome)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
    }

    func testSyncCurrentAuthImportsAndActivatesManagedAccount() throws {
        let authURL = manager.activeAuthURL()
        try writeAuth(
            to: authURL,
            email: "first@example.com",
            plan: "team",
            userID: "user-1",
            accountID: "acct-1",
            accessToken: "access-1"
        )

        let activeAccount = try XCTUnwrap(try manager.syncCurrentAuth())
        XCTAssertEqual(activeAccount.email, "first@example.com")
        XCTAssertEqual(activeAccount.accountKey, "user-1::acct-1")

        let status = try manager.status(syncCurrentAuth: false)
        XCTAssertEqual(status.registry.accounts.count, 1)
        XCTAssertEqual(status.activeAccount?.accountKey, "user-1::acct-1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.snapshotURL(for: "user-1::acct-1").path))
    }

    func testSwitchAccountUpdatesActiveAuthAndCreatesBackup() throws {
        try writeAuth(
            to: manager.activeAuthURL(),
            email: "first@example.com",
            plan: "plus",
            userID: "user-1",
            accountID: "acct-1",
            accessToken: "access-1"
        )
        _ = try manager.syncCurrentAuth()

        let secondAuth = temporaryRoot.appendingPathComponent("second.json", isDirectory: false)
        try writeAuth(
            to: secondAuth,
            email: "second@example.com",
            plan: "pro",
            userID: "user-2",
            accountID: "acct-2",
            accessToken: "access-2"
        )
        let summary = try manager.importPath(secondAuth)
        XCTAssertEqual(summary.importedCount, 1)

        let switched = try manager.switchAccount(matching: "second@example.com")
        XCTAssertEqual(switched.accountKey, "user-2::acct-2")

        let currentAuth = try XCTUnwrap(CodexAuthStore.load(from: manager.activeAuthURL()))
        XCTAssertEqual(currentAuth.email, "second@example.com")
        XCTAssertEqual(currentAuth.accessToken, "access-2")

        let backups = try FileManager.default.contentsOfDirectory(
            at: manager.accountsDirectoryURL(),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        XCTAssertTrue(backups.contains(where: { $0.lastPathComponent.hasPrefix("auth.json.bak.") }))
    }

    func testRemovingActiveAccountPromotesBestRemainingAccount() throws {
        try writeAuth(
            to: manager.activeAuthURL(),
            email: "first@example.com",
            plan: "team",
            userID: "user-1",
            accountID: "acct-1",
            accessToken: "access-1"
        )
        _ = try manager.syncCurrentAuth()

        let secondAuth = temporaryRoot.appendingPathComponent("second.json", isDirectory: false)
        try writeAuth(
            to: secondAuth,
            email: "second@example.com",
            plan: "team",
            userID: "user-2",
            accountID: "acct-2",
            accessToken: "access-2"
        )
        _ = try manager.importPath(secondAuth)
        _ = try manager.switchAccount(matching: "second@example.com")

        let removed = try manager.removeAccounts(accountKey: "user-2::acct-2")
        XCTAssertEqual(removed.map(\.email), ["second@example.com"])

        let status = try manager.status(syncCurrentAuth: false)
        XCTAssertEqual(status.activeAccount?.accountKey, "user-1::acct-1")

        let currentAuth = try XCTUnwrap(CodexAuthStore.load(from: manager.activeAuthURL()))
        XCTAssertEqual(currentAuth.email, "first@example.com")
        XCTAssertEqual(currentAuth.accessToken, "access-1")
    }

    func testImportCpaFileCreatesStandardManagedSnapshot() throws {
        let cpaURL = temporaryRoot.appendingPathComponent("cpa.json", isDirectory: false)
        let cpaJSON = """
        {
          "id_token": "\(makeJWT(payload: [
              "email": "cpa@example.com",
              "https://api.openai.com/auth": [
                  "chatgpt_account_id": "acct-cpa",
                  "chatgpt_user_id": "user-cpa",
                  "chatgpt_plan_type": "team",
              ],
          ]))",
          "access_token": "access-cpa",
          "refresh_token": "refresh-cpa",
          "account_id": "acct-cpa",
          "last_refresh": "2026-04-09T08:00:00Z"
        }
        """
        try Data(cpaJSON.utf8).write(to: cpaURL)

        let summary = try manager.importPath(cpaURL, cpa: true)
        XCTAssertEqual(summary.importedCount, 1)

        let stored = try XCTUnwrap(CodexAuthStore.load(from: manager.snapshotURL(for: "user-cpa::acct-cpa")))
        XCTAssertEqual(stored.email, "cpa@example.com")
        XCTAssertEqual(stored.accessToken, "access-cpa")
        XCTAssertEqual(stored.recordKey, "user-cpa::acct-cpa")
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
}
