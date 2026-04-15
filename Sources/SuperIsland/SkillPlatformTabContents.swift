import SwiftUI
import AppKit
import Observation

// SkillPlatformTabContents keeps the page shell small by moving each tab's section composition into its own view.
struct SkillLibraryTabContent: View {
    @ObservedObject private var l10n = L10n.shared
    @Bindable var viewModel: SkillPlatformViewModel
    @Binding var installedSearchQuery: String
    let sharedSkills: [InstalledSkill]
    @Binding var sharedSkillRenderLimit: Int
    let totalFilteredSharedSkillsCount: Int
    let filteredSharedSkills: [InstalledSkill]
    @Binding var externalSkillRenderLimit: Int
    let totalFilteredExternalSkillsCount: Int
    let filteredExternalSkills: [InstalledSkill]
    let installedSearchSummary: String
    let onDeleteRequest: (InstalledSkill) -> Void

    var body: some View {
        installSection
        installedSearchSection
        installedSkillsSection

        if shouldShowExternalSkillsSection {
            externalSkillsSection
        }

        Section(l10n["skills_security"]) {
            Text(l10n["skills_security_hint"])
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var shouldShowExternalSkillsSection: Bool {
        totalFilteredExternalSkillsCount > 0 || !installedSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldShowMoreSharedSkills: Bool {
        installedSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && filteredSharedSkills.count < totalFilteredSharedSkillsCount
    }

    private var hiddenSharedSkillsCount: Int {
        max(totalFilteredSharedSkillsCount - filteredSharedSkills.count, 0)
    }

    private var shouldShowMoreExternalSkills: Bool {
        installedSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && filteredExternalSkills.count < totalFilteredExternalSkillsCount
    }

    private var hiddenExternalSkillsCount: Int {
        max(totalFilteredExternalSkillsCount - filteredExternalSkills.count, 0)
    }

    private var installSection: some View {
        Section(l10n["skills_install"]) {
            VStack(alignment: .leading, spacing: 8) {
                TextField(l10n["skills_install_placeholder"], text: $viewModel.installReference)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.isInstallingReference)
                    .onSubmit {
                        viewModel.installFromReference()
                    }

                HStack(spacing: 8) {
                    Button {
                        viewModel.installFromReference()
                    } label: {
                        HStack(spacing: 6) {
                            Text(l10n["skills_install_from_github"])
                            if viewModel.isInstallingReference {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        viewModel.isInstallingReference
                            || viewModel.installReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    Button(l10n["import"]) {
                        viewModel.importFolder()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isInstallingReference)
                }

                Text(l10n["skills_install_hint"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var installedSearchSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField(l10n["skills_installed_search_placeholder"], text: $installedSearchQuery)
                        .textFieldStyle(.roundedBorder)

                    if !installedSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            installedSearchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(installedSearchSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var installedSkillsSection: some View {
        Section(l10n["skills_installed"]) {
            if !sharedSkills.filter(\.isUpdatable).isEmpty {
                Button {
                    viewModel.updateAllSkills()
                } label: {
                    HStack(spacing: 6) {
                        Text(l10n["skills_update_all"])
                        if viewModel.isUpdatingSkills {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .buttonStyle(.bordered)
            }

            if sharedSkills.isEmpty {
                Text(l10n["skills_empty"])
                    .foregroundStyle(.secondary)
            } else if filteredSharedSkills.isEmpty {
                Text(l10n["skills_installed_search_empty"])
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredSharedSkills) { skill in
                    InstalledSkillRow(skill: skill) {
                        viewModel.reveal(skill.directoryURL)
                    } onPreview: {
                        viewModel.preview(skill)
                    } onUpdate: {
                        viewModel.update(skill)
                    } onAdopt: {
                        viewModel.adopt(skill)
                    } onDelete: {
                        onDeleteRequest(skill)
                    }
                }

                if shouldShowMoreSharedSkills {
                    Button(String(format: l10n["skills_show_more"], hiddenSharedSkillsCount)) {
                        // Expand in-place so users can keep the grouped form look without paying the full first-render cost.
                        sharedSkillRenderLimit += 24
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var externalSkillsSection: some View {
        Section(l10n["skills_external"]) {
            Text(l10n["skills_external_hint"])
                .font(.caption)
                .foregroundStyle(.secondary)

            if filteredExternalSkills.contains(where: \.isAdoptableToSharedLibrary) {
                Button(l10n["skills_adopt_all"]) {
                    viewModel.adoptAllExternalSkills()
                }
                .buttonStyle(.borderedProminent)
            }

            if filteredExternalSkills.isEmpty {
                Text(l10n["skills_installed_search_empty"])
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredExternalSkills) { skill in
                    InstalledSkillRow(skill: skill) {
                        viewModel.reveal(skill.directoryURL)
                    } onPreview: {
                        viewModel.preview(skill)
                    } onUpdate: {
                        viewModel.update(skill)
                    } onAdopt: {
                        viewModel.adopt(skill)
                    } onDelete: {
                        onDeleteRequest(skill)
                    }
                }

                if shouldShowMoreExternalSkills {
                    Button(String(format: l10n["skills_show_more"], hiddenExternalSkillsCount)) {
                        // Expand external skills on demand because legacy folders can also produce many expensive rows.
                        externalSkillRenderLimit += 24
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}

struct SkillAgentsTabContent: View {
    @ObservedObject private var l10n = L10n.shared
    @Bindable var viewModel: SkillPlatformViewModel
    let sharedSkillsCount: Int
    let linkedAgentCount: Int
    let externalSkillsCount: Int
    let conflictAgentSnapshots: [SkillAgentLinkSnapshot]
    let platformHealthItems: [String]

    var body: some View {
        sharedLibrarySection

        if !platformHealthItems.isEmpty {
            Section(l10n["skills_health"]) {
                ForEach(platformHealthItems, id: \.self) { item in
                    Text(item)
                        .font(.system(size: 12))
                }
            }
        }

        Section(l10n["skills_agent_links"]) {
            if !conflictAgentSnapshots.isEmpty {
                Button(l10n["skills_resolve_all_conflicts"]) {
                    viewModel.resolveAllConflicts()
                }
                .buttonStyle(.borderedProminent)
            }

            ForEach(viewModel.agentSnapshots) { snapshot in
                SkillAgentLinkRow(
                    snapshot: snapshot,
                    path: viewModel.manager.displayPath(snapshot.skillsURL)
                ) {
                    viewModel.reveal(snapshot.skillsURL.deletingLastPathComponent())
                } onLink: {
                    viewModel.link(snapshot)
                } onResolve: {
                    viewModel.resolveConflict(snapshot)
                } onUnlink: {
                    viewModel.unlink(snapshot)
                }
            }
        }
    }

    private var sharedLibrarySection: some View {
        Section(l10n["skills_shared_library"]) {
            VStack(alignment: .leading, spacing: 8) {
                Text(l10n["skills_shared_library_desc"])
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Text(viewModel.manager.displayPath(viewModel.manager.sharedRootURL))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    Button(l10n["open_folder"]) {
                        viewModel.openSharedRoot()
                    }
                    .buttonStyle(.bordered)

                    Button {
                        viewModel.refreshLocal()
                    } label: {
                        HStack(spacing: 6) {
                            Text(l10n["refresh_now"])
                            if viewModel.isRefreshingLocal {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .buttonStyle(.bordered)

                    Button(l10n["skills_link_all_agents"]) {
                        viewModel.linkAllAgents()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Text(String(format: l10n["skills_shared_library_summary"], sharedSkillsCount, linkedAgentCount))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                if externalSkillsCount > 0 {
                    Text(String(format: l10n["skills_external_summary"], externalSkillsCount))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

struct SkillMarketplaceTabContent: View {
    @ObservedObject private var l10n = L10n.shared
    @Bindable var viewModel: SkillPlatformViewModel

    var body: some View {
        Section(l10n["skills_marketplace"]) {
            Picker(l10n["skills_marketplace_source"], selection: $viewModel.marketplaceSource) {
                Text(l10n["skills_marketplace_source_skills_sh"]).tag(SkillMarketplaceSource.skillsSh)
                Text(l10n["skills_marketplace_source_mayidata"]).tag(SkillMarketplaceSource.mayidata)
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.marketplaceSource) { _, _ in
                refreshMarketplace()
            }

            if viewModel.marketplaceSource == .skillsSh {
                Picker(l10n["skills_marketplace_skills_sh_board"], selection: $viewModel.skillsShLeaderboard) {
                    Text(l10n["skills_marketplace_board_hot"]).tag(SkillsShLeaderboardKind.hot)
                    Text(l10n["skills_marketplace_board_trending"]).tag(SkillsShLeaderboardKind.trending)
                    Text(l10n["skills_marketplace_board_all_time"]).tag(SkillsShLeaderboardKind.allTime)
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.skillsShLeaderboard) { _, _ in
                    refreshMarketplace()
                }
            }

            HStack(spacing: 8) {
                TextField(l10n["skills_search_placeholder"], text: $viewModel.marketplaceQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        refreshMarketplace()
                    }

                Button(l10n["skills_search"]) {
                    refreshMarketplace()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isRefreshingMarketplace)
            }

            HStack(spacing: 8) {
                Button {
                    refreshMarketplace()
                } label: {
                    HStack(spacing: 6) {
                        Text(l10n["skills_refresh_hot"])
                        if viewModel.isRefreshingMarketplace {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .buttonStyle(.bordered)
            }

            Text(l10n["skills_marketplace_hint"])
                .font(.caption)
                .foregroundStyle(.secondary)

            if viewModel.marketplaceHasLoaded && viewModel.marketplaceItems.isEmpty && !viewModel.isRefreshingMarketplace {
                Text(l10n["skills_marketplace_empty"])
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.marketplaceItems) { item in
                    SkillMarketplaceRow(
                        item: item,
                        onOpen: {
                            NSWorkspace.shared.open(item.htmlURL)
                        },
                        onPreview: {
                            viewModel.preview(item)
                        },
                        onInstall: {
                            viewModel.install(item)
                        },
                        isInstalling: viewModel.installingMarketplaceItemID == item.id
                    )
                }
            }
        }
    }

    private func refreshMarketplace() {
        // Refresh through a single helper so every picker and button shares the same async dispatch path.
        Task {
            await viewModel.refreshMarketplace()
        }
    }
}
