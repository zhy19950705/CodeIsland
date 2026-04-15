import Foundation
import CoreServices
import os.log

private let sessionDiscoveryLog = Logger(subsystem: "com.superisland", category: "SessionDiscoveryService")

@MainActor
final class SessionDiscoveryService {
    typealias CleanupAction = @MainActor () -> Void
    typealias AsyncAction = @Sendable () async -> Void

    private let projectsPath: String
    private let watcherLatency: TimeInterval
    private let debounceInterval: TimeInterval
    private let cleanupInterval: TimeInterval

    private var cleanupTimer: Timer?
    private var fsEventStream: FSEventStreamRef?
    private var lastScanTime: Date = .distantPast
    private var cleanupAction: CleanupAction?
    private var scanLiveSessionsAction: AsyncAction?

    init(
        projectsPath: String = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects").path,
        watcherLatency: TimeInterval = 2,
        debounceInterval: TimeInterval = 3,
        cleanupInterval: TimeInterval = 60
    ) {
        self.projectsPath = projectsPath
        self.watcherLatency = watcherLatency
        self.debounceInterval = debounceInterval
        self.cleanupInterval = cleanupInterval
    }

    func start(
        onCleanup: @escaping CleanupAction,
        restoreStartup: @escaping AsyncAction,
        scanLiveSessions: @escaping AsyncAction
    ) {
        stop()
        cleanupAction = onCleanup
        scanLiveSessionsAction = scanLiveSessions

        cleanupTimer = Timer.scheduledTimer(withTimeInterval: cleanupInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupAction?()
            }
        }

        Task.detached(priority: .utility) {
            await restoreStartup()
        }
        Task.detached(priority: .utility) {
            await scanLiveSessions()
        }

        startProjectsWatcher()
    }

    func stop() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        cleanupAction = nil
        scanLiveSessionsAction = nil
        lastScanTime = .distantPast

        if let stream = fsEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            fsEventStream = nil
        }
    }

    private func startProjectsWatcher() {
        guard FileManager.default.fileExists(atPath: projectsPath) else { return }

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let stream = FSEventStreamCreate(
            nil,
            { _, info, _, _, _, _ in
                guard let info else { return }
                let service = Unmanaged<SessionDiscoveryService>.fromOpaque(info).takeUnretainedValue()
                service.handleProjectsDirChange()
            },
            &context,
            [projectsPath] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            watcherLatency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)
        )

        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        fsEventStream = stream
        sessionDiscoveryLog.info("Projects watcher started on \(self.projectsPath, privacy: .public)")
    }

    nonisolated private func handleProjectsDirChange() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard Date().timeIntervalSince(self.lastScanTime) > self.debounceInterval else { return }
            self.lastScanTime = Date()
            guard let scanLiveSessionsAction = self.scanLiveSessionsAction else { return }
            Task.detached(priority: .utility) {
                await scanLiveSessionsAction()
            }
        }
    }
}
