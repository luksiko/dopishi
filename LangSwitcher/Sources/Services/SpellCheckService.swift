import Foundation
import AppKit

// MARK: - Spell Check Service
// Wrapper around NSSpellChecker for validating words in specific languages.
// Used to reduce false positives in auto-correction: only correct wrong-layout
// words if the converted result is a valid word in the target language.

final class SpellCheckService {

    static let shared = SpellCheckService()

    private let checker = NSSpellChecker.shared

    /// Map from layout language codes to NSSpellChecker language identifiers.
    /// NSSpellChecker uses BCP 47 / ISO codes.
    private let languageMap: [String: String] = [
        "en": "en",
        "ru": "ru",
        "uk": "uk",
        "ua": "uk",
        "de": "de",
        "fr": "fr",
        "es": "es",
    ]

    private init() {}

    /// Normalize language codes (e.g., "en-US", "en_GB", "ru-RU") to base language codes
    func normalizeLanguage(_ language: String) -> String {
        let base = language.components(separatedBy: CharacterSet(charactersIn: "-_")).first?.lowercased() ?? language.lowercased()
        return languageMap[base] ?? language
    }

    /// Check whether a word is correctly spelled in a given language.
    /// Returns true if the word is recognized (no misspelling found).
    func isValidWord(_ word: String, language: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lang = normalizeLanguage(language)
        let range = checker.checkSpelling(
            of: trimmed,
            startingAt: 0,
            language: lang,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )

        // If range.location == NSNotFound, no misspelling was found → word is valid
        let valid = range.location == NSNotFound
        NSLog("[LangSwitcher] SpellCheckService.isValidWord('\(trimmed)', lang='\(lang)') = \(valid)")
        return valid
    }

    /// Check whether a word is valid in ANY of the provided languages.
    func isValidWordInAnyLanguage(_ word: String, languages: [String]) -> Bool {
        for lang in languages {
            if isValidWord(word, language: lang) {
                return true
            }
        }
        return false
    }

    /// Get spelling completions for a partial word.
    func completions(forPartialWord word: String, language: String) -> [String] {
        let lang = normalizeLanguage(language)
        let completions = checker.completions(
            forPartialWordRange: NSRange(location: 0, length: (word as NSString).length),
            in: word,
            language: lang,
            inSpellDocumentWithTag: 0
        )
        return completions ?? []
    }
}
