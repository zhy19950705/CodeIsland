import XCTest
import SuperIslandCore
@testable import SuperIsland

final class BlockingInteractionCoordinatorTests: XCTestCase {
    func testPermissionAllowResponseIncludesSessionRuleWhenAlwaysEnabled() throws {
        let event = HookEvent(
            eventName: "PermissionRequest",
            sessionId: "session-1",
            toolName: "Write",
            toolInput: nil,
            rawJSON: [:]
        )

        let data = BlockingInteractionCoordinator.permissionAllowResponse(event: event, always: true)
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let output = try XCTUnwrap(payload["hookSpecificOutput"] as? [String: Any])
        let decision = try XCTUnwrap(output["decision"] as? [String: Any])
        let updatedPermissions = try XCTUnwrap(decision["updatedPermissions"] as? [[String: Any]])
        let firstRule = try XCTUnwrap(updatedPermissions.first?["rules"] as? [[String: String]])

        XCTAssertEqual(decision["behavior"] as? String, "allow")
        XCTAssertEqual(firstRule.first?["toolName"], "Write")
        XCTAssertEqual(firstRule.first?["ruleContent"], "*")
    }

    func testQuestionSkipResponseDeniesUnderlyingPermissionForAskUserQuestion() throws {
        let data = BlockingInteractionCoordinator.questionSkipResponse(isFromPermission: true)
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let output = try XCTUnwrap(payload["hookSpecificOutput"] as? [String: Any])
        let decision = try XCTUnwrap(output["decision"] as? [String: Any])

        XCTAssertEqual(output["hookEventName"] as? String, "PermissionRequest")
        XCTAssertEqual(decision["behavior"] as? String, "deny")
    }

    func testNextPresentationPrefersPermissionBeforeQuestionAndCollapsesWhenQueuesDrain() {
        let permission = PermissionRequest(
            event: HookEvent(eventName: "PermissionRequest", sessionId: "permission", toolName: "Write", toolInput: nil, rawJSON: [:]),
            approveAction: { _ in },
            denyAction: {}
        )
        let question = QuestionRequest(
            event: HookEvent(eventName: "Notification", sessionId: "question", toolName: nil, toolInput: nil, rawJSON: [:]),
            question: QuestionPayload(question: "Ship it?", options: nil),
            answerAction: { _ in },
            skipAction: {}
        )

        let permissionState = BlockingInteractionCoordinator.nextPresentation(
            permissionQueue: [permission],
            questionQueue: [question],
            currentSurface: .questionCard(sessionId: "question")
        )
        XCTAssertEqual(permissionState?.activeSessionId, "permission")
        XCTAssertEqual(permissionState?.surface, .approvalCard(sessionId: "permission"))

        let collapsedState = BlockingInteractionCoordinator.nextPresentation(
            permissionQueue: [],
            questionQueue: [],
            currentSurface: .approvalCard(sessionId: "permission")
        )
        XCTAssertEqual(collapsedState?.surface, .collapsed)
        XCTAssertNil(collapsedState?.activeSessionId)
    }
}
