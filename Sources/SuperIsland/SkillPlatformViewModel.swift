import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class SkillPlatformViewModel {
    private(set) var skills: [InstalledSkill] = []
    private(set) var agentSnapshots: [SkillAgentLinkSnapshot] = []
    private(set) var marketplaceItems: [SkillMarketplaceItem] = []
    var installReference = ""
    var marketplaceQuery = ""
    var marketplaceSource: SkillMarketplaceSource = .skillsSh
    var skillsShLeaderboard: SkillsShLeaderboardKind = .trending
    var isRefreshingLocal = false
    var isRefreshingMarketplace = false
    var isInstallingReference = false
    var isUpdatingSkills = false
    var marketplaceHasLoaded = false
    var isPreviewLoading = false
    var previewDocument: SkillPreviewDocument?
    var installingMarketplaceItemID: String?
    var statusMessage = ""
    var statusIsError = false
    var statusIsBusy = false

    let manager: SkillManager
    private var didInitialLoad = false
    var skillUpdateRefreshTask: Task<Void, Never>?

    init(manager: SkillManager = SkillManager()) {
        self.manager = manager
    }

    func loadIfNeeded() {
        guard !didInitialLoad else { return }
        didInitialLoad = true
        refreshLocal()
        Task {
            await refreshMarketplace()
        }
    }

    func refreshLocal() {
        isRefreshingLocal = true
        defer { isRefreshingLocal = false }

        do {
            skills = try manager.discoverSkills()
            agentSnapshots = manager.agentSnapshots()
            refreshSkillUpdateAvailability()
        } catch {
            publish(error)
        }
    }

    func refreshMarketplace() async {
        isRefreshingMarketplace = true
        defer {
            isRefreshingMarketplace = false
            marketplaceHasLoaded = true
        }

        do {
            marketplaceItems = try await manager.marketplaceItems(
                source: marketplaceSource,
                query: marketplaceQuery,
                leaderboard: skillsShLeaderboard
            )
        } catch {
            publish(error)
        }
    }

    func openSharedRoot() {
        manager.openSharedRoot()
    }

    func reveal(_ url: URL) {
        manager.reveal(url)
    }

    func importFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let installed = try manager.importSkills(from: url)
            let repair = manager.repairGlobalAgentLinks()
            refreshLocal()
            publishSuccess(successMessage("Imported \(installed.count) skill(s)", repair: repair))
        } catch {
            publish(error)
        }
    }

    func installFromReference() {
        let reference = installReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty else { return }

        isInstallingReference = true
        publishProgress("Installing \(reference)…")
        Task {
            do {
                let installed = try await manager.installRepository(reference: reference)
                await MainActor.run {
                    let repair = self.manager.repairGlobalAgentLinks()
                    self.installReference = ""
                    self.isInstallingReference = false
                    self.refreshLocal()
                    self.publishSuccess(self.successMessage("Installed \(installed.count) skill(s)", repair: repair))
                }
            } catch {
                await MainActor.run {
                    self.isInstallingReference = false
                    self.publish(error)
                }
            }
        }
    }

    func install(_ item: SkillMarketplaceItem) {
        guard item.canInstallDirectly else {
            publishSuccess("This source can be browsed and previewed, but direct install is not supported yet")
            return
        }
        isInstallingReference = true
        installingMarketplaceItemID = item.id
        publishProgress("Installing \(item.title)…")
        Task {
            do {
                let installed = try await manager.installMarketplaceItem(item)
                await MainActor.run {
                    let repair = self.manager.repairGlobalAgentLinks()
                    self.isInstallingReference = false
                    self.installingMarketplaceItemID = nil
                    self.refreshLocal()
                    self.publishSuccess(self.successMessage("Installed \(installed.count) skill(s)", repair: repair))
                }
            } catch {
                await MainActor.run {
                    self.isInstallingReference = false
                    self.installingMarketplaceItemID = nil
                    self.publish(error)
                }
            }
        }
    }

    func adopt(_ skill: InstalledSkill) {
        do {
            _ = try manager.importSkillToSharedLibrary(skill)
            let repair = manager.repairGlobalAgentLinks()
            refreshLocal()
            publishSuccess(successMessage("Imported \(skill.name) into the shared library", repair: repair))
        } catch {
            publish(error)
        }
    }

    func adoptAllExternalSkills() {
        let candidates = skills.filter { !$0.isSharedLibrarySkill && $0.isAdoptableToSharedLibrary }
        guard !candidates.isEmpty else { return }

        do {
            let summary = try manager.importSkillsToSharedLibrary(candidates)
            let repair = manager.repairGlobalAgentLinks()
            refreshLocal()
            if summary.skippedCount > 0 {
                publishSuccess(successMessage("Imported \(summary.importedCount) skill(s), skipped \(summary.skippedCount)", repair: repair))
            } else {
                publishSuccess(successMessage("Imported \(summary.importedCount) skill(s) into the shared library", repair: repair))
            }
        } catch {
            publish(error)
        }
    }

    func preview(_ skill: InstalledSkill) {
        do {
            previewDocument = try manager.previewDocument(for: skill)
        } catch {
            publish(error)
        }
    }

    func preview(_ item: SkillMarketplaceItem) {
        isPreviewLoading = true
        Task {
            do {
                let document = try await manager.previewDocument(for: item)
                await MainActor.run {
                    self.isPreviewLoading = false
                    self.previewDocument = document
                }
            } catch {
                await MainActor.run {
                    self.isPreviewLoading = false
                    self.publish(error)
                }
            }
        }
    }

    func updateAllSkills() {
        let updatableSkills = skills.filter(\.isUpdatable)
        guard !updatableSkills.isEmpty else {
            publish(SkillPlatformError.noUpdateSource)
            return
        }

        isUpdatingSkills = true
        Task {
            do {
                let updated = try await manager.updateAllSkills(updatableSkills)
                await MainActor.run {
                    let repair = self.manager.repairGlobalAgentLinks()
                    self.isUpdatingSkills = false
                    self.refreshLocal()
                    self.publishSuccess(self.successMessage("Updated \(updated.count) skill(s)", repair: repair))
                }
            } catch {
                await MainActor.run {
                    self.isUpdatingSkills = false
                    self.publish(error)
                }
            }
        }
    }

    func update(_ skill: InstalledSkill) {
        guard skill.isUpdatable else {
            publish(SkillPlatformError.noUpdateSource)
            return
        }

        isUpdatingSkills = true
        Task {
            do {
                let updated = try await manager.updateSkill(skill)
                await MainActor.run {
                    let repair = self.manager.repairGlobalAgentLinks()
                    self.isUpdatingSkills = false
                    self.refreshLocal()
                    self.publishSuccess(self.successMessage("Updated \(updated.count) skill(s)", repair: repair))
                }
            } catch {
                await MainActor.run {
                    self.isUpdatingSkills = false
                    self.publish(error)
                }
            }
        }
    }

    func linkAllAgents() {
        do {
            try manager.linkAllAgents()
            refreshLocal()
            publishSuccess("Linked supported agents")
        } catch {
            publish(error)
        }
    }

    func link(_ snapshot: SkillAgentLinkSnapshot) {
        do {
            try manager.link(snapshot.agent)
            refreshLocal()
            publishSuccess("Linked \(snapshot.agent.title)")
        } catch {
            publish(error)
        }
    }

    func unlink(_ snapshot: SkillAgentLinkSnapshot) {
        do {
            try manager.unlink(snapshot.agent)
            refreshLocal()
            publishSuccess("Unlinked \(snapshot.agent.title)")
        } catch {
            publish(error)
        }
    }

    func resolveConflict(_ snapshot: SkillAgentLinkSnapshot) {
        do {
            let summary = try manager.resolveConflict(for: snapshot.agent)
            refreshLocal()
            publishSuccess(conflictResolutionMessage(summary))
        } catch {
            publish(error)
        }
    }

    func resolveAllConflicts() {
        do {
            let summary = try manager.resolveAllConflicts()
            refreshLocal()
            publishSuccess(bulkConflictResolutionMessage(summary))
        } catch {
            publish(error)
        }
    }

    func remove(_ skill: InstalledSkill) {
        do {
            try manager.removeSkill(skill)
            refreshLocal()
            publishSuccess("Removed \(skill.name)")
        } catch {
            publish(error)
        }
    }

    private func publishProgress(_ message: String) {
        statusMessage = message
        statusIsError = false
        statusIsBusy = true
    }

    private func publishSuccess(_ message: String) {
        statusMessage = message
        statusIsError = false
        statusIsBusy = false
    }

    private func successMessage(_ base: String, repair: SkillLinkRepairSummary) -> String {
        guard repair.linkedCount > 0 || repair.conflictCount > 0 else { return base }
        if repair.conflictCount > 0 {
            return "\(base) · linked \(repair.linkedCount) agent(s), \(repair.conflictCount) conflict(s)"
        }
        return "\(base) · linked \(repair.linkedCount) agent(s)"
    }

    private func conflictResolutionMessage(_ summary: SkillConflictResolutionSummary) -> String {
        if summary.skippedCount > 0 {
            return "Resolved \(summary.agent.title) conflict · imported \(summary.importedCount), skipped \(summary.skippedCount)"
        }
        return "Resolved \(summary.agent.title) conflict · imported \(summary.importedCount) skill(s)"
    }

    private func bulkConflictResolutionMessage(_ summary: SkillBulkConflictResolutionSummary) -> String {
        guard summary.resolvedCount > 0 else {
            return "No conflicts were resolved"
        }
        if summary.skippedCount > 0 {
            return "Resolved \(summary.resolvedCount) conflict(s) · imported \(summary.importedCount), skipped \(summary.skippedCount)"
        }
        return "Resolved \(summary.resolvedCount) conflict(s) · imported \(summary.importedCount) skill(s)"
    }

    private func publish(_ error: Error) {
        statusMessage = error.localizedDescription
        statusIsError = true
        statusIsBusy = false
    }
}
