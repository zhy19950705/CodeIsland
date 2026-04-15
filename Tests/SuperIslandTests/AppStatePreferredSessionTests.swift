import XCTest
import SuperIslandCore
@testable import SuperIsland

@MainActor
final class AppStatePreferredSessionTests: XCTestCase {
    func testPreferredSessionIdUsesMostRecentlyActiveNonIdleSession() {
        let appState = AppState()
        let now = Date()
        var idle = SessionSnapshot()
        idle.status = .idle
        idle.lastActivity = now.addingTimeInterval(-10)
        var olderActive = SessionSnapshot()
        olderActive.status = .running
        olderActive.lastActivity = now.addingTimeInterval(-20)
        var newerActive = SessionSnapshot()
        newerActive.status = .processing
        newerActive.lastActivity = now

        appState.sessions = [
            "idle": idle,
            "older-active": olderActive,
            "newer-active": newerActive,
        ]

        XCTAssertEqual(appState.preferredSessionId, "newer-active")
    }

    func testPreferredSessionIdFallsBackToStableSortedSessionIdWhenAllIdle() {
        let appState = AppState()
        let now = Date()
        var bravo = SessionSnapshot()
        bravo.status = .idle
        bravo.lastActivity = now
        var alpha = SessionSnapshot()
        alpha.status = .idle
        alpha.lastActivity = now.addingTimeInterval(10)

        appState.sessions = [
            "bravo": bravo,
            "alpha": alpha,
        ]

        XCTAssertEqual(appState.preferredSessionId, "alpha")
    }
}
