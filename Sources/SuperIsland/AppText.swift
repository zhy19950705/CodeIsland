import Foundation
import Combine

// AppText keeps a single Chinese copy catalog after the language-switching i18n layer is removed.
final class AppText: ObservableObject {
    static let shared = AppText()

    private init() {}

    subscript(_ key: String) -> String {
        Self.strings[key] ?? key
    }

    // Merge section dictionaries once so existing key-based call sites can stay simple and cheap.
    private static let strings: [String: String] =
        settingsAndSkillsStrings
        .merging(behaviorAndTestingStrings) { current, _ in current }
        .merging(hooksAndSessionStrings) { current, _ in current }
}
