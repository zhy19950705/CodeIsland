import Foundation
import Darwin

public enum SocketPath {
    public static var path: String {
        if let rawValue = getenv("SUPERISLAND_SOCKET_PATH") {
            return String(cString: rawValue)
        }
        return "/tmp/superisland-\(getuid()).sock"
    }
}
