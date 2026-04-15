import SwiftUI
import AppKit
import SuperIslandCore

// MARK: - Sound Page

struct SoundPage: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.soundEnabled) private var soundEnabled = SettingsDefaults.soundEnabled
    @AppStorage(SettingsKey.soundVolume) private var soundVolume = SettingsDefaults.soundVolume
    @AppStorage(SettingsKey.soundSessionStart) private var soundSessionStart = SettingsDefaults.soundSessionStart
    @AppStorage(SettingsKey.soundTaskComplete) private var soundTaskComplete = SettingsDefaults.soundTaskComplete
    @AppStorage(SettingsKey.soundTaskError) private var soundTaskError = SettingsDefaults.soundTaskError
    @AppStorage(SettingsKey.soundApprovalNeeded) private var soundApprovalNeeded = SettingsDefaults.soundApprovalNeeded
    @AppStorage(SettingsKey.soundPromptSubmit) private var soundPromptSubmit = SettingsDefaults.soundPromptSubmit
    @AppStorage(SettingsKey.soundBoot) private var soundBoot = SettingsDefaults.soundBoot
    @AppStorage(SettingsKey.soundPackID) private var soundPackID = SettingsDefaults.soundPackID
    @State private var soundPacks: [SoundPack] = SoundPackCatalog.discoverPacks()
    @State private var registryEntries: [SoundPackRegistryEntry] = SoundPackRegistry.loadCachedEntries()
    @State private var isRefreshingRegistry = false
    @State private var installingRegistryIDs: Set<String> = []
    @State private var registryStatusMessage = ""
    @State private var registryStatusIsError = false

    var body: some View {
        Form {
            Section {
                Toggle(l10n["enable_sound"], isOn: $soundEnabled)
                if soundEnabled {
                    HStack(spacing: 8) {
                        Text(l10n["volume"])
                        Image(systemName: "speaker.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { Double(soundVolume) },
                                set: { soundVolume = Int($0) }
                            ),
                            in: 0...100,
                            step: 5
                        )
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("\(soundVolume)%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }

                    Picker(l10n["sound_pack"], selection: $soundPackID) {
                        ForEach(soundPacks) { pack in
                            Text(pack.title).tag(pack.id)
                        }
                    }

                    HStack(spacing: 8) {
                        if let selectedPack = soundPacks.first(where: { $0.id == soundPackID }) {
                            Text(selectedPack.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(l10n["open_sound_pack_folder"]) {
                            SoundPackCatalog.openUserPackRoot()
                            refreshSoundPacks()
                        }
                        .buttonStyle(.link)

                        Button(isRefreshingRegistry ? l10n["sound_pack_syncing"] : l10n["sound_pack_sync"]) {
                            refreshRegistry()
                        }
                        .buttonStyle(.link)
                        .disabled(isRefreshingRegistry)
                    }
                }
            }

            if !registryEntries.isEmpty || !registryStatusMessage.isEmpty {
                Section(l10n["sound_pack_catalog"]) {
                    if !registryStatusMessage.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: registryStatusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(registryStatusIsError ? .red : .green)
                            Text(registryStatusMessage)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(registryEntries) { entry in
                        RegistrySoundPackRow(
                            entry: entry,
                            isInstalled: soundPacks.contains(where: { $0.id == entry.id }),
                            isInstalling: installingRegistryIDs.contains(entry.id),
                            isSelected: soundPackID == entry.id
                        ) {
                            useOrInstall(entry)
                        }
                    }
                }
            }

            if soundEnabled {
                Section(l10n["sessions"]) {
                    SoundEventRow(title: l10n["session_start"], subtitle: l10n["new_claude_session"], cue: .sessionStart, isOn: $soundSessionStart)
                    SoundEventRow(title: l10n["task_complete"], subtitle: l10n["ai_completed_reply"], cue: .taskComplete, isOn: $soundTaskComplete)
                    SoundEventRow(title: l10n["task_error"], subtitle: l10n["tool_or_api_error"], cue: .taskError, isOn: $soundTaskError)
                }

                Section(l10n["interaction"]) {
                    SoundEventRow(title: l10n["approval_needed"], subtitle: l10n["waiting_approval_desc"], cue: .inputRequired, isOn: $soundApprovalNeeded)
                    SoundEventRow(title: l10n["task_confirmation"], subtitle: l10n["you_sent_message"], cue: .taskAcknowledge, isOn: $soundPromptSubmit)
                }

                Section(l10n["system_section"]) {
                    BootSoundRow(title: l10n["boot_sound"], subtitle: l10n["boot_sound_desc"], isOn: $soundBoot)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshSoundPacks()
            registryEntries = SoundPackRegistry.loadCachedEntries()
        }
    }

    private func refreshSoundPacks() {
        soundPacks = SoundPackCatalog.discoverPacks()
        if !soundPacks.contains(where: { $0.id == soundPackID }) {
            soundPackID = SettingsDefaults.soundPackID
        }
    }

    private func refreshRegistry() {
        isRefreshingRegistry = true
        registryStatusMessage = ""
        registryStatusIsError = false

        Task {
            do {
                let entries = try await SoundPackRegistry.refreshEntries()
                await MainActor.run {
                    registryEntries = entries
                    isRefreshingRegistry = false
                    registryStatusMessage = l10n["sound_pack_sync_complete"]
                    registryStatusIsError = false
                }
            } catch {
                await MainActor.run {
                    isRefreshingRegistry = false
                    registryStatusMessage = error.localizedDescription
                    registryStatusIsError = true
                }
            }
        }
    }

    private func useOrInstall(_ entry: SoundPackRegistryEntry) {
        if soundPacks.contains(where: { $0.id == entry.id }) {
            soundPackID = entry.id
            return
        }

        installingRegistryIDs.insert(entry.id)
        registryStatusMessage = ""

        Task {
            do {
                _ = try await SoundPackRegistry.install(entry: entry)
                await MainActor.run {
                    installingRegistryIDs.remove(entry.id)
                    refreshSoundPacks()
                    soundPackID = entry.id
                    registryStatusMessage = l10n["sound_pack_install_complete"]
                    registryStatusIsError = false
                }
            } catch {
                await MainActor.run {
                    installingRegistryIDs.remove(entry.id)
                    registryStatusMessage = error.localizedDescription
                    registryStatusIsError = true
                }
            }
        }
    }
}

private struct SoundEventRow: View {
    let title: String
    var subtitle: String? = nil
    let cue: SoundCue
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 16)
            Button {
                SoundManager.shared.preview(cue: cue)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

private struct BootSoundRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 16)
            Button {
                SoundManager.shared.previewBoot()
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

private struct RegistrySoundPackRow: View {
    let entry: SoundPackRegistryEntry
    let isInstalled: Bool
    let isInstalling: Bool
    let isSelected: Bool
    let action: () -> Void

    private var accent: Color {
        color(from: entry.accentHex) ?? .blue
    }

    private var actionTitle: String {
        if isInstalling {
            return L10n.shared["sound_pack_installing"]
        }
        if isInstalled {
            return isSelected ? L10n.shared["sound_pack_in_use"] : L10n.shared["sound_pack_use"]
        }
        return L10n.shared["sound_pack_install"]
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.systemName)
                .frame(width: 20)
                .foregroundStyle(accent)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                    Text(entry.trustLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule(style: .continuous).fill(accent.opacity(0.12)))
                }

                Text(entry.compactMeta)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                Text(entry.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button(actionTitle) {
                action()
            }
            .buttonStyle(.bordered)
            .disabled(isInstalling)
        }
    }

    private func color(from hex: String) -> Color? {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") {
            raw.removeFirst()
        }
        guard raw.count == 6, let value = Int(raw, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return Color(red: red, green: green, blue: blue)
    }
}
