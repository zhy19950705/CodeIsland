import XCTest
import Darwin
@testable import SuperIsland

@MainActor
final class HookServerTests: XCTestCase {
    override func tearDown() {
        unsetenv("SUPERISLAND_SOCKET_PATH")
        super.tearDown()
    }

    func testAutoApprovedPermissionReturnsAllowWithoutQueueing() async throws {
        let socketPath = uniqueSocketPath()
        setenv("SUPERISLAND_SOCKET_PATH", socketPath, 1)

        let appState = AppState()
        let server = HookServer(appState: appState)
        server.start()
        defer {
            server.stop()
            appState.teardown()
            unlink(socketPath)
        }

        try waitForSocket(at: socketPath)

        let payload = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "PermissionRequest",
            "session_id": "session-auto-approve",
            "tool_name": "TaskCreate",
            "_source": "claude",
        ])

        let response = try await Task.detached {
            try Self.sendAndReceive(payload, socketPath: socketPath)
        }.value
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: response) as? [String: Any])
        let output = try XCTUnwrap(object["hookSpecificOutput"] as? [String: Any])
        let decision = try XCTUnwrap(output["decision"] as? [String: Any])

        XCTAssertEqual(output["hookEventName"] as? String, "PermissionRequest")
        XCTAssertEqual(decision["behavior"] as? String, "allow")
        XCTAssertTrue(appState.permissionQueue.isEmpty)
        XCTAssertTrue(appState.sessions.isEmpty)
    }

    func testOversizedPayloadClosesConnectionWithoutResponse() async throws {
        let socketPath = uniqueSocketPath()
        setenv("SUPERISLAND_SOCKET_PATH", socketPath, 1)

        let appState = AppState()
        let server = HookServer(appState: appState)
        server.start()
        defer {
            server.stop()
            appState.teardown()
            unlink(socketPath)
        }

        try waitForSocket(at: socketPath)

        let payload = Data(repeating: 0x61, count: 1_048_577)
        let response = try await Task.detached {
            try Self.sendAndReceive(payload, socketPath: socketPath)
        }.value

        XCTAssertTrue(response.isEmpty)
        XCTAssertTrue(appState.sessions.isEmpty)
        XCTAssertTrue(appState.permissionQueue.isEmpty)
        XCTAssertTrue(appState.questionQueue.isEmpty)
    }

    private func uniqueSocketPath() -> String {
        "/tmp/superisland-\(UUID().uuidString.prefix(8)).sock"
    }

    private func waitForSocket(at path: String, timeout: TimeInterval = 2) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: path) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTFail("Timed out waiting for socket at \(path)")
    }

    nonisolated private static func sendAndReceive(_ payload: Data, socketPath: String) throws -> Data {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }

        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        let setTimeoutResult = withUnsafePointer(to: &timeout) { pointer in
            setsockopt(
                fd,
                SOL_SOCKET,
                SO_RCVTIMEO,
                pointer,
                socklen_t(MemoryLayout<timeval>.stride)
            )
        }
        XCTAssertEqual(setTimeoutResult, 0)

        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.stride)
        address.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        XCTAssertLessThanOrEqual(pathBytes.count, capacity)

        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            let rawPointer = UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self)
            for (index, byte) in pathBytes.enumerated() {
                rawPointer[index] = byte
            }
        }

        let addressLength = socklen_t(MemoryLayout.offset(of: \sockaddr_un.sun_path)! + pathBytes.count)
        let didConnect = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketPointer in
                connect(fd, socketPointer, addressLength)
            }
        }
        XCTAssertEqual(didConnect, 0)

        let didWrite = payload.withUnsafeBytes { rawBuffer -> Int in
            guard let baseAddress = rawBuffer.baseAddress else { return -1 }
            var totalWritten = 0
            while totalWritten < rawBuffer.count {
                let written = write(fd, baseAddress.advanced(by: totalWritten), rawBuffer.count - totalWritten)
                if written <= 0 {
                    return -1
                }
                totalWritten += written
            }
            return totalWritten
        }
        XCTAssertEqual(didWrite, payload.count)

        shutdown(fd, SHUT_WR)

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                response.append(buffer, count: count)
                continue
            }
            if count < 0, errno == EAGAIN {
                break
            }
            XCTAssertGreaterThanOrEqual(count, 0)
            break
        }
        return response
    }
}
