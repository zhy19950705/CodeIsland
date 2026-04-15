import Foundation

// The background refresh keeps the UI responsive while still converging to real remote update state.
@MainActor
extension SkillPlatformViewModel {
    func refreshSkillUpdateAvailability() {
        skillUpdateRefreshTask?.cancel()

        let snapshot = skills.filter(\.hasUpdateSource)
        guard !snapshot.isEmpty else { return }

        skillUpdateRefreshTask = Task { [manager] in
            let didChange = await manager.refreshAvailableUpdates(for: snapshot)
            guard !Task.isCancelled, didChange else { return }
            await MainActor.run {
                self.refreshLocal()
            }
        }
    }
}
