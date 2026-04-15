import AppKit
import Foundation

// UpdateCheckerInstaller contains the download, mount, replace, and relaunch pipeline used by in-app updates.
extension UpdateChecker {
    func performUpdate(dmgURL: URL, releaseURL: String) async {
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

        let tempDirectory = FileManager.default.temporaryDirectory
        let dmgURLOnDisk = tempDirectory.appendingPathComponent("SuperIsland-update.dmg")
        let mountPoint = tempDirectory.appendingPathComponent("superisland-update-\(UUID().uuidString)").path
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

    func downloadUpdate(from remoteURL: URL, to destinationURL: URL) async throws {
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

    func updateProgress(message: String, fractionCompleted: Double?) {
        updateStatusMessage = message
        downloadProgress = fractionCompleted
        presentProgressWindow()
        progressWindowController?.update(
            message: message,
            detail: L10n.shared["update_progress_detail"],
            fractionCompleted: fractionCompleted
        )
    }

    func presentProgressWindow() {
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

    func dismissProgressWindow() {
        progressWindowController?.close()
        progressWindowController = nil
        if let previousPolicy = progressWindowPreviousPolicy, previousPolicy == .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
        progressWindowPreviousPolicy = nil
    }

    @discardableResult
    nonisolated static func runProcess(_ executable: String, args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            // Bubble the subprocess failure up to the UI so failed installs do not masquerade as successful upgrades.
            let reason = output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpdateError.processFailed(
                executable: executable,
                reason: reason.isEmpty ? "Exited with status \(process.terminationStatus)." : reason
            )
        }
        return output
    }

    nonisolated static func resolveInstallTargetPath(currentAppPath: String) -> String {
        UpdateInstallPaths.resolveInstallTargetPath(currentAppPath: currentAppPath)
    }

    nonisolated static func scheduleRelaunch(appPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open -n \(UpdateShell.shellQuoted(appPath))"]
        try process.run()
    }
}

private extension UpdateChecker {
    static func installAppFromDMG(dmgPath: String, mountPoint: String, targetAppPath: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default

            do {
                try? fileManager.removeItem(atPath: mountPoint)
                try fileManager.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)

                Self.log.info("Mounting DMG at \(dmgPath)")
                let attachOutput = try Self.runProcess(
                    "/usr/bin/hdiutil",
                    args: ["attach", "-nobrowse", "-quiet", "-mountpoint", mountPoint, dmgPath]
                )
                Self.log.debug("hdiutil attach output: \(attachOutput)")

                guard let contents = try? fileManager.contentsOfDirectory(atPath: mountPoint),
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
                try fileManager.createDirectory(atPath: targetParentPath, withIntermediateDirectories: true)

                Self.log.info("Replacing \(targetAppPath) with \(sourceAppPath)")
                if fileManager.fileExists(atPath: targetAppPath) {
                    try fileManager.removeItem(atPath: targetAppPath)
                }
                _ = try Self.runProcess("/usr/bin/ditto", args: [sourceAppPath, targetAppPath])
                try Self.clearQuarantineAttribute(at: targetAppPath)
            } catch {
                _ = try? Self.runProcess("/usr/bin/hdiutil", args: ["detach", mountPoint, "-quiet"])
                try? fileManager.removeItem(atPath: dmgPath)
                try? fileManager.removeItem(atPath: mountPoint)
                throw error
            }

            _ = try? Self.runProcess("/usr/bin/hdiutil", args: ["detach", mountPoint, "-quiet"])
            try? fileManager.removeItem(atPath: dmgPath)
            try? fileManager.removeItem(atPath: mountPoint)
        }.value
    }

    nonisolated static func clearQuarantineAttribute(at appPath: String) throws {
        // DMG-installed apps inherit the download quarantine flag, so remove it before the relaunch step.
        _ = try Self.runProcess("/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", appPath])
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
            continuation.resume(throwing: UpdateError.downloadDidNotFinish)
            return
        }

        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: tempFileURL, to: destinationURL)
            continuation.resume()
        } catch {
            continuation.resume(throwing: error)
        }
    }
}
