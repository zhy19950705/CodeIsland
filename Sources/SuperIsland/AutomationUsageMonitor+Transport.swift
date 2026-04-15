import Foundation
import Darwin
import SuperIslandCore

extension UsageMonitorCommand {
    // Keep synchronous transport helpers out of the orchestration file so provider code can share one request path.
    func fetchJSON(url: URL, headers: [String: String]) -> [String: Any]? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let semaphore = DispatchSemaphore(value: 0)
        var result: [String: Any]?

        URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            result = object
        }.resume()

        _ = semaphore.wait(timeout: .now() + 35)
        return result
    }

    func fetchJSONResponse(url: URL, headers: [String: String]) -> (statusCode: Int, object: [String: Any]?)? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let semaphore = DispatchSemaphore(value: 0)
        var statusCode = 0
        var result: [String: Any]?

        URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let httpResponse = response as? HTTPURLResponse else {
                return
            }

            statusCode = httpResponse.statusCode
            guard let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            result = object
        }.resume()

        _ = semaphore.wait(timeout: .now() + 35)
        guard statusCode > 0 else { return nil }
        return (statusCode, result)
    }

    func fetchJSONArray(url: URL, headers: [String: String]) -> [[String: Any]]? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let semaphore = DispatchSemaphore(value: 0)
        var result: [[String: Any]]?

        URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return
            }
            result = object
        }.resume()

        _ = semaphore.wait(timeout: .now() + 35)
        return result
    }

    func sendToSocket(_ data: Data) -> String? {
        for candidate in socketCandidates() where UnixSocketSender.send(data, to: candidate) {
            return candidate
        }
        return nil
    }

    func runProcess(executable: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func debug(_ message: String) {
        guard isVerbose else { return }
        FileHandle.standardError.write(Data("[usage-monitor] \(message)\n".utf8))
    }

    private func socketCandidates() -> [String] {
        var candidates: [String] = []
        if let explicitSocketPath, !explicitSocketPath.isEmpty {
            candidates.append(explicitSocketPath)
        }
        let defaultPath = SocketPath.path
        if !candidates.contains(defaultPath) {
            candidates.append(defaultPath)
        }
        return candidates
    }
}

private enum UnixSocketSender {
    // The raw Unix socket send stays isolated here because it uses Darwin APIs directly.
    static func send(_ data: Data, to path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.stride)
        address.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = path.utf8CString
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count <= capacity else { return false }

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
        guard didConnect == 0 else { return false }

        let didWrite = data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return -1 }
            return write(fd, baseAddress, rawBuffer.count)
        }
        return didWrite >= 0
    }
}
