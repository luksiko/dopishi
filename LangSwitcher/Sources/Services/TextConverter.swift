import Foundation

// MARK: - Text Converter
// High-level service that orchestrates text conversion between layouts

@MainActor
final class TextConverter {
    
    private let settingsManager: SettingsManager
    
    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }
    
    /// Result of a conversion: converted text + target layout ID
    struct ConversionResult {
        let text: String
        let targetLayoutID: String
    }
    
    /// Convert selected text from one layout to another
    /// Auto-detects source layout and converts to the "other" layout
    func convertSelectedText(_ text: String) -> String? {
        return convertSelectedTextWithInfo(text)?.text
    }
    
    /// Convert selected text and return both the result text and the target layout ID.
    func convertSelectedTextWithInfo(_ text: String) -> ConversionResult? {
        let layouts = settingsManager.enabledLayouts
        NSLog("[LangSwitcher] convertSelectedText: enabledLayouts count=\(layouts.count), IDs=\(layouts.map(\.id))")
        guard layouts.count >= 2 else {
            NSLog("[LangSwitcher] convertSelectedText: fewer than 2 layouts, returning nil")
            return nil
        }
        
        let layoutIDs = layouts.map(\.id)
        
        // Detect which layout the text was likely typed in
        guard let detectedSourceID = LayoutMapper.detectSourceLayout(
            text: text,
            candidateLayouts: layoutIDs
        ) else {
            NSLog("[LangSwitcher] convertSelectedText: detectSourceLayout returned nil")
            return nil
        }
        
        NSLog("[LangSwitcher] convertSelectedText: detected source layout = '\(detectedSourceID)'")
        
        // Find the target layout (the "other" one)
        guard let targetLayout = layouts.first(where: { $0.id != detectedSourceID }) else {
            NSLog("[LangSwitcher] convertSelectedText: no target layout found different from source")
            guard let firstLayout = layouts.first else { return nil }
            if let result = LayoutMapper.convert(text: text, from: detectedSourceID, to: firstLayout.id) {
                return ConversionResult(text: result, targetLayoutID: firstLayout.id)
            }
            return nil
        }
        
        NSLog("[LangSwitcher] convertSelectedText: converting from '\(detectedSourceID)' to '\(targetLayout.id)'")
        let result = LayoutMapper.convert(text: text, from: detectedSourceID, to: targetLayout.id)
        NSLog("[LangSwitcher] convertSelectedText: result = '\(result ?? "nil")'")
        if let result = result {
            return ConversionResult(text: result, targetLayoutID: targetLayout.id)
        }
        return nil
    }
    
    /// Convert text explicitly between two specified layouts
    func convertText(_ text: String, from sourceID: String, to targetID: String) -> String? {
        return LayoutMapper.convert(text: text, from: sourceID, to: targetID)
    }

    /// Decide whether a word needs automatic correction.
    /// Returns the conversion if and only if the text looks like it was
    /// typed in the wrong layout; otherwise returns nil (abstain).
    func convertIfWrongLayout(_ text: String) -> ConversionResult? {
        guard looksLikeWrongLayout(text) else {
            NSLog("[LangSwitcher] convertIfWrongLayout: abstaining for '\(text)'")
            return nil
        }
        return convertSelectedTextWithInfo(text)
    }

    /// Minimum letters for automatic correction.
    static let autoCorrectMinLetters = 2

    /// Whether a word is eligible for automatic correction.
    func shouldAutoCorrect(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let letters = trimmed.filter(\.isLetter)
        guard letters.count >= Self.autoCorrectMinLetters else { return false }
        guard !trimmed.contains(where: \.isNumber) else { return false }

        let layouts = settingsManager.enabledLayouts
        guard layouts.count >= 2 else { return false }
        guard let sourceID = LayoutMapper.detectSourceLayout(
            text: trimmed,
            candidateLayouts: layouts.map(\.id)
        ) else { return false }
        guard let sourceMap = LayoutCharacterMap.characterMap(for: sourceID) else {
            return false
        }
        let alphabet = Set(sourceMap.values)
        let isPolishSource = sourceID.lowercased().contains("polish")
        let sourceOptionChars = LayoutCharacterMap.optionCharacterMap(for: sourceID).map { Set($0.values) }
        for letter in letters {
            if alphabet.contains(letter) { continue }
            if isPolishSource, LayoutCharacterMap.polishDiacriticBases[letter] != nil { continue }
            if let sourceOptionChars, sourceOptionChars.contains(letter) { continue }
            return false
        }
        return true
    }

    /// Automatic-correction decision: boundary rules first,
    /// then the wrong-layout check. Returns nil whenever the flow abstains.
    func autoCorrectWord(_ text: String) -> ConversionResult? {
        guard shouldAutoCorrect(text) else {
            NSLog("[LangSwitcher] autoCorrectWord: abstaining for '\(text)'")
            return nil
        }
        return convertIfWrongLayout(text)
    }

    /// Fixes words with two initial capital letters followed by lowercase letters (e.g. "ПРобую" -> "Пробую", "THis" -> "This").
    /// - Conditions:
    ///   - Minimum 3 characters
    ///   - 1st character is uppercase letter
    ///   - 2nd character is uppercase letter
    ///   - 3rd character is lowercase letter
    ///   - All remaining characters from index 2 onwards must not be uppercase
    /// - Returns: corrected string with the 2nd character converted to lowercase, or nil if not applicable.
    static func fixTwoInitialCapitals(_ text: String) -> String? {
        guard text.count >= 3 else { return nil }
        let chars = Array(text)
        guard chars[0].isLetter && chars[0].isUppercase else { return nil }
        guard chars[1].isLetter && chars[1].isUppercase else { return nil }
        guard chars[2].isLetter && chars[2].isLowercase else { return nil }
        guard chars.dropFirst(2).allSatisfy({ !$0.isUppercase }) else { return nil }
        return String(chars[0]) + chars[1].lowercased() + String(chars.dropFirst(2))
    }

    /// Instance wrapper for fixTwoInitialCapitals.
    func fixTwoInitialCapitals(_ text: String) -> String? {
        Self.fixTwoInitialCapitals(text)
    }
    
    /// Check if text looks like it was typed in the wrong keyboard layout.
    /// For example, "ghbdtn" typed on QWERTY when meaning "привет" on Russian layout.
    /// We check: if converting the text to another layout produces something more "readable".
    func looksLikeWrongLayout(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            NSLog("[LangSwitcher] looksLikeWrongLayout: empty text")
            return false
        }
        
        let layouts = settingsManager.enabledLayouts
        guard layouts.count >= 2 else {
            NSLog("[LangSwitcher] looksLikeWrongLayout: fewer than 2 layouts")
            return false
        }
        
        let layoutIDs = layouts.map(\.id)
        
        // Detect source layout
        guard let detectedSourceID = LayoutMapper.detectSourceLayout(
            text: trimmed,
            candidateLayouts: layoutIDs
        ) else {
            NSLog("[LangSwitcher] looksLikeWrongLayout: detectSourceLayout returned nil")
            return false
        }
        
        NSLog("[LangSwitcher] looksLikeWrongLayout: detected source='\(detectedSourceID)' for '\(trimmed)'")
        
        // Dictionary veto (embedded PL/UA/EN/RU frequency lists): if the text is
        // already correct language, converting it would garble real words — refuse.
        if LanguageWordlists.shouldVeto(text: trimmed) {
            NSLog("[LangSwitcher] looksLikeWrongLayout: vetoed — text is already valid language")
            return false
        }

        // Personal dictionary: words the user taught us by reverting a
        // Thought Recovery are intentional by definition.
        if UserDictionary.shared.containsAny(in: trimmed) {
            NSLog("[LangSwitcher] looksLikeWrongLayout: vetoed — user dictionary word")
            return false
        }
        
        // Try converting to each other layout and see if it "makes more sense"
        for layout in layouts where layout.id != detectedSourceID {
            if let converted = LayoutMapper.convert(text: trimmed, from: detectedSourceID, to: layout.id) {
                NSLog("[LangSwitcher] looksLikeWrongLayout: converted to '\(converted)' via layout '\(layout.id)'")
                
                // Script classification must use Unicode script, not isASCII:
                // Polish diacritics (ś ć ą …) and accented Latin letters (é ñ ü)
                // are Latin-script letters but NOT ASCII.
                func isLatinScript(_ c: Character) -> Bool {
                    guard c.isLetter else { return false }
                    return c.unicodeScalars.allSatisfy { scalar in
                        switch scalar.value {
                        case 0x300...0x36F: return true   // combining marks (decomposed forms)
                        case 0x41...0x5A, 0x61...0x7A: return true   // A–Z a–z
                        case 0xC0...0xFF: return true     // Latin-1 Supplement (À–ÿ, ü é ñ ó)
                        case 0x100...0x24F: return true   // Latin Extended-A/B (ą ć ś ł Ő …)
                        case 0x1E00...0x1EFF: return true // Latin Extended Additional
                        default: return false
                        }
                    }
                }
                func hasNonLatinLetter(_ s: String) -> Bool {
                    s.contains { $0.isLetter && !isLatinScript($0) }
                }
                
                let sourceHasLatinOnly = !hasNonLatinLetter(trimmed)
                let convertedHasNonLatin = hasNonLatinLetter(converted)
                
                let sourceHasNonLatin = hasNonLatinLetter(trimmed)
                let convertedHasLatinOnly = !hasNonLatinLetter(converted)
                
                NSLog("[LangSwitcher] looksLikeWrongLayout: srcLatinOnly=\(sourceHasLatinOnly) convNonLatin=\(convertedHasNonLatin) srcNonLatin=\(sourceHasNonLatin) convLatinOnly=\(convertedHasLatinOnly)")
                
                // Case 1: "ghbdtn" (all Latin) -> "привет" (non-Latin) = wrong layout
                if sourceHasLatinOnly && convertedHasNonLatin {
                    return true
                }
                
                // Case 2: "руддщ" (non-Latin) -> "hello" (all Latin) = wrong layout
                if sourceHasNonLatin && convertedHasLatinOnly {
                    return true
                }
            }
        }
        
        NSLog("[LangSwitcher] looksLikeWrongLayout: no wrong layout detected")
        return false
    }
    
    // MARK: - Greedy Phrase Conversion
    
    /// Recognizes leading code comments (e.g. "// ", "/// ", "/* ", " * ", "# ", "-- ", "% ")
    /// with optional indentation. Preserves the syntax marker intact so it won't be garbled by layout mapping.
    static func extractCodeCommentPrefix(from line: String) -> (prefix: String, remainder: String)? {
        let whitespace = line.prefix(while: { $0.isWhitespace })
        let afterWhitespace = line.dropFirst(whitespace.count)
        
        let commentMarkers = ["///", "//", "/*", "*", "#", "--", "%"]
        for marker in commentMarkers {
            if afterWhitespace.hasPrefix(marker) {
                let markerEnd = afterWhitespace.dropFirst(marker.count)
                if markerEnd.isEmpty || markerEnd.first?.isWhitespace == true {
                    let trailingSpaces = markerEnd.prefix(while: { $0.isWhitespace })
                    let fullPrefixLength = whitespace.count + marker.count + trailingSpaces.count
                    let prefix = String(line.prefix(fullPrefixLength))
                    let remainder = String(line.dropFirst(fullPrefixLength))
                    if !remainder.isEmpty {
                        return (prefix, remainder)
                    }
                }
            }
        }
        return nil
    }
    
    /// Given a line of text (from cursor to start of line), find the boundary where
    /// the wrong layout begins and return: (prefix to keep unchanged, suffix to convert).
    /// Returns nil if no wrong-layout portion found.
    ///
    /// Algorithm (two-pass):
    ///
    /// Pass 1 — Whole-line check:
    ///   If the entire line converts to a different script (all Latin→Cyrillic or
    ///   all Cyrillic→Latin), convert the whole thing. This handles the common case
    ///   "ghbdtn rfr ltkf lheu" where every word is wrong-layout.
    ///
    /// Pass 2 — Right-to-left boundary scan:
    ///   If only some words switch script, scan from right to left using the basic
    ///   script-switch check (looksLikeWrongLayout). Stop at the first word that
    ///   does NOT switch. This handles mixed lines like "Привет ghbdtn rfr".
    ///
    /// Key insight: per-word gibberish scoring doesn't work because many
    /// wrong-layout words (like "lheu" = "друг") look like valid English
    /// (50% vowels, no consonant clusters). Instead, when ALL words on a line
    /// switch script, that's strong enough signal to convert everything.
    func findWrongLayoutBoundary(in text: String) -> (keep: String, convert: String)? {
        let layouts = settingsManager.enabledLayouts
        guard layouts.count >= 2 else { return nil }
        
        // Preserve code comments (VS Code, Xcode, JetBrains, terminal scripts)
        if let (commentPrefix, remainder) = Self.extractCodeCommentPrefix(from: text) {
            if let boundary = findWrongLayoutBoundary(in: remainder) {
                return (keep: commentPrefix + boundary.keep, convert: boundary.convert)
            }
        }
        
        // Tokenize: split into words and separators, preserving order and whitespace
        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return nil }
        
        let wordTokens = tokens.filter { !$0.isWhitespaceOrPunctuation }
        guard !wordTokens.isEmpty else { return nil }
        
        NSLog("[LangSwitcher] findWrongLayoutBoundary: \(tokens.count) tokens (\(wordTokens.count) words) from '\(text)'")
        
        // --- Pass 1: Check if the whole line is wrong-layout ---
        // Count how many word tokens pass the basic script-switch check
        var wrongCount = 0
        for word in wordTokens {
            if looksLikeWrongLayout(word) {
                wrongCount += 1
            }
        }
        
        NSLog("[LangSwitcher] findWrongLayoutBoundary: \(wrongCount)/\(wordTokens.count) words look wrong-layout")
        
        // If ALL words (or all but maybe one short word) switch script, convert the whole line
        if wrongCount == wordTokens.count {
            NSLog("[LangSwitcher] findWrongLayoutBoundary: ALL words are wrong-layout, converting entire line")
            return (keep: "", convert: text)
        }
        
        // If most words switch (>=70% and at least 2), also convert the whole line.
        // This handles cases where one ambiguous word doesn't trip the check.
        if wordTokens.count >= 3 && Double(wrongCount) / Double(wordTokens.count) >= 0.7 {
            NSLog("[LangSwitcher] findWrongLayoutBoundary: \(wrongCount)/\(wordTokens.count) words wrong (>=70%%), converting entire line")
            return (keep: "", convert: text)
        }
        
        // --- Pass 2: Right-to-left scan to find boundary ---
        // Some words are correct, some are wrong. Find where wrong region starts.
        var wrongStartIndex = tokens.count
        var foundAtLeastOneWrongWord = false
        
        for i in stride(from: tokens.count - 1, through: 0, by: -1) {
            let token = tokens[i]
            
            if token.isWhitespaceOrPunctuation {
                continue
            }
            
            // Use basic script-switch check (no gibberish scoring — that's too fragile)
            if looksLikeWrongLayout(token) {
                wrongStartIndex = i
                foundAtLeastOneWrongWord = true
                NSLog("[LangSwitcher] findWrongLayoutBoundary: token[\(i)] '\(token)' = wrong layout")
            } else {
                NSLog("[LangSwitcher] findWrongLayoutBoundary: token[\(i)] '\(token)' = OK, stopping")
                break
            }
        }
        
        guard foundAtLeastOneWrongWord, wrongStartIndex < tokens.count else {
            NSLog("[LangSwitcher] findWrongLayoutBoundary: no wrong-layout tokens found")
            return nil
        }
        
        let keepTokens = tokens[0..<wrongStartIndex]
        let convertTokens = tokens[wrongStartIndex...]
        
        let keep = keepTokens.joined()
        let convert = convertTokens.joined()
        
        NSLog("[LangSwitcher] findWrongLayoutBoundary: keep='\(keep)' convert='\(convert)'")
        
        guard !convert.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        
        return (keep: keep, convert: convert)
    }
    
    // MARK: - Thought Recovery

    /// Span-level reconstruction of a whole line (see ThoughtRecovery).
    /// Unlike the boundary search below, this keeps correct words, code, links and
    /// intentional foreign words in place and rewrites only the spans with decisive evidence.
    /// Returns nil when nothing should change (or the feature is off), so the
    /// caller can fall back to the boundary heuristic.
    func recoverLine(_ text: String) -> ConversionResult? {
        guard settingsManager.thoughtRecoveryEnabled else { return nil }
        let layouts = settingsManager.enabledLayouts
        guard layouts.count >= 2 else { return nil }

        // Preserve code comments (VS Code, Xcode, JetBrains, terminal scripts)
        if let (commentPrefix, remainder) = Self.extractCodeCommentPrefix(from: text) {
            if let recovered = recoverLine(remainder) {
                return ConversionResult(text: commentPrefix + recovered.text, targetLayoutID: recovered.targetLayoutID)
            }
        }

        let plan = ThoughtRecovery.decode(
            text,
            layoutIDs: layouts.map(\.id),
            learnedWords: UserDictionary.shared.words
        )
        guard plan.isChanged else {
            NSLog("[LangSwitcher] recoverLine: nothing to change in '\(text)'")
            return nil
        }

        NSLog("[LangSwitcher] recoverLine: '\(text)' -> '\(plan.reconstructed)' (confidence=\(plan.confidence), target=\(plan.primaryTargetLayoutID ?? "nil"))")
        return ConversionResult(text: plan.reconstructed, targetLayoutID: plan.primaryTargetLayoutID ?? "")
    }

    /// Full plan for the preview window: original, reconstruction, per-span
    /// kinds and the runner-up reconstructions.
    func recoveryPlan(for text: String) -> ThoughtRecovery.Plan? {
        guard settingsManager.thoughtRecoveryEnabled else { return nil }
        let layouts = settingsManager.enabledLayouts
        guard layouts.count >= 2 else { return nil }
        
        if let (commentPrefix, remainder) = Self.extractCodeCommentPrefix(from: text),
           let subPlan = recoveryPlan(for: remainder) {
            let offsetReconstructed = commentPrefix + subPlan.reconstructed
            return ThoughtRecovery.Plan(
                original: text,
                reconstructed: offsetReconstructed,
                spans: subPlan.spans,
                alternatives: subPlan.alternatives.map { commentPrefix + $0 }
            )
        }
        
        return ThoughtRecovery.decode(
            text,
            layoutIDs: layouts.map(\.id),
            learnedWords: UserDictionary.shared.words
        )
    }

    /// Convert only the wrong-layout portion of a line.
    /// Returns the full replacement text (keep + converted) or nil if nothing to convert.
    func convertLineGreedy(_ text: String) -> String? {
        return convertLineGreedyWithInfo(text)?.text
    }
    
    /// Convert only the wrong-layout portion of a line, returning layout info.
    func convertLineGreedyWithInfo(_ text: String) -> ConversionResult? {
        guard let boundary = findWrongLayoutBoundary(in: text) else {
            return nil
        }
        
        guard let info = convertSelectedTextWithInfo(boundary.convert) else {
            NSLog("[LangSwitcher] convertLineGreedy: convertSelectedText failed for '\(boundary.convert)'")
            return nil
        }
        
        let result = boundary.keep + info.text
        NSLog("[LangSwitcher] convertLineGreedy: '\(text)' → '\(result)'")
        return ConversionResult(text: result, targetLayoutID: info.targetLayoutID)
    }
    
    // MARK: - Tokenization
    
    /// Split text into tokens: words and whitespace/punctuation runs.
    /// Preserves original text exactly (join of tokens == original text).
    private func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inWord = false
        
        for char in text {
            let charIsWord = char.isLetter || char.isNumber
            
            if charIsWord {
                if !inWord && !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                inWord = true
                current.append(char)
            } else {
                if inWord && !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                inWord = false
                current.append(char)
            }
        }
        
        if !current.isEmpty {
            tokens.append(current)
        }
        
        return tokens
    }
}

// MARK: - String Helpers

private extension String {
    /// True if the string contains only whitespace, punctuation, symbols — no letters/digits
    var isWhitespaceOrPunctuation: Bool {
        allSatisfy { !$0.isLetter && !$0.isNumber }
    }
}
