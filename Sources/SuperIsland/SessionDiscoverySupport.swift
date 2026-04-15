import Foundation
import Darwin

private struct DiscoveryCacheEntry<Value> {
    let expiresAt: Date
    let value: Value
}

private final class SessionDiscoveryCacheStore {
    static let shared = SessionDiscoveryCacheStore()

    private let lock = NSLock()
    private var pidEntries: [String: DiscoveryCacheEntry<[pid_t]>] = [:]
    private var directoryEntries: [String: DiscoveryCacheEntry<[String]>] = [:]

    func pids(for key: String, ttl: TimeInterval = 2, loader: () -> [pid_t]) -> [pid_t] {
        let now = Date()
        lock.lock()
        if let cached = pidEntries[key], cached.expiresAt > now {
            lock.unlock()
            return cached.value
        }
        lock.unlock()

        let loaded = loader()

        lock.lock()
        pidEntries[key] = DiscoveryCacheEntry(expiresAt: now.addingTimeInterval(ttl), value: loaded)
        lock.unlock()
        return loaded
    }

    func directoryContents(atPath path: String, ttl: TimeInterval = 3, fileManager: FileManager) -> [String]? {
        let now = Date()
        lock.lock()
        if let cached = directoryEntries[path], cached.expiresAt > now {
            lock.unlock()
            return cached.value
        }
        lock.unlock()

        guard let loaded = try? fileManager.contentsOfDirectory(atPath: path) else {
            return nil
        }

        lock.lock()
        directoryEntries[path] = DiscoveryCacheEntry(expiresAt: now.addingTimeInterval(ttl), value: loaded)
        lock.unlock()
        return loaded
    }
}

enum SessionProcessInspector {
    static func findPIDs(cacheKey: String, matcher: (pid_t, String) -> Bool) -> [pid_t] {
        SessionDiscoveryCacheStore.shared.pids(for: cacheKey) {
            var bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
            guard bufferSize > 0 else { return [] }

            var pids = [pid_t](repeating: 0, count: Int(bufferSize) / MemoryLayout<pid_t>.size + 10)
            bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, bufferSize)
            let count = Int(bufferSize) / MemoryLayout<pid_t>.size

            var results: [pid_t] = []
            var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))

            for index in 0..<count {
                let pid = pids[index]
                guard pid > 0 else { continue }
                let len = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
                guard len > 0 else { continue }
                let path = String(cString: pathBuffer)
                if matcher(pid, path) {
                    results.append(pid)
                }
            }
            return results
        }
    }

    static func cwd(for pid: pid_t) -> String? {
        var pathInfo = proc_vnodepathinfo()
        let size = MemoryLayout<proc_vnodepathinfo>.size
        let ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &pathInfo, Int32(size))
        guard ret > 0 else { return nil }
        return withUnsafePointer(to: pathInfo.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
    }

    static func processStartTime(for pid: pid_t) -> Date? {
        var info = proc_bsdinfo()
        let ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard ret > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec))
    }

    static func processArgs(for pid: pid_t) -> [String]? {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        guard size > MemoryLayout<Int32>.size else { return nil }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        guard argc > 0, argc < 256 else { return nil }

        var offset = MemoryLayout<Int32>.size
        while offset < size && buffer[offset] != 0 { offset += 1 }
        while offset < size && buffer[offset] == 0 { offset += 1 }

        var args: [String] = []
        var argStart = offset
        for _ in 0..<argc {
            while offset < size && buffer[offset] != 0 { offset += 1 }
            if offset > argStart {
                args.append(String(bytes: buffer[argStart..<offset], encoding: .utf8) ?? "")
            }
            offset += 1
            argStart = offset
        }
        return args
    }

    static func directoryContents(atPath path: String, fileManager: FileManager = .default) -> [String]? {
        SessionDiscoveryCacheStore.shared.directoryContents(atPath: path, fileManager: fileManager)
    }
}
