import Foundation

// SkillPlatformLocalSnapshot batches local discovery so the view model can publish a single UI update.
struct SkillPlatformLocalSnapshot {
    let skills: [InstalledSkill]
    let agentSnapshots: [SkillAgentLinkSnapshot]
}

extension SkillManager {
    // Build the complete local snapshot off the main thread because skill discovery reads many files from disk.
    func buildLocalSnapshot() throws -> SkillPlatformLocalSnapshot {
        SkillPlatformLocalSnapshot(
            skills: try discoverSkills(),
            agentSnapshots: agentSnapshots()
        )
    }
}

@MainActor
extension SkillPlatformViewModel {
    // Refresh local state from a background queue so entering the Skills page does not hitch the settings UI.
    func refreshLocalInBackground() {
        localRefreshTask?.cancel()
        isRefreshingLocal = true

        let manager = self.manager
        localRefreshTask = Task { [weak self] in
            do {
                let snapshot = try await Self.loadLocalSnapshot(using: manager)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    self.applyLocalSnapshot(snapshot)
                    self.isRefreshingLocal = false
                    self.refreshSkillUpdateAvailability()
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    self.isRefreshingLocal = false
                    self.statusMessage = error.localizedDescription
                    self.statusIsError = true
                    self.statusIsBusy = false
                }
            }
        }
    }

    // Defer marketplace boot until the tab is visible so the library tab can appear immediately.
    func loadMarketplaceIfNeeded() {
        guard !marketplaceHasLoaded, !isRefreshingMarketplace else { return }
        Task {
            await refreshMarketplace()
        }
    }

    // Wrap synchronous filesystem work in a continuation so SwiftUI can keep the main actor responsive.
    private static func loadLocalSnapshot(using manager: SkillManager) async throws -> SkillPlatformLocalSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try manager.buildLocalSnapshot())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
