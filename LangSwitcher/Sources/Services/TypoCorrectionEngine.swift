import Foundation

// MARK: - Typo Correction Engine
// Detects and corrects single-edit mechanical typing errors on the fly within the same keyboard layout:
//   1. Adjacent letter transpositions (e.g. "привте" → "привет", "тчо" → "что", "hte" → "the")
//   2. Accidental extra characters / fat-finger keys (e.g. "большоей" → "большой", "поставитьл" → "поставить")
//   3. Single missing letters (e.g. "больой" → "большой", "исправлось" → "исправилось")
//   4. Single physically adjacent key substitutions (e.g. "привкт" → "привет")

@MainActor
struct TypoCorrectionEngine {

    // MARK: - Physical Keyboard Layouts (Row, Col)

    private static let russianRows: [[Character]] = [
        ["й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х", "ъ"],
        ["ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э"],
        ["я", "ч", "с", "м", "и", "т", "ь", "б", "ю"]
    ]

    private static let englishRows: [[Character]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"]
    ]

    private static let russianAlphabet: [Character] = Array("абвгдежзийклмнопрстуфхцчшщъыьэюя")
    private static let englishAlphabet: [Character] = Array("abcdefghijklmnopqrstuvwxyz")

    private static let keyCoordinates: [Character: (row: Int, col: Int)] = {
        var map: [Character: (Int, Int)] = [:]
        for (r, row) in russianRows.enumerated() {
            for (c, ch) in row.enumerated() {
                map[ch] = (r, c)
            }
        }
        for (r, row) in englishRows.enumerated() {
            for (c, ch) in row.enumerated() {
                map[ch] = (r, c)
            }
        }
        return map
    }()

    private static let keyNeighborsMap: [Character: [Character]] = {
        var result: [Character: [Character]] = [:]
        let groups = [russianRows, englishRows]
        for rows in groups {
            for (r1, row1) in rows.enumerated() {
                for (c1, ch1) in row1.enumerated() {
                    var neighbors: [Character] = []
                    for (r2, row2) in rows.enumerated() where abs(r1 - r2) <= 1 {
                        for (c2, ch2) in row2.enumerated() where abs(c1 - c2) <= 1 {
                            if r1 != r2 || c1 != c2 {
                                neighbors.append(ch2)
                            }
                        }
                    }
                    result[ch1] = neighbors
                }
            }
        }
        return result
    }()

    /// Returns true if two characters are on physically adjacent keys (including diagonals).
    static func areKeysAdjacent(_ a: Character, _ b: Character) -> Bool {
        guard let lowerA = a.lowercased().first,
              let lowerB = b.lowercased().first,
              let coordA = keyCoordinates[lowerA],
              let coordB = keyCoordinates[lowerB] else {
            return false
        }
        let dr = abs(coordA.row - coordB.row)
        let dc = abs(coordA.col - coordB.col)
        return dr <= 1 && dc <= 1 && (dr != 0 || dc != 0)
    }

    // MARK: - Main Entry Point

    /// Attempts to correct a misspelled word typed in the active script.
    /// Returns the corrected word preserving initial capitalization, or `nil` if the word is already valid
    /// or no high-confidence single-edit correction exists.
    static func correctTypo(
        _ word: String,
        languages: [String] = ["ru", "en"],
        spellCheckService: SpellCheckService = .shared
    ) -> String? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let chars = Array(trimmed)
        let n = chars.count
        guard n >= 3, n <= 24 else { return nil }
        guard chars.allSatisfy(\.isLetter) else { return nil }

        // Skip ALL-CAPS acronyms (e.g. "API", "СССР") or internal camelCase (e.g. "macOS", "iPhone")
        if chars.allSatisfy(\.isUppercase) { return nil }
        if chars.dropFirst().contains(where: \.isUppercase) { return nil }

        guard let script = LanguageWordlists.writingScript(of: trimmed) else { return nil }
        let isCyrillic = (script == "cyrillic")
        let lowerWord = trimmed.lowercased()
        let lowerChars = Array(lowerWord)

        let targetLangs: [String] = isCyrillic
            ? (languages.filter { ["ru", "uk", "ua"].contains($0.lowercased()) }.isEmpty ? ["ru"] : languages.filter { ["ru", "uk", "ua"].contains($0.lowercased()) })
            : (languages.filter { !["ru", "uk", "ua"].contains($0.lowercased()) }.isEmpty ? ["en"] : languages.filter { !["ru", "uk", "ua"].contains($0.lowercased()) })

        // 0. Veto: never modify a word that is already valid in wordlists, user dictionary, or spellchecker
        if LanguageWordlists.contains(word: lowerWord) { return nil }
        if UserDictionary.shared.contains(lowerWord) { return nil }
        if spellCheckService.isValidWordInAnyLanguage(lowerWord, languages: targetLangs) { return nil }

        var bestCandidate: String?
        var bestScore: Int = 0

        func consider(_ candidate: String, baseScore: Int) {
            guard candidate != lowerWord else { return }
            var score = baseScore
            if let rank = LanguageWordlists.frequencyRank(of: candidate) {
                score += 55 + max(0, 30 - rank / 1000)
            }
            if score > bestScore {
                bestScore = score
                bestCandidate = candidate
            }
        }

        // 1. Adjacent Transposition: swap(i, i+1) — e.g. "привте" → "привет", "тчо" → "что"
        for i in 0..<(n - 1) where lowerChars[i] != lowerChars[i + 1] {
            var swapped = lowerChars
            swapped.swapAt(i, i + 1)
            let candidate = String(swapped)
            if n == 3 {
                // For 3-letter words, require high-frequency wordlist presence
                if let rank = LanguageWordlists.frequencyRank(of: candidate), rank < 5000 {
                    consider(candidate, baseScore: 120)
                }
            } else {
                let inWordlist = LanguageWordlists.contains(word: candidate)
                let inSpell = inWordlist || spellCheckService.isValidWordInAnyLanguage(candidate, languages: targetLangs)
                if inSpell {
                    consider(candidate, baseScore: 120)
                }
            }
        }

        // 2. Extra Character Deletion: delete(i) — e.g. "большоей" → "большой", "поставитьл" → "поставить"
        if n >= 4 {
            var seenDeletions = Set<String>()
            for i in 0..<n {
                let removedChar = lowerChars[i]
                let isDuplicate = (i > 0 && lowerChars[i - 1] == removedChar) || (i + 1 < n && lowerChars[i + 1] == removedChar)
                let isAdjacentKey = (i > 0 && areKeysAdjacent(removedChar, lowerChars[i - 1]))
                    || (i + 1 < n && areKeysAdjacent(removedChar, lowerChars[i + 1]))
                let isNearEnd = (i >= n - 2)

                // For 4-letter words, only delete duplicate letters or adjacent trailing fat-finger
                if n == 4 && !isDuplicate && !(isAdjacentKey && i == n - 1) {
                    continue
                }

                var shortened = lowerChars
                shortened.remove(at: i)
                let candidate = String(shortened)
                guard seenDeletions.insert(candidate).inserted else { continue }

                let inWordlist = LanguageWordlists.contains(word: candidate)
                let inSpell = inWordlist || (n >= 5 && (isDuplicate || isAdjacentKey || isNearEnd) && spellCheckService.isValidWordInAnyLanguage(candidate, languages: targetLangs))

                guard inSpell else { continue }
                if n == 4 {
                    guard let rank = LanguageWordlists.frequencyRank(of: candidate), rank < 3000 else { continue }
                }

                var score = 85
                if isDuplicate { score += 30 }
                if isAdjacentKey { score += 25 }
                if isNearEnd { score += 12 }
                consider(candidate, baseScore: score)
            }
        }

        // 3. Single Physically-Adjacent Key Substitution: substitute(i, neighbor) — e.g. "привкт" → "привет"
        if n >= 4 {
            for i in 0..<n {
                guard let neighbors = keyNeighborsMap[lowerChars[i]] else { continue }
                for neighbor in neighbors {
                    var modified = lowerChars
                    modified[i] = neighbor
                    let candidate = String(modified)
                    if LanguageWordlists.contains(word: candidate) {
                        if n == 4 {
                            guard let rank = LanguageWordlists.frequencyRank(of: candidate), rank < 3000 else { continue }
                        }
                        consider(candidate, baseScore: 75)
                    }
                }
            }
        }

        // 4. Single Missing Character Insertion: insert(i, letter) — e.g. "больой" → "большой", "исправлось" → "исправилось"
        if n >= 5 {
            let alphabet = isCyrillic ? russianAlphabet : englishAlphabet
            // 4a. Fast in-memory check against LanguageWordlists
            for i in 1...n {
                var buffer = Array(repeating: Character(" "), count: n + 1)
                for k in 0..<i { buffer[k] = lowerChars[k] }
                for k in i..<n { buffer[k + 1] = lowerChars[k] }

                for letter in alphabet {
                    buffer[i] = letter
                    let candidate = String(buffer)
                    if LanguageWordlists.contains(word: candidate) {
                        consider(candidate, baseScore: 70)
                    }
                }
            }

            // 4b. Common Russian verb/reflexive suffix missing vowel (e.g. "исправлось" → "исправилось")
            if isCyrillic && bestScore < 120 {
                let suffixes = ["лось", "лся", "лась", "лись", "ться"]
                let vowels: [Character] = ["и", "а", "е", "о", "я", "у", "ы"]
                for suffix in suffixes where lowerWord.hasSuffix(suffix) && n > suffix.count + 2 {
                    let insertIdx = n - suffix.count
                    for v in vowels {
                        var charsCopy = lowerChars
                        charsCopy.insert(v, at: insertIdx)
                        let candidate = String(charsCopy)
                        if spellCheckService.isValidWordInAnyLanguage(candidate, languages: targetLangs) {
                            consider(candidate, baseScore: 110)
                        }
                    }
                }
            }

            // 4c. NSSpellChecker guesses filtered strictly to 1-character insertion
            if bestScore < 120 {
                for lang in targetLangs {
                    let guesses = spellCheckService.guesses(forWord: lowerWord, language: lang)
                    for guess in guesses.prefix(5) {
                        let lowerGuess = guess.lowercased()
                        if isSingleInsertion(shorter: lowerChars, longer: Array(lowerGuess)) {
                            consider(lowerGuess, baseScore: 105)
                        }
                    }
                }
            }
        }

        guard let winner = bestCandidate, bestScore >= 95 else { return nil }

        // Preserve initial uppercase if the user typed an initial capital letter
        if let first = chars.first, first.isUppercase {
            return winner.prefix(1).uppercased() + winner.dropFirst()
        }
        return winner
    }

    /// Returns true if `longer` can be formed by inserting exactly 1 character into `shorter`.
    private static func isSingleInsertion(shorter: [Character], longer: [Character]) -> Bool {
        guard longer.count == shorter.count + 1 else { return false }
        var i = 0
        var j = 0
        var diffs = 0
        while i < shorter.count && j < longer.count {
            if shorter[i] == longer[j] {
                i += 1
                j += 1
            } else {
                diffs += 1
                if diffs > 1 { return false }
                j += 1
            }
        }
        return true
    }
}
