import Foundation

// MARK: - Profanity Filter
// Detects offensive words, profanity, and curse words (Russian mat, English, Ukrainian, etc.).
// Used by AutocompletionEngine and AIInferenceEngine to filter out vulgar suggestions and completions.

public enum ProfanityFilter {
    
    /// Normalizes input string for comparison: lowercase, trim whitespace/punctuation,
    /// and normalize 'ё' to 'е' for simplified Cyrillic root matching.
    private static func normalize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.replacingOccurrences(of: "ё", with: "е")
    }
    
    // Exact match lookup for common profane words across supported languages
    private static let exactWords: Set<String> = [
        // English
        "fuck", "fucks", "fucker", "fuckers", "fucking", "fucked", "fuckin",
        "motherfucker", "motherfucking", "fuckhead", "fuckup",
        "shit", "shits", "shitted", "shitting", "shitty", "bullshit", "horseshit", "dipshit", "shithead", "shitload", "shitfaced",
        "bitch", "bitches", "bitching", "bitchy",
        "asshole", "assholes", "arsehole", "arseholes", "bastard", "bastards",
        "cunt", "cunts", "dick", "dicks", "dickhead", "cock", "cocks", "cocksucker",
        "pussy", "pussies", "whore", "whores", "slut", "sluts",
        "twat", "wanker", "prick", "pricks", "blowjob", "handjob",
        "fag", "faggot", "faggots", "nigger", "niggers", "nigga", "niggas",
        
        // Russian base forms & common colloquial mat
        "бля", "блять", "блядь", "бляди", "блядей", "блядям", "блядство", "блядский", "блядина", "блядовать",
        "мудак", "мудака", "мудаку", "мудаком", "мудаки", "мудаков", "мудила", "мудило", "мудень", "мудозвон", "мудачье",
        "гондон", "гондона", "гондону", "гондоном", "гондоны", "гондонов",
        "гандон", "гандона", "гандону", "гандоном", "гандоны", "гандонов",
        "пидор", "пидора", "пидору", "пидором", "пидоры", "пидоров", "пидорас", "пидораса", "пидорасы", "пидарас", "пидараса", "пидарасы", "пидар", "пидара", "пидары", "пидрила",
        "шлюха", "шлюхи", "шлюхе", "шлюху", "шлюхой", "шлюх", "шлюхам", "шлюхами", "шлюхах", "шлюшка", "шлюшки", "шлюхин",
        "сука", "суки", "суке", "суку", "сукой", "сук", "сукам", "суками", "суках", "сучка", "сучки", "сучке", "сучку", "сучкой", "сучара", "сучары", "сучий", "сучья", "сучье", "сучьи", "сукин",
        "говно", "говна", "говну", "говном", "говне", "говнище", "говняный", "говнюк", "говнюка", "говнюки",
        "дерьмо", "дерьма", "дерьму", "дерьмом", "дерьме", "дерьмовый", "дерьмовая", "дерьмовое", "дерьмовые",
        "залупа", "залупы", "залупе", "залупу", "залупой", "залупаться", "залупился",
        "дрочить", "дрочит", "дрочу", "дрочишь", "дрочат", "дрочил", "дрочила", "дрочка", "задрот", "задрота", "задроты",
        "манда", "манды", "манде", "манду", "мандой", "мандовошка",
        "жопа", "жопы", "жопе", "жопу", "жопой", "жоп", "жопам", "жопами", "жопах", "жопный", "жополиз",
        "срать", "сру", "срешь", "срете", "срет", "срут", "срал", "срала", "срали", "обосрался", "обосралась", "обосрались", "засранец", "засранка", "срань", "сраный", "сраная", "сраное", "сраные",
        "пердеть", "пердит", "пердят", "пернул", "пердун", "пердеж",
        "хер", "хера", "херу", "хером", "херы",
        
        // Ukrainian
        "курва", "курви", "курві", "курву", "курвою", "курвище",
        "лайно", "лайна", "падло",
        "гівно", "гівна", "гівном",
        
        // Polish
        "chuj", "chuja", "chuju", "chujem", "chuje",
        "jebac", "jebany", "pierdolic", "gówno", "gowno"
    ]
    
    // Regular expression patterns for productive morphological stems
    private static let patterns: [NSRegularExpression] = {
        let regexStrings = [
            // English roots
            "fuck",
            "shit",
            "bitch",
            "asshole",
            "arsehole",
            "dickhead",
            "cocksucker",
            
            // Russian 'хуй' / 'хуе' / 'хуя' / 'хуи' / 'хую' (matches as root anywhere in word: похуй, нахуй, охуеть, etc.)
            "(хуй|хуе|хуя|хуи|хую)",
            
            // Russian/Ukrainian 'пизд' / 'пізд'
            "(пизд|пізд)",
            
            // Russian 'еб' (note: ё is normalized to е)
            // Covers base forms (ебать, ебет, ебу, еблан, ебнутый) and prefixed forms (въебать, съебать, заебись, долбоеб, etc.)
            // Prefix 'с' requires 'ъ' or 'ь' to avoid false positives on legitimate 'себя', 'себе'.
            "(^|[^а-яa-z0-9])(еб[аеиоулнщяь]|(вы|до|за|из[ъь]?|ис|на|не|об[ъь]|от[ъь]|пере|по|под[ъь]?|подо|при|про|раз[ъь]?|разо|с[ъь]|у|в[ъь]|во|долбо|мозго)еб[аеиоулнщяь]?)",
            
            // Ukrainian 'їб', 'єб', 'йоб'
            "(їб|єб|йоб)",
            
            // Russian 'бляд' (блядь, бляди, блядство, блядина, блядский, etc.)
            "бляд",
            
            // 'блять' or standalone 'бля'
            "(^|[^а-яa-z0-9])бля($|[^а-яa-z0-9])",
            "(^|[^а-яa-z0-9])блять",
            
            // Russian 'хер' derivatives
            "(^|[^а-яa-z0-9])(похер|нахер|херня|нихера|захерач)"
        ]
        return regexStrings.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()
    
    /// Checks if a word is a known legitimate word with common false-positive prefixes.
    private static func isWhitelisted(_ word: String) -> Bool {
        if word.hasPrefix("бляшк") { return true }
        if word.hasPrefix("худо") || word.hasPrefix("худе") || word.hasPrefix("хутор") || word.hasPrefix("хулиган") || word.hasPrefix("хунт") || word.hasPrefix("хурм") {
            return true
        }
        return false
    }
    
    /// Finds the full surrounding word token around a given character range in text.
    private static func wordSurrounding(range: Range<String.Index>, in text: String) -> String {
        var start = range.lowerBound
        while start > text.startIndex {
            let prev = text.index(before: start)
            if text[prev].isLetter || text[prev].isNumber {
                start = prev
            } else {
                break
            }
        }
        var end = range.upperBound
        while end < text.endIndex {
            if text[end].isLetter || text[end].isNumber {
                end = text.index(after: end)
            } else {
                break
            }
        }
        return String(text[start..<end])
    }
    
    /// Returns true if the text (word, phrase, or sentence) is detected as offensive or profane.
    public static func isProfane(_ text: String) -> Bool {
        let norm = normalize(text)
        guard !norm.isEmpty else { return false }
        
        // 1. Token check: check individual words against exact list and patterns
        let tokens = norm.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        for token in tokens {
            if isWhitelisted(token) { continue }
            if exactWords.contains(token) { return true }
            let range = NSRange(location: 0, length: (token as NSString).length)
            for regex in patterns {
                if regex.firstMatch(in: token, options: [], range: range) != nil {
                    return true
                }
            }
        }
        
        // 2. Full text scan for multi-token phrases or boundary-sensitive regex patterns
        let fullRange = NSRange(location: 0, length: (norm as NSString).length)
        for regex in patterns {
            let matches = regex.matches(in: norm, options: [], range: fullRange)
            for match in matches {
                if let swiftRange = Range(match.range, in: norm) {
                    let word = wordSurrounding(range: swiftRange, in: norm)
                    if !isWhitelisted(word) {
                        return true
                    }
                }
            }
        }
        
        return false
    }
    
    /// Convenience alias for `isProfane(_:)` to check if a sentence or passage contains profanity.
    public static func containsProfanity(in text: String) -> Bool {
        isProfane(text)
    }
}
