import SwiftUI
import AppKit

struct SkillsPage: View {
    @ObservedObject private var l10n = L10n.shared
    @StateObject private var viewModel = SkillPlatformViewModel()
    @State private var selectedTab: SkillsPageTab = .library
    @State private var skillPendingDeletion: InstalledSkill?

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
                            Image(systemName: viewModel.statusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(viewModel.statusIsError ? .red : .green)
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

    @ViewBuilder
    private var librarySections: some View {
        installSection
        installedSkillsSection

        if !externalSkills.isEmpty {
            externalSkillsSection
        }

        Section(l10n["skills_security"]) {
            Text(l10n["skills_security_hint"])
                .font(.caption)
                .foregroundStyle(.secondary)
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
                Text(l10n["skills_marketplace_source_all"]).tag(SkillMarketplaceSource.all)
                Text(l10n["skills_marketplace_source_skills_sh"]).tag(SkillMarketplaceSource.skillsSh)
                Text(l10n["skills_marketplace_source_github"]).tag(SkillMarketplaceSource.github)
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.marketplaceSource) { _, _ in
                Task { await viewModel.refreshMarketplace() }
            }

            if viewModel.marketplaceSource != .github {
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

                Button(l10n["skills_open_curated_list"]) {
                    if let url = URL(string: "https://github.com/VoltAgent/awesome-agent-skills") {
                        NSWorkspace.shared.open(url)
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
                    SkillMarketplaceRow(item: item) {
                        NSWorkspace.shared.open(item.htmlURL)
                    } onPreview: {
                        viewModel.preview(item)
                    } onInstall: {
                        viewModel.install(item)
                    }
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

    private var installSection: some View {
        Section(l10n["skills_install"]) {
            HStack(spacing: 8) {
                TextField(l10n["skills_install_placeholder"], text: $viewModel.installReference)
                    .textFieldStyle(.roundedBorder)

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
                .disabled(viewModel.isInstallingReference || viewModel.installReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Button(l10n["skills_import_folder"]) {
                viewModel.importFolder()
            }
            .buttonStyle(.bordered)

            Text(l10n["skills_install_hint"])
                .font(.caption)
                .foregroundStyle(.secondary)
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
            } else {
                ForEach(sharedSkills) { skill in
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

            if externalSkills.contains(where: \.isAdoptableToSharedLibrary) {
                Button(l10n["skills_adopt_all"]) {
                    viewModel.adoptAllExternalSkills()
                }
                .buttonStyle(.borderedProminent)
            }

            ForEach(externalSkills) { skill in
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.text.fill")
                .frame(width: 20)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(skill.name)
                    storageBadge
                    sourceBadge
                }

                Text(skill.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let version = skill.version {
                        Text("v\(version)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    if let author = skill.author {
                        Text(author)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    Text(skill.directoryURL.deletingLastPathComponent().path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(skill.folderName)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    if let modifiedLabel {
                        Text(modifiedLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button(l10n["open_folder"]) {
                    onReveal()
                }
                .buttonStyle(.bordered)

                Button(l10n["preview"]) {
                    onPreview()
                }
                .buttonStyle(.bordered)

                if skill.isUpdatable {
                    Button(l10n["skills_update"]) {
                        onUpdate()
                    }
                    .buttonStyle(.bordered)
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
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.source == .skillsSh ? "sparkles.rectangle.stack.fill" : "flame.fill")
                .frame(width: 20)
                .foregroundStyle(item.source == .skillsSh ? .blue : .orange)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.title)
                    Text(sourceTitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(item.source == .skillsSh ? .blue : .orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule(style: .continuous).fill((item.source == .skillsSh ? Color.blue : Color.orange).opacity(0.12)))
                    if let stars = item.stars {
                        Text("★ \(stars)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule(style: .continuous).fill(Color.orange.opacity(0.12)))
                    }
                    if let installs = item.installsText {
                        Text(installs)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule(style: .continuous).fill(Color.green.opacity(0.12)))
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

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button(l10n["open"]) {
                    onOpen()
                }
                .buttonStyle(.bordered)

                Button(l10n["preview"]) {
                    onPreview()
                }
                .buttonStyle(.bordered)

                Button(l10n["install"]) {
                    onInstall()
                }
                .buttonStyle(.borderedProminent)
            }
        }
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
