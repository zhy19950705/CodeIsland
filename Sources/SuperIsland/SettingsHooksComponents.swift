import SwiftUI
import AppKit
import SuperIslandCore

// These row-level components are shared by the hooks and AI settings pages, so keep them out of the page shell.
struct EditorBridgeRow: View {
    @ObservedObject private var l10n = L10n.shared
    let snapshot: EditorBridgeSnapshot
    let onOpen: () -> Void
    let onInstallExtension: () -> Void
    let onReinstallExtension: () -> Void
    let onUninstallExtension: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: snapshot.host.systemName)
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.host.title)
                    Text(l10n[snapshot.state.detailKey])
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text(snapshot.extensionInstalled ? l10n["editor_extension_installed"] : l10n["editor_extension_missing"])
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(snapshot.extensionInstalled ? .green : .orange)
                    if let installPath = snapshot.installPath {
                        Text(installPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                IntegrationStateBadge(title: l10n[snapshot.state.titleKey], state: snapshot.state)
                if snapshot.state != .unavailable {
                    Button(l10n["open_app"]) {
                        onOpen()
                    }
                    .buttonStyle(.link)
                }
                if snapshot.extensionInstalled {
                    Button(l10n["reinstall_extension"]) {
                        onReinstallExtension()
                    }
                    .buttonStyle(.link)

                    Button(l10n["uninstall_extension"]) {
                        onUninstallExtension()
                    }
                    .buttonStyle(.link)
                } else if snapshot.state != .unavailable {
                    Button(l10n["install_extension"]) {
                        onInstallExtension()
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }
}

struct CLIIntegrationRow: View {
    @ObservedObject private var l10n = L10n.shared
    let snapshot: CLIIntegrationSnapshot
    let onOpenConfig: () -> Void
    let onToggle: (Bool) -> Void

    @State private var enabled: Bool

    init(snapshot: CLIIntegrationSnapshot, onOpenConfig: @escaping () -> Void, onToggle: @escaping (Bool) -> Void) {
        self.snapshot = snapshot
        self.onOpenConfig = onOpenConfig
        self.onToggle = onToggle
        _enabled = State(initialValue: ConfigInstaller.isEnabled(source: snapshot.integration.rawValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let icon = cliIcon(source: snapshot.integration.rawValue, size: 20) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.integration.title)
                    Text(snapshot.detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                IntegrationStateBadge(title: l10n[snapshot.state.titleKey], state: snapshot.state)
                if snapshot.configPath != nil {
                    Button(l10n["open_config"]) {
                        onOpenConfig()
                    }
                    .buttonStyle(.link)
                }
                Toggle("", isOn: $enabled)
                    .labelsHidden()
                    .onChange(of: enabled) { _, newValue in
                        onToggle(newValue)
                    }
            }
        }
    }
}

private struct IntegrationStateBadge: View {
    let title: String
    let state: Any

    private var color: Color {
        switch state {
        case let editor as EditorBridgeState:
            switch editor {
            case .live: return .green
            case .installed: return .blue
            case .unavailable: return .secondary
            }
        case let cli as CLIIntegrationState:
            switch cli {
            case .active: return .green
            case .installed: return .blue
            case .notInstalled: return .orange
            case .cliNotFound: return .secondary
            case .disabled: return .pink
            }
        default:
            return .secondary
        }
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.12))
            )
    }
}

// CodexManagedAccountRow is reused by the AI settings page, so keep it isolated from hooks-specific views.
struct CodexManagedAccountRow: View {
    @ObservedObject private var l10n = L10n.shared
    let account: CodexManagedAccount
    let isActive: Bool
    let onActivate: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(account.displayName)
                        if isActive {
                            Text(l10n["codex_account_active_badge"])
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.green.opacity(0.12))
                                )
                        }
                    }
                    Text(account.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(account.accountKey)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                HStack(spacing: 8) {
                    if !isActive {
                        Button(l10n["codex_account_activate"]) {
                            onActivate()
                        }
                        .buttonStyle(.link)
                    }
                    Button(l10n["codex_account_remove"], role: .destructive) {
                        onRemove()
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
