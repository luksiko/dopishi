import Foundation

// MARK: - Autocompletion Adaptive Store
// Persists and tracks user word selection frequencies and contextual bigrams.
// Integrates with AutocompletionEngine to boost words the user uses often,
// and suggest natural continuations based on the previous word.

@MainActor
final class AutocompletionAdaptiveStore: ObservableObject {
    
    static let shared = AutocompletionAdaptiveStore()
    
    // In-memory frequency map: lowercased word -> selection count
    @Published private(set) var wordFrequencies: [String: Int] = [:]
    
    // In-memory bigrams map: lowercased previousWord -> [lowercased nextWord : count]
    @Published private(set) var bigramFrequencies: [String: [String: Int]] = [:]
    
    // Limits to prevent unbounded dictionary growth in UserDefaults
    static let maxTrackedWords = 2000
    static let maxTrackedBigramHeads = 1000
    
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let wordFrequencies = "autocompletion_adaptive_word_freq"
        static let bigrams = "autocompletion_adaptive_bigrams"
    }
    
    // Built-in high-frequency bigram pairs (Russian & English)
    static let defaultBigrams: [String: [String]] = [
        // Russian
        "добрый": ["день", "вечер", "утро"],
        "доброе": ["утро"],
        "доброй": ["ночи"],
        "большое": ["спасибо"],
        "огромное": ["спасибо"],
        "с": ["уважением", "новым", "днем", "праздником", "точки"],
        "как": ["дела", "поживаешь", "всегда", "правило"],
        "обратите": ["внимание"],
        "обратить": ["внимание"],
        "в": ["том", "течение", "свою", "любом", "случае", "первую", "очередь"],
        "по": ["поводу", "умолчанию", "крайней", "мере", "причине"],
        "на": ["самом", "деле", "мой", "взгляд"],
        "все": ["равно", "хорошо", "будет"],
        "всего": ["доброго", "хорошего"],
        "до": ["свидания", "встречи", "скорого"],
        "исходный": ["код"],
        "база": ["данных"],
        "учетная": ["запись"],
        "операционная": ["система"],
        "техническая": ["поддержка"],
        
        // English
        "pull": ["request", "requests"],
        "good": ["morning", "afternoon", "evening", "luck", "job"],
        "thank": ["you"],
        "thanks": ["for", "a", "lot"],
        "let": ["me", "us", "know"],
        "look": ["forward", "at"],
        "looking": ["forward"],
        "best": ["regards", "wishes", "practices"],
        "git": ["status", "commit", "push", "pull", "checkout", "branch"],
        "as": ["well", "soon", "long", "always"],
        "in": ["order", "case", "terms", "general"],
        "on": ["the", "other", "behalf"],
        "at": ["the", "same", "least"],
        "make": ["sure", "sense"],
        "take": ["care", "a", "look"],
        "have": ["a", "been", "done"],
        "please": ["find", "let", "note", "check"]
    ]
    
    private init() {
        loadData()
    }
    
    // MARK: - Learning & Recording
    
    /// Records a word usage, optionally linked to the immediately preceding word.
    func recordWordUsage(word: String, after previousWord: String? = nil) {
        let cleanWord = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanWord.isEmpty else { return }
        
        // 1. Update personal word frequency
        wordFrequencies[cleanWord, default: 0] += 1
        
        // 2. Update bigram frequency if previous word exists
        if let prev = previousWord?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !prev.isEmpty {
            var nextMap = bigramFrequencies[prev] ?? [:]
            nextMap[cleanWord, default: 0] += 1
            bigramFrequencies[prev] = nextMap
        }
        
        pruneIfNeeded()
        saveData()
    }
    
    // Prune least frequent entries when capacity limits are exceeded
    func pruneIfNeeded() {
        if wordFrequencies.count > Self.maxTrackedWords {
            let targetCount = Self.maxTrackedWords * 3 / 4
            let sorted = wordFrequencies.sorted { $0.value > $1.value }
            wordFrequencies = Dictionary(uniqueKeysWithValues: sorted.prefix(targetCount).map { ($0.key, $0.value) })
        }
        
        if bigramFrequencies.count > Self.maxTrackedBigramHeads {
            let targetCount = Self.maxTrackedBigramHeads * 3 / 4
            let sorted = bigramFrequencies.sorted { lhs, rhs in
                let sumL = lhs.value.values.reduce(0, +)
                let sumR = rhs.value.values.reduce(0, +)
                return sumL > sumR
            }
            bigramFrequencies = Dictionary(uniqueKeysWithValues: sorted.prefix(targetCount).map { ($0.key, $0.value) })
        }
    }
    
    // MARK: - Scoring & Continuations
    
    /// Returns adaptive score boost (0 ... 1500) based on user frequency.
    func frequencyScore(for word: String) -> Int {
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let count = wordFrequencies[clean] ?? 0
        guard count > 0 else { return 0 }
        return min(1500, count * 200)
    }
    
    /// Returns bigram bonus (0 ... 1200) if the candidate naturally follows previousWord.
    func bigramBonus(for word: String, after previousWord: String?) -> Int {
        guard let prev = previousWord?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !prev.isEmpty else {
            return 0
        }
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // 1. Check user learned bigrams first (highest weight)
        if let userNextMap = bigramFrequencies[prev], let userCount = userNextMap[clean], userCount > 0 {
            return min(1200, 600 + userCount * 150)
        }
        
        // 2. Check built-in common bigrams
        if let builtIn = Self.defaultBigrams[prev], builtIn.contains(clean) {
            return 800
        }
        
        return 0
    }
    
    /// Top next-word continuations following `previousWord`.
    func topContinuations(after previousWord: String, limit: Int = 3) -> [String] {
        let prev = previousWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !prev.isEmpty else { return [] }
        
        var candidates: [String] = []
        var seen = Set<String>()
        
        // User learned bigrams first, sorted by count descending
        if let userNextMap = bigramFrequencies[prev] {
            let sorted = userNextMap.sorted { $0.value > $1.value }
            for (w, _) in sorted {
                if seen.insert(w).inserted {
                    candidates.append(w)
                    if candidates.count >= limit { return candidates }
                }
            }
        }
        
        // Default built-in bigrams next
        if let builtIn = Self.defaultBigrams[prev] {
            for w in builtIn {
                if seen.insert(w).inserted {
                    candidates.append(w)
                    if candidates.count >= limit { return candidates }
                }
            }
        }
        
        return candidates
    }
    
    // MARK: - Reset
    
    func clearAll() {
        wordFrequencies.removeAll()
        bigramFrequencies.removeAll()
        defaults.removeObject(forKey: Keys.wordFrequencies)
        defaults.removeObject(forKey: Keys.bigrams)
    }
    
    // MARK: - Persistence
    
    private func loadData() {
        if let storedFreq = defaults.dictionary(forKey: Keys.wordFrequencies) as? [String: Int] {
            self.wordFrequencies = storedFreq
        }
        if let storedBigrams = defaults.dictionary(forKey: Keys.bigrams) as? [String: [String: Int]] {
            self.bigramFrequencies = storedBigrams
        }
    }
    
    private func saveData() {
        defaults.set(wordFrequencies, forKey: Keys.wordFrequencies)
        defaults.set(bigramFrequencies, forKey: Keys.bigrams)
    }
}
