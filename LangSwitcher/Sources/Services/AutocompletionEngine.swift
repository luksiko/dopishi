import Foundation

// MARK: - Autocompletion Engine
// Generates ranked word completions for partial typing buffers.
// Supports both active-layout completions and cross-layout completions (e.g. "ghbd" -> "привет").

@MainActor
final class AutocompletionEngine {
    
    private let spellCheckService: SpellCheckService
    private let userDictionary: UserDictionary
    
    // Cached word arrays for fast prefix scanning
    private static let englishWords: [String] = {
        WordlistData.english.split(separator: "\n").map(String.init)
    }()
    
    private static let russianWords: [String] = {
        WordlistData.russian.split(separator: "\n").map(String.init)
    }()
    
    private static let ukrainianWords: [String] = {
        WordlistData.ukrainian.split(separator: "\n").map(String.init)
    }()
    
    private static let polishWords: [String] = {
        WordlistData.polish.split(separator: "\n").map(String.init)
    }()
    
    init(
        spellCheckService: SpellCheckService = .shared,
        userDictionary: UserDictionary? = nil
    ) {
        self.spellCheckService = spellCheckService
        self.userDictionary = userDictionary ?? .shared
    }
    
    /// Generate completions for the given partial word.
    func suggest(
        for partialWord: String,
        activeLayoutID: String,
        enabledLayouts: [KeyboardLayout],
        maxSuggestions: Int = 4,
        includeCrossLayout: Bool = true
    ) -> [AutocompletionCandidate] {
        let trimmed = partialWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        
        let lower = trimmed.lowercased()
        let isCapitalized = trimmed.first?.isUppercase == true
        
        var results: [AutocompletionCandidate] = []
        var seenWords = Set<String>()
        
        // Find language code of active layout
        let effectiveActiveLayoutID = activeLayoutID.isEmpty ? (KeyboardLayoutDetector.getCurrentLayout()?.id ?? enabledLayouts.first?.id ?? "com.apple.keylayout.US") : activeLayoutID
        let activeLayout = enabledLayouts.first(where: { $0.id == effectiveActiveLayoutID })
        let activeLang = activeLayout?.languageCode ?? "en"
        
        // 1. Check User Dictionary first (highest priority score: 1000)
        for userWord in userDictionary.words {
            if userWord.lowercased().hasPrefix(lower) && userWord.lowercased() != lower {
                let formatted = formatCase(userWord, isCapitalized: isCapitalized)
                if seenWords.insert(formatted.lowercased()).inserted {
                    results.append(AutocompletionCandidate(
                        word: formatted,
                        targetLayoutID: effectiveActiveLayoutID,
                        isCrossLayout: false,
                        score: 1000
                    ))
                }
            }
        }
        
        // 2. Frequency wordlist prefix matches in active language (score: 500 down to 100)
        let wordlist = wordsForLanguage(activeLang)
        var countFromWordlist = 0
        for (index, word) in wordlist.enumerated() {
            if word.hasPrefix(lower) && word != lower {
                let formatted = formatCase(word, isCapitalized: isCapitalized)
                if seenWords.insert(formatted.lowercased()).inserted {
                    let score = max(100, 500 - index)
                    results.append(AutocompletionCandidate(
                        word: formatted,
                        targetLayoutID: effectiveActiveLayoutID,
                        isCrossLayout: false,
                        score: score
                    ))
                    countFromWordlist += 1
                    if countFromWordlist >= maxSuggestions { break }
                }
            }
        }
        
        // 3. System NSSpellChecker completions for active language
        let systemCompletions = spellCheckService.completions(forPartialWord: lower, language: activeLang)
        for word in systemCompletions {
            let wordLower = word.lowercased()
            if wordLower.hasPrefix(lower) && wordLower != lower {
                let formatted = formatCase(word, isCapitalized: isCapitalized)
                if seenWords.insert(formatted.lowercased()).inserted {
                    results.append(AutocompletionCandidate(
                        word: formatted,
                        targetLayoutID: effectiveActiveLayoutID,
                        isCrossLayout: false,
                        score: 50
                    ))
                }
            }
        }
        
        // 4. Cross-layout completions if enabled
        if includeCrossLayout && enabledLayouts.count >= 2 {
            for otherLayout in enabledLayouts where otherLayout.id != effectiveActiveLayoutID {
                if let converted = LayoutMapper.convert(text: trimmed, from: effectiveActiveLayoutID, to: otherLayout.id) {
                    let convertedLower = converted.lowercased()
                    let otherLang = otherLayout.languageCode
                    
                    // Cross-layout wordlist matches
                    let otherWordlist = wordsForLanguage(otherLang)
                    var countCross = 0
                    for (index, word) in otherWordlist.enumerated() {
                        if word.hasPrefix(convertedLower) {
                            let formatted = formatCase(word, isCapitalized: isCapitalized)
                            if seenWords.insert(formatted.lowercased()).inserted {
                                let score = max(50, 400 - index)
                                results.append(AutocompletionCandidate(
                                    word: formatted,
                                    targetLayoutID: otherLayout.id,
                                    isCrossLayout: true,
                                    score: score
                                ))
                                countCross += 1
                                if countCross >= 3 { break }
                            }
                        }
                    }
                    
                    // Cross-layout NSSpellChecker matches
                    let crossSystem = spellCheckService.completions(forPartialWord: convertedLower, language: otherLang)
                    for word in crossSystem {
                        let wordLower = word.lowercased()
                        if wordLower.hasPrefix(convertedLower) {
                            let formatted = formatCase(word, isCapitalized: isCapitalized)
                            if seenWords.insert(formatted.lowercased()).inserted {
                                results.append(AutocompletionCandidate(
                                    word: formatted,
                                    targetLayoutID: otherLayout.id,
                                    isCrossLayout: true,
                                    score: 40
                                ))
                            }
                        }
                    }
                }
            }
        }
        
        // Sort by score descending, take top N
        results.sort { $0.score > $1.score }
        return Array(results.prefix(maxSuggestions))
    }
    
    private func wordsForLanguage(_ lang: String) -> [String] {
        switch lang.lowercased() {
        case "ru": return Self.russianWords
        case "uk", "ua": return Self.ukrainianWords
        case "pl": return Self.polishWords
        default: return Self.englishWords
        }
    }
    
    private func formatCase(_ word: String, isCapitalized: Bool) -> String {
        guard isCapitalized, !word.isEmpty else { return word }
        return word.prefix(1).uppercased() + word.dropFirst()
    }
}
