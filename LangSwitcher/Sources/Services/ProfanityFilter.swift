import Foundation

// MARK: - Profanity Filter
// Detects offensive words, profanity, and curse words (Russian mat, English, Ukrainian, etc.).
// Used by AutocompletionEngine to filter out vulgar suggestions by default unless enabled by user.

public enum ProfanityFilter {
    
    /// Normalizes input string for comparison: lowercase, trim whitespace/punctuation,
    /// and normalize 'ё' to 'е' for simplified Cyrillic root matching.
    private static func normalize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
            .lowercased()
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
        "мудак", "мудака", "мудаку", "мудаком", "мудаки", "мудаков", "мудила", "мудило", "мудень", "мудозвон",
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
            
            // Russian 'хуй' / 'хуе' / 'хуя' / 'хуи' / 'хую' (including prefixed forms like охуе, похуй, нахуй, etc.)
            "(^|[а-яa-z])(хуй|хуе|хуя|хуи|хую)",
            
            // Russian/Ukrainian 'пизд' / 'пізд'
            "(пизд|пізд)",
            
            // Russian 'еб' (note: ё is normalized to е)
            // Starts with еб followed by vowel or l/n: e.g. ебать, ебет, ебу, ебли, ебаный, еблан, etc.
            "^еб[аеиоулн]",
            
            // Prefixed Russian 'еб': (вы|за|на|не|до|от|ото|отъ|пере|по|под|подо|подъ|при|про|раз|разо|разъ|с|со|съ|у)(еб|ъеб)[аеиоулнщяь]
            "(вы|за|на|не|до|от|ото|отъ|пере|по|под|подо|подъ|при|про|раз|разо|разъ|с|со|съ|у)(еб|ъеб)[аеиоулнщяь]",
            
            // Ukrainian 'їб', 'єб', 'йоб'
            "(їб|єб|йоб)",
            
            // Russian 'бляд' (блядь, бляди, блядство, блядина, блядский, etc.)
            "бляд",
            
            // 'блять' or standalone 'бля'
            "(^|[^а-яa-z])бля($|[^а-яa-z])",
            "(^|[^а-яa-z])блять"
        ]
        return regexStrings.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()
    
    /// Returns true if the word is detected as offensive or profane.
    public static func isProfane(_ text: String) -> Bool {
        let norm = normalize(text)
        guard !norm.isEmpty else { return false }
        
        // Whitelist for common non-profane words that share prefixes
        // e.g. 'бляшка' (medical / anatomical plate)
        if norm.hasPrefix("бляшк") { return false }
        // e.g. 'художник', 'худой', 'худеть', 'хутор', 'хулиган', 'хунта', 'хурма'
        if norm.hasPrefix("худо") || norm.hasPrefix("худе") || norm.hasPrefix("хутор") || norm.hasPrefix("хулиган") || norm.hasPrefix("хунт") || norm.hasPrefix("хурм") {
            return false
        }
        
        // Exact words check
        if exactWords.contains(norm) {
            return true
        }
        
        // Productive pattern check
        let range = NSRange(location: 0, length: (norm as NSString).length)
        for regex in patterns {
            if regex.firstMatch(in: norm, options: [], range: range) != nil {
                return true
            }
        }
        
        return false
    }
}
