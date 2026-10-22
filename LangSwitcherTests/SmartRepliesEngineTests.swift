import XCTest
@testable import LangSwitcher

final class SmartRepliesEngineTests: XCTestCase {

    func testRussianMeetingInquiry() {
        let replies = SmartRepliesEngine.generateReplies(for: "Во сколько завтра созвонимся?")
        XCTAssertEqual(replies.count, 3)
        XCTAssertEqual(replies[0].category, .affirmative)
        XCTAssertEqual(replies[1].category, .deferral)
        XCTAssertEqual(replies[2].category, .decline)
        XCTAssertTrue(replies[0].text.contains("договорились"))
        XCTAssertTrue(replies[1].text.contains("расписание"))
        XCTAssertEqual(replies[0].shortcut, "1")
        XCTAssertEqual(replies[1].shortcut, "2")
        XCTAssertEqual(replies[2].shortcut, "3")
    }

    func testRussianCodeReviewInquiry() {
        let replies = SmartRepliesEngine.generateReplies(for: "Сможешь глянуть мой PR до вечера?")
        XCTAssertEqual(replies.count, 3)
        XCTAssertTrue(replies[0].text.contains("посмотрю"))
    }

    func testEnglishMeetingInquiry() {
        let replies = SmartRepliesEngine.generateReplies(for: "Are you available for a quick call at 3pm?")
        XCTAssertEqual(replies.count, 3)
        XCTAssertEqual(replies[0].category, .affirmative)
        XCTAssertTrue(replies[0].text.contains("confirmed"))
    }

    func testEnglishReviewInquiry() {
        let replies = SmartRepliesEngine.generateReplies(for: "Could you please review the latest commit?")
        XCTAssertEqual(replies.count, 3)
        XCTAssertTrue(replies[0].text.contains("taking a look"))
    }
}
