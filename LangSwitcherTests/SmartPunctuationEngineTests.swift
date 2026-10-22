import XCTest
@testable import LangSwitcher

final class SmartPunctuationEngineTests: XCTestCase {

    // MARK: - Capitalization Tests

    func testCapitalizeAfterPeriod() {
        let result = SmartPunctuationEngine.capitalizeAfterSentence(word: "привет", precedingText: "Как дела. ")
        XCTAssertEqual(result, "Привет")
    }

    func testCapitalizeAfterExclamation() {
        let result = SmartPunctuationEngine.capitalizeAfterSentence(word: "как", precedingText: "Отлично! ")
        XCTAssertEqual(result, "Как")
    }

    func testCapitalizeAfterQuestionMark() {
        let result = SmartPunctuationEngine.capitalizeAfterSentence(word: "hello", precedingText: "Are you ready? ")
        XCTAssertEqual(result, "Hello")
    }

    func testCapitalizeAtStartOfText() {
        let result = SmartPunctuationEngine.capitalizeAfterSentence(word: "первое", precedingText: "")
        XCTAssertEqual(result, "Первое")
    }

    func testCapitalizeAtStartOfParagraph() {
        let result = SmartPunctuationEngine.capitalizeAfterSentence(word: "новая", precedingText: "Старая строка\n")
        XCTAssertEqual(result, "Новая")
    }

    func testDoNotCapitalizeAfterAbbreviations() {
        XCTAssertNil(SmartPunctuationEngine.capitalizeAfterSentence(word: "москва", precedingText: "в г. "))
        XCTAssertNil(SmartPunctuationEngine.capitalizeAfterSentence(word: "ленина", precedingText: "на ул. "))
        XCTAssertNil(SmartPunctuationEngine.capitalizeAfterSentence(word: "apple", precedingText: "such as e.g. "))
        XCTAssertNil(SmartPunctuationEngine.capitalizeAfterSentence(word: "dale", precedingText: "chip vs. "))
    }

    func testDoNotCapitalizeAlreadyCapitalized() {
        XCTAssertNil(SmartPunctuationEngine.capitalizeAfterSentence(word: "Привет", precedingText: "Тест. "))
    }

    func testDoNotCapitalizeWithoutSentenceTerminator() {
        XCTAssertNil(SmartPunctuationEngine.capitalizeAfterSentence(word: "привет", precedingText: "просто слово "))
    }

    // MARK: - Comma Before Conjunction Tests

    func testCommaBeforeRussianA() {
        let shouldInsert = SmartPunctuationEngine.shouldInsertCommaBeforeConjunction(word: "а", precedingText: "хотел ")
        XCTAssertTrue(shouldInsert)
    }

    func testCommaBeforeRussianNo() {
        let shouldInsert = SmartPunctuationEngine.shouldInsertCommaBeforeConjunction(word: "но", precedingText: "быстро ")
        XCTAssertTrue(shouldInsert)
    }

    func testDoNotInsertCommaIfAlreadyHasComma() {
        let shouldInsert = SmartPunctuationEngine.shouldInsertCommaBeforeConjunction(word: "а", precedingText: "хотел, ")
        XCTAssertFalse(shouldInsert)
    }

    func testDoNotInsertCommaIfStartOfSentence() {
        let shouldInsertNo = SmartPunctuationEngine.shouldInsertCommaBeforeConjunction(word: "Но", precedingText: "Привет. ")
        XCTAssertFalse(shouldInsertNo)

        let shouldInsertA = SmartPunctuationEngine.shouldInsertCommaBeforeConjunction(word: "А", precedingText: "")
        XCTAssertFalse(shouldInsertA)
    }

    func testDoNotInsertCommaAfterSentencePunctuation() {
        let shouldInsert = SmartPunctuationEngine.shouldInsertCommaBeforeConjunction(word: "а", precedingText: "конец. ")
        XCTAssertFalse(shouldInsert)
    }

    // MARK: - Space Before Punctuation Tests

    func testFixSpaceBeforeComma() {
        let fix = SmartPunctuationEngine.fixSpaceBeforePunctuation(char: ",", precedingText: "слово ")
        XCTAssertNotNil(fix)
        XCTAssertEqual(fix?.expected, " ,")
        XCTAssertEqual(fix?.replacement, ",")
    }

    func testFixSpaceBeforeDot() {
        let fix = SmartPunctuationEngine.fixSpaceBeforePunctuation(char: ".", precedingText: "слово ")
        XCTAssertNotNil(fix)
        XCTAssertEqual(fix?.expected, " .")
        XCTAssertEqual(fix?.replacement, ".")
    }

    func testFixSpaceBeforeQuestion() {
        let fix = SmartPunctuationEngine.fixSpaceBeforePunctuation(char: "?", precedingText: "почему ")
        XCTAssertNotNil(fix)
        XCTAssertEqual(fix?.expected, " ?")
        XCTAssertEqual(fix?.replacement, "?")
    }

    func testDoNotFixWithoutSpace() {
        let fix = SmartPunctuationEngine.fixSpaceBeforePunctuation(char: ",", precedingText: "слово")
        XCTAssertNil(fix)
    }

    // MARK: - Smart Dashes & Ellipsis Tests

    func testSmartDashOnDoubleHyphen() {
        let fix = SmartPunctuationEngine.smartDashesAndEllipsis(char: "-", precedingText: "тест -")
        XCTAssertNotNil(fix)
        XCTAssertEqual(fix?.expected, "--")
        XCTAssertEqual(fix?.replacement, "—")
    }

    func testSmartEllipsisOnTripleDot() {
        let fix = SmartPunctuationEngine.smartDashesAndEllipsis(char: ".", precedingText: "тест..")
        XCTAssertNotNil(fix)
        XCTAssertEqual(fix?.expected, "...")
        XCTAssertEqual(fix?.replacement, "…")
    }

    func testDoNotTriggerOnQuadrupleDot() {
        let fix = SmartPunctuationEngine.smartDashesAndEllipsis(char: ".", precedingText: "тест...")
        XCTAssertNil(fix)
    }

    // MARK: - Caps Lock Error Tests

    func testFixCapsLockErrorRussian() {
        let fixed = SmartPunctuationEngine.fixCapsLockError("пРИВЕТ")
        XCTAssertEqual(fixed, "Привет")
    }

    func testFixCapsLockErrorEnglish() {
        let fixed = SmartPunctuationEngine.fixCapsLockError("hELLO")
        XCTAssertEqual(fixed, "Hello")
    }

    func testPreserveMixedCaseTechTerms() {
        XCTAssertNil(SmartPunctuationEngine.fixCapsLockError("iOS"))
        XCTAssertNil(SmartPunctuationEngine.fixCapsLockError("macOS"))
        XCTAssertNil(SmartPunctuationEngine.fixCapsLockError("eBay"))
    }

    func testDoNotFixNormalWords() {
        XCTAssertNil(SmartPunctuationEngine.fixCapsLockError("Привет"))
        XCTAssertNil(SmartPunctuationEngine.fixCapsLockError("HELLO"))
        XCTAssertNil(SmartPunctuationEngine.fixCapsLockError("hello"))
    }
}
