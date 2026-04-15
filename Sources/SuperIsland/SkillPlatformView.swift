import SwiftUI

struct SkillsPage: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var viewModel = SkillPlatformViewModel()
    @State private var selectedTab: SkillsPageTab = .library
    @State private var skillPendingDeletion: InstalledSkill?
    @State private var installedSearchQuery = ""

    var body: some View {
        VStack(spacing: 12) {
            Picker(l10n["skills_tabs"], selection: $selectedTab) {
                ForEach(SkillsPageTab.allCases) { tab in
                    Text(tab.title(l10n: l10n))
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)

            Form {
                // Keep the page shell local while tab-specific sections live in dedicated view files.
                switch selectedTab {
                case .library:
                    SkillLibraryTabContent(
                        viewModel: viewModel,
                        installedSearchQuery: $installedSearchQuery,
                        sharedSkills: sharedSkills,
                        filteredSharedSkills: filteredSharedSkills,
                        filteredExternalSkills: filteredExternalSkills,
                        installedSearchSummary: installedSearchSummary
                    ) { skill in
                        skillPendingDeletion = skill
                    }
                case .agents:
                    SkillAgentsTabContent(
                        viewModel: viewModel,
                        sharedSkillsCount: sharedSkills.count,
                        linkedAgentCount: linkedAgentCount,
                        externalSkillsCount: externalSkills.count,
                        conflictAgentSnapshots: conflictAgentSnapshots,
                        platformHealthItems: platformHealthItems
                    )
                case .marketplace:
                    SkillMarketplaceTabContent(viewModel: viewModel)
                }

                if !viewModel.statusMessage.isEmpty {
                    Section {
                        HStack(spacing: 6) {
                            if viewModel.statusIsBusy {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: viewModel.statusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                                    .foregroundStyle(viewModel.statusIsError ? .red : .green)
                            }
                            Text(viewModel.statusMessage)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding(.top, 8)
        .onAppear {
            viewModel.loadIfNeeded()
        }
        .confirmationDialog(
            l10n["skills_delete_confirm_title"],
            isPresented: deleteConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button(l10n["delete"], role: .destructive) {
                if let skillPendingDeletion {
                    viewModel.remove(skillPendingDeletion)
                    self.skillPendingDeletion = nil
                }
            }
            Button(l10n["cancel"], role: .cancel) {
                skillPendingDeletion = nil
            }
        } message: {
            if let skillPendingDeletion {
                Text(String(format: l10n["skills_delete_confirm_message"], skillPendingDeletion.name))
            }
        }
        .sheet(item: $viewModel.previewDocument) { document in
            SkillPreviewSheet(document: document)
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { skillPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    skillPendingDeletion = nil
                }
            }
        )
    }

    private var linkedAgentCount: Int {
        viewModel.agentSnapshots.filter { snapshot in
            snapshot.state == .native || snapshot.state == .linked
        }.count
    }

    private var sharedSkills: [InstalledSkill] {
        viewModel.skills.filter(\.isSharedLibrarySkill)
    }

    private var externalSkills: [InstalledSkill] {
        viewModel.skills.filter { !$0.isSharedLibrarySkill }
    }

    private var adoptableExternalSkills: [InstalledSkill] {
        externalSkills.filter(\.isAdoptableToSharedLibrary)
    }

    private var projectScopedSkills: [InstalledSkill] {
        externalSkills.filter { !$0.isAdoptableToSharedLibrary }
    }

    private var conflictAgentSnapshots: [SkillAgentLinkSnapshot] {
        viewModel.agentSnapshots.filter { $0.state == .conflict }
    }

    private var filteredSharedSkills: [InstalledSkill] {
        filteredSkills(from: sharedSkills)
    }

    private var filteredExternalSkills: [InstalledSkill] {
        filteredSkills(from: externalSkills)
    }

    private var installedSearchSummary: String {
        String(
            format: l10n["skills_installed_search_results"],
            filteredSharedSkills.count + filteredExternalSkills.count,
            sharedSkills.count + externalSkills.count
        )
    }

    private var platformHealthItems: [String] {
        var items: [String] = []
        if !adoptableExternalSkills.isEmpty {
            items.append(String(format: l10n["skills_health_external_pending"], adoptableExternalSkills.count))
        }
        if !projectScopedSkills.isEmpty {
            items.append(String(format: l10n["skills_health_project_scoped"], projectScopedSkills.count))
        }
        if !conflictAgentSnapshots.isEmpty {
            items.append(String(format: l10n["skills_health_link_conflicts"], conflictAgentSnapshots.count))
        }
        return items
    }

    private func filteredSkills(from skills: [InstalledSkill]) -> [InstalledSkill] {
        let normalizedQuery = normalizeInstalledSearchText(installedSearchQuery)
        guard !normalizedQuery.isEmpty else { return skills }

        let tokens = normalizedQuery.split(separator: " ").map(String.init)
        return skills.filter { skill in
            let haystack = [
                skill.name,
                skill.description,
                skill.version ?? "",
                skill.author ?? "",
                skill.folderName,
                skill.directoryURL.path,
                skill.sourceMetadata?.repoFullName ?? "",
                skill.sourceMetadata?.sourcePath ?? "",
                storageSearchTitle(for: skill.storageKind),
            ]
            .map(normalizeInstalledSearchText)
            .joined(separator: " ")

            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    private func storageSearchTitle(for storageKind: SkillStorageKind) -> String {
        switch storageKind {
        case .shared:
            return l10n["skills_storage_shared"]
        case .legacyAgent:
            return l10n["skills_storage_legacy"]
        case let .agent(agent):
            return agent.title
        }
    }

    private func normalizeInstalledSearchText(_ text: String) -> String {
        // Fold user input once so installed-skill search stays locale-friendly without extra allocations per token.
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let scalars = folded.unicodeScalars.map { scalar -> UnicodeScalar in
            CharacterSet.alphanumerics.contains(scalar) ? scalar : " "
        }
        return String(String.UnicodeScalarView(scalars))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

private enum SkillsPageTab: String, CaseIterable, Identifiable {
    case library
    case agents
    case marketplace

    var id: String { rawValue }

    func title(l10n: L10n) -> String {
        switch self {
        case .library:
            return l10n["skills_tab_library"]
        case .agents:
            return l10n["skills_tab_agents"]
        case .marketplace:
            return l10n["skills_tab_marketplace"]
        }
    }
}
