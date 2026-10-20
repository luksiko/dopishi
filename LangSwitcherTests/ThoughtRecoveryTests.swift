import XCTest
@testable import LangSwitcher

// MARK: - Thought Recovery
//
// Thought Recovery (docs/content/en/guide/6.thought-recovery.md) reconstructs a
// whole line span by span instead of converting one wrong-layout tail:
//
//     ghbdsn, я вже зробив rjvsn але tests gflf.nm
//     → привіт, я вже зробив коміт але tests падають
//
// The tests below cover the four promises of the idea document:
// 1. spans that mix languages inside one sentence are recovered,
// 2. code, links and intentional foreign words are never touched,
// 3. only spans with decisive evidence are rewritten — an ambiguous reading
//    keeps the original text, and the single exception (a lone lowercase Latin
//    letter in a Cyrillic sentence whose wrong-layout reading is a real word of
//    that language) is pinned by its own tests,
// 4. undoing a recovery teaches the personal dictionary.

@MainActor
final class ThoughtRecoveryTests: XCTestCase {

    private let usLayout = "com.apple.keylayout.US"
    private let ukrainianLayout = "com.apple.keylayout.Ukrainian-PC"
    private let polishLayout = "com.apple.keylayout.PolishPro"

    private var settings: SettingsManager!
    private var converter: TextConverter!

    override func setUp() {
        super.setUp()
        settings = SettingsManager.shared
        settings.enabledLayouts = [
            KeyboardLayout(id: usLayout, localizedName: "U.S.", languageCode: "en"),
            KeyboardLayout(id: ukrainianLayout, localizedName: "Ukrainian – PC", languageCode: "uk"),
        ]
        settings.thoughtRecoveryEnabled = true
        settings.thoughtRecoveryPreview = false
        converter = TextConverter(settingsManager: settings)
        UserDictionary.shared.removeAll()
    }

    override func tearDown() {
        UserDictionary.shared.removeAll()
        settings.thoughtRecoveryEnabled = true
        converter = nil
        settings = nil
        super.tearDown()
    }

    private func plan(_ text: String, layouts: [String]? = nil) -> ThoughtRecovery.Plan {
        ThoughtRecovery.decode(text, layoutIDs: layouts ?? [usLayout, ukrainianLayout])
    }

    // MARK: - The example from the idea document

    func testRecoversMixedSentence() {
        let result = plan("ghbdsn, я вже зробив rjvsn але tests gflf.nm")
        XCTAssertEqual(result.reconstructed, "привіт, я вже зробив коміт але tests падають")
        XCTAssertTrue(result.isChanged)
        XCTAssertEqual(result.primaryTargetLayoutID, ukrainianLayout)
        XCTAssertGreaterThan(result.confidence, 0.5)
    }

    func testRecoveredSentenceKeepsEnglishWordUntouched() {
        let result = plan("ghbdsn, я вже зробив rjvsn але tests gflf.nm")
        let english = result.spans.first { $0.text == "tests" }
        XCTAssertNotNil(english)
        XCTAssertFalse(english!.changed, "An English word inside a Ukrainian sentence must survive")
        XCTAssertEqual(english!.kind, .intentionalForeign)
    }

    // MARK: - A wrong-layout letter can look like punctuation

    func testPeriodInsideWordIsRecovered() {
        // "gflf.nm" is "падають" typed on the wrong layout: the period IS the
        // letter ю on Ukrainian-PC.
        XCTAssertEqual(plan("gflf.nm").reconstructed, "падають")
        XCTAssertEqual(plan("dcnbuf. я не").reconstructed, "встигаю я не")
    }

    func testTrailingCommaIsNotALetter() {
        // "ghbdtn," is "привет," — the comma is real punctuation, so it must
        // not become б.
        XCTAssertEqual(plan("ghbdtn,").reconstructed, "привет,")
    }

    func testRecoversWholeWrongLayoutLine() {
        XCTAssertEqual(plan("ghbdtn rfr ltkf").reconstructed, "привет как дела")
    }

    // MARK: - Correct text never changes

    func testKeepsCorrectUkrainianSentence() {
        let text = "дякую за допомогу, все працює"
        XCTAssertEqual(plan(text).reconstructed, text)
    }

    func testKeepsCorrectEnglishSentence() {
        let text = "hello world, this is a test"
        XCTAssertEqual(plan(text).reconstructed, text)
    }

    func testKeepsCorrectPolishSentence() {
        let text = "cześć, jak się masz?"
        XCTAssertEqual(plan(text).reconstructed, text)
    }

    func testKeepsCorrectPolishSentenceWithPolishLayout() {
        let text = "dziękuję bardzo, wszystko dobrze"
        XCTAssertEqual(plan(text, layouts: [polishLayout, ukrainianLayout]).reconstructed, text)
    }

    // MARK: - Lone letters

    func testRewritesLoneLetterThatSpellsAWordOfTheSentenceLanguage() {
        // A lone lowercase Latin letter in a Ukrainian sentence is the wrong
        // layout for a one-letter Ukrainian word: "z" is "я", "s" is "і".
        XCTAssertEqual(plan("z не встигаю").reconstructed, "я не встигаю")
        XCTAssertEqual(plan("s не встигаю").reconstructed, "і не встигаю")
    }

    func testKeepsLoneLetterThatIsAWordOfAnotherLanguage() {
        // The very same letter in Polish text is the preposition "z", so the
        // sentence language keeps it — the mirror-image guess never happens.
        XCTAssertEqual(plan("z nie wiem", layouts: [polishLayout, ukrainianLayout]).reconstructed,
                       "z nie wiem")
        // Nothing for it to spell in the sentence's language: unchanged.
        XCTAssertEqual(plan("this is a test").reconstructed, "this is a test")
    }

    func testKeepsUppercaseLoneLetter() {
        // An uppercase single letter is a label (a size, an option), not a
        // mistyped word: "S" must not become "І".
        XCTAssertEqual(plan("розмір S").reconstructed, "розмір S")
    }

    func testLoneLetterNeverStealsALetterFromAGluedWord() {
        // "d" and "t" each map to a one-letter Ukrainian word ("в", "е"), but
        // here they are letters of "вже", so the word reading has to win.
        XCTAssertEqual(plan("d;t").reconstructed, "вже")
        XCTAssertEqual(plan("z d;t").reconstructed, "я вже")
    }

    // MARK: - Punctuation that is really a letter

    func testCommaAndSemicolonBetweenLettersAreLetters() {
        // On Ukrainian-PC the "," key types б and the ";" key types ж, so
        // between two letters they belong to the word itself.
        XCTAssertEqual(plan("cghj,eq").reconstructed, "спробуй")
        XCTAssertEqual(plan("phj,bd").reconstructed, "зробив")
        XCTAssertEqual(plan("d;t").reconstructed, "вже")
        XCTAssertEqual(plan("нова версія вже на сервері, cghj,eq").reconstructed,
                       "нова версія вже на сервері, спробуй")
    }

    func testWordCarryingItsOwnPunctuationSplits() {
        // "wt," is "це" followed by a real comma. A segment is scored through
        // its letter core, so keeping the comma attached used to tie with
        // splitting it off; the split has to win.
        XCTAssertEqual(plan("я вже зробив wt, але спробуй ще раз").reconstructed,
                       "я вже зробив це, але спробуй ще раз")
        XCTAssertEqual(plan("nj, але").reconstructed, "то, але")
    }

    // MARK: - ⌥-layer (Polish diacritics typed on a Cyrillic layout)

    func testRecoversPolishOptionChords() {
        let result = plan("сяуы≠", layouts: [polishLayout, ukrainianLayout])
        XCTAssertEqual(result.reconstructed, "cześć")
    }

    // MARK: - Code, links, e-mail, intentional foreign words

    func testKeepsURL() {
        let text = "перевір https://github.com/reg2005/langSwitcher"
        XCTAssertEqual(plan(text).reconstructed, text)
    }

    func testKeepsEmail() {
        let text = "напиши на test@example.com"
        XCTAssertEqual(plan(text).reconstructed, text)
    }

    func testKeepsCodeSnippet() {
        let text = "user_id = 42"
        XCTAssertEqual(plan(text).reconstructed, text)
    }

    func testKeepsCamelCaseIdentifier() {
        let text = "виклич getUserName() перед save"
        XCTAssertEqual(plan(text).reconstructed, text)
    }

    func testKeepsIntentionalEnglishWords() {
        let text = "зробив pull request у main"
        XCTAssertEqual(plan(text).reconstructed, text)
    }

    // MARK: - Segment kinds

    func testClassifiesSegments() {
        var kinds: [String: ThoughtRecovery.SpanKind] = [:]
        for span in plan("перевір https://github.com/reg2005/langSwitcher").spans where span.letterCount > 0 {
            kinds[span.text] = span.kind
        }
        XCTAssertEqual(kinds["перевір"], .correct)
        XCTAssertEqual(kinds["github"], .url)
        XCTAssertEqual(kinds["https"], .url)

        let snippetSpans = plan("user_id = 42").spans.filter { $0.letterCount > 0 }
        XCTAssertEqual(snippetSpans.first?.kind, .code)
    }

    func testReportsWrongLayoutSpans() {
        let result = plan("ghbdsn, я вже зробив rjvsn")
        XCTAssertEqual(result.changedSpans.count, 2)
        XCTAssertTrue(result.changedSpans.allSatisfy { $0.kind == .wrongLayout })
    }

    // MARK: - Alternatives (idea document UX)

    func testAlternativesAreDistinctAndBounded() {
        let result = plan("ghbdsn, z d;t rjvsn")
        XCTAssertLessThanOrEqual(result.alternatives.count, 2)
        XCTAssertEqual(Set(result.alternatives).count, result.alternatives.count)
        XCTAssertFalse(result.alternatives.contains(result.reconstructed))
    }

    func testConfidenceIsZeroWhenNothingChanges() {
        let result = plan("привіт, як справи?")
        XCTAssertFalse(result.isChanged)
        XCTAssertEqual(result.confidence, 0, accuracy: 0.0001)
        XCTAssertTrue(result.changedSpans.isEmpty)
    }

    // MARK: - Personal dictionary (undo teaches it)

    func testLearnedWordsAreNeverRewritten() {
        let result = ThoughtRecovery.decode("зробив rjvsn", layoutIDs: [usLayout, ukrainianLayout], learnedWords: ["rjvsn"])
        XCTAssertEqual(result.reconstructed, "зробив rjvsn")
    }

    func testUserDictionaryBlocksWrongLayoutAutoConversion() {
        // The same word is normally corrected…
        XCTAssertTrue(converter.looksLikeWrongLayout("ghbdtn"))

        // …until the user reverts a recovery that touched it.
        UserDictionary.shared.learnWords(in: "ghbdtn файл")
        XCTAssertTrue(UserDictionary.shared.contains("ghbdtn"))
        XCTAssertFalse(converter.looksLikeWrongLayout("ghbdtn"),
                       "A word taught by undoing a recovery must never be rewritten")
        XCTAssertNil(converter.convertIfWrongLayout("ghbdtn"))

        UserDictionary.shared.removeAll()
        XCTAssertTrue(converter.looksLikeWrongLayout("ghbdtn"))
    }

    func testUserDictionaryIgnoresSingleLetters() {
        XCTAssertFalse(UserDictionary.shared.learn("z"))
        XCTAssertTrue(UserDictionary.shared.learn("тест"))
        XCTAssertTrue(UserDictionary.shared.contains("ТЕСТ"))
        UserDictionary.shared.forget("тест")
        XCTAssertFalse(UserDictionary.shared.contains("тест"))
    }

    // MARK: - TextConverter integration

    func testConverterRecoversLine() {
        let result = converter.recoverLine("ghbdsn, я вже зробив rjvsn але tests gflf.nm")
        XCTAssertEqual(result?.text, "привіт, я вже зробив коміт але tests падають")
        XCTAssertEqual(result?.targetLayoutID, ukrainianLayout)
    }

    func testConverterAbstainsOnCorrectText() {
        XCTAssertNil(converter.recoverLine("привіт, як справи?"))
    }

    func testConverterRespectsDisabledSetting() {
        settings.thoughtRecoveryEnabled = false
        XCTAssertNil(converter.recoverLine("gflf.nm"))
        XCTAssertNil(converter.recoveryPlan(for: "gflf.nm"))
    }

    func testConverterPlanExposesSpans() {
        let result = converter.recoveryPlan(for: "ghbdtn rfr ltkf")
        XCTAssertEqual(result?.reconstructed, "привет как дела")
        XCTAssertEqual(result?.changedSpans.count, 3)
    }

    // MARK: - Metrics (idea document MVP)

    /// Wrong-layout input with its expected reconstruction, plus correct input
    /// that must stay untouched. The wrong-layout lines are generated from
    /// correct Ukrainian sentences (English tech words left alone) by
    /// converting only some of the Cyrillic words — the kind of half-broken
    /// line users actually hit the hotkey on.
    func testMetricsOnMixedAndCorrectText() {
        var corrected: [(input: String, expected: String)] = []
        for sentence in Self.sentences {
            corrected.append((mixed(sentence) { _ in true }, sentence))
            corrected.append((mixed(sentence) { $0 == sentence.split(separator: " ").count - 1 }, sentence))
            corrected.append((mixed(sentence) { $0 % 2 == 0 }, sentence))
        }

        let control: [(input: String, expected: String)] = Self.correctLines.map { ($0, $0) }

        // The three variants per sentence cover the three shapes that used to
        // be missed: a whole sentence in the wrong layout, a single broken
        // word, and a scattering that includes the one-letter words ("я") and
        // the comma/semicolon keys ("вже", "може", "спробуй").
        let recovered = ThoughtRecovery.evaluate(corrected, layoutIDs: [usLayout, ukrainianLayout])
        XCTAssertGreaterThan(recovered.characterRecoveryAccuracy, 0.99,
                             "Per-character recovery accuracy dropped")
        XCTAssertGreaterThan(recovered.exactMatchRate, 0.95,
                             "Whole-sentence reconstruction rate dropped")

        // False replacements are only measurable on lines that must not change:
        // `evaluate` charges a line for the characters it rewrote when its
        // input already equals its expected text.
        let untouched = ThoughtRecovery.evaluate(control, layoutIDs: [usLayout, ukrainianLayout])
        XCTAssertEqual(untouched.falseReplacementRate, 0,
                       "Correct text must never be rewritten")
        XCTAssertEqual(untouched.exactMatchRate, 1, "Correct text must come back unchanged")
    }

    func testCharacterAccuracyHelper() {
        XCTAssertEqual(ThoughtRecovery.characterAccuracy("привіт", expected: "привіт"), 1, accuracy: 0.0001)
        XCTAssertEqual(ThoughtRecovery.characterAccuracy("привет", expected: "привіт"), 5.0 / 6.0, accuracy: 0.01)
        XCTAssertEqual(ThoughtRecovery.differenceCount("abc", "abd"), 1)
        XCTAssertEqual(ThoughtRecovery.differenceCount("abc", "ab"), 1)
    }

    // MARK: - Corpus fixtures

    private static let sentences = [
        "привіт, я вже зробив коміт але tests падають",
        "добрий день, колеги, як справи?",
        "мені дуже подобається ця ідея",
        "перевір будь ласка цей файл ще раз",
        "я не встигаю зробити все сьогодні",
        "тут все добре, дякую за допомогу",
        "нова версія вже на сервері, спробуй",
        "зроби pull request і напиши мені",
        "може вже час додому",
        "він ще не прийшов але вже скоро",
        "я вже зробив це, але спробуй ще раз",
        "скажи мені, будь ласка, коли все готово",
        "це вже не потрібно, але дякую за спробу",
        "перевір, будь ласка, чи все добре",
    ]

    private static let correctLines = [
        "привіт, як справи?",
        "добрий день, колеги",
        "дякую за допомогу, все працює",
        "hello world, this is a test",
        "see the docs at https://langswitcher.io",
        "write to support@example.com please",
        "call getUserName() before saving",
        "set user_id and max_retries",
        // Adversarial for the two new rules: a comma between letters in correct
        // text, uppercase lone letters, and a lone lowercase Latin letter in a
        // Latin sentence that must keep it.
        "ні,ні",
        "привіт,як справи",
        "розмір S та M",
        "z tego nie ma",
    ]

    /// Convert the selected Cyrillic words of a sentence to the wrong layout.
    private func mixed(_ sentence: String, convert: (Int) -> Bool) -> String {
        var words = sentence.split(separator: " ").map(String.init)
        for (index, word) in words.enumerated() where word.contains(where: { !$0.isASCII }) && convert(index) {
            words[index] = LayoutMapper.convert(text: word, from: ukrainianLayout, to: usLayout) ?? word
        }
        return words.joined(separator: " ")
    }
}
