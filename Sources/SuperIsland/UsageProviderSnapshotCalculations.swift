import Foundation

extension UsageProviderSnapshot {
    func remainingPercentage(for window: UsageWindowStat) -> Int {
        guard hasQuotaMetrics else { return 0 }
        switch source {
        case .claude, .cursor:
            return max(0, min(100, 100 - window.percentage))
        case .codex:
            return max(0, min(100, window.percentage))
        }
    }

    func usedPercentage(for window: UsageWindowStat) -> Int {
        max(0, min(100, 100 - remainingPercentage(for: window)))
    }

    var primaryRemainingPercentage: Int {
        remainingPercentage(for: primary)
    }

    var primaryUsedPercentage: Int {
        usedPercentage(for: primary)
    }
}
