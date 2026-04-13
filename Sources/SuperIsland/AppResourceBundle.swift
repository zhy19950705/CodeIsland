import Foundation

enum AppResourceBundle {
    static let bundle: Bundle = {
        let candidateNames = [
            "SuperIsland_SuperIsland.bundle",
            "SuperIsland_SuperIsland.bundle",
        ]

        let candidateRoots: [URL] = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.bundleURL.deletingLastPathComponent(),
        ].compactMap { $0 }

        for root in candidateRoots {
            for name in candidateNames {
                let url = root.appendingPathComponent(name, isDirectory: true)
                if let bundle = Bundle(url: url) {
                    return bundle
                }
            }
        }

        Swift.fatalError("could not locate the app resource bundle")
    }()
}
