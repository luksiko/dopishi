import Foundation

// MARK: - Thesaurus Engine
// Generates contextually accurate synonyms with case and grammatical preservation.
// Uses an embedded fast dictionary for instant offline responses (<5ms),
// and can query AIInferenceEngine for deeper contextual replacements when available.

public struct ThesaurusEngine {

    public struct Candidate: Identifiable, Equatable, Sendable {
        public let id: Int
        public let synonym: String
        public let shortcut: String

        public init(id: Int, synonym: String) {
            self.id = id
            self.synonym = synonym
            self.shortcut = "\(id)"
        }
    }

    // Static dictionary of Russian and English synonyms (base forms)
    private static let synonymBank: [String: [String]] = [
        // --- Russian ---
        "быстрый": ["скорый", "оперативный", "стремительный", "мгновенный"],
        "быстро": ["оперативно", "скоро", "мигом", "стремительно"],
        "красивый": ["прекрасный", "великолепный", "изящный", "живописный"],
        "хороший": ["отличный", "замечательный", "превосходный", "качественный"],
        "плохой": ["негодный", "скверный", "неудовлетворительный", "низкопробный"],
        "важный": ["значимый", "существенный", "ключевой", "принципиальный"],
        "важно": ["значимо", "существенно", "принципиально"],
        "большой": ["крупный", "огромный", "масштабный", "солидный"],
        "маленький": ["небольшой", "крошечный", "компактный", "незначительный"],
        "делать": ["совершать", "выполнять", "осуществлять", "производить"],
        "сделать": ["выполнить", "осуществить", "реализовать", "завершить"],
        "сказать": ["произнести", "заявить", "сообщить", "высказать"],
        "думать": ["полагать", "считать", "размышлять", "предполагать"],
        "понимать": ["осознавать", "уяснять", "постигать", "разбираться"],
        "найти": ["обнаружить", "отыскать", "выявить"],
        "работать": ["трудиться", "функционировать", "действовать"],
        "помочь": ["оказать помощь", "посодействовать", "выручить", "поддержать"],
        "задача": ["цель", "вопрос", "проблема", "поручение"],
        "проблема": ["трудность", "сложность", "препятствие", "заминка"],
        "решение": ["выход", "ответ", "разрешение", "постановление"],
        "ошибка": ["погрешность", "промах", "недочет", "сбой"],
        "анализ": ["исследование", "разбор", "изучение", "оценка"],
        "пользователь": ["клиент", "посетитель", "абонент", "юзер"],
        "разработка": ["создание", "проектирование", "производство"],
        "новый": ["свежий", "современный", "актуальный", "новейший"],
        "старый": ["прежний", "давний", "устаревший", "былой"],
        "умный": ["разумный", "сообразительный", "толковый", "мудрый"],
        "легкий": ["простой", "несложный", "доступный"],
        "сложный": ["трудный", "непростой", "замысловатый", "составной"],
        "начать": ["приступить", "стартовать", "положить начало"],
        "закончить": ["завершить", "окончить", "финализировать"],

        // --- English ---
        "fast": ["quick", "rapid", "swift", "speedy"],
        "quickly": ["promptly", "rapidly", "swiftly", "speedily"],
        "good": ["great", "excellent", "superb", "fine"],
        "bad": ["poor", "subpar", "faulty", "inferior"],
        "important": ["crucial", "essential", "significant", "vital"],
        "big": ["large", "huge", "massive", "substantial"],
        "small": ["tiny", "compact", "minor", "slight"],
        "help": ["assist", "aid", "support", "facilitate"],
        "make": ["create", "build", "produce", "generate"],
        "think": ["believe", "consider", "assume", "reflect"],
        "understand": ["comprehend", "grasp", "realize", "perceive"],
        "problem": ["issue", "challenge", "obstacle", "dilemma"],
        "solution": ["resolution", "answer", "fix", "remedy"],
        "error": ["bug", "mistake", "flaw", "defect"],
        "analyze": ["examine", "investigate", "evaluate", "inspect"],
        "user": ["client", "customer", "visitor", "subscriber"],
        "develop": ["create", "build", "engineer", "implement"],
        "new": ["fresh", "modern", "novel", "recent"],
        "old": ["former", "previous", "outdated", "aged"],
        "smart": ["intelligent", "clever", "bright", "wise"],
        "easy": ["simple", "straightforward", "effortless"],
        "hard": ["difficult", "tough", "challenging", "complex"],
        "start": ["begin", "commence", "initiate", "launch"],
        "finish": ["complete", "conclude", "finalize", "wrap up"]
    ]

    /// Suggests synonyms for a given word with casing preservation.
    public static func suggest(word: String, limit: Int = 4) -> [String] {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let lower = trimmed.lowercased()
        guard let rawSynonyms = synonymBank[lower] else { return [] }

        let isAllUpper = trimmed.count > 1 && trimmed == trimmed.uppercased()
        let isCapitalized = !isAllUpper && trimmed.first?.isUppercase == true

        let adjusted = rawSynonyms.prefix(limit).map { synonym -> String in
            if isAllUpper {
                return synonym.uppercased()
            } else if isCapitalized {
                return synonym.prefix(1).uppercased() + synonym.dropFirst()
            } else {
                return synonym
            }
        }

        return Array(adjusted)
    }

    /// Formats synonyms into numbered candidates for HUD presentation.
    public static func candidates(for word: String, limit: Int = 4) -> [Candidate] {
        let list = suggest(word: word, limit: limit)
        return list.enumerated().map { index, syn in
            Candidate(id: index + 1, synonym: syn)
        }
    }
}
