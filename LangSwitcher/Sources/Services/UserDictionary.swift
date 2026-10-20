import Foundation

// MARK: - User Dictionary
//
// The user's personal dictionary: words the user has told us are intentional.
// Two writers:
//
// 1. Undo — when a Thought Recovery is reverted (the reconstruction was
//    wrong), the original spans are learned here, so the same text is never
//    rewritten again. This is the "undo teaches the local dictionary" loop
//    from the upstream idea doc (langswitcher-linux
//    docs/ideas/thought-recovery.md): the decoder abstains on learned words
//    (their score is above every dictionary hit), and the wrong-layout veto
//    in TextConverter.looksLikeWrongLayout refuses them too, so the teaching
//    also protects the Space auto-correction flow.
// 2. Manual additions (settings UI / future).
//
// Stored as an ordered array in UserDefaults so the newest entries can be
// dropped when the cap is reached; a Set index keeps lookups O(1).

@MainActor
final class UserDictionary: ObservableObject {

    static let shared = UserDictionary()

    /// Words the user marked as intentional. Lowercased.
    @Published private(set) var words: Set<String>

    /// Insertion order (oldest first) so learning cannot grow without bound.
    private var order: [String]

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let words = "userDictionaryWords"
    }

    /// Keep the dictionary small enough to stay a signal, not a corpus.
    static let maxWords = 5000

    private init() {
        let stored = defaults.stringArray(forKey: Keys.words) ?? []
        self.order = stored
        self.words = Set(stored)
    }

    // MARK: - Lookup

    /// True when the user has taught us this word is intentional.
    func contains(_ word: String) -> Bool {
        words.contains(Self.normalize(word))
    }

    /// True when any alphabetic token of `text` is a learned word.
    func containsAny(in text: String) -> Bool {
        Self.tokens(in: text).contains { words.contains($0) }
    }

    // MARK: - Learning

    /// Learn a single word. Ignores non-word input.
    @discardableResult
    func learn(_ word: String) -> Bool {
        let normalized = Self.normalize(word)
        guard normalized.count >= 2, normalized.contains(where: \.isLetter) else { return false }
        guard !words.contains(normalized) else { return false }
        words.insert(normalized)
        order.append(normalized)
        trim()
        persist()
        return true
    }

    /// Learn every word of `text` — used when the user reverts a recovery so
    /// the original spans are never touched again. Returns the number of new
    /// words.
    @discardableResult
    func learnWords(in text: String) -> Int {
        var learnedCount = 0
        for token in Self.tokens(in: text) where learn(token) {
            learnedCount += 1
        }
        return learnedCount
    }

    /// Forget a word (settings UI).
    func forget(_ word: String) {
        let normalized = Self.normalize(word)
        guard words.remove(normalized) != nil else { return }
        order.removeAll { $0 == normalized }
        persist()
    }

    func removeAll() {
        guard !words.isEmpty else { return }
        words.removeAll()
        order.removeAll()
        persist()
    }

    // MARK: - Internals

    private func trim() {
        guard order.count > Self.maxWords else { return }
        let excess = order.count - Self.maxWords
        let dropped = order.prefix(excess)
        for word in dropped { words.remove(word) }
        order.removeFirst(excess)
    }

    private func persist() {
        defaults.set(order, forKey: Keys.words)
    }

    /// Lowercased word form. Only the letters matter for the decision, but
    /// keeping apostrophes matches the wordlist tokenizer ("з'їсти").
    private static func normalize(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Alphabetic tokens (≥2 letters), lowercased.
    private static func tokens(in text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && $0 != "'" }
            .map(String.init)
            .filter { $0.count >= 2 && $0.contains(where: \.isLetter) }
    }
}
