import XCTest
@testable import LangSwitcher

@MainActor
final class DictionaryDownloadManagerTests: XCTestCase {

    func testSystemSupportedLanguages() {
        let manager = DictionaryDownloadManager.shared
        // Native languages known to macOS
        XCTAssertTrue(manager.isSystemSupported("en"))
        XCTAssertTrue(manager.isSystemSupported("ru"))
        XCTAssertTrue(manager.isSystemSupported("de"))
        XCTAssertTrue(manager.isSystemSupported("fr"))

        // Language not natively provided in macOS AppleSpell
        XCTAssertFalse(manager.isSystemSupported("unknown_lang_xyz"))
    }

    func testCatalogEntriesValidity() {
        XCTAssertFalse(DictionaryDownloadManager.catalog.isEmpty)
        
        guard let tg = DictionaryDownloadManager.catalog["tg"] else {
            XCTFail("Missing tg catalog entry")
            return
        }
        XCTAssertEqual(tg.languageCode, "tg")
        XCTAssertTrue(tg.affFileName.hasSuffix(".aff"))
        XCTAssertTrue(tg.dicFileName.hasSuffix(".dic"))
        XCTAssertTrue(tg.affURL.absoluteString.hasPrefix("https://"))
        XCTAssertTrue(tg.dicURL.absoluteString.hasPrefix("https://"))
        XCTAssertGreaterThan(tg.approximateSizeMB, 0)
    }

    func testCustomDictionaryStoreParsingAndLookup() throws {
        let store = CustomDictionaryStore.shared
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleDic = """
        4
        салом/25,852
        тоҷик/25,852
        китоб/25
        дӯст/25
        """
        let dicURL = tempDir.appendingPathComponent("tg_test.dic")
        try sampleDic.write(to: dicURL, atomically: true, encoding: .utf8)

        store.loadDictionary(at: dicURL, forLanguage: "tg_test")
        XCTAssertTrue(store.hasDictionary(for: "tg_test"))

        // Exact match
        XCTAssertTrue(store.isValidWord("салом", language: "tg_test"))
        XCTAssertTrue(store.isValidWord("китоб", language: "tg_test"))
        XCTAssertTrue(store.isValidWord("САЛОМ", language: "tg_test"))

        // Gibberish rejection
        XCTAssertFalse(store.isValidWord("фывджалыв", language: "tg_test"))
        XCTAssertFalse(store.isValidWord("hello", language: "tg_test"))
    }

    func testCustomDictionaryStoreTajikSuffixInflection() throws {
        let store = CustomDictionaryStore.shared
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleDic = """
        2
        тоҷик/25,852
        китоб/25
        """
        let dicURL = tempDir.appendingPathComponent("tg.dic")
        try sampleDic.write(to: dicURL, atomically: true, encoding: .utf8)

        store.loadDictionary(at: dicURL, forLanguage: "tg")

        // Exact stems
        XCTAssertTrue(store.isValidWord("тоҷик", language: "tg"))
        XCTAssertTrue(store.isValidWord("китоб", language: "tg"))

        // Suffix inflections: -ӣ, -ҳо, -ро, -он
        XCTAssertTrue(store.isValidWord("тоҷикӣ", language: "tg"))
        XCTAssertTrue(store.isValidWord("тоҷикҳо", language: "tg"))
        XCTAssertTrue(store.isValidWord("китобҳо", language: "tg"))
        XCTAssertTrue(store.isValidWord("китобро", language: "tg"))

        // Gibberish with suffix should not match random stems
        XCTAssertFalse(store.isValidWord("йцукенгӣ", language: "tg"))
    }

    func testCustomDictionaryStoreCandidateCompletions() throws {
        let store = CustomDictionaryStore.shared
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleDic = """
        5
        салом
        саломатӣ
        саломнома
        субҳ
        ситора
        """
        let dicURL = tempDir.appendingPathComponent("tg_comp.dic")
        try sampleDic.write(to: dicURL, atomically: true, encoding: .utf8)

        store.loadDictionary(at: dicURL, forLanguage: "tg_comp")

        let candidates = store.candidateCompletions(prefix: "сал", language: "tg_comp", limit: 3)
        XCTAssertTrue(candidates.contains("салом"))
        XCTAssertTrue(candidates.contains("саломатӣ") || candidates.contains("саломнома"))
        XCTAssertFalse(candidates.contains("субҳ"))
    }
}
