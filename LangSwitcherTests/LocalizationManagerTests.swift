import XCTest
@testable import LangSwitcher

final class LocalizationManagerTests: XCTestCase {

    @MainActor
    override func setUp() {
        super.setUp()
        // Register all language catalogs
        Strings_en.register()
        Strings_ru.register()
        Strings_uk.register()
        Strings_de.register()
        Strings_fr.register()
        Strings_es.register()
    }

    @MainActor
    func testAvailableLanguages() {
        let codes = LocalizationManager.availableLanguages.map(\.code)
        XCTAssertTrue(codes.contains("en"))
        XCTAssertTrue(codes.contains("ru"))
        XCTAssertTrue(codes.contains("uk"))
        XCTAssertTrue(codes.contains("de"))
        XCTAssertTrue(codes.contains("fr"))
        XCTAssertTrue(codes.contains("es"))
        XCTAssertEqual(codes.count, 6)
    }

    @MainActor
    func testKeyParityAcrossAllCatalogs() {
        let enKeys = Set(Strings_en.strings.keys)
        XCTAssertEqual(enKeys.count, 580)

        let catalogs: [(String, [String: String])] = [
            ("ru", Strings_ru.strings),
            ("uk", Strings_uk.strings),
            ("de", Strings_de.strings),
            ("fr", Strings_fr.strings),
            ("es", Strings_es.strings)
        ]

        for (code, dict) in catalogs {
            let keys = Set(dict.keys)
            let missing = enKeys.subtracting(keys)
            let extra = keys.subtracting(enKeys)
            XCTAssertTrue(missing.isEmpty, "Missing keys in \(code): \(missing)")
            XCTAssertTrue(extra.isEmpty, "Extra keys in \(code): \(extra)")
            XCTAssertEqual(keys.count, enKeys.count, "Count mismatch for \(code)")
        }
    }

    @MainActor
    func testDynamicLanguageSwitching() {
        let manager = LocalizationManager.shared
        let original = manager.currentLanguage

        defer {
            manager.currentLanguage = original
        }

        manager.currentLanguage = "en"
        XCTAssertEqual(manager.t("settings.tab.general"), "General")

        manager.currentLanguage = "ru"
        XCTAssertEqual(manager.t("settings.tab.general"), "Основные")

        manager.currentLanguage = "uk"
        XCTAssertEqual(manager.t("settings.tab.general"), "Загальні")

        manager.currentLanguage = "de"
        XCTAssertEqual(manager.t("settings.tab.general"), "Allgemein")

        manager.currentLanguage = "fr"
        XCTAssertEqual(manager.t("settings.tab.general"), "Général")

        manager.currentLanguage = "es"
        XCTAssertEqual(manager.t("settings.tab.general"), "General")
    }

    @MainActor
    func testFallbackToEnglish() {
        let manager = LocalizationManager.shared
        let original = manager.currentLanguage

        defer {
            manager.currentLanguage = original
        }

        manager.currentLanguage = "de"
        // If an imaginary key doesn't exist in de or en, it returns raw key
        XCTAssertEqual(manager.t("non_existent_key_xyz"), "non_existent_key_xyz")
    }
}
