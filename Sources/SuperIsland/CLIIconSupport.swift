import AppKit

private let cliIconFiles: [String: String] = [
    "claude": "claude",
    "codex": "codex",
    "gemini": "gemini",
    "cursor": "cursor",
    "copilot": "copilot",
    "qoder": "qoder",
    "droid": "factory",
    "codebuddy": "codebuddy",
    "opencode": "opencode",
]

private var cliIconCache: [String: NSImage] = [:]

func cliIcon(source: String, size: CGFloat = 16) -> NSImage? {
    let key = "\(source)_\(Int(size))"
    if let cached = cliIconCache[key] { return cached }
    guard let filename = cliIconFiles[source],
          let url = AppResourceBundle.bundle.url(forResource: filename, withExtension: "png", subdirectory: "Resources/cli-icons"),
          let image = NSImage(contentsOf: url)
    else { return nil }
    image.size = NSSize(width: size, height: size)
    cliIconCache[key] = image
    return image
}
