import XCTest
@testable import LangSwitcher

// MARK: - Language Wordlist Veto/Confirm
//
// The embedded frequency wordlists (WordlistData) back two decisions:
// 1. VETO — looksLikeWrongLayout must refuse to convert text that is
//    already real language (dictionary evidence). The veto is script-
//    based: Latin text checks Polish ∪ English, Cyrillic text checks
//    Ukrainian ∪ Russian — so English/Russian words are protected in
//    every layout pair.
// 2. CONFIRM — LanguageWordlists.confirmsConversion recognizes real
//    conversion output (primitive for richer scoring).
//
// Regression context: with PolishPro+Ukrainian-PC enabled, the automatic
// Space flow garbled every correctly typed PL/UA word (cześć → сяуы)
// because the script-switch heuristic alone cannot distinguish intended
// text from wrong-layout text. The manual hotkey flow stays permissive —
// the user's hotkey press is the intent signal there.

@MainActor
final class LanguageWordlistTests: XCTestCase {

    private var settings: SettingsManager!
    private var converter: TextConverter!

    override func setUp() {
        super.setUp()
        settings = SettingsManager.shared
        // The real working pair for the Polish↔Ukrainian flow.
        settings.enabledLayouts = [
            KeyboardLayout(id: "com.apple.keylayout.PolishPro", localizedName: "Polish", languageCode: "pl"),
            KeyboardLayout(id: "com.apple.keylayout.Ukrainian-PC", localizedName: "Ukrainian – PC", languageCode: "uk"),
        ]
        converter = TextConverter(settingsManager: settings)
    }

    override func tearDown() {
        converter = nil
        settings = nil
        super.tearDown()
    }

    // MARK: - shouldVeto: multi-word text

    func testShouldVeto_CorrectPolishPhrases() {
        XCTAssertTrue(LanguageWordlists.shouldVeto(text: "dzień dobry"))
        XCTAssertTrue(LanguageWordlists.shouldVeto(text: "dziękuję bardzo"))
        XCTAssertTrue(LanguageWordlists.shouldVeto(text: "to jest dobrze"))
    }

    func testShouldVeto_CorrectUkrainianPhrases() {
        XCTAssertTrue(LanguageWordlists.shouldVeto(text: "добрий день"))
        XCTAssertTrue(LanguageWordlists.shouldVeto(text: "все добре"))
        XCTAssertTrue(LanguageWordlists.shouldVeto(text: "сьогодні дуже добре"))
    }

    func testShouldVeto_PartialCoverageDoesNotVeto() {
        // One dictionary word + one non-word: not enough evidence the text
        // is intentional language, conversion stays possible.
        XCTAssertFalse(LanguageWordlists.shouldVeto(text: "cześć zzqqq"))
        XCTAssertFalse(LanguageWordlists.shouldVeto(text: "привіт zzzxx"))
    }

    // MARK: - shouldVeto: single-word rule (≥4 letters)

    func testShouldVeto_SingleCorrectPolishWord() {
        // 5 letters, real Polish: must be protected from auto-conversion.
        XCTAssertTrue(LanguageWordlists.shouldVeto(text: "cześć"))
        XCTAssertTrue(LanguageWordlists.shouldVeto(text: "wszystko"))
    }

    func testShouldVeto_SingleCorrectUkrainianWord() {
        XCTAssertTrue(LanguageWordlists.shouldVeto(text: "привіт"))
        XCTAssertTrue(LanguageWordlists.shouldVeto(text: "сьогодні"))
    }

    func testShouldVeto_ShortWordsTooAmbiguous() {
        // 1–3-letter words exist in both languages ("to", "nie" in PL,
        // "не", "на" in UA) — too weak to veto.
        XCTAssertFalse(LanguageWordlists.shouldVeto(text: "tak"))
        XCTAssertFalse(LanguageWordlists.shouldVeto(text: "nie"))
        XCTAssertFalse(LanguageWordlists.shouldVeto(text: "не"))
    }

    func testShouldVeto_NonWordsNeverVeto() {
        XCTAssertFalse(LanguageWordlists.shouldVeto(text: "ghbdtn"))
        XCTAssertFalse(LanguageWordlists.shouldVeto(text: "сяуы"))
        XCTAssertFalse(LanguageWordlists.shouldVeto(text: "руддщ"))
    }

    // MARK: - English and Russian (script unions)
    //
    // The veto is script-based, not layout-based: Latin text checks
    // Polish ∪ English, Cyrillic text checks Ukrainian ∪ Russian. This is
    // what makes the default-ON Space auto-correction safe for every
    // supported layout pair.

    func testShouldVeto_CorrectEnglishWords() {
        // Single ≥4-letter English words must be protected via the Latin
        // union (Polish ∪ English).
        XCTAssertTrue(LanguageWordlists.shouldVeto(text: "hello"))
        XCTAssertTrue(LanguageWordlists.shouldVeto(text: "world"))
        XCTAssertTrue(LanguageWordlists.shouldVeto(text: "sorry"))
    }

    func testShouldVeto_CorrectRussianWords() {
        // привет/когда live in the RU dictionary list (the old UA-list leak
        // is fixed); the Cyrillic union protects them as real words.
        XCTAssertTrue(LanguageWordlists.shouldVeto(text: "привет"))
        XCTAssertTrue(LanguageWordlists.shouldVeto(text: "когда"))
        XCTAssertTrue(LanguageWordlists.shouldVeto(text: "тем более"))
    }

    func testShouldVeto_RussianPhrase() {
        XCTAssertTrue(LanguageWordlists.shouldVeto(text: "добрий день"))
    }

    func testConfirmsConversion_EnglishAndRussian() {
        XCTAssertTrue(LanguageWordlists.confirmsConversion("hello"))
        XCTAssertTrue(LanguageWordlists.confirmsConversion("привет"))
        XCTAssertTrue(LanguageWordlists.confirmsConversion("тем более"))
    }

    func testBestMatch_IdentifiesLanguagePerList() {
        // Regression: Russian words leaked into the old Ukrainian list.
        // Per-language lists stay clean (dictionary-filtered), so language
        // identification is exact — while the VETO deliberately unions all
        // lists of a script, so "когда"/"привет" still veto as real words.
        XCTAssertEqual(LanguageWordlists.bestMatch(for: "cześć")?.language, .polish)
        XCTAssertEqual(LanguageWordlists.bestMatch(for: "привіт")?.language, .ukrainian)
        XCTAssertEqual(LanguageWordlists.bestMatch(for: "когда")?.language, .russian)
        XCTAssertNotNil(LanguageWordlists.bestMatch(for: "hello"),
                        "hello is a real word (it exists in both PL and EN lists)")
        // Gibberish matches nothing.
        XCTAssertNil(LanguageWordlists.bestMatch(for: "ghbdtn"))
        XCTAssertNil(LanguageWordlists.bestMatch(for: "сяуы"))
    }

    func testShouldVeto_MixedScriptAbstains() {
        XCTAssertFalse(LanguageWordlists.shouldVeto(text: "cześćпривіт"))
    }

    // MARK: - confirmsConversion

    func testConfirmsConversion_RealWords() {
        XCTAssertTrue(LanguageWordlists.confirmsConversion("cześć"))
        XCTAssertTrue(LanguageWordlists.confirmsConversion("dobrze"))
        XCTAssertTrue(LanguageWordlists.confirmsConversion("привіт"))
        XCTAssertTrue(LanguageWordlists.confirmsConversion("сьогодні"))
    }

    func testConfirmsConversion_NonWords() {
        XCTAssertFalse(LanguageWordlists.confirmsConversion("ghbdtn"))
        XCTAssertFalse(LanguageWordlists.confirmsConversion("сяуы"))
        XCTAssertFalse(LanguageWordlists.confirmsConversion(""))
    }

    // MARK: - Integration: wrong-layout detection with dictionary veto

    func testLooksLikeWrongLayout_CorrectPolishWordNotFlagged() {
        // Regression: cześć typed on Polish Pro (with Ukrainian-PC enabled)
        // must NOT be flagged — the auto flow would garble it to сяуы.
        XCTAssertFalse(converter.looksLikeWrongLayout("cześć"))
        XCTAssertFalse(converter.looksLikeWrongLayout("wszystko"))
    }

    func testLooksLikeWrongLayout_CorrectUkrainianWordNotFlagged() {
        XCTAssertFalse(converter.looksLikeWrongLayout("привіт"))
        XCTAssertFalse(converter.looksLikeWrongLayout("сьогодні"))
    }

    func testLooksLikeWrongLayout_GibberishStillFlagged() {
        // The veto must not swallow actual wrong-layout text.
        XCTAssertTrue(converter.looksLikeWrongLayout("сяуы"), "Ukrainian-PC gibberish for cześć must convert")
        XCTAssertTrue(converter.looksLikeWrongLayout("ghbdtn"), "Polish-typed gibberish for привет must convert")
    }

    func testAutoCorrectWord_ProtectsCorrectWords() {
        // The silent Space flow must abstain on real words — this is the
        // cześć → сяуы garbling regression.
        XCTAssertNil(converter.autoCorrectWord("cześć"))
        XCTAssertNil(converter.autoCorrectWord("cześć "))
        XCTAssertNil(converter.autoCorrectWord("привіт"))
    }

    func testAutoCorrectWord_StillConvertsGibberish() {
        // Full real-flow capture: the ≠ chord rides along when the user
        // typed cześć + Space on Ukrainian-PC, so the output keeps ć.
        XCTAssertEqual(converter.autoCorrectWord("сяуы≠ ")?.text, "cześć ")
        // Ukrainian-PC maps g→п h→р b→и d→в t→е n→т, so ghbdtn → привет.
        XCTAssertEqual(converter.autoCorrectWord("ghbdtn ")?.text, "привет ")
    }

    func testManualHotkeyConversionStaysPermissive() {
        // The manual hotkey path does NOT consult the dictionary veto:
        // pressing the hotkey IS the intent signal, and the user may
        // deliberately want a literal conversion.
        XCTAssertEqual(converter.convertSelectedText("cześć"), "сяуіс")
        XCTAssertEqual(converter.convertSelectedText("привіт"), "ghbdsn")
    }
}
