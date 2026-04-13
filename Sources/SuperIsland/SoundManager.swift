import AppKit

@MainActor
class SoundManager {
    static let shared = SoundManager()

    private let defaults = UserDefaults.standard
    private var soundCache: [String: NSSound] = [:]

    static let eventSounds: [(event: String, cue: SoundCue, key: String, label: String)] = [
        ("SessionStart", .sessionStart, SettingsKey.soundSessionStart, "会话开始"),
        ("Stop", .taskComplete, SettingsKey.soundTaskComplete, "任务完成"),
        ("PostToolUseFailure", .taskError, SettingsKey.soundTaskError, "任务错误"),
        ("PermissionRequest", .inputRequired, SettingsKey.soundApprovalNeeded, "需要审批"),
        ("UserPromptSubmit", .taskAcknowledge, SettingsKey.soundPromptSubmit, "任务确认"),
    ]

    private init() {
        preloadDefaultSounds()
    }

    func handleEvent(_ eventName: String) {
        guard defaults.bool(forKey: SettingsKey.soundEnabled) else { return }
        guard let entry = Self.eventSounds.first(where: { $0.event == eventName }) else { return }
        guard defaults.bool(forKey: entry.key) else { return }
        play(cue: entry.cue)
    }

    func playBoot() {
        guard defaults.bool(forKey: SettingsKey.soundEnabled) else { return }
        guard defaults.bool(forKey: SettingsKey.soundBoot) else { return }
        playDefault(named: "8bit_boot")
    }

    func preview(cue: SoundCue) {
        play(cue: cue, prefersPreview: true)
    }

    func previewBoot() {
        playDefault(named: "8bit_boot")
    }

    private func preloadDefaultSounds() {
        for name in ["8bit_start", "8bit_submit", "8bit_approval", "8bit_complete", "8bit_error", "8bit_boot"] {
            if let sound = loadDefaultSound(name) {
                soundCache[name] = sound
            }
        }
    }

    private func play(cue: SoundCue, prefersPreview: Bool = false) {
        let selectedPack = SoundPackCatalog.selectedPack()
        if let url = selectedPack.url(for: cue, prefersPreview: prefersPreview) {
            play(url: url)
            return
        }
        playDefault(named: fallbackSoundName(for: cue))
    }

    private func fallbackSoundName(for cue: SoundCue) -> String {
        switch cue {
        case .sessionStart: return "8bit_start"
        case .taskAcknowledge: return "8bit_submit"
        case .inputRequired: return "8bit_approval"
        case .taskComplete: return "8bit_complete"
        case .taskError: return "8bit_error"
        }
    }

    private func playDefault(named name: String) {
        guard let sound = soundCache[name] ?? loadDefaultSound(name) else {
            NSSound.beep()
            return
        }
        if sound.isPlaying { sound.stop() }
        let volume = defaults.integer(forKey: SettingsKey.soundVolume)
        sound.volume = Float(volume) / 100.0
        sound.play()
    }

    private func play(url: URL) {
        guard let sound = NSSound(contentsOf: url, byReference: false) else {
            NSSound.beep()
            return
        }
        let volume = defaults.integer(forKey: SettingsKey.soundVolume)
        sound.volume = Float(volume) / 100.0
        sound.play()
    }

    private func loadDefaultSound(_ name: String) -> NSSound? {
        if let url = AppResourceBundle.bundle.url(forResource: name, withExtension: "wav", subdirectory: "Resources") {
            return NSSound(contentsOf: url, byReference: false)
        }
        if let url = AppResourceBundle.bundle.url(forResource: name, withExtension: "wav") {
            return NSSound(contentsOf: url, byReference: false)
        }
        return nil
    }
}
