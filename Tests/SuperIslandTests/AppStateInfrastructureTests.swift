import XCTest
@testable import SuperIsland

final class AppStateInfrastructureTests: XCTestCase {
    func testDerivedStateRefreshDelayReturnsNilAfterIntervalExpires() {
        let now = Date()

        XCTAssertNil(
            AppState.derivedStateRefreshDelay(
                now: now,
                lastRefreshAt: now.addingTimeInterval(-0.2)
            )
        )
    }

    func testDerivedStateRefreshDelayReturnsRemainingWindowDuringBurst() throws {
        let now = Date()
        let delay = try XCTUnwrap(
            AppState.derivedStateRefreshDelay(
                now: now,
                lastRefreshAt: now.addingTimeInterval(-0.01)
            )
        )

        XCTAssertGreaterThan(delay, 0)
        XCTAssertLessThanOrEqual(delay, AppRuntimeConstants.derivedStateRefreshInterval)
    }

    func testSyntheticAgentWorktreeDetectionIsCentralized() {
        XCTAssertTrue(SessionFilter.isSyntheticAgentWorktree("/tmp/demo/.claude/worktrees/agent-123"))
        XCTAssertTrue(SessionFilter.isSyntheticAgentWorktree("/tmp/demo/.git/worktrees/agent-123"))
        XCTAssertFalse(SessionFilter.isSyntheticAgentWorktree("/tmp/demo/project"))
    }
}
