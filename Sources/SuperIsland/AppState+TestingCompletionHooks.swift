import Foundation
import SuperIslandCore

/// Testing page can inject multiple completion cards either all at once or as a short burst over time.
enum TestingCompletionHookMode {
    case simultaneous
    case staggered
}

/// Lightweight seed used to generate deterministic testing completion sessions without touching runtime hook handling.
private struct TestingCompletionSeed {
    let sessionId: String
    let cwd: String
    let source: String
    let model: String
    let prompt: String
    let summary: String
    let toolTrail: [(name: String, detail: String)]
}

extension AppState {
    /// Keep hook-created sessions under a dedicated prefix so the testing page can reset them without disturbing previews.
    static let testingCompletionHookPrefix = "\(AppRuntimeConstants.testingSessionPrefix)completion-hook-"

    /// Public entry point used by Settings > Testing to simulate real completion-notification bursts.
    func triggerTestingCompletionHook(
        mode: TestingCompletionHookMode,
        interval: Duration = .seconds(1)
    ) {
        testingCompletionInjectionTask?.cancel()
        testingCompletionInjectionTask = nil
        clearTestingCompletionHookSessions()

        let seeds = makeTestingCompletionSeeds()
        guard let first = seeds.first else { return }

        injectTestingCompletionSeed(first)

        guard mode == .staggered else {
            for seed in seeds.dropFirst() {
                injectTestingCompletionSeed(seed)
            }
            return
        }

        // Staggered mode mirrors real-world hook storms where separate sessions finish seconds apart.
        testingCompletionInjectionTask = Task { [weak self] in
            for seed in seeds.dropFirst() {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.injectTestingCompletionSeed(seed)
                }
            }
        }
    }

    /// Tests need a deterministic cleanup path so repeated runs do not leave stale preview completions behind.
    func clearTestingCompletionHookSessions() {
        let hookSessionIds = sessions.keys.filter { $0.hasPrefix(Self.testingCompletionHookPrefix) }
        guard !hookSessionIds.isEmpty || !completionQueue.isEmpty else { return }

        testingCompletionInjectionTask?.cancel()
        testingCompletionInjectionTask = nil

        let hookSessionIdSet = Set(hookSessionIds)
        for sessionId in hookSessionIds {
            sessions.removeValue(forKey: sessionId)
            stopMonitor(sessionId)
            pendingTerminalIndexSessionIds.remove(sessionId)
        }

        completionQueue.removeAll { hookSessionIdSet.contains($0) }
        pendingCompletionReviewSessionIds.subtract(hookSessionIdSet)

        if let activeSessionId, hookSessionIdSet.contains(activeSessionId) {
            self.activeSessionId = mostActiveSessionId()
        }

        if let surfaceSessionId = surface.sessionId, hookSessionIdSet.contains(surfaceSessionId) {
            if let nextCompletion = completionQueue.first, sessions[nextCompletion] != nil {
                showNextCompletionOrCollapse()
            } else if sessions.isEmpty {
                panelCoordinator.collapse(reason: .unknown)
            } else {
                panelCoordinator.openSessionList(reason: .unknown)
            }
        }

        refreshDerivedState()
    }

    /// Shared seed factory keeps the testing UI and unit tests aligned on the exact same completion payloads.
    private func makeTestingCompletionSeeds() -> [TestingCompletionSeed] {
        [
            TestingCompletionSeed(
                sessionId: "\(Self.testingCompletionHookPrefix)1",
                cwd: "/tmp/SuperIsland/hook-alpha",
                source: "claude",
                model: "claude-sonnet-4-20250514",
                prompt: "优化会话列表行布局",
                summary: "会话行外观已收紧，主点击区域现在会稳定进入详情页。",
                toolTrail: [
                    (name: "读取", detail: "Sources/SuperIsland/NotchPanelSessionRowViews.swift"),
                    (name: "编辑", detail: "Sources/SuperIsland/CompactSessionRow.swift"),
                    (name: "命令", detail: "swift test --filter SessionListViewTests"),
                ]
            ),
            TestingCompletionSeed(
                sessionId: "\(Self.testingCompletionHookPrefix)2",
                cwd: "/tmp/SuperIsland/hook-beta",
                source: "codex",
                model: "o3",
                prompt: "修复完成态详情跳转",
                summary: "完成通知现在会进入详情视图，并让排队中的会话按顺序继续推进。",
                toolTrail: [
                    (name: "读取", detail: "Sources/SuperIsland/SessionDetailView.swift"),
                    (name: "编辑", detail: "Sources/SuperIsland/IslandPanelCoordinator.swift"),
                    (name: "命令", detail: "swift test --filter PanelWindowControllerTests"),
                ]
            ),
            TestingCompletionSeed(
                sessionId: "\(Self.testingCompletionHookPrefix)3",
                cwd: "/tmp/SuperIsland/hook-gamma",
                source: "cursor",
                model: "gpt-5.4",
                prompt: "验证指针命中区域",
                summary: "右上角交互区已重新平衡，状态、时间和跳转按钮不再互相重叠。",
                toolTrail: [
                    (name: "读取", detail: "Sources/SuperIsland/NotchPanelSessionListSupport.swift"),
                    (name: "编辑", detail: "Sources/SuperIsland/NotchPanelSessionActionViews.swift"),
                    (name: "命令", detail: "swift test --filter WorkspaceJumpManagerTests"),
                ]
            ),
        ]
    }

    /// Hook-generated completions bypass hook parsing, so this helper fills the exact fields the UI expects.
    private func injectTestingCompletionSeed(_ seed: TestingCompletionSeed) {
        var session = SessionSnapshot()
        session.status = .idle
        session.cwd = seed.cwd
        session.source = seed.source
        session.model = seed.model
        session.lastActivity = Date()
        session.lastUserPrompt = seed.prompt
        session.lastAssistantMessage = seed.summary
        session.addRecentMessage(ChatMessage(isUser: true, text: seed.prompt))
        session.addRecentMessage(ChatMessage(isUser: false, text: seed.summary))

        for tool in seed.toolTrail {
            // The testing hook keeps a short tool trail so completion cards and detail view share realistic preview content.
            session.recordTool(tool.name, description: tool.detail, success: true, agentType: nil, maxHistory: maxHistory)
        }

        sessions[seed.sessionId] = session
        enqueueCompletion(seed.sessionId)
        refreshDerivedState()
    }
}
