import CryptoKit
import Foundation

struct SoundPackRegistryAuthor: Codable, Hashable, Sendable {
    var name: String?
    var github: String?
}

struct SoundPackRegistryEntry: Codable, Hashable, Identifiable, Sendable {
    var name: String
    var displayName: String
    var version: String
    var description: String
    var author: SoundPackRegistryAuthor?
    var trustTier: String
    var categories: [String]
    var language: String?
    var license: String?
    var soundCount: Int?
    var totalSizeBytes: Int?
    var sourceRepo: String
    var sourceRef: String
    var sourcePath: String
    var manifestSHA256: String?
    var tags: [String]
    var previewSounds: [String]
    var added: String?
    var updated: String?
    var quality: String?

    enum CodingKeys: String, CodingKey {
        case name
        case displayName = "display_name"
        case version
        case description
        case author
        case trustTier = "trust_tier"
        case categories
        case language
        case license
        case soundCount = "sound_count"
        case totalSizeBytes = "total_size_bytes"
        case sourceRepo = "source_repo"
        case sourceRef = "source_ref"
        case sourcePath = "source_path"
        case manifestSHA256 = "manifest_sha256"
        case tags
        case previewSounds = "preview_sounds"
        case added
        case updated
        case quality
    }

    var id: String { name }

    var trustLabel: String {
        switch trustTier {
        case "official":
            return "Official"
        case "community":
            return "Community"
        default:
            return "Catalog"
        }
    }

    var accentHex: String {
        switch trustTier {
        case "official":
            return "#61A9FF"
        case "community":
            return "#7CE3A0"
        default:
            return "#A58CFF"
        }
    }

    var systemName: String {
        switch trustTier {
        case "official":
            return "checkmark.seal.fill"
        case "community":
            return "person.2.fill"
        default:
            return "music.note.list"
        }
    }

    var authorLabel: String {
        if let authorName = author?.name, !authorName.isEmpty {
            return authorName
        }
        return "Unknown Author"
    }

    var compactMeta: String {
        var items: [String] = [trustLabel]
        if let license, !license.isEmpty {
            items.append(license)
        }
        if let totalSizeBytes, totalSizeBytes > 0 {
            items.append(ByteCountFormatter.string(fromByteCount: Int64(totalSizeBytes), countStyle: .file))
        }
        return items.joined(separator: " · ")
    }
}

private struct SoundPackRegistryIndex: Decodable {
    var version: Int
    var packs: [SoundPackRegistryEntry]
    var totalPacks: Int?

    enum CodingKeys: String, CodingKey {
        case version
        case packs
        case totalPacks = "total_packs"
    }
}

struct OpenPeonManifestAuthor: Codable, Hashable, Sendable {
    var name: String?
    var github: String?
}

struct OpenPeonSoundClip: Codable, Hashable, Sendable {
    var file: String
    var label: String?
    var sha256: String?
}

struct OpenPeonCategoryGroup: Codable, Hashable, Sendable {
    var sounds: [OpenPeonSoundClip]
}

struct OpenPeonManifest: Codable, Hashable, Sendable {
    var cespVersion: String?
    var name: String
    var displayName: String?
    var version: String?
    var description: String?
    var author: OpenPeonManifestAuthor?
    var license: String?
    var language: String?
    var categories: [String: OpenPeonCategoryGroup]

    enum CodingKeys: String, CodingKey {
        case cespVersion = "cesp_version"
        case name
        case displayName = "display_name"
        case version
        case description
        case author
        case license
        case language
        case categories
    }
}

enum SoundPackRegistryError: LocalizedError {
    case badResponse(URL)
    case invalidRegistry
    case invalidManifest
    case shaMismatch(file: String)

    var errorDescription: String? {
        switch self {
        case let .badResponse(url):
            return "Download failed: \(url.lastPathComponent)"
        case .invalidRegistry:
            return "Sound pack registry is invalid"
        case .invalidManifest:
            return "openpeon.json could not be parsed"
        case let .shaMismatch(file):
            return "Checksum mismatch: \(file)"
        }
    }
}

enum SoundPackRegistry {
    static let indexURL = URL(string: "https://PeonPing.github.io/registry/index.json")!
    static let sidecarFileName = ".registry-entry.json"
    private static let curatedPackIDs: Set<String> = ["ae_qianyu"]

    static func cacheURL(fileManager: FileManager = .default) -> URL {
        catalogRoot(fileManager: fileManager).appendingPathComponent(".registry-cache.json", isDirectory: false)
    }

    static func loadCachedEntries(fileManager: FileManager = .default) -> [SoundPackRegistryEntry] {
        guard let data = try? Data(contentsOf: cacheURL(fileManager: fileManager)),
              let index = try? JSONDecoder().decode(SoundPackRegistryIndex.self, from: data) else {
            return []
        }
        return sort(filterCuratedEntries(index.packs))
    }

    static func refreshEntries(
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) async throws -> [SoundPackRegistryEntry] {
        let (data, response) = try await session.data(from: indexURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw SoundPackRegistryError.badResponse(indexURL)
        }
        guard let index = try? JSONDecoder().decode(SoundPackRegistryIndex.self, from: data) else {
            throw SoundPackRegistryError.invalidRegistry
        }

        ensureCatalogRootExists(fileManager: fileManager)
        try data.write(to: cacheURL(fileManager: fileManager), options: .atomic)
        return sort(filterCuratedEntries(index.packs))
    }

    static func install(
        entry: SoundPackRegistryEntry,
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) async throws -> URL {
        let manifestURL = rawFileURL(for: entry, relativePath: "openpeon.json")
        let (manifestData, manifestResponse) = try await session.data(from: manifestURL)
        guard let httpResponse = manifestResponse as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw SoundPackRegistryError.badResponse(manifestURL)
        }
        guard let manifest = try? JSONDecoder().decode(OpenPeonManifest.self, from: manifestData) else {
            throw SoundPackRegistryError.invalidManifest
        }

        let packRoot = SoundPackCatalog.userPackRoot(fileManager: fileManager)
        try fileManager.createDirectory(at: packRoot, withIntermediateDirectories: true)

        let tempURL = packRoot.appendingPathComponent(".tmp-\(entry.name)-\(UUID().uuidString)", isDirectory: true)
        let installURL = packRoot.appendingPathComponent(entry.name, isDirectory: true)
        try fileManager.createDirectory(at: tempURL, withIntermediateDirectories: true)

        try manifestData.write(to: tempURL.appendingPathComponent("openpeon.json", isDirectory: false), options: .atomic)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let entryData = try encoder.encode(entry)
        try entryData.write(to: tempURL.appendingPathComponent(sidecarFileName, isDirectory: false), options: .atomic)

        let allClips = manifest.categories.values.flatMap(\.sounds)
        let uniqueClips = Dictionary(uniqueKeysWithValues: allClips.map { ($0.file, $0) }).values

        for clip in uniqueClips {
            let remoteURL = rawFileURL(for: entry, relativePath: clip.file)
            let (data, response) = try await session.data(from: remoteURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw SoundPackRegistryError.badResponse(remoteURL)
            }

            if let expectedSHA = clip.sha256?.lowercased(), !expectedSHA.isEmpty {
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard digest == expectedSHA else {
                    throw SoundPackRegistryError.shaMismatch(file: clip.file)
                }
            }

            let destinationURL = tempURL.appendingPathComponent(clip.file, isDirectory: false)
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destinationURL, options: .atomic)
        }

        if fileManager.fileExists(atPath: installURL.path) {
            try fileManager.removeItem(at: installURL)
        }
        try fileManager.moveItem(at: tempURL, to: installURL)
        return installURL
    }

    static func rawFileURL(for entry: SoundPackRegistryEntry, relativePath: String) -> URL {
        var url = URL(string: "https://raw.githubusercontent.com")!
        for component in entry.sourceRepo.split(separator: "/") {
            url.append(path: String(component))
        }
        url.append(path: entry.sourceRef)

        let basePath = entry.sourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !basePath.isEmpty, basePath != "." {
            for component in basePath.split(separator: "/") {
                url.append(path: String(component))
            }
        }

        for component in relativePath.split(separator: "/") {
            url.append(path: String(component))
        }
        return url
    }

    private static func catalogRoot(fileManager: FileManager) -> URL {
        SoundPackCatalog.userPackRoot(fileManager: fileManager).deletingLastPathComponent()
    }

    private static func ensureCatalogRootExists(fileManager: FileManager) {
        try? fileManager.createDirectory(at: catalogRoot(fileManager: fileManager), withIntermediateDirectories: true)
    }

    private static func sort(_ entries: [SoundPackRegistryEntry]) -> [SoundPackRegistryEntry] {
        entries.sorted { lhs, rhs in
            if lhs.trustTier != rhs.trustTier {
                return lhs.trustTier == "official"
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private static func filterCuratedEntries(_ entries: [SoundPackRegistryEntry]) -> [SoundPackRegistryEntry] {
        entries.filter { curatedPackIDs.contains($0.id) }
    }
}
