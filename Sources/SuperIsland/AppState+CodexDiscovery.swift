import Foundation
import Darwin
import SuperIslandCore

struct DiscoveredSession {
    let sessionId: String
    let cwd: String
    let tty: String?
    let model: String?
    let pid: pid_t?
    let modifiedAt: Date
    let recentMessages: [ChatMessage]
    var source: String = "claude"
}
