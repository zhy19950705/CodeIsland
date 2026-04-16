import SwiftUI
import AppKit
import SuperIslandCore

// HooksPage owns the diagnostics state and actions for hook, editor bridge, and CLI integration management.
struct HooksPage: View {
    @ObservedObject private var l10n = AppText.shared
    let appState: AppState?
    @State private var cliSnapshots: [CLIIntegrationSnapshot] = []
    @State private var editorSnapshots: [EditorBridgeSnapshot] = []
    @State private var statusMessage = ""
    @State private var statusIsError = false
    @State private var refreshKey = UUID()
    @State private var isExportingDiagnostics = false

    private let cliIntegrationManager = CLIIntegrationManager()
    private let editorBridgeManager = EditorBridgeManager()

    private var enabledHealthyCount: Int {
        cliSnapshots.filter { snapshot in
            ConfigInstaller.isEnabled(source: snapshot.integration.rawValue) && snapshot.state == .active
        }.count
    }

    private var enabledNeedsRepairCount: Int {
        cliSnapshots.filter { snapshot in
            ConfigInstaller.isEnabled(source: snapshot.integration.rawValue) && snapshot.state != .active
        }.count
    }

    private var disabledCount: Int {
        cliSnapshots.filter { snapshot in
            !ConfigInstaller.isEnabled(source: snapshot.integration.rawValue)
        }.count
    }

    var body: some View {
        Form {
            Section(l10n["hooks_health"]) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: enabledNeedsRepairCount == 0 ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(enabledNeedsRepairCount == 0 ? .green : .orange)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(enabledNeedsRepairCount == 0 ? l10n["hooks_health_ok"] : "\(enabledNeedsRepairCount) \(l10n["hooks_health_attention"])")
                            .font(.headline)
                        Text("\(l10n["hooks_health_enabled_active"]): \(enabledHealthyCount)")
                            .foregroundStyle(.secondary)
                        Text("\(l10n["hooks_health_enabled_issues"]): \(enabledNeedsRepairCount)")
                            .foregroundStyle(enabledNeedsRepairCount == 0 ? Color.secondary : .orange)
                        Text("\(l10n["hooks_health_disabled"]): \(disabledCount)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    Button {
                        let repaired = ConfigInstaller.verifyAndRepair()
                        refreshDiagnostics()
                        if repaired.isEmpty {
                            statusMessage = enabledNeedsRepairCount == 0
                                ? l10n["hooks_repair_not_needed"]
                                : l10n["install_failed"]
                            statusIsError = enabledNeedsRepairCount != 0
                        } else {
                            statusMessage = "\(l10n["hooks_repaired"]): \(repaired.joined(separator: ", "))"
                            statusIsError = false
                        }
                    } label: {
                        Text(l10n["hooks_repair"])
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        refreshDiagnostics()
                    } label: {
                        Text(l10n["hooks_refresh_status"])
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }

            Section(l10n["editor_bridges"]) {
                ForEach(editorSnapshots) { snapshot in
                    EditorBridgeRow(snapshot: snapshot) {
                        editorBridgeManager.openInstallLocation(for: snapshot.host)
                    } onInstallExtension: {
                        do {
                            try IDEExtensionInstaller.install(snapshot.host.extensionHost)
                            refreshDiagnostics()
                            statusMessage = "\(snapshot.host.title) \(l10n["editor_extension_installed"].lowercased())"
                            statusIsError = false
                        } catch {
                            statusMessage = error.localizedDescription
                            statusIsError = true
                        }
                    } onReinstallExtension: {
                        do {
                            try IDEExtensionInstaller.reinstall(snapshot.host.extensionHost)
                            refreshDiagnostics()
                            statusMessage = "\(snapshot.host.title) \(l10n["reinstall_extension"].lowercased())"
                            statusIsError = false
                        } catch {
                            statusMessage = error.localizedDescription
                            statusIsError = true
                        }
                    } onUninstallExtension: {
                        IDEExtensionInstaller.uninstall(snapshot.host.extensionHost)
                        refreshDiagnostics()
                        statusMessage = "\(snapshot.host.title) \(l10n["uninstall_extension"].lowercased())"
                        statusIsError = false
                    }
                }
            }

            Section(l10n["cli_integrations"]) {
                ForEach(cliSnapshots) { snapshot in
                    CLIIntegrationRow(snapshot: snapshot) {
                        cliIntegrationManager.openConfig(for: snapshot.integration)
                    } onToggle: { enabled in
                        _ = ConfigInstaller.setEnabled(source: snapshot.integration.rawValue, enabled: enabled)
                        refreshDiagnostics()
                    }
                    .id("\(snapshot.integration.rawValue)-\(refreshKey)")
                }
            }

            Section(l10n["management"]) {
                HStack(spacing: 8) {
                    Button {
                        // Enable all detected CLIs before reinstalling
                        for cli in ConfigInstaller.allCLIs where ConfigInstaller.cliExists(source: cli.source) {
                            UserDefaults.standard.set(true, forKey: "cli_enabled_\(cli.source)")
                        }
                        if ConfigInstaller.cliExists(source: "opencode") {
                            UserDefaults.standard.set(true, forKey: "cli_enabled_opencode")
                        }
                        if ConfigInstaller.install() {
                            refreshDiagnostics()
                            statusMessage = l10n["hooks_installed"]
                            statusIsError = false
                        } else {
                            statusMessage = l10n["install_failed"]
                            statusIsError = true
                        }
                    } label: {
                        Text(l10n["reinstall"])
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        // Disable all CLIs before uninstalling
                        for cli in ConfigInstaller.allCLIs {
                            UserDefaults.standard.set(false, forKey: "cli_enabled_\(cli.source)")
                        }
                        UserDefaults.standard.set(false, forKey: "cli_enabled_opencode")
                        ConfigInstaller.uninstall()
                        refreshDiagnostics()
                        statusMessage = l10n["hooks_uninstalled"]
                        statusIsError = false
                    } label: {
                        Text(l10n["uninstall"])
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                if !statusMessage.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: statusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(statusIsError ? .red : .green)
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(l10n["diagnostics"]) {
                Button {
                    exportDiagnostics()
                } label: {
                    HStack {
                        Text(l10n["diagnostics_export_archive"])
                        Spacer()
                        if isExportingDiagnostics {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(isExportingDiagnostics || appState == nil)

                Text(l10n["diagnostics_export_desc"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshDiagnostics() }
    }

    private func refreshDiagnostics() {
        cliSnapshots = cliIntegrationManager.snapshots()
        editorSnapshots = editorBridgeManager.snapshots()
        refreshKey = UUID()
    }

    private func exportDiagnostics() {
        guard let appState else { return }

        let panel = NSSavePanel()
        panel.title = l10n["diagnostics_save_title"]
        panel.nameFieldStringValue = l10n["diagnostics_save_filename"]
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        isExportingDiagnostics = true
        statusMessage = ""
        statusIsError = false

        let snapshot = appState.diagnosticsSnapshot()
        Task {
            do {
                let result = try await DiagnosticsExporter.shared.exportArchive(
                    snapshot: snapshot,
                    to: destinationURL
                )
                await MainActor.run {
                    isExportingDiagnostics = false
                    statusIsError = false
                    statusMessage = result.warnings.isEmpty
                        ? String(format: l10n["diagnostics_exported_format"], result.archiveURL.path)
                        : String(format: l10n["diagnostics_exported_with_warnings_format"], result.warnings.count, result.archiveURL.path)
                    NSWorkspace.shared.activateFileViewerSelecting([result.archiveURL])
                }
            } catch {
                await MainActor.run {
                    isExportingDiagnostics = false
                    statusIsError = true
                    statusMessage = error.localizedDescription
                }
            }
        }
    }
}
