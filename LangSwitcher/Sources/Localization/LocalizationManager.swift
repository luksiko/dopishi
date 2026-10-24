import Foundation

// MARK: - Localization Manager
// Custom runtime localization system — no Apple .lproj/.strings.
// Allows instant language switching without app restart.
// Contributors add new languages by copying Strings_en.swift.

@MainActor
final class LocalizationManager: ObservableObject {

    static let shared = LocalizationManager()

    /// Available languages: code + native name
    static let availableLanguages: [(code: String, name: String)] = [
        ("en", "English"),
        ("ru", "Русский"),
        ("uk", "Українська"),
        ("de", "Deutsch"),
        ("fr", "Français"),
        ("es", "Español"),
    ]

    /// Currently active language code
    @Published var currentLanguage: String {
        didSet {
            UserDefaults.standard.set(currentLanguage, forKey: "appLanguage")
        }
    }

    /// Registry: language code -> [key: localized string]
    private var registry: [String: [String: String]] = [:]

    // MARK: - Init

    private init() {
        // Read persisted choice, or detect system language in order of user preference
        if let saved = UserDefaults.standard.string(forKey: "appLanguage"),
           Self.availableLanguages.contains(where: { $0.code == saved }) {
            self.currentLanguage = saved
        } else {
            self.currentLanguage = Self.detectSystemLanguage()
            UserDefaults.standard.set(self.currentLanguage, forKey: "appLanguage")
        }
    }

    /// Detect the highest priority supported language from system preferred languages
    static func detectSystemLanguage() -> String {
        for preferred in Locale.preferredLanguages {
            let base = preferred.components(separatedBy: CharacterSet(charactersIn: "-_")).first?.lowercased() ?? preferred.lowercased()
            if availableLanguages.contains(where: { $0.code == base }) {
                return base
            }
        }
        return "en"
    }

    // MARK: - Registration

    /// Called by each Strings_xx file to register its dictionary
    func register(language: String, strings: [String: String]) {
        registry[language] = strings
    }

    // MARK: - Lookup

    /// Translate a key. Falls back to English, then returns the key itself.
    func t(_ key: String) -> String {
        if let value = registry[currentLanguage]?[key] {
            return value
        }
        if let value = registry["en"]?[key] {
            return value
        }
        return key
    }
}
