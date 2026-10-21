import XCTest
@testable import LangSwitcher

final class ProfanityFilterTests: XCTestCase {
    
    func testRussianObscenitiesDetected() {
        let profaneWords = [
            "хуй", "хуйня", "хуевый", "хуёвый", "охуеть", "похуй", "нахуй", "дохуя", "нихуя",
            "пизда", "пиздец", "пиздит", "пиздюк", "распиздяй", "впизду",
            "ебать", "ебет", "ебёт", "ебу", "ёбаный", "ебаный", "заебись", "выебон", "наебать", "уебок", "проебал", "съебать",
            "бля", "блять", "блядь", "блядство", "блядина",
            "мудак", "мудила", "гондон", "гандон", "пидор", "шлюха", "сука", "сучка", "говно", "дерьмо", "залупа", "дрочить", "манда", "жопа"
        ]
        
        for word in profaneWords {
            XCTAssertTrue(ProfanityFilter.isProfane(word), "Expected '\(word)' to be detected as profane")
            XCTAssertTrue(ProfanityFilter.isProfane(word.uppercased()), "Expected uppercase '\(word)' to be detected as profane")
            XCTAssertTrue(ProfanityFilter.isProfane(word.capitalized), "Expected capitalized '\(word)' to be detected as profane")
        }
    }
    
    func testEnglishObscenitiesDetected() {
        let profaneWords = [
            "fuck", "fucking", "fucker", "motherfucker", "shit", "bullshit", "shitty",
            "bitch", "asshole", "cunt", "dickhead", "cocksucker", "twat", "wanker"
        ]
        
        for word in profaneWords {
            XCTAssertTrue(ProfanityFilter.isProfane(word), "Expected '\(word)' to be detected as profane")
        }
    }
    
    func testUkrainianObscenitiesDetected() {
        let profaneWords = [
            "їбати", "заїбав", "йобнутий", "піздець", "курва", "гівно", "лайно"
        ]
        
        for word in profaneWords {
            XCTAssertTrue(ProfanityFilter.isProfane(word), "Expected '\(word)' to be detected as profane")
        }
    }
    
    func testLegitimateWordsNotFlagged() {
        let cleanWords = [
            "хлеб", "ребенок", "ребёнок", "оскорблять", "употреблять", "рубля", "корабля", "сабля", "бляшка", "бляшки",
            "потребность", "колебание", "художник", "худой", "худеть", "хутор", "хулиган",
            "cocktail", "cockpit", "peacock", "classic", "assistant", "glass", "grass", "shift", "shirt",
            "hello", "привет", "спасибо", "учеба", "учёба", "серебро", "гребля", "погреб", "выгребать"
        ]
        
        for word in cleanWords {
            XCTAssertFalse(ProfanityFilter.isProfane(word), "Expected '\(word)' NOT to be flagged as profane")
        }
    }
}
