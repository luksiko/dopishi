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
            "hello", "привет", "спасибо", "учеба", "учёба", "серебро", "гребля", "погреб", "выгребать", "себе", "себя", "дебаты"
        ]
        
        for word in cleanWords {
            XCTAssertFalse(ProfanityFilter.isProfane(word), "Expected '\(word)' NOT to be flagged as profane")
        }
    }
    
    func testProfaneSentencesAndPhrasesDetected() {
        let profaneSentences = [
            "ты сука",
            "пошел на хуй",
            "это полный пиздец",
            "он ебнулся совсем",
            "да мне вообще похуй",
            "какого хуя ты тут делаешь",
            "ну и блядь ты",
            "ну блять опять ошибка",
            "ну ты и мудак конечно",
            "зачем ты это въебал сюда",
            "это долбоеб какой-то",
            "this is fucking crazy",
            "he is a real asshole",
            "what the fuck are you doing",
            "dont give me this shit"
        ]
        
        for sentence in profaneSentences {
            XCTAssertTrue(ProfanityFilter.containsProfanity(in: sentence), "Expected sentence '\(sentence)' to be detected as profane")
            XCTAssertTrue(ProfanityFilter.isProfane(sentence), "Expected isProfane('\(sentence)') to be true")
        }
    }
    
    func testCleanSentencesNotFlagged() {
        let cleanSentences = [
            "Привет, как дела?",
            "Художник нарисовал красивую картину",
            "Худой человек пошел в магазин",
            "Купи свежий хлеб и молоко",
            "Ребенок играет на площадке",
            "Учеба в университете очень интересная",
            "Я помогу тебе выгребать листья",
            "Он обратил внимание на себя и на свои мысли",
            "У нас на работе сейчас бурные дебаты",
            "Врач осмотрел атеросклеротические бляшки",
            "This cocktail is delicious",
            "The pilot is in the cockpit",
            "Peacock has beautiful feathers",
            "Classic music is relaxing",
            "He works as an assistant",
            "Please bring a glass of water",
            "Please press Shift to switch",
            "I bought a new shirt today"
        ]
        
        for sentence in cleanSentences {
            XCTAssertFalse(ProfanityFilter.containsProfanity(in: sentence), "Expected clean sentence '\(sentence)' NOT to be flagged as profane")
            XCTAssertFalse(ProfanityFilter.isProfane(sentence), "Expected clean sentence '\(sentence)' NOT to be flagged as profane")
        }
    }
}
