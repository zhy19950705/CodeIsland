import AppKit
import Combine
import os.log

@MainActor
final class UpdateChecker: ObservableObject {
    struct AvailableUpdate {
        let version: String
        let releaseURL: String
        let dmgURL: URL?
    }

    static let shared = UpdateChecker()
    private nonisolated static let log = Logger(subsystem: "com.superisland", category: "UpdateChecker")
    private let defaultManifestURLString = "https://guandata-autotest-report.oss-cn-hangzhou.aliyuncs.com/cdn/superIsland/version.json"
    private let defaultDownloadPageURLString = "https://guandata-autotest-report.oss-cn-hangzhou.aliyuncs.com/cdn/superIsland/"

    @Published var isDownloading = false
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var updateStatusMessage = ""
    @Published private(set) var availableUpdate: AvailableUpdate?

    private var currentVersion: String { AppVersion.current }
    private var progressWindowController: UpdateProgressWindowController?
    private var progressWindowPreviousPolicy: NSApplication.ActivationPolicy?

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

    private var isHomebrewInstall: Bool {
        let path = Bundle.main.bundlePath
        return path.contains("/Caskroom/") || path.contains("/homebrew/")
    }

    func checkForUpdates(silent: Bool = true) {
        // Skip silent check in Xcode preview / test environment
        if silent && currentVersion == AppVersion.fallback && Bundle.main.bundleIdentifier == nil { return }

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
                let remote = manifest.version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                let local = self.currentVersion
                let releaseURL = manifest.releaseURL ?? manifest.downloadUrl ?? self.downloadPageURLString
                let update = AvailableUpdate(
                    version: remote,
                    releaseURL: releaseURL,
                    dmgURL: manifest.downloadUrl.flatMap(URL.init(string:))
                )

                if self.isNewer(remote: remote, local: local) {
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

    private func isNewer(remote: String, local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }

    private func showUpdateAlert(_ update: AvailableUpdate) {
        if isHomebrewInstall {
            showHomebrewAlert(remoteVersion: update.version)
            return
        }

        let previousPolicy = NSApp.activationPolicy()
        if previousPolicy == .accessory {
            NSApp.setActivationPolicy(.regular)
        }

        let alert = NSAlert()
        alert.messageText = L10n.shared["update_available_title"]
        alert.informativeText = String(format: L10n.shared["update_available_body"], update.version, currentVersion)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.shared["update_now"])
        alert.addButton(withTitle: L10n.shared["later"])

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if previousPolicy == .accessory {
            NSApp.setActivationPolicy(.accessory)
        }

        if response == .alertFirstButtonReturn {
            if let downloadURL = update.dmgURL {
                Task {
                    await self.performUpdate(dmgURL: downloadURL, releaseURL: update.releaseURL)
                }
            } else if let url = URL(string: update.releaseURL) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func showHomebrewAlert(remoteVersion: String) {
        let previousPolicy = NSApp.activationPolicy()
        if previousPolicy == .accessory {
            NSApp.setActivationPolicy(.regular)
        }

        let alert = NSAlert()
        alert.messageText = L10n.shared["update_homebrew_title"]
        alert.informativeText = String(format: L10n.shared["update_homebrew_body"], remoteVersion)
        alert.alertStyle = .informational
        // Show the brew command in a text field so it's visible
        let tf = NSTextField(string: L10n.shared["update_homebrew_command"])
        tf.isEditable = false
        tf.isBezeled = true
        tf.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
        alert.accessoryView = tf
        alert.addButton(withTitle: L10n.shared["update_copy_command"])
        alert.addButton(withTitle: L10n.shared["ok"])

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if previousPolicy == .accessory {
            NSApp.setActivationPolicy(.accessory)
        }

        if response == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(L10n.shared["update_homebrew_command"], forType: .string)
        }
    }

    private func showUpToDateAlert() {
        let previousPolicy = NSApp.activationPolicy()
        if previousPolicy == .accessory {
            NSApp.setActivationPolicy(.regular)
        }

        let alert = NSAlert()
        alert.messageText = L10n.shared["no_update_title"]
        alert.informativeText = String(format: L10n.shared["no_update_body"], currentVersion)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.shared["ok"])

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()

        if previousPolicy == .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func showUpdateFailedAlert(message: String, releaseURL: String) {
        let previousPolicy = NSApp.activationPolicy()
        if previousPolicy == .accessory {
            NSApp.setActivationPolicy(.regular)
        }

        let alert = NSAlert()
        alert.messageText = L10n.shared["update_failed_title"]
        alert.informativeText = String(format: L10n.shared["update_failed_body"], message)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.shared["update_manual_download"])
        alert.addButton(withTitle: L10n.shared["ok"])

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if previousPolicy == .accessory {
            NSApp.setActivationPolicy(.accessory)
        }

        if response == .alertFirstButtonReturn, let url = URL(string: releaseURL) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Auto-update flow

    private func performUpdate(dmgURL: URL, releaseURL: String) async {
        if isDownloading {
            presentProgressWindow()
            return
        }

        isDownloading = true
        downloadProgress = 0
        defer {
            isDownloading = false
            downloadProgress = nil
            updateStatusMessage = ""
        }

        let tempDir = FileManager.default.temporaryDirectory
        let dmgURLOnDisk = tempDir.appendingPathComponent("SuperIsland-update.dmg")
        let mountPoint = tempDir.appendingPathComponent("superisland-update-\(UUID().uuidString)").path
        let currentAppPath = Bundle.main.bundlePath
        let installTargetPath = Self.resolveInstallTargetPath(currentAppPath: currentAppPath)

        do {
            updateProgress(message: L10n.shared["update_progress_prepare"], fractionCompleted: nil)
            updateProgress(message: String(format: L10n.shared["update_progress_download_percent"], 0), fractionCompleted: 0)

            Self.log.info("Downloading update from \(dmgURL.absoluteString)")
            try await downloadUpdate(from: dmgURL, to: dmgURLOnDisk)

            updateProgress(message: L10n.shared["update_progress_mounting"], fractionCompleted: nil)

            try await Self.installAppFromDMG(
                dmgPath: dmgURLOnDisk.path,
                mountPoint: mountPoint,
                targetAppPath: installTargetPath
            )

            updateProgress(message: L10n.shared["update_progress_relaunching"], fractionCompleted: nil)
            availableUpdate = nil

            Self.log.info("Scheduling relaunch for \(installTargetPath)")
            try Self.scheduleRelaunch(appPath: installTargetPath)
            try await Task.sleep(nanoseconds: 500_000_000)
            NSApp.terminate(nil)

        } catch {
            Self.log.error("Update failed: \(error.localizedDescription)")
            dismissProgressWindow()
            showUpdateFailedAlert(message: error.localizedDescription, releaseURL: releaseURL)
        }
    }

    private func downloadUpdate(from remoteURL: URL, to destinationURL: URL) async throws {
        let delegate = DownloadDelegate(destinationURL: destinationURL) { [weak self] progress in
            Task { @MainActor in
                self?.updateProgress(
                    message: String(format: L10n.shared["update_progress_download_percent"], Int(progress * 100)),
                    fractionCompleted: progress
                )
            }
        }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 30

        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            delegate.continuation = continuation
            session.downloadTask(with: remoteURL).resume()
        }
    }

    private func updateProgress(message: String, fractionCompleted: Double?) {
        updateStatusMessage = message
        downloadProgress = fractionCompleted
        presentProgressWindow()
        progressWindowController?.update(
            message: message,
            detail: L10n.shared["update_progress_detail"],
            fractionCompleted: fractionCompleted
        )
    }

    private func presentProgressWindow() {
        if progressWindowController == nil {
            progressWindowController = UpdateProgressWindowController()
        }
        if progressWindowPreviousPolicy == nil {
            progressWindowPreviousPolicy = NSApp.activationPolicy()
            if progressWindowPreviousPolicy == .accessory {
                NSApp.setActivationPolicy(.regular)
            }
        }
        progressWindowController?.showWindow(nil)
        progressWindowController?.window?.center()
        progressWindowController?.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismissProgressWindow() {
        progressWindowController?.close()
        progressWindowController = nil
        if let previousPolicy = progressWindowPreviousPolicy, previousPolicy == .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
        progressWindowPreviousPolicy = nil
    }

    @discardableResult
    private nonisolated static func runProcess(_ executable: String, args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: outputData, encoding: .utf8) ?? ""
    }

    private nonisolated static func resolveInstallTargetPath(currentAppPath: String) -> String {
        let currentURL = URL(fileURLWithPath: currentAppPath).standardizedFileURL
        let normalizedPath = currentURL.path
        let lowercasedPath = normalizedPath.lowercased()

        if lowercasedPath.contains("/apptranslocation/") || lowercasedPath.hasPrefix("/volumes/") {
            let appName = currentURL.lastPathComponent
            let fm = FileManager.default
            let candidates = [
                URL(fileURLWithPath: NSHomeDirectory())
                    .appendingPathComponent("Applications", isDirectory: true)
                    .appendingPathComponent(appName, isDirectory: true)
                    .path,
                URL(fileURLWithPath: "/Applications", isDirectory: true)
                    .appendingPathComponent(appName, isDirectory: true)
                    .path,
            ]

            if let existing = candidates.first(where: { fm.fileExists(atPath: $0) }) {
                return existing
            }
            return candidates[0]
        }

        return normalizedPath
    }

    private nonisolated static func scheduleRelaunch(appPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open -n \(shellQuoted(appPath))"]
        try process.run()
    }

    private nonisolated static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    fileprivate enum UpdateError: LocalizedError {
        case appNotFoundInDMG
        case downloadDidNotFinish

        var errorDescription: String? {
            switch self {
            case .appNotFoundInDMG:
                return "Could not find the app bundle in the downloaded disk image."
            case .downloadDidNotFinish:
                return "The update download finished without a disk image."
            }
        }
    }
}

private extension UpdateChecker {
    static func installAppFromDMG(dmgPath: String, mountPoint: String, targetAppPath: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default

            do {
                try? fm.removeItem(atPath: mountPoint)
                try fm.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)

                Self.log.info("Mounting DMG at \(dmgPath)")
                let attachOutput = try Self.runProcess(
                    "/usr/bin/hdiutil",
                    args: ["attach", "-nobrowse", "-quiet", "-mountpoint", mountPoint, dmgPath]
                )
                Self.log.debug("hdiutil attach output: \(attachOutput)")

                guard let contents = try? fm.contentsOfDirectory(atPath: mountPoint),
                      let appName = contents.first(where: { $0.hasSuffix(".app") }) else {
                    throw UpdateError.appNotFoundInDMG
                }

                let sourceAppPath = mountPoint + "/" + appName

                await MainActor.run {
                    UpdateChecker.shared.updateProgress(
                        message: L10n.shared["update_progress_installing"],
                        fractionCompleted: nil
                    )
                }

                let targetParentPath = URL(fileURLWithPath: targetAppPath).deletingLastPathComponent().path
                try fm.createDirectory(atPath: targetParentPath, withIntermediateDirectories: true)

                Self.log.info("Replacing \(targetAppPath) with \(sourceAppPath)")
                if fm.fileExists(atPath: targetAppPath) {
                    try fm.removeItem(atPath: targetAppPath)
                }
                _ = try Self.runProcess("/usr/bin/ditto", args: [sourceAppPath, targetAppPath])
            } catch {
                _ = try? Self.runProcess("/usr/bin/hdiutil", args: ["detach", mountPoint, "-quiet"])
                try? fm.removeItem(atPath: dmgPath)
                try? fm.removeItem(atPath: mountPoint)
                throw error
            }

            _ = try? Self.runProcess("/usr/bin/hdiutil", args: ["detach", mountPoint, "-quiet"])
            try? fm.removeItem(atPath: dmgPath)
            try? fm.removeItem(atPath: mountPoint)
        }.value
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let destinationURL: URL
    let progressHandler: @Sendable (Double) -> Void

    var continuation: CheckedContinuation<Void, Error>?
    private var tempFileURL: URL?

    init(destinationURL: URL, progressHandler: @escaping @Sendable (Double) -> Void) {
        self.destinationURL = destinationURL
        self.progressHandler = progressHandler
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0), 1)
        progressHandler(progress)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        tempFileURL = location
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let continuation else { return }
        self.continuation = nil

        if let error {
            continuation.resume(throwing: error)
            return
        }

        guard let tempFileURL else {
            continuation.resume(throwing: UpdateChecker.UpdateError.downloadDidNotFinish)
            return
        }

        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.moveItem(at: tempFileURL, to: destinationURL)
            continuation.resume()
        } catch {
            continuation.resume(throwing: error)
        }
    }
}

@MainActor
private final class UpdateProgressWindowController: NSWindowController {
    private let messageLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 148),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.shared["update_progress_title"]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        let contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = contentView

        messageLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 2

        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = 2

        progressIndicator.minValue = 0
        progressIndicator.maxValue = 100
        progressIndicator.isIndeterminate = false
        progressIndicator.controlSize = .regular

        let stack = NSStackView(views: [messageLabel, detailLabel, progressIndicator])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(message: String, detail: String, fractionCompleted: Double?) {
        messageLabel.stringValue = message
        detailLabel.stringValue = detail

        if let fractionCompleted {
            if progressIndicator.isIndeterminate {
                progressIndicator.stopAnimation(nil)
                progressIndicator.isIndeterminate = false
            }
            progressIndicator.doubleValue = fractionCompleted * 100
        } else {
            progressIndicator.doubleValue = 0
            if !progressIndicator.isIndeterminate {
                progressIndicator.isIndeterminate = true
            }
            progressIndicator.startAnimation(nil)
        }
    }
}

private extension UpdateChecker {
    struct UpdateManifest: Decodable {
        let version: String
        let downloadUrl: String?
        let releaseURL: String?
        let publishedAt: String?
        let notes: String?

        enum CodingKeys: String, CodingKey {
            case version
            case downloadUrl
            case releaseURL = "releaseUrl"
            case publishedAt
            case notes
        }
    }
}
