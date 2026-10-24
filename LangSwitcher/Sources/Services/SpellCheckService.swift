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
        "tg": "tg",
        "kk": "kk",
        "be": "be",
        "pl": "pl",
        "it": "it",
        "tr": "tr",
    ]

    // NSSpellChecker omits some ordinary application terminology and its
    // inflections. Keep the fallback finite: an arbitrary Cyrillic string is
    // never sufficient evidence for automatic replacement.
    private static let russianApplicationWords: Set<String> = Set("""
        раскладка раскладки раскладке раскладку раскладкой раскладок раскладкам раскладками раскладках
        автосмена автосмены автосмене автосмену автосменой
        автозамена автозамены автозамене автозамену автозаменой
        автодополнение автодополнения автодополнению автодополнением автодополнении
        автоисправление автоисправления автоисправлению автоисправлением автоисправлении
        автопереключение автопереключения автопереключению автопереключением
        шорткат шорткаты шортката шорткатов шорткату шорткатом шорткатах
        хоткей хоткеи хоткея хоткеев хоткею хоткеем хоткеях
        клавиатура клавиатуры клавиатуре клавиатуру клавиатурой клавиатур клавиатурам клавиатурами клавиатурах
        клавиатурный клавиатурная клавиатурное клавиатурные клавиатурного клавиатурной
        бэкап бэкапы бэкапа бэкапов
        логин логины логина логинов
        скриншот скриншоты скриншота скриншотов
        репозиторий репозитория репозитории репозиториев
        """.split(whereSeparator: { $0.isWhitespace }).map(String.init))

    private static let russianCompoundPrefixes: [String] = [
        "авто", "видео", "аудио", "онлайн", "кибер", "микро", "макро", "мега", "мини", "мульти", "псевдо", "супер", "гипер", "экстра", "ультра", "эко"
    ]

    private init() {}

    /// Normalize language codes (e.g., "en-US", "en_GB", "ru-RU") to base language codes
    func normalizeLanguage(_ language: String) -> String {
        let base = language.components(separatedBy: CharacterSet(charactersIn: "-_")).first?.lowercased() ?? language.lowercased()
        return languageMap[base] ?? language
    }

    /// Verify that the characters in the word belong to the expected script for the language.
    /// NSSpellChecker returns NSNotFound (no error) when given words in an unrelated script
    /// (e.g. Cyrillic in English), which falsely marks wrong-layout words as valid.
    func matchesExpectedScript(word: String, language: String) -> Bool {
        let letters = word.filter { $0.isLetter }
        guard !letters.isEmpty else { return false }
        
        let lang = normalizeLanguage(language)
        switch lang {
        case "ru", "uk", "ua", "tg", "kk", "be", "ky", "bg", "sr", "mk":
            // Cyrillic script: Unicode ranges U+0400...U+052F
            return letters.allSatisfy { char in
                char.unicodeScalars.allSatisfy { scalar in
                    (0x0400...0x052F).contains(scalar.value)
                }
            }
        default:
            // Latin script: Unicode ranges basic Latin + Latin Supplement + Extended
            return letters.allSatisfy { char in
                char.unicodeScalars.allSatisfy { scalar in
                    (0x0041...0x005A).contains(scalar.value) ||
                    (0x0061...0x007A).contains(scalar.value) ||
                    (0x00C0...0x024F).contains(scalar.value)
                }
            }
        }
    }

    /// Check whether a word is correctly spelled in a given language.
    /// Returns true if the word is recognized (no misspelling found).
    func isValidWord(_ word: String, language: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lang = normalizeLanguage(language)
        guard matchesExpectedScript(word: trimmed, language: lang) else {
            return false
        }

        let lower = trimmed.lowercased()
        if lang == "ru" && Self.russianApplicationWords.contains(lower) {
            return true
        }

        // 1. Check custom installed Hunspell dictionaries (e.g. tg, kk, be)
        if CustomDictionaryStore.shared.hasDictionary(for: lang) {
            let valid = CustomDictionaryStore.shared.isValidWord(trimmed, language: lang)
            NSLog("[LangSwitcher] SpellCheckService.isValidWord (custom)('\(trimmed)', lang='\(lang)') = \(valid)")
            return valid
        }

        // Support compound words with common prefixes (e.g. автосмены -> авто + смены)
        if (lang == "ru" || lang == "uk") {
            for prefix in Self.russianCompoundPrefixes {
                if lower.hasPrefix(prefix) && lower.count >= prefix.count + 3 {
                    let remainder = String(lower.dropFirst(prefix.count))
                    let remRange = checker.checkSpelling(
                        of: remainder,
                        startingAt: 0,
                        language: lang,
                        wrap: false,
                        inSpellDocumentWithTag: 0,
                        wordCount: nil
                    )
                    if remRange.location == NSNotFound || (lang == "ru" && Self.russianApplicationWords.contains(remainder)) {
                        return true
                    }
                }
            }
        }

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
        var completions = checker.completions(
            forPartialWordRange: NSRange(location: 0, length: (word as NSString).length),
            in: word,
            language: lang,
            inSpellDocumentWithTag: 0
        )
        if (completions == nil || completions?.isEmpty == true) {
            let prefix = lang + "_"
            for available in checker.availableLanguages {
                if available.hasPrefix(prefix) {
                    if let fallback = checker.completions(
                        forPartialWordRange: NSRange(location: 0, length: (word as NSString).length),
                        in: word,
                        language: available,
                        inSpellDocumentWithTag: 0
                    ), !fallback.isEmpty {
                        return fallback
                    }
                }
            }
        }
        return completions ?? []
    }

    /// Get spelling correction guesses for a misspelled word.
    func guesses(forWord word: String, language: String) -> [String] {
        let lang = normalizeLanguage(language)
        let nsRange = NSRange(location: 0, length: (word as NSString).length)
        if let result = checker.guesses(forWordRange: nsRange, in: word, language: lang, inSpellDocumentWithTag: 0), !result.isEmpty {
            return result
        }
        let prefix = lang + "_"
        for available in checker.availableLanguages where available.hasPrefix(prefix) {
            if let fallback = checker.guesses(forWordRange: nsRange, in: word, language: available, inSpellDocumentWithTag: 0), !fallback.isEmpty {
                return fallback
            }
        }
        return []
    }
}
