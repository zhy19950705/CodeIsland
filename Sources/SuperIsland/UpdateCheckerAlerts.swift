import AppKit

// UpdateCheckerAlerts isolates modal UI so update network logic can stay separate from AppKit presentation details.
extension UpdateChecker {
    func showUpdateAlert(_ update: AvailableUpdate) {
        if isHomebrewInstall {
            showHomebrewAlert(remoteVersion: update.version)
            return
        }

        withRegularActivationPolicy {
            let alert = NSAlert()
            alert.messageText = AppText.shared["update_available_title"]
            alert.informativeText = String(format: AppText.shared["update_available_body"], update.version, currentVersion)
            alert.alertStyle = .informational
            alert.addButton(withTitle: AppText.shared["update_now"])
            alert.addButton(withTitle: AppText.shared["later"])

            let response = runAlert(alert)
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
    }

    func showHomebrewAlert(remoteVersion: String) {
        withRegularActivationPolicy {
            let alert = NSAlert()
            alert.messageText = AppText.shared["update_homebrew_title"]
            alert.informativeText = String(format: AppText.shared["update_homebrew_body"], remoteVersion)
            alert.alertStyle = .informational

            // Keep the command visible so the user can verify what will be copied before accepting.
            let commandField = NSTextField(string: AppText.shared["update_homebrew_command"])
            commandField.isEditable = false
            commandField.isBezeled = true
            commandField.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
            alert.accessoryView = commandField
            alert.addButton(withTitle: AppText.shared["update_copy_command"])
            alert.addButton(withTitle: AppText.shared["ok"])

            let response = runAlert(alert)
            if response == .alertFirstButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(AppText.shared["update_homebrew_command"], forType: .string)
            }
        }
    }

    func showUpToDateAlert() {
        withRegularActivationPolicy {
            let alert = NSAlert()
            alert.messageText = AppText.shared["no_update_title"]
            alert.informativeText = String(format: AppText.shared["no_update_body"], currentVersion)
            alert.alertStyle = .informational
            alert.addButton(withTitle: AppText.shared["ok"])
            _ = runAlert(alert)
        }
    }

    func showUpdateFailedAlert(message: String, releaseURL: String) {
        withRegularActivationPolicy {
            let alert = NSAlert()
            alert.messageText = AppText.shared["update_failed_title"]
            alert.informativeText = String(format: AppText.shared["update_failed_body"], message)
            alert.alertStyle = .warning
            alert.addButton(withTitle: AppText.shared["update_manual_download"])
            alert.addButton(withTitle: AppText.shared["ok"])

            let response = runAlert(alert)
            if response == .alertFirstButtonReturn, let url = URL(string: releaseURL) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func withRegularActivationPolicy(_ body: () -> Void) {
        let previousPolicy = NSApp.activationPolicy()
        if previousPolicy == .accessory {
            NSApp.setActivationPolicy(.regular)
        }
        defer {
            if previousPolicy == .accessory {
                NSApp.setActivationPolicy(.accessory)
            }
        }

        body()
    }

    private func runAlert(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }
}
