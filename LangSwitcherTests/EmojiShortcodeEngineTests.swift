import XCTest
@testable import LangSwitcher

final class EmojiShortcodeEngineTests: XCTestCase {

    func testDirectEnglishShortcodes() {
        XCTAssertEqual(EmojiShortcodeEngine.lookup(rawCode: "fire"), "🔥")
        XCTAssertEqual(EmojiShortcodeEngine.lookup(rawCode: "rocket"), "🚀")
        XCTAssertEqual(EmojiShortcodeEngine.lookup(rawCode: "heart"), "❤️")
        XCTAssertEqual(EmojiShortcodeEngine.lookup(rawCode: "+1"), "👍")
        XCTAssertEqual(EmojiShortcodeEngine.lookup(rawCode: "thumbsup"), "👍")
        XCTAssertEqual(EmojiShortcodeEngine.lookup(rawCode: "sparkles"), "✨")
    }

    func testDirectRussianShortcodes() {
        XCTAssertEqual(EmojiShortcodeEngine.lookup(rawCode: "огонь"), "🔥")
        XCTAssertEqual(EmojiShortcodeEngine.lookup(rawCode: "ракета"), "🚀")
        XCTAssertEqual(EmojiShortcodeEngine.lookup(rawCode: "лайк"), "👍")
        XCTAssertEqual(EmojiShortcodeEngine.lookup(rawCode: "сердце"), "❤️")
        XCTAssertEqual(EmojiShortcodeEngine.lookup(rawCode: "смайл"), "😄")
    }

    func testCrossLayoutUSMisTypedRussian() {
        // "jujym" typed in US layout corresponds physically to "огонь"
        XCTAssertEqual(EmojiShortcodeEngine.lookup(rawCode: "jujym"), "🔥")
        // "hfrtnf" typed in US layout corresponds to "ракета"
        XCTAssertEqual(EmojiShortcodeEngine.lookup(rawCode: "hfrtnf"), "🚀")
    }

    func testCrossLayoutRussianMisTypedEnglish() {
        // "ашку" typed in Russian layout corresponds physically to "fire"
        XCTAssertEqual(EmojiShortcodeEngine.lookup(rawCode: "ашку"), "🔥")
        // "кщслуе" typed in Russian layout corresponds to "rocket"
        XCTAssertEqual(EmojiShortcodeEngine.lookup(rawCode: "кщслуе"), "🚀")
    }

    func testColonReplacementDetection() {
        let text1 = "Привет! Это просто :огонь:"
        let match1 = EmojiShortcodeEngine.findColonReplacement(in: text1)
        XCTAssertNotNil(match1)
        XCTAssertEqual(match1?.expected, ":огонь:")
        XCTAssertEqual(match1?.replacement, "🔥")

        let text2 = "Check this out :fire:"
        let match2 = EmojiShortcodeEngine.findColonReplacement(in: text2)
        XCTAssertNotNil(match2)
        XCTAssertEqual(match2?.expected, ":fire:")
        XCTAssertEqual(match2?.replacement, "🔥")

        // Cross-layout with colon
        let text3 = "Вау :jujym:"
        let match3 = EmojiShortcodeEngine.findColonReplacement(in: text3)
        XCTAssertNotNil(match3)
        XCTAssertEqual(match3?.expected, ":jujym:")
        XCTAssertEqual(match3?.replacement, "🔥")
    }

    func testSpaceReplacementDetection() {
        let text1 = "Посмотри :огонь "
        let match1 = EmojiShortcodeEngine.findSpaceReplacement(in: text1)
        XCTAssertNotNil(match1)
        XCTAssertEqual(match1?.expected, ":огонь ")
        XCTAssertEqual(match1?.replacement, "🔥 ")

        let text2 = "Launch :rocket "
        let match2 = EmojiShortcodeEngine.findSpaceReplacement(in: text2)
        XCTAssertNotNil(match2)
        XCTAssertEqual(match2?.expected, ":rocket ")
        XCTAssertEqual(match2?.replacement, "🚀 ")
    }

    func testInvalidOrUnknownShortcodes() {
        XCTAssertNil(EmojiShortcodeEngine.lookup(rawCode: "some_random_gibberish_123"))
        XCTAssertNil(EmojiShortcodeEngine.findColonReplacement(in: "nothing here:"))
        XCTAssertNil(EmojiShortcodeEngine.findColonReplacement(in: "just words"))
        XCTAssertNil(EmojiShortcodeEngine.findColonReplacement(in: ":unknown_code_xyz:"))
        XCTAssertNil(EmojiShortcodeEngine.findColonReplacement(in: ":spaces inside code:"))
    }

    func testCandidatesSuggestions() {
        let candidatesRu = EmojiShortcodeEngine.candidates(for: ":ог")
        XCTAssertFalse(candidatesRu.isEmpty)
        XCTAssertTrue(candidatesRu.contains(where: { $0.emoji == "🔥" }))

        let candidatesEn = EmojiShortcodeEngine.candidates(for: ":fi")
        XCTAssertFalse(candidatesEn.isEmpty)
        XCTAssertTrue(candidatesEn.contains(where: { $0.emoji == "🔥" }))

        // Cross-layout candidate search
        let candidatesCross = EmojiShortcodeEngine.candidates(for: ":juj")
        XCTAssertFalse(candidatesCross.isEmpty)
        XCTAssertTrue(candidatesCross.contains(where: { $0.emoji == "🔥" }))
    }
}
