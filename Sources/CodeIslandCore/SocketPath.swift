import Foundation
import Darwin

public enum SocketPath {
    public static var path: String {
        if let env = ProcessInfo.processInfo.environment["SUPERISLAND_SOCKET_PATH"] {
            return env
        }
        if let env = ProcessInfo.processInfo.environment["CODEISLAND_SOCKET_PATH"] {
            return env
        }
        return "/tmp/superisland-\(getuid()).sock"
    }
}
