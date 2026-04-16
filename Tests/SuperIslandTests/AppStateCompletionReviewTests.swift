import XCTest
import SuperIslandCore
@testable import SuperIsland

@MainActor
final class AppStateCompletionReviewTests: XCTestCase {
    private func withSessionTimeout<T>(_ timeout: Int, run body: () throws -> T) rethrows -> T {
        let defaults = UserDefaults.standard
        let key = SettingsKey.sessionTimeout
        let previousValue = defaults.object(forKey: key)
        defaults.set(timeout, forKey: key)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        return try body()
    }

    private func withPersistenceStore<T>(run body: () throws -> T) rethrows -> T {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("sessions.json", isDirectory: false)
        SessionPersistence.useOverrideFileURLForTesting(fileURL)
        defer {
            SessionPersistence.clear()
            SessionPersistence.useOverrideFileURLForTesting(nil)
            try? FileManager.default.removeItem(at: directoryURL)
        }
        return try body()
    }

    func testStopEventMarksSessionAsPendingCompletionReview() {
        let appState = AppState()

        appState.handleEvent(
            HookEvent(
                eventName: "Stop",
                sessionId: "done",
                toolName: nil,
                toolInput: nil,
                rawJSON: [
                    "_source": "claude",
                    "cwd": "/tmp/project",
                    "message": "Finished the task.",
                ]
            )
        )

        XCTAssertTrue(appState.needsCompletionReview(sessionId: "done"))
    }

    func testStopEventClearsActiveSessionWhenOnlyPendingReviewRemains() {
        let appState = AppState()

        appState.handleEvent(
            HookEvent(
                eventName: "PreToolUse",
                sessionId: "done",
                toolName: "Read",
                toolInput: nil,
                rawJSON: [
                    "_source": "claude",
                    "cwd": "/tmp/project",
                ]
            )
        )

        XCTAssertEqual(appState.activeSessionId, "done")

        appState.handleEvent(
            HookEvent(
                eventName: "Stop",
                sessionId: "done",
                toolName: nil,
                toolInput: nil,
                rawJSON: [
                    "_source": "claude",
                    "cwd": "/tmp/project",
                    "message": "Finished the task.",
                ]
            )
        )

        XCTAssertTrue(appState.needsCompletionReview(sessionId: "done"))
        XCTAssertNil(appState.activeSessionId)
    }

    func testFocusSessionAcknowledgesPendingCompletionReview() {
        let appState = AppState()

        appState.handleEvent(
            HookEvent(
                eventName: "Stop",
                sessionId: "done",
                toolName: nil,
                toolInput: nil,
                rawJSON: [
                    "_source": "claude",
                    "cwd": "/tmp/project",
                    "message": "Finished the task.",
                ]
            )
        )

        XCTAssertTrue(appState.needsCompletionReview(sessionId: "done"))
        XCTAssertTrue(appState.focusSession(sessionId: "done"))
        XCTAssertFalse(appState.needsCompletionReview(sessionId: "done"))
    }

    func testTestingCompletionHookSimultaneousModeShowsFirstAndQueuesRemainingSessions() {
        let appState = AppState()
        defer { appState.teardown() }

        appState.triggerTestingCompletionHook(mode: .simultaneous)

        XCTAssertEqual(appState.justCompletedSessionId, "\(AppState.testingCompletionHookPrefix)1")
        XCTAssertEqual(
            appState.completionQueue,
            ["\(AppState.testingCompletionHookPrefix)2", "\(AppState.testingCompletionHookPrefix)3"]
        )
        XCTAssertEqual(
            appState.completionSequence,
            ["\(AppState.testingCompletionHookPrefix)1", "\(AppState.testingCompletionHookPrefix)2", "\(AppState.testingCompletionHookPrefix)3"]
        )
        XCTAssertEqual(appState.completionSequenceIndex, 0)
        XCTAssertTrue(appState.needsCompletionReview(sessionId: "\(AppState.testingCompletionHookPrefix)1"))
        XCTAssertTrue(appState.needsCompletionReview(sessionId: "\(AppState.testingCompletionHookPrefix)2"))
        XCTAssertTrue(appState.needsCompletionReview(sessionId: "\(AppState.testingCompletionHookPrefix)3"))
    }

    func testTestingCompletionHookStaggeredModeAppendsSessionsOverTime() async {
        let appState = AppState()
        defer { appState.teardown() }

        appState.triggerTestingCompletionHook(mode: .staggered, interval: .milliseconds(20))

        XCTAssertEqual(appState.justCompletedSessionId, "\(AppState.testingCompletionHookPrefix)1")
        XCTAssertTrue(appState.completionQueue.isEmpty)

        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(appState.completionQueue, ["\(AppState.testingCompletionHookPrefix)2"])

        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(
            appState.completionQueue,
            ["\(AppState.testingCompletionHookPrefix)2", "\(AppState.testingCompletionHookPrefix)3"]
        )
        XCTAssertEqual(
            appState.completionSequence,
            ["\(AppState.testingCompletionHookPrefix)1", "\(AppState.testingCompletionHookPrefix)2", "\(AppState.testingCompletionHookPrefix)3"]
        )
    }

    func testShowNextCompletionOrCollapseAdvancesCompletionProgress() {
        let appState = AppState()
        defer { appState.teardown() }

        appState.triggerTestingCompletionHook(mode: .simultaneous)
        appState.showNextCompletionOrCollapse()

        XCTAssertEqual(appState.justCompletedSessionId, "\(AppState.testingCompletionHookPrefix)2")
        XCTAssertEqual(appState.completionQueue, ["\(AppState.testingCompletionHookPrefix)3"])
        XCTAssertEqual(appState.completionProgress(for: "\(AppState.testingCompletionHookPrefix)2")?.current, 2)
        XCTAssertEqual(appState.completionProgress(for: "\(AppState.testingCompletionHookPrefix)2")?.total, 3)
        XCTAssertEqual(appState.completionSequenceIndex, 1)
    }

    func testFinalCompletionAdvanceClearsSequenceAndCollapses() {
        let appState = AppState()
        defer { appState.teardown() }

        appState.triggerTestingCompletionHook(mode: .simultaneous)
        appState.showNextCompletionOrCollapse()
        appState.showNextCompletionOrCollapse()
        appState.showNextCompletionOrCollapse()

        XCTAssertEqual(appState.surface, .collapsed)
        XCTAssertTrue(appState.completionQueue.isEmpty)
        XCTAssertTrue(appState.completionSequence.isEmpty)
        XCTAssertEqual(appState.completionSequenceIndex, 0)
    }

    func testNewActivityClearsPendingCompletionReview() {
        let appState = AppState()

        appState.handleEvent(
            HookEvent(
                eventName: "Stop",
                sessionId: "done",
                toolName: nil,
                toolInput: nil,
                rawJSON: [
                    "_source": "claude",
                    "cwd": "/tmp/project",
                    "message": "Finished the task.",
                ]
            )
        )

        XCTAssertTrue(appState.needsCompletionReview(sessionId: "done"))

        appState.handleEvent(
            HookEvent(
                eventName: "UserPromptSubmit",
                sessionId: "done",
                toolName: nil,
                toolInput: nil,
                rawJSON: [
                    "_source": "claude",
                    "prompt": "Continue with follow-up changes.",
                ]
            )
        )

        XCTAssertFalse(appState.needsCompletionReview(sessionId: "done"))
    }

    func testApplyRestoredSessionsDoesNotPromoteIdleSessionToActive() {
        let appState = AppState()

        let now = Date()
        let persisted = PersistedSession(
            sessionId: "idle-restored",
            cwd: "/tmp/project",
            source: "codex",
            model: nil,
            sessionTitle: nil,
            sessionTitleSource: nil,
            providerSessionId: "idle-restored",
            lastUserPrompt: "done",
            lastAssistantMessage: "finished",
            termApp: nil,
            itermSessionId: nil,
            ttyPath: nil,
            kittyWindowId: nil,
            tmuxPane: nil,
            tmuxClientTty: nil,
            cmuxWorkspaceRef: nil,
            cmuxSurfaceRef: nil,
            cmuxPaneRef: nil,
            cmuxWorkspaceId: nil,
            cmuxSurfaceId: nil,
            cmuxSocketPath: nil,
            termBundleId: nil,
            cliPid: nil,
            startTime: now.addingTimeInterval(-60),
            lastActivity: now
        )

        appState.applyRestoredSessions(persisted: [persisted], historicalCodexSessions: [])

        XCTAssertNotNil(appState.sessions["idle-restored"])
        XCTAssertNil(appState.activeSessionId)
    }

    func testApplyRestoredSessionsHonorsConfiguredTimeoutOnStartup() {
        withSessionTimeout(120) {
            let appState = AppState()
            let now = Date()

            let withinTimeout = PersistedSession(
                sessionId: "within-timeout",
                cwd: "/tmp/project",
                source: "claude",
                model: nil,
                sessionTitle: nil,
                sessionTitleSource: nil,
                providerSessionId: nil,
                lastUserPrompt: nil,
                lastAssistantMessage: nil,
                termApp: nil,
                itermSessionId: nil,
                ttyPath: nil,
                kittyWindowId: nil,
                tmuxPane: nil,
                tmuxClientTty: nil,
                cmuxWorkspaceRef: nil,
                cmuxSurfaceRef: nil,
                cmuxPaneRef: nil,
                cmuxWorkspaceId: nil,
                cmuxSurfaceId: nil,
                cmuxSocketPath: nil,
                termBundleId: nil,
                cliPid: nil,
                startTime: now.addingTimeInterval(-90 * 60),
                lastActivity: now.addingTimeInterval(-90 * 60)
            )

            let expired = PersistedSession(
                sessionId: "expired",
                cwd: "/tmp/project",
                source: "claude",
                model: nil,
                sessionTitle: nil,
                sessionTitleSource: nil,
                providerSessionId: nil,
                lastUserPrompt: nil,
                lastAssistantMessage: nil,
                termApp: nil,
                itermSessionId: nil,
                ttyPath: nil,
                kittyWindowId: nil,
                tmuxPane: nil,
                tmuxClientTty: nil,
                cmuxWorkspaceRef: nil,
                cmuxSurfaceRef: nil,
                cmuxPaneRef: nil,
                cmuxWorkspaceId: nil,
                cmuxSurfaceId: nil,
                cmuxSocketPath: nil,
                termBundleId: nil,
                cliPid: nil,
                startTime: now.addingTimeInterval(-150 * 60),
                lastActivity: now.addingTimeInterval(-150 * 60)
            )

            appState.applyRestoredSessions(persisted: [withinTimeout, expired], historicalCodexSessions: [])

            XCTAssertNotNil(appState.sessions["within-timeout"])
            XCTAssertNil(appState.sessions["expired"])
        }
    }

    func testApplyRestoredSessionsKeepsOldSessionsWhenCleanupDisabled() {
        withSessionTimeout(0) {
            let appState = AppState()
            let now = Date()

            let persisted = PersistedSession(
                sessionId: "ancient",
                cwd: "/tmp/project",
                source: "claude",
                model: nil,
                sessionTitle: nil,
                sessionTitleSource: nil,
                providerSessionId: nil,
                lastUserPrompt: "old prompt",
                lastAssistantMessage: "old reply",
                termApp: nil,
                itermSessionId: nil,
                ttyPath: nil,
                kittyWindowId: nil,
                tmuxPane: nil,
                tmuxClientTty: nil,
                cmuxWorkspaceRef: nil,
                cmuxSurfaceRef: nil,
                cmuxPaneRef: nil,
                cmuxWorkspaceId: nil,
                cmuxSurfaceId: nil,
                cmuxSocketPath: nil,
                termBundleId: nil,
                cliPid: nil,
                startTime: now.addingTimeInterval(-3 * 24 * 60 * 60),
                lastActivity: now.addingTimeInterval(-3 * 24 * 60 * 60)
            )

            appState.applyRestoredSessions(persisted: [persisted], historicalCodexSessions: [])

            XCTAssertNotNil(appState.sessions["ancient"])
        }
    }

    func testRestoreStartupSessionsKeepsPersistedSnapshotForNextLaunch() {
        withPersistenceStore {
            let now = Date()
            var snapshot = SessionSnapshot(startTime: now.addingTimeInterval(-60))
            snapshot.source = "claude"
            snapshot.cwd = "/tmp/project"
            snapshot.lastUserPrompt = "hello"
            snapshot.lastAssistantMessage = "world"
            snapshot.lastActivity = now

            SessionPersistence.save(["restored": snapshot])
            XCTAssertEqual(SessionPersistence.load().map(\.sessionId), ["restored"])

            let appState = AppState()
            appState.restoreStartupSessions(
                persisted: SessionPersistence.load(),
                historicalCodexSessions: []
            )

            XCTAssertNotNil(appState.sessions["restored"])
            XCTAssertEqual(SessionPersistence.load().map(\.sessionId), ["restored"])
        }
    }
}
