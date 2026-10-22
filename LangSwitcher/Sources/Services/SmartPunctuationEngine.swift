import Foundation

// MARK: - Smart Punctuation Engine
// High-accuracy heuristics for smart punctuation, capitalization after sentence terminators,
// Russian coordinating conjunction commas (e.g. «, а », «, но »), space removal before punctuation,
// accidental Caps Lock correction, and smart typographic dashes and ellipsis.

public struct SmartPunctuationEngine {

    // Common abbreviations in Russian and English that end with a dot but do NOT terminate a sentence.
    public static let commonAbbreviations: Set<String> = [
        // Russian
        "т.д.", "т.п.", "т.е.", "т.к.", "т.н.", "т.о.",
        "г.", "ул.", "д.", "кв.", "руб.", "коп.", "стр.", "рис.", "табл.", "см.", "с.", "в.", "вв.",
        "др.", "проф.", "акад.", "доц.", "тов.", "млн.", "млрд.", "тыс.", "экз.",
        // English
        "e.g.", "i.e.", "etc.", "vs.", "al.", "dr.", "mr.", "mrs.", "ms.", "prof.", "sr.", "jr.",
        "inc.", "ltd.", "co.", "corp.", "approx.", "dept.", "fig.", "no.", "vol."
    ]

    // Preserved mixed-case brand and technology names
    public static let preservedMixedCaseTerms: Set<String> = [
        "ios", "macos", "ipados", "watchos", "tvos", "visionos",
        "iphone", "ipad", "ipod", "imac", "ebay", "emacs"
    ]

    /// Checks if a word typed after a sentence terminator ('.', '!', '?', or start of paragraph/text)
    /// should be capitalized.
    /// - Parameters:
    ///   - word: The word currently being completed (e.g. "привет", "hello").
    ///   - precedingText: The text typed before this word (e.g. "Как дела? ").
    /// - Returns: The capitalized word if eligible, or nil if not applicable.
    public static func capitalizeAfterSentence(word: String, precedingText: String) -> String? {
        guard !word.isEmpty else { return nil }
        guard let firstChar = word.first, firstChar.isLetter, firstChar.isLowercase else { return nil }

        let trimmedPreceding = precedingText.trimmingCharacters(in: .whitespaces)

        // If preceding is empty, it's the start of the field/buffer
        if trimmedPreceding.isEmpty {
            return word.prefix(1).uppercased() + word.dropFirst()
        }

        // Check if preceding ended with newline (paragraph start)
        if trimmedPreceding.hasSuffix("\n") || trimmedPreceding.hasSuffix("\r") {
            return word.prefix(1).uppercased() + word.dropFirst()
        }

        // Check for sentence terminator
        guard let lastChar = trimmedPreceding.last,
              lastChar == "." || lastChar == "!" || lastChar == "?" else {
            return nil
        }

        // If it's a dot, make sure it's not part of an abbreviation
        if lastChar == "." {
            let lowerPreceding = trimmedPreceding.lowercased()
            for abbr in commonAbbreviations {
                if lowerPreceding.hasSuffix(abbr) {
                    return nil
                }
            }
            // Check if it's a number/decimal like "3."
            let withoutDot = trimmedPreceding.dropLast()
            if let beforeDot = withoutDot.last, beforeDot.isNumber {
                return nil
            }
        }

        return word.prefix(1).uppercased() + word.dropFirst()
    }

    /// Evaluates whether a comma should be inserted before the Russian coordinating conjunctions «а» or «но».
    /// - Parameters:
    ///   - word: The completed word (e.g. "а", "но").
    ///   - precedingText: The text before this word (e.g. "хотел ").
    /// - Returns: True if a comma should be placed before the word.
    public static func shouldInsertCommaBeforeConjunction(word: String, precedingText: String) -> Bool {
        // Only target exact lowercase "а" and "но". Uppercase "А" / "Но" indicates sentence start!
        guard word == "а" || word == "но" else { return false }

        // Preceding text must end with a space (e.g. "хотел ")
        guard precedingText.hasSuffix(" ") else { return false }

        let trimmed = precedingText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        // Must not be immediately preceded by punctuation or sentence boundary
        let disallowedTrailing: [Character] = [",", ".", "!", "?", ";", ":", "—", "-", "–", "(", "[", "{", "\"", "«", "“", "\n", "\r"]
        guard let lastChar = trimmed.last, !disallowedTrailing.contains(lastChar) else {
            return false
        }

        // Must be preceded by a word (letter or number), e.g. "хотел ", "быстро "
        guard lastChar.isLetter || lastChar.isNumber else {
            return false
        }

        return true
    }

    /// Checks if a typed punctuation character is preceded by an accidental space (e.g. "слово ," -> "слово,").
    /// - Parameters:
    ///   - char: The punctuation character just typed.
    ///   - precedingText: The text before this character.
    /// - Returns: Tuple of (expected: " ,", replacement: ",") or nil.
    public static func fixSpaceBeforePunctuation(char: Character, precedingText: String) -> (expected: String, replacement: String)? {
        let targetPunctuation: Set<Character> = [",", ".", "!", "?", ":", ";"]
        guard targetPunctuation.contains(char) else { return nil }

        // Must end with single space
        guard precedingText.hasSuffix(" ") else { return nil }

        // The character before the space must NOT be whitespace and NOT another punctuation mark
        let trimmed = precedingText.trimmingCharacters(in: .whitespaces)
        guard let charBeforeSpace = trimmed.last else { return nil }
        guard charBeforeSpace.isLetter || charBeforeSpace.isNumber || charBeforeSpace == ")" || charBeforeSpace == "»" || charBeforeSpace == "”" || charBeforeSpace == "\"" else {
            return nil
        }

        return (expected: " " + String(char), replacement: String(char))
    }

    /// Checks for typographic double hyphen "--" -> "—" or triple dot "..." -> "…".
    /// - Parameters:
    ///   - char: The character just typed.
    ///   - precedingText: The text before this character.
    /// - Returns: Tuple of (expected, replacement) or nil.
    public static func smartDashesAndEllipsis(char: Character, precedingText: String) -> (expected: String, replacement: String)? {
        if char == "-" && precedingText.hasSuffix("-") {
            // Check if it's already a triple hyphen or comment like "---"
            if precedingText.hasSuffix("--") { return nil }
            return (expected: "--", replacement: "—")
        }
        if char == "." && precedingText.hasSuffix("..") {
            // Check if already 4 dots "...."
            if precedingText.hasSuffix("...") { return nil }
            return (expected: "...", replacement: "…")
        }
        return nil
    }

    /// Corrects accidental Caps Lock inversion where 1st char is lowercase and the rest are uppercase
    /// (e.g. "пРИВЕТ" -> "Привет", "hELLO" -> "Hello").
    public static func fixCapsLockError(_ word: String) -> String? {
        guard word.count >= 2 else { return nil }
        let chars = Array(word)
        guard chars[0].isLetter && chars[0].isLowercase else { return nil }
        guard chars[1].isLetter && chars[1].isUppercase else { return nil }
        guard chars.dropFirst(1).allSatisfy({ $0.isLetter && $0.isUppercase }) else { return nil }

        // Check if it's a preserved tech term like "iOS" or "macOS"
        let lower = word.lowercased()
        if preservedMixedCaseTerms.contains(lower) {
            return nil
        }

        return String(chars[0]).uppercased() + String(chars.dropFirst(1)).lowercased()
    }
}
