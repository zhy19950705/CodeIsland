import XCTest
@testable import SuperIsland

@MainActor
final class CodexRefreshServiceTests: XCTestCase {
    func testLatestTurnIdsAreStoredForAllIdentifiers() {
        let service = CodexRefreshService(readThread: { _ in
            XCTFail("readThread should not be called")
            throw CancellationError()
        })

        service.storeLatestTurnId("turn-1", for: ["thread-1", "session-1"])

        XCTAssertEqual(service.latestTurnId(for: ["thread-1"]), "turn-1")
        XCTAssertEqual(service.latestTurnId(for: ["session-1"]), "turn-1")
        XCTAssertTrue(service.hasLatestTurnId(for: ["missing", "session-1"]))
    }

    func testRequestRefreshHonorsMinimumInterval() async {
        let service = CodexRefreshService(readThread: { threadId in
            CodexAppThreadSnapshot(
                threadId: threadId,
                title: nil,
                cwd: nil,
                updatedAt: Date(),
                status: .processing,
                latestTurnId: nil,
                lastUserText: nil,
                lastAssistantText: nil,
                recentMessages: []
            )
        })

        var refreshCalls = 0
        await service.performRefreshIfNeeded(
            isEnabled: true,
            trackedThreadIds: ["thread-1"],
            applySnapshot: { _ in
                refreshCalls += 1
                return false
            },
            didChange: {}
        )

        service.requestRefresh(minimumInterval: 60) {
            refreshCalls += 10
        }

        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(refreshCalls, 1)
    }
}
