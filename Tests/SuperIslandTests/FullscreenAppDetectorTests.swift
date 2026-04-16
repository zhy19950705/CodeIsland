import XCTest
@testable import SuperIsland

final class FullscreenAppDetectorTests: XCTestCase {
    func testTreatsExactScreenSizedWindowAsFullscreen() {
        XCTAssertTrue(
            FullscreenAppDetector.isWindowEffectivelyFullscreen(
                windowFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)
            )
        )
    }

    func testRejectsCommonMaximizedWindowThatStillLeavesBreathingRoom() {
        XCTAssertFalse(
            FullscreenAppDetector.isWindowEffectivelyFullscreen(
                windowFrame: CGRect(x: 0, y: 0, width: 1470, height: 940),
                screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)
            )
        )
    }

    func testRejectsWindowOnDifferentScreen() {
        XCTAssertFalse(
            FullscreenAppDetector.isWindowEffectivelyFullscreen(
                windowFrame: CGRect(x: 1600, y: 0, width: 1512, height: 982),
                screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)
            )
        )
    }
}
