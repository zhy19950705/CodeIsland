import SwiftUI
import AppKit

struct SkillsPage: View {
    @ObservedObject private var l10n = L10n.shared
    @StateObject private var viewModel = SkillPlatformViewModel()
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
                switch selectedTab {
                case .library:
                    librarySections
                case .agents:
                    agentSections
                case .marketplace:
                    marketplaceSections
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

    @ViewBuilder
    private var librarySections: some View {
        installedSearchSection
        installedSkillsSection

        if !filteredExternalSkills.isEmpty || !installedSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            externalSkillsSection
        }

        Section(l10n["skills_security"]) {
            Text(l10n["skills_security_hint"])
                .font(.caption)
                .foregroundStyle(.secondary)
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

    @ViewBuilder
    private var agentSections: some View {
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

    @ViewBuilder
    private var marketplaceSections: some View {
        Section(l10n["skills_marketplace"]) {
            Picker(l10n["skills_marketplace_source"], selection: $viewModel.marketplaceSource) {
                Text(l10n["skills_marketplace_source_skills_sh"]).tag(SkillMarketplaceSource.skillsSh)
                Text(l10n["skills_marketplace_source_mayidata"]).tag(SkillMarketplaceSource.mayidata)
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.marketplaceSource) { _, _ in
                Task { await viewModel.refreshMarketplace() }
            }

            if viewModel.marketplaceSource == .skillsSh {
                Picker(l10n["skills_marketplace_skills_sh_board"], selection: $viewModel.skillsShLeaderboard) {
                    Text(l10n["skills_marketplace_board_hot"]).tag(SkillsShLeaderboardKind.hot)
                    Text(l10n["skills_marketplace_board_trending"]).tag(SkillsShLeaderboardKind.trending)
                    Text(l10n["skills_marketplace_board_all_time"]).tag(SkillsShLeaderboardKind.allTime)
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.skillsShLeaderboard) { _, _ in
                    Task { await viewModel.refreshMarketplace() }
                }
            }

            HStack(spacing: 8) {
                TextField(l10n["skills_search_placeholder"], text: $viewModel.marketplaceQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await viewModel.refreshMarketplace() }
                    }

                Button(l10n["skills_search"]) {
                    Task {
                        await viewModel.refreshMarketplace()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isRefreshingMarketplace)
            }

            HStack(spacing: 8) {
                Button {
                    Task {
                        await viewModel.refreshMarketplace()
                    }
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

                Text(String(format: l10n["skills_shared_library_summary"], sharedSkills.count, linkedAgentCount))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                if !externalSkills.isEmpty {
                    Text(String(format: l10n["skills_external_summary"], externalSkills.count))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
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
                        skillPendingDeletion = skill
                    }
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
                        skillPendingDeletion = skill
                    }
                }
            }
        }
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

private struct SkillAgentLinkRow: View {
    @ObservedObject private var l10n = L10n.shared
    let snapshot: SkillAgentLinkSnapshot
    let path: String
    let onRevealParent: () -> Void
    let onLink: () -> Void
    let onResolve: () -> Void
    let onUnlink: () -> Void

    private var badgeTitle: String {
        switch snapshot.state {
        case .native: return l10n["skills_status_native"]
        case .linked: return l10n["skills_status_linked"]
        case .missing: return l10n["skills_status_missing"]
        case .conflict: return l10n["skills_status_conflict"]
        }
    }

    private var badgeColor: Color {
        switch snapshot.state {
        case .native: return .blue
        case .linked: return .green
        case .missing: return .orange
        case .conflict: return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: snapshot.agent.systemName)
                .frame(width: 22)
                .foregroundStyle(badgeColor)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(snapshot.agent.title)
                    Text(badgeTitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(badgeColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule(style: .continuous).fill(badgeColor.opacity(0.12)))
                }

                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)

                Text(snapshot.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button(l10n["open_folder"]) {
                    onRevealParent()
                }
                .buttonStyle(.bordered)

                switch snapshot.state {
                case .native:
                    EmptyView()
                case .linked:
                    Button(l10n["skills_unlink"]) {
                        onUnlink()
                    }
                    .buttonStyle(.bordered)
                case .missing:
                    Button(l10n["skills_link"]) {
                        onLink()
                    }
                    .buttonStyle(.borderedProminent)
                case .conflict:
                    Button(l10n["skills_resolve_conflict"]) {
                        onResolve()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

private struct InstalledSkillRow: View {
    @ObservedObject private var l10n = L10n.shared
    let skill: InstalledSkill
    let onReveal: () -> Void
    let onPreview: () -> Void
    let onUpdate: () -> Void
    let onAdopt: () -> Void
    let onDelete: () -> Void

    private var modifiedLabel: String? {
        guard let modifiedAt = skill.modifiedAt else { return nil }
        return RelativeDateTimeFormatter().localizedString(for: modifiedAt, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "doc.text.fill")
                    .frame(width: 20)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 6) {
                    Text(skill.name)
                        .font(.system(size: 16, weight: .semibold))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            storageBadge
                            sourceBadge
                        }
                    }

                    Text(skill.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text(skill.directoryURL.deletingLastPathComponent().path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            if let version = skill.version {
                                metadataTag("v\(version)", monospaced: true)
                            }
                            if let author = skill.author {
                                metadataTag(author)
                            }
                            metadataTag(skill.folderName, monospaced: true)
                            if let modifiedLabel {
                                metadataTag(modifiedLabel)
                            }
                        }
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    actionButton(l10n["open_folder"]) {
                        onReveal()
                    }

                    actionButton(l10n["preview"]) {
                        onPreview()
                    }

                    if skill.isUpdatable {
                        actionButton(l10n["skills_update"]) {
                            onUpdate()
                        }
                    }

                    if skill.isAdoptableToSharedLibrary {
                        Button(l10n["skills_adopt"]) {
                            onAdopt()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Text(l10n["delete"])
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.leading, 30)
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
    }

    private func metadataTag(_ title: String, monospaced: Bool = false) -> some View {
        Text(title)
            .font(.system(size: 11, design: monospaced ? .monospaced : .default))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
    }

    @ViewBuilder
    private var sourceBadge: some View {
        if let source = skill.sourceMetadata?.repoFullName {
            Text(source)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.blue)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule(style: .continuous).fill(Color.blue.opacity(0.12)))
        }
    }

    private var storageBadgeColor: Color {
        switch skill.storageKind {
        case .shared:
            return .green
        case .legacyAgent:
            return .orange
        case .agent:
            return .purple
        }
    }

    private var storageBadgeTitle: String {
        switch skill.storageKind {
        case .shared:
            return l10n["skills_storage_shared"]
        case .legacyAgent:
            return l10n["skills_storage_legacy"]
        case .agent(let agent):
            return agent.title
        }
    }

    private var storageBadge: some View {
        Text(storageBadgeTitle)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(storageBadgeColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule(style: .continuous).fill(storageBadgeColor.opacity(0.12)))
    }
}

private struct SkillMarketplaceRow: View {
    @ObservedObject private var l10n = L10n.shared
    let item: SkillMarketplaceItem
    let onOpen: () -> Void
    let onPreview: () -> Void
    let onInstall: () -> Void
    let isInstalling: Bool

    private var updatedLabel: String? {
        guard let updatedAt = item.updatedAt else { return nil }
        return RelativeDateTimeFormatter().localizedString(for: updatedAt, relativeTo: Date())
    }

    private var sourceTitle: String {
        switch item.source {
        case .github:
            return "GitHub"
        case .skillsSh:
            return "skills.sh"
        case .mayidata:
            return "Mayidata"
        }
    }

    private var sourceColor: Color {
        switch item.source {
        case .github:
            return .orange
        case .skillsSh:
            return .blue
        case .mayidata:
            return .green
        }
    }

    private var sourceIcon: String {
        switch item.source {
        case .github:
            return "flame.fill"
        case .skillsSh:
            return "sparkles.rectangle.stack.fill"
        case .mayidata:
            return "building.2.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: sourceIcon)
                    .frame(width: 20)
                    .foregroundStyle(sourceColor)

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 16, weight: .semibold))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            marketplaceBadge(sourceTitle, color: sourceColor)
                            if let stars = item.stars {
                                marketplaceBadge("★ \(stars)", color: .orange)
                            }
                            if let installs = item.installsText {
                                marketplaceBadge(installs, color: .green)
                            }
                        }
                    }

                    Text(item.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    let tags = Array(item.topics.prefix(4))
                    if !tags.isEmpty || item.language != nil || !item.repoFullName.isEmpty {
                        let meta = [item.repoFullName] + [item.language].compactMap { $0 }
                        Text((meta.filter { !$0.isEmpty } + tags).joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }

                    if let updatedLabel {
                        Text(String(format: l10n["skills_marketplace_updated"], updatedLabel))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button(l10n["open"]) {
                        onOpen()
                    }
                    .buttonStyle(.bordered)

                    Button(l10n["preview"]) {
                        onPreview()
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onInstall()
                    } label: {
                        HStack(spacing: 6) {
                            if isInstalling {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isInstalling ? "Installing…" : l10n["install"])
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!item.canInstallDirectly || isInstalling)
                }
            }
            .padding(.leading, 30)
        }
    }

    private func marketplaceBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule(style: .continuous).fill(color.opacity(0.12)))
    }
}

private struct SkillPreviewSheet: View {
    let document: SkillPreviewDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.system(size: 18, weight: .semibold))
                Text(document.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if !document.metadata.isEmpty {
                FlowMetadataView(items: document.metadata)
            }

            if let sourceURL = document.sourceURL {
                Button("Open Source") {
                    NSWorkspace.shared.open(sourceURL)
                }
                .buttonStyle(.bordered)
            }

            ScrollView {
                SkillMarkdownText(markdown: document.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 520)
    }
}

private struct FlowMetadataView: View {
    let items: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                }
            }
        }
    }
}

private struct SkillMarkdownText: View {
    let markdown: String

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        ) {
            Text(attributed)
                .textSelection(.enabled)
        } else {
            Text(markdown)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}
