import SwiftUI
import AppKit

// SkillPlatformComponents groups reusable row and preview views so the page file only owns tab state and filtering.
struct SkillAgentLinkRow: View {
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

struct InstalledSkillRow: View {
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

struct SkillMarketplaceRow: View {
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
