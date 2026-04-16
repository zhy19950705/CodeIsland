import AppKit
import Foundation

enum SoundCue: String, CaseIterable, Identifiable, Sendable {
    case sessionStart
    case taskAcknowledge
    case inputRequired
    case taskComplete
    case taskError

    var id: String { rawValue }

    init?(openPeonCategoryKey: String) {
        switch openPeonCategoryKey {
        case "session.start":
            self = .sessionStart
        case "task.acknowledge":
            self = .taskAcknowledge
        case "input.required":
            self = .inputRequired
        case "task.complete":
            self = .taskComplete
        case "task.error":
            self = .taskError
        default:
            return nil
        }
    }
}

enum SoundPackSource: String, Codable, Sendable {
    case builtIn
    case local
    case bundledDefault

    var title: String {
        switch self {
        case .builtIn: "Built-in"
        case .local: "Local"
        case .bundledDefault: "Default"
        }
    }
}

private struct LegacySoundPackManifest: Decodable {
    var id: String
    var title: String
    var subtitle: String
    var author: String?
    var accentHex: String?
    var systemName: String?
    var sounds: [String: String]
}

struct SoundPackClip: Hashable, Sendable {
    let relativePath: String
    let label: String?
}

struct SoundPack: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let author: String?
    let accentHex: String
    let systemName: String
    let source: SoundPackSource
    let manifestURL: URL?
    let registryEntry: SoundPackRegistryEntry?
    let clipsByCue: [SoundCue: [SoundPackClip]]

    var sourceDetail: String {
        if let registryEntry {
            return registryEntry.compactMeta
        }
        if let author, !author.isEmpty {
            return "\(source.title) · \(author)"
        }
        return source.title
    }

    func url(for cue: SoundCue, prefersPreview: Bool = false) -> URL? {
        guard let manifestURL,
              let clips = clipsByCue[cue],
              !clips.isEmpty else { return nil }

        let manifestDirectory = manifestURL.deletingLastPathComponent()
        let selectedClip = prefersPreview ? clips.first : (clips.randomElement() ?? clips.first)
        guard let selectedClip else { return nil }

        let candidates = [
            manifestDirectory.appendingPathComponent(selectedClip.relativePath).standardizedFileURL,
            manifestDirectory.appendingPathComponent(URL(fileURLWithPath: selectedClip.relativePath).lastPathComponent).standardizedFileURL,
        ]

        return candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }
}

enum SoundPackCatalog {
    static let defaultPackID = "default-8bit"
    private static let manifestNames = ["openpeon.json", "manifest.json"]

    static func discoverPacks(bundle: Bundle = AppResourceBundle.bundle, fileManager: FileManager = .default) -> [SoundPack] {
        var packs = [defaultPack(bundle: bundle)]
        packs.append(contentsOf: discoverBundledPacks(bundle: bundle, fileManager: fileManager))
        packs.append(contentsOf: discoverLocalPacks(fileManager: fileManager))
        return packs
    }

    static func selectedPack(bundle: Bundle = AppResourceBundle.bundle, fileManager: FileManager = .default) -> SoundPack {
        let selectedID = UserDefaults.standard.string(forKey: SettingsKey.soundPackID) ?? SettingsDefaults.soundPackID
        return discoverPacks(bundle: bundle, fileManager: fileManager).first(where: { $0.id == selectedID })
            ?? defaultPack(bundle: bundle)
    }

    static func userPackRoot(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".superisland", isDirectory: true)
            .appendingPathComponent("sound-packs", isDirectory: true)
    }

    static func ensureUserPackRootExists(fileManager: FileManager = .default) {
        let root = userPackRoot(fileManager: fileManager)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)
    }

    static func openUserPackRoot(fileManager: FileManager = .default) {
        ensureUserPackRootExists(fileManager: fileManager)
        NSWorkspace.shared.open(userPackRoot(fileManager: fileManager))
    }

    private static func defaultPack(bundle: Bundle) -> SoundPack {
        let manifestURL = bundle.resourceURL?.appendingPathComponent("Resources/default.soundpack.json", isDirectory: false)
        let clipsByCue: [SoundCue: [SoundPackClip]] = [
            .sessionStart: [SoundPackClip(relativePath: "8bit_start.wav", label: nil)],
            .taskAcknowledge: [SoundPackClip(relativePath: "8bit_submit.wav", label: nil)],
            .inputRequired: [SoundPackClip(relativePath: "8bit_approval.wav", label: nil)],
            .taskComplete: [SoundPackClip(relativePath: "8bit_complete.wav", label: nil)],
            .taskError: [SoundPackClip(relativePath: "8bit_error.wav", label: nil)],
        ]

        return SoundPack(
            id: defaultPackID,
            title: "8-bit 经典",
            subtitle: "SuperIsland 原版提示音",
            author: nil,
            accentHex: "#7BC6FF",
            systemName: "waveform.path",
            source: .bundledDefault,
            manifestURL: manifestURL,
            registryEntry: nil,
            clipsByCue: clipsByCue
        )
    }

    private static func discoverBundledPacks(bundle: Bundle, fileManager: FileManager) -> [SoundPack] {
        let roots = [
            bundle.resourceURL?.appendingPathComponent("Resources/SoundPacks", isDirectory: true),
            bundle.resourceURL?.appendingPathComponent("SoundPacks", isDirectory: true),
        ].compactMap { $0 }

        for root in roots where fileManager.fileExists(atPath: root.path) {
            return discoverPacks(at: root, source: .builtIn, allowLegacyManifest: true, fileManager: fileManager)
        }
        return []
    }

    private static func discoverLocalPacks(fileManager: FileManager) -> [SoundPack] {
        ensureUserPackRootExists(fileManager: fileManager)
        return discoverPacks(at: userPackRoot(fileManager: fileManager), source: .local, allowLegacyManifest: true, fileManager: fileManager)
    }

    private static func discoverPacks(
        at root: URL,
        source: SoundPackSource,
        allowLegacyManifest: Bool,
        fileManager: FileManager
    ) -> [SoundPack] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .compactMap { loadPack(from: $0, source: source, allowLegacyManifest: allowLegacyManifest, fileManager: fileManager) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private static func loadPack(
        from directory: URL,
        source: SoundPackSource,
        allowLegacyManifest: Bool,
        fileManager: FileManager
    ) -> SoundPack? {
        let manifestCandidates = manifestNames
            .map { directory.appendingPathComponent($0, isDirectory: false) }
            .filter { fileManager.fileExists(atPath: $0.path) }

        if let openPeonURL = manifestCandidates.first(where: { $0.lastPathComponent == "openpeon.json" }),
           let data = try? Data(contentsOf: openPeonURL),
           let manifest = try? JSONDecoder().decode(OpenPeonManifest.self, from: data) {
            return loadOpenPeonPack(
                manifest: manifest,
                manifestURL: openPeonURL,
                source: source
            )
        }

        guard allowLegacyManifest else { return nil }

        let manifestURLs = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?
            .filter {
                $0.pathExtension == "json"
                    && $0.lastPathComponent.hasSuffix(".soundpack.json")
            }
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) ?? []

        guard let manifestURL = manifestURLs.first,
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(LegacySoundPackManifest.self, from: data) else {
            return nil
        }

        let clipsByCue = manifest.sounds.reduce(into: [SoundCue: [SoundPackClip]]()) { result, pair in
            guard let cue = SoundCue(rawValue: pair.key) else { return }
            result[cue, default: []].append(SoundPackClip(relativePath: pair.value, label: nil))
        }

        guard !clipsByCue.isEmpty else { return nil }

        return SoundPack(
            id: manifest.id,
            title: manifest.title,
            subtitle: manifest.subtitle,
            author: manifest.author,
            accentHex: manifest.accentHex ?? "#61A9FF",
            systemName: manifest.systemName ?? "music.note",
            source: source,
            manifestURL: manifestURL,
            registryEntry: loadRegistryEntry(from: directory),
            clipsByCue: clipsByCue
        )
    }

    private static func loadOpenPeonPack(
        manifest: OpenPeonManifest,
        manifestURL: URL,
        source: SoundPackSource
    ) -> SoundPack? {
        let directory = manifestURL.deletingLastPathComponent()
        let registryEntry = loadRegistryEntry(from: directory)
        let clipsByCue = manifest.categories.reduce(into: [SoundCue: [SoundPackClip]]()) { result, pair in
            guard let cue = SoundCue(openPeonCategoryKey: pair.key) else { return }
            let clips = pair.value.sounds.map { SoundPackClip(relativePath: $0.file, label: $0.label) }
            guard !clips.isEmpty else { return }
            result[cue] = clips
        }

        guard !clipsByCue.isEmpty else { return nil }

        return SoundPack(
            id: registryEntry?.id ?? manifest.name,
            title: registryEntry?.displayName ?? manifest.displayName ?? manifest.name,
            subtitle: registryEntry?.description ?? manifest.description ?? "OpenPeon sound pack",
            author: registryEntry?.authorLabel ?? manifest.author?.name,
            accentHex: registryEntry?.accentHex ?? "#61A9FF",
            systemName: registryEntry?.systemName ?? "music.note.list",
            source: source,
            manifestURL: manifestURL,
            registryEntry: registryEntry,
            clipsByCue: clipsByCue
        )
    }

    private static func loadRegistryEntry(from directory: URL) -> SoundPackRegistryEntry? {
        let sidecarURL = directory.appendingPathComponent(SoundPackRegistry.sidecarFileName, isDirectory: false)
        guard let data = try? Data(contentsOf: sidecarURL) else { return nil }
        return try? JSONDecoder().decode(SoundPackRegistryEntry.self, from: data)
    }
}
