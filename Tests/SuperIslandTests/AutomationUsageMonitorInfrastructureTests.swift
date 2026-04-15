import XCTest
@testable import SuperIsland

final class AutomationUsageMonitorInfrastructureTests: XCTestCase {
    // Cover low-level parsing helpers so future file moves do not silently break token and cookie decoding.
    func testDataFromHexStringDecodesASCIIPayload() {
        let command = UsageMonitorCommand(arguments: [])

        let decoded = command.dataFromHexString("68656C6C6F")

        XCTAssertEqual(decoded, Data("hello".utf8))
    }

    func testExtractClaudeSessionKeyFindsEmbeddedToken() {
        let command = UsageMonitorCommand(arguments: [])
        let payload = Data("prefix sk-ant-demo_123 suffix".utf8)

        let sessionKey = command.extractClaudeSessionKey(from: payload)

        XCTAssertEqual(sessionKey, "sk-ant-demo_123")
    }
}
