import XCTest
@testable import SuperIsland

@MainActor
final class SessionDiscoveryServiceTests: XCTestCase {
    func testStartTriggersInitialRestoreAndScan() async {
        let service = SessionDiscoveryService(
            projectsPath: NSTemporaryDirectory().appending("missing-projects-path"),
            cleanupInterval: 3600
        )

        let restoreExpectation = expectation(description: "restore")
        let scanExpectation = expectation(description: "scan")

        service.start(
            onCleanup: {},
            restoreStartup: {
                restoreExpectation.fulfill()
            },
            scanLiveSessions: {
                scanExpectation.fulfill()
            }
        )

        await fulfillment(of: [restoreExpectation, scanExpectation], timeout: 1)
        service.stop()
    }
}
