import AppKit
import XCTest
@testable import SuperIsland

final class NotchHardwareDetectorTests: XCTestCase {
    func testFallbackVirtualWidthClampsToExpectedRange() {
        XCTAssertEqual(NotchHardwareDetector.fallbackVirtualWidth(for: 900), 160, accuracy: 0.001)
        XCTAssertEqual(NotchHardwareDetector.fallbackVirtualWidth(for: 1728), 240, accuracy: 0.001)
        XCTAssertEqual(NotchHardwareDetector.fallbackVirtualWidth(for: 4000), 240, accuracy: 0.001)
    }

    func testResolvedNotchWidthPrefersOverrideBeforeHardwareMetrics() {
        let screen = NSScreen.main ?? NSScreen()
        let width = NotchHardwareDetector.resolvedNotchWidth(
            on: screen,
            mode: .forceVirtual,
            override: 222
        )

        XCTAssertEqual(width, 222, accuracy: 0.001)
    }

    func testClampedHorizontalOffsetKeepsIslandInsideScreenBounds() {
        let offset = NotchHardwareDetector.clampedHorizontalOffset(
            storedOffset: 500,
            runtimeWidth: 420,
            screenFrame: CGRect(x: 100, y: 50, width: 1440, height: 900)
        )

        XCTAssertEqual(offset, 500, accuracy: 0.001)
    }

    func testClampedHeightStaysWithinSupportedRange() {
        XCTAssertEqual(NotchHardwareDetector.clampedHeight(8), 20, accuracy: 0.001)
        XCTAssertEqual(NotchHardwareDetector.clampedHeight(40), 40, accuracy: 0.001)
        XCTAssertEqual(NotchHardwareDetector.clampedHeight(120), 80, accuracy: 0.001)
    }
}
