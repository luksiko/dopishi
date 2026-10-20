import Foundation

// MARK: - Language Wordlists
//
// Dictionary evidence for wrong-layout decisions, built on the embedded
// frequency lists in WordlistData. Two jobs:
//
// 1. VETO — if text is already a real word/phrase in ANY supported
//    dictionary language, converting it would garble real words.
//    looksLikeWrongLayout must refuse. Veto is script-based, not
//    layout-based: Latin text is checked against the Polish AND English
//    lists, Cyrillic text against the Ukrainian AND Russian lists. This
//    is what lets the automatic Space flow be ON by default: typing
//    "cześć", "hello", "привіт" or "привет" correctly is always safe,
//    regardless of which layout pair is enabled.
// 2. CONFIRM — if a conversion result is real language, strengthen the
//    script-switch signal. Absence of a word in the lists is weak
//    evidence and never blocks.
//
// Lists are frequency-ranked tops filtered against hunspell dictionaries
// (see WordlistData header + scripts/generate-wordlists.py), so
// wrong-layout gibberish ("ghbdtn", "руддщ", "сяуы") is never a member.

@MainActor
enum LanguageWordlists {

    // MARK: - Data (lazily parsed once)

    private static let polishWords: Set<String> = {
        Set(WordlistData.polish.split(separator: "\n").map(String.init))
    }()

    private static let ukrainianWords: Set<String> = {
        Set(WordlistData.ukrainian.split(separator: "\n").map(String.init))
    }()

    private static let englishWords: Set<String> = {
        Set(WordlistData.english.split(separator: "\n").map(String.init))
    }()

    private static let russianWords: Set<String> = {
        Set(WordlistData.russian.split(separator: "\n").map(String.init))
    }()

    // MARK: - Public API

    /// Coverage = share of the text's alphabetic tokens found in `list`.
    /// Single-token words: 1.0 when found, 0.0 when not.
    static func coverage(of text: String, in list: Set<String>) -> Double {
        let tokens = text.lowercased()
            .split { !$0.isLetter && $0 != "'" }
        guard !tokens.isEmpty else { return 0 }
        let hits = tokens.filter { list.contains(String($0)) }.count
        return Double(hits) / Double(tokens.count)
    }

    /// Which of the supported dictionary languages does this text belong to,
    /// and how strongly? Uses per-word coverage; single-token texts score
    /// either 1.0 (hit) or 0.0 (miss) — that's the correct behavior for the
    /// one-word selections this app handles.
    static func bestMatch(for text: String) -> (language: Language, coverage: Double)? {
        var best: (Language, Double)?
        for language in Language.allCases {
            let cov = coverage(of: text, in: words(for: language))
            if cov > 0, best == nil || cov > best!.1 {
                best = (language, cov)
            }
        }
        return best
    }

    /// Should conversion of this text be vetoed because it is already real
    /// language (Polish, Ukrainian, English, or Russian)?
    ///
    /// The candidate script must be unambiguous, and the text must be fully
    /// covered by the union of dictionary lists for that script:
    /// - Latin text → Polish ∪ English
    /// - Cyrillic text → Ukrainian ∪ Russian
    ///
    /// Single words additionally require ≥4 letters: 1–3-letter words are
    /// too ambiguous ("to"/"nie" in Latin, "не"/"на" in Cyrillic), but a
    /// single ≥4-letter dictionary hit is decisive — the auto flow has no
    /// user hotkey press to vouch for intent, so the dictionary veto is
    /// the only protection against garbling "cześć"/"hello"/"привіт".
    static func shouldVeto(text: String) -> Bool {
        let tokens = tokenize(text)
        guard let script = script(of: text), let lists = lists(for: script) else {
            return false
        }

        if tokens.count == 1 {
            let word = tokens[0]
            guard word.count >= 4 else { return false }
            return lists.contains { $0.contains(word) }
        }

        guard tokens.count >= 2 else { return false }
        return coverage(of: text, in: union(lists)) >= 1.0
    }

    /// Does this converted result look like real language in any supported
    /// dictionary? Used to CONFIRM a conversion: at least one alphabetic
    /// token that is a dictionary word in the result's script.
    static func confirmsConversion(_ text: String) -> Bool {
        let tokens = tokenize(text)
        guard !tokens.isEmpty, let script = script(of: text), let lists = lists(for: script) else {
            return false
        }
        let combined = union(lists)
        return tokens.contains { combined.contains($0) }
    }

    // MARK: - Per-word evidence (Thought Recovery)

    /// Is `word` a dictionary word of `language`? Case-insensitive.
    /// Single-word evidence for the span-level decoder: a dictionary hit is
    /// the strongest signal available without an LLM, so it must be
    /// queryable per language (not just as a script union).
    static func isDictionaryWord(_ word: String, language: Language) -> Bool {
        let normalized = word.lowercased()
        guard !normalized.isEmpty else { return false }
        return words(for: language).contains(normalized)
    }

    /// Dictionary words of `language`, most frequent first (the embedded
    /// lists are frequency-ranked). Used to train the character n-gram
    /// tables of the span-level decoder.
    static func topWords(_ language: Language, limit: Int) -> [String] {
        if let cached = topWordCache[language], cached.count >= limit {
            return Array(cached.prefix(limit))
        }
        let all = topWordList(for: language)
        topWordCache[language] = all
        return Array(all.prefix(limit))
    }

    /// Languages that write with a given script, in tie-break order.
    static func languages(writing script: String) -> [Language] {
        script == "latin" ? [.polish, .english] : [.ukrainian, .russian]
    }

    /// "latin" / "cyrillic" / nil for mixed or letter-less text.
    /// Uses the same Unicode-block classification as the veto path.
    static func writingScript(of text: String) -> String? {
        switch script(of: text) {
        case .latin: return "latin"
        case .cyrillic: return "cyrillic"
        case nil: return nil
        }
    }

    private static var topWordCache: [Language: [String]] = [:]

    private static func topWordList(for language: Language) -> [String] {
        let raw: String
        switch language {
        case .polish: raw = WordlistData.polish
        case .ukrainian: raw = WordlistData.ukrainian
        case .english: raw = WordlistData.english
        case .russian: raw = WordlistData.russian
        }
        return raw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    // MARK: - Internals

    enum Language: CaseIterable {
        case polish
        case ukrainian
        case english
        case russian
    }

    /// Writing system of a text, based on its letters. Mixed-script text
    /// (conversion targets are single-script by construction, but stay
    /// defensive) yields nil — no veto, no confirm.
    private enum Script {
        case latin
        case cyrillic
    }

    private static func script(of text: String) -> Script? {
        let hasLatin = text.contains { $0.isLetter && isLatinScript($0) }
        let hasCyrillic = text.contains { $0.isLetter && !isLatinScript($0) }
        if hasLatin && !hasCyrillic { return .latin }
        if hasCyrillic && !hasLatin { return .cyrillic }
        return nil
    }

    private static func union(_ sets: [Set<String>]) -> Set<String> {
        var result: Set<String> = []
        for set in sets { result.formUnion(set) }
        return result
    }

    /// Dictionary lists for a writing system. Latin covers both Polish and
    /// English (they share the alphabet); Cyrillic covers Ukrainian and
    /// Russian. A word in ANY of the script's languages is real language —
    /// converting it would garble the user's correct text.
    private static func lists(for script: Script) -> [Set<String>]? {
        switch script {
        case .latin: return [polishWords, englishWords]
        case .cyrillic: return [ukrainianWords, russianWords]
        }
    }

    private static func words(for language: Language) -> Set<String> {
        switch language {
        case .polish: return polishWords
        case .ukrainian: return ukrainianWords
        case .english: return englishWords
        case .russian: return russianWords
        }
    }

    /// Lowercased alphabetic tokens (apostrophes kept inside words:
    /// Ukrainian "з'їсти", don't → split punctuation aside).
    private static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && $0 != "'" }
            .map(String.init)
            .filter { $0.contains(where: \.isLetter) }
    }

    /// Same classification as TextConverter.looksLikeWrongLayout:
    /// letters in the Latin Unicode blocks are Latin, all other letters
    /// (Cyrillic etc.) are non-Latin.
    private static func isLatinScript(_ c: Character) -> Bool {
        c.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x300...0x36F,                     // combining marks
                 0x41...0x5A, 0x61...0x7A,          // A–Z a–z
                 0xC0...0xFF,                       // Latin-1 Supplement
                 0x100...0x24F,                     // Latin Extended-A/B
                 0x1E00...0x1EFF:                   // Latin Extended Additional
                return true
            default:
                return false
            }
        }
    }
}
