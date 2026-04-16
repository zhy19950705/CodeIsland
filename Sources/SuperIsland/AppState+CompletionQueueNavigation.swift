import SwiftUI

/// 完成通知保留“通知流”语义，但额外维护一个轻量序列，方便显示当前位置并提供显式“下一条”操作。
extension AppState {
    func enqueueCompletion(_ sessionId: String) {
        markPendingCompletionReview(for: sessionId)

        // 同一轮完成流里只保留一份会话，避免重复 hook 把进度和按钮文案冲乱。
        if completionSequence.contains(sessionId) || justCompletedSessionId == sessionId {
            return
        }

        if isShowingCompletion {
            completionQueue.append(sessionId)
            completionSequence.append(sessionId)
        } else {
            completionSequence = [sessionId]
            completionSequenceIndex = 0
            showCompletion(sessionId)
        }
    }

    func cancelCompletionQueue() {
        autoCollapseTask?.cancel()
        completionQueue.removeAll()
        completionSequence.removeAll()
        completionSequenceIndex = 0
    }

    func showNextCompletionOrCollapse() {
        while let next = completionQueue.first {
            completionQueue.removeFirst()

            guard sessions[next] != nil else {
                removeCompletionFromSequence(next)
                continue
            }

            withAnimation(NotchAnimation.pop) {
                showCompletion(next)
            }
            return
        }

        // 队列消费完后顺手清掉进度状态，避免再次展开时看到上一次的残留序号。
        completionSequence.removeAll()
        completionSequenceIndex = 0

        // 完成通知的最终收起仍然交给展示协调器，避免和 hover/click 状态机打架。
        panelCoordinator.collapse(reason: .notification)
    }

    /// 只在完成卡片上显示序号，普通详情页不需要引入队列概念。
    func completionProgress(for sessionId: String) -> (current: Int, total: Int)? {
        guard case .completionCard = surface else { return nil }

        if let sequenceIndex = completionSequence.firstIndex(of: sessionId) {
            return (sequenceIndex + 1, completionSequence.count)
        }

        guard justCompletedSessionId == sessionId else { return nil }
        let total = max(completionSequence.count, completionQueue.count + 1)
        let current = min(max(completionSequenceIndex + 1, 1), total)
        return (current, total)
    }

    /// 下一条按钮会优先跳到后续完成通知；已经是末尾时就直接收起。
    func completionAdvanceButtonTitle(for sessionId: String) -> String {
        hasNextCompletion(after: sessionId) ? AppText.shared["completion_next"] : AppText.shared["completion_close"]
    }

    func advanceCompletionPresentation(from sessionId: String) {
        guard case .completionCard(let activeSessionId) = surface, activeSessionId == sessionId else { return }
        showNextCompletionOrCollapse()
    }

    private func shouldSuppressAppLevel(for sessionId: String) -> Bool {
        guard UserDefaults.standard.bool(forKey: SettingsKey.smartSuppress) else { return false }
        guard let session = sessions[sessionId],
              (session.termApp != nil || session.termBundleId != nil) else { return false }
        return TerminalVisibilityDetector.isTerminalFrontmostForSession(session)
    }

    private func showCompletion(_ sessionId: String) {
        guard shouldSuppressAppLevel(for: sessionId) == false else {
            presentCompletionWhenTerminalIsNotVisible(sessionId)
            return
        }

        doShowCompletion(sessionId)
    }

    /// 终端正好在前台时仍然沿用原来的抑制逻辑，只在目标标签页不可见时才自动弹出。
    private func presentCompletionWhenTerminalIsNotVisible(_ sessionId: String) {
        guard let session = sessions[sessionId] else { return }
        let sessionCopy = session

        let now = Date()
        let shouldSkipCheck = now.timeIntervalSince(lastTabVisibilityCheckTime) < minTabVisibilityCheckInterval

        Task.detached {
            let tabVisible: Bool
            if shouldSkipCheck {
                tabVisible = await MainActor.run { [weak self] in self?.lastTabVisibilityCheckResult ?? false }
            } else {
                tabVisible = TerminalVisibilityDetector.isSessionTabVisible(sessionCopy)
                await MainActor.run { [weak self] in
                    self?.lastTabVisibilityCheckTime = now
                    self?.lastTabVisibilityCheckResult = tabVisible
                }
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.sessions[sessionId] != nil else { return }

                switch self.surface {
                case .approvalCard, .questionCard:
                    return
                default:
                    break
                }

                if tabVisible == false {
                    withAnimation(NotchAnimation.pop) {
                        self.doShowCompletion(sessionId)
                    }
                }
            }
        }
    }

    private func doShowCompletion(_ sessionId: String) {
        syncCompletionSequencePosition(with: sessionId)
        activeSessionId = sessionId

        // 完成通知是短暂弹层，因此始终走 notification 打开原因，保持动画和 hover 策略一致。
        panelCoordinator.presentCompletionCard(sessionId: sessionId, reason: .notification)
        scheduleCompletionAutoCollapse(for: sessionId)
    }

    /// 每次切到新完成项时都重新计时，避免上一条剩下的倒计时立刻把当前卡片收掉。
    private func scheduleCompletionAutoCollapse(for sessionId: String) {
        let displaySeconds = SettingsManager.shared.completionCardDisplaySeconds

        autoCollapseTask?.cancel()
        autoCollapseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(displaySeconds))
            guard Task.isCancelled == false else { return }
            guard shouldAutoCollapseCompletionCard(sessionId: sessionId) else { return }
            showNextCompletionOrCollapse()
        }
    }

    private func hasNextCompletion(after sessionId: String) -> Bool {
        guard let currentIndex = completionSequence.firstIndex(of: sessionId) else {
            return completionQueue.contains { sessions[$0] != nil }
        }

        guard currentIndex + 1 < completionSequence.count else { return false }
        let suffix = completionSequence[(currentIndex + 1)...]
        return suffix.contains { sessions[$0] != nil }
    }

    /// 当前会话不一定总能在序列里找到，所以切换时统一在这里兜底并修正游标。
    private func syncCompletionSequencePosition(with sessionId: String) {
        if let sequenceIndex = completionSequence.firstIndex(of: sessionId) {
            completionSequenceIndex = sequenceIndex
            return
        }

        completionSequence = [sessionId] + completionQueue.filter { $0 != sessionId }
        completionSequenceIndex = 0
    }

    private func removeCompletionFromSequence(_ sessionId: String) {
        guard let sequenceIndex = completionSequence.firstIndex(of: sessionId) else { return }
        completionSequence.remove(at: sequenceIndex)

        if completionSequence.isEmpty {
            completionSequenceIndex = 0
            return
        }

        if completionSequenceIndex >= completionSequence.count {
            completionSequenceIndex = completionSequence.count - 1
        } else if sequenceIndex <= completionSequenceIndex {
            completionSequenceIndex = max(0, completionSequenceIndex - 1)
        }
    }
}
