import Foundation

@MainActor
enum SettingsNotificationTester {
    private static let osascriptExecutablePath = "/usr/bin/osascript"

    static func sendTestNotification() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: osascriptExecutablePath)
        process.arguments = [
            "-e",
            """
            display notification "This is a test notification from CodeIsland Settings." with title "CodeIsland" subtitle "Settings Test" sound name "Glass"
            """
        ]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "CodeIsland.SettingsNotificationTester",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Failed to send macOS test notification."]
            )
        }
    }
}
