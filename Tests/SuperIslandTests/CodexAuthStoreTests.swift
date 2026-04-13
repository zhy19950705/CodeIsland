import XCTest
@testable import SuperIsland

final class CodexAuthStoreTests: XCTestCase {
    func testParseChatGPTAuthExtractsIdentityAndAccessToken() throws {
        let authJSON = """
        {
          "tokens": {
            "access_token": "access-123",
            "account_id": "acct-123",
            "id_token": "\(makeJWT(payload: [
                "email": "User@Example.com",
                "https://api.openai.com/auth": [
                    "chatgpt_account_id": "acct-123",
                    "chatgpt_user_id": "user-456",
                    "chatgpt_plan_type": "team",
                ],
            ]))"
          },
          "last_refresh": "2026-04-09T08:00:00Z"
        }
        """

        let snapshot = try XCTUnwrap(try CodexAuthStore.parse(data: Data(authJSON.utf8)))
        XCTAssertEqual(snapshot.authMode, .chatgpt)
        XCTAssertEqual(snapshot.email, "user@example.com")
        XCTAssertEqual(snapshot.planType, "team")
        XCTAssertEqual(snapshot.chatgptAccountId, "acct-123")
        XCTAssertEqual(snapshot.chatgptUserId, "user-456")
        XCTAssertEqual(snapshot.recordKey, "user-456::acct-123")
        XCTAssertEqual(snapshot.accessToken, "access-123")
        XCTAssertEqual(snapshot.lastRefresh, "2026-04-09T08:00:00Z")
        XCTAssertTrue(snapshot.isConsistentAccount)
    }

    func testParseChatGPTAuthFallsBackToLegacyUserIDClaim() throws {
        let authJSON = """
        {
          "tokens": {
            "access_token": "access-123",
            "account_id": "acct-123",
            "id_token": "\(makeJWT(payload: [
                "email": "legacy@example.com",
                "https://api.openai.com/auth": [
                    "chatgpt_account_id": "acct-123",
                    "user_id": "legacy-user",
                    "chatgpt_plan_type": "plus",
                ],
            ]))"
          }
        }
        """

        let snapshot = try XCTUnwrap(try CodexAuthStore.parse(data: Data(authJSON.utf8)))
        XCTAssertEqual(snapshot.chatgptUserId, "legacy-user")
        XCTAssertEqual(snapshot.recordKey, "legacy-user::acct-123")
        XCTAssertEqual(snapshot.planType, "plus")
    }

    func testParseAPIKeyAuthMarksModeWithoutChatGPTIdentity() throws {
        let authJSON = """
        {
          "OPENAI_API_KEY": "sk-test"
        }
        """

        let snapshot = try XCTUnwrap(try CodexAuthStore.parse(data: Data(authJSON.utf8)))
        XCTAssertEqual(snapshot.authMode, .apiKey)
        XCTAssertNil(snapshot.email)
        XCTAssertNil(snapshot.accessToken)
        XCTAssertNil(snapshot.recordKey)
        XCTAssertFalse(snapshot.isConsistentAccount)
    }

    func testParseMismatchKeepsBestEffortSnapshotButDropsRecordKey() throws {
        let authJSON = """
        {
          "tokens": {
            "access_token": "access-123",
            "account_id": "acct-a",
            "id_token": "\(makeJWT(payload: [
                "email": "user@example.com",
                "https://api.openai.com/auth": [
                    "chatgpt_account_id": "acct-b",
                    "chatgpt_user_id": "user-456",
                    "chatgpt_plan_type": "pro",
                ],
            ]))"
          }
        }
        """

        let snapshot = try XCTUnwrap(try CodexAuthStore.parse(data: Data(authJSON.utf8)))
        XCTAssertEqual(snapshot.accessToken, "access-123")
        XCTAssertEqual(snapshot.chatgptAccountId, "acct-a")
        XCTAssertEqual(snapshot.chatgptUserId, "user-456")
        XCTAssertNil(snapshot.recordKey)
        XCTAssertFalse(snapshot.isConsistentAccount)
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
