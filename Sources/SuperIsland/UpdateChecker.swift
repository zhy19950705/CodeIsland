import AppKit
import Combine
import os.log

// UpdateChecker keeps observable update state in one place while installation and alert flows live in dedicated files.
@MainActor
final class UpdateChecker: ObservableObject {
    struct AvailableUpdate {
        let version: String
        let releaseURL: String
        let dmgURL: URL?
    }

    static let shared = UpdateChecker()
    nonisolated static let log = Logger(subsystem: "com.superisland", category: "UpdateChecker")

    private let defaultManifestURLString = "https://guandata-autotest-report.oss-cn-hangzhou.aliyuncs.com/cdn/superIsland/version.json"
    private let defaultDownloadPageURLString = "https://guandata-autotest-report.oss-cn-hangzhou.aliyuncs.com/cdn/superIsland/"

    @Published var isDownloading = false
    @Published var downloadProgress: Double?
    @Published var updateStatusMessage = ""
    @Published var availableUpdate: AvailableUpdate?

    var currentVersion: String { AppVersion.current }
    var progressWindowController: UpdateProgressWindowController?
    var progressWindowPreviousPolicy: NSApplication.ActivationPolicy?

    private var updateManifestURL: URL? {
        if let configured = updateInfoValue(primaryKey: "SuperIslandUpdateManifestURL", legacyKey: "SuperIslandUpdateManifestURL"),
           let url = URL(string: configured),
           !configured.isEmpty {
            return url
        }
        return URL(string: defaultManifestURLString)
    }

    private var downloadPageURLString: String {
        if let configured = updateInfoValue(primaryKey: "SuperIslandUpdateDownloadPageURL", legacyKey: "SuperIslandUpdateDownloadPageURL"),
           !configured.isEmpty {
            return configured
        }
        return defaultDownloadPageURLString
    }

    var isHomebrewInstall: Bool {
        let path = Bundle.main.bundlePath
        return path.contains("/Caskroom/") || path.contains("/homebrew/")
    }

    private func updateInfoValue(primaryKey: String, legacyKey: String) -> String? {
        if let configured = Bundle.main.object(forInfoDictionaryKey: primaryKey) as? String,
           !configured.isEmpty {
            return configured
        }
        if let configured = Bundle.main.object(forInfoDictionaryKey: legacyKey) as? String,
           !configured.isEmpty {
            return configured
        }
        return nil
    }

    func checkForUpdates(silent: Bool = true) {
        // Silent checks should stay out of previews and tests where Info.plist metadata is intentionally incomplete.
        if silent && currentVersion == AppVersion.fallback && Bundle.main.bundleIdentifier == nil {
            return
        }

        guard let url = updateManifestURL else {
            Self.log.error("Update manifest URL is invalid")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    Self.log.error("Update manifest request failed with status \(http.statusCode)")
                    return
                }

                let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
                let remoteVersion = manifest.normalizedVersion
                let releaseURL = manifest.releaseURL ?? manifest.downloadUrl ?? self.downloadPageURLString
                let update = AvailableUpdate(
                    version: remoteVersion,
                    releaseURL: releaseURL,
                    dmgURL: manifest.downloadUrl.flatMap(URL.init(string:))
                )

                if UpdateVersioning.isRemoteVersionNewer(remote: remoteVersion, local: self.currentVersion) {
                    self.availableUpdate = update
                    if !silent {
                        self.showUpdateAlert(update)
                    }
                } else if !silent {
                    self.availableUpdate = nil
                    self.showUpToDateAlert()
                } else {
                    self.availableUpdate = nil
                }
            } catch {
                Self.log.debug("Update check failed: \(error.localizedDescription)")
            }
        }
    }

    func presentAvailableUpdateOrCheck() {
        if let availableUpdate {
            showUpdateAlert(availableUpdate)
        } else {
            checkForUpdates(silent: false)
        }
    }
}
