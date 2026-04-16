import Foundation

enum AppResourceBundle {
    static let bundle: Bundle = {
        // SwiftPM tests expose copied resources through Bundle.module, so prefer it before manual lookup.
        let moduleBundle = Bundle.module
        if moduleBundle.resourceURL != nil {
            return moduleBundle
        }

        let candidateNames = [
            "SuperIsland_SuperIsland.bundle",
            "SuperIsland_SuperIsland.bundle",
        ]

        let candidateRoots: [URL] = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.bundleURL.deletingLastPathComponent(),
            Bundle.main.executableURL?.deletingLastPathComponent(),
        ].compactMap { $0 }

        for root in candidateRoots {
            for name in candidateNames {
                let url = root.appendingPathComponent(name, isDirectory: true)
                if let bundle = Bundle(url: url) {
                    return bundle
                }
            }
        }

        let searchedRoots = candidateRoots.map { $0.path }.joined(separator: ", ")
        Swift.fatalError("could not locate the app resource bundle under: \(searchedRoots)")
    }()
}
