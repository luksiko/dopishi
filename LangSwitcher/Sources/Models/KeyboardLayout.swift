import Foundation
import Carbon

// MARK: - Keyboard Layout Model

struct KeyboardLayout: Identifiable, Hashable, Codable {
    let id: String           // e.g. "com.apple.keylayout.US"
    let localizedName: String // e.g. "U.S." or "Russian"
    let languageCode: String  // e.g. "en", "ru"
    
    var displayName: String {
        "\(localizedName) (\(languageCode.uppercased()))"
    }
}

// MARK: - Layout Pair

struct LayoutPair: Identifiable, Hashable, Codable {
    var id: String { "\(source.id)->\(target.id)" }
    let source: KeyboardLayout
    let target: KeyboardLayout
}

// MARK: - Layout Character Maps
// Standard QWERTY <-> various layout mappings for physical key positions

enum LayoutCharacterMap {
    
    // Standard US QWERTY keyboard
    static let qwertyUS: [Character: Character] = {
        let chars = "`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?"
        var map: [Character: Character] = [:]
        for (i, c) in chars.enumerated() {
            map[c] = c
        }
        return map
    }()
    
    // Russian (standard) keyboard — mapped to same physical keys as US QWERTY
    static let russian: [Character: Character] = {
        let qwerty = Array("`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?")
        let russian = Array("ё1234567890-=йцукенгшщзхъ\\фывапролджэячсмитьбю.Ё!\"№;%:?*()_+ЙЦУКЕНГШЩЗХЪ/ФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,")
        var map: [Character: Character] = [:]
        for i in 0..<min(qwerty.count, russian.count) {
            map[qwerty[i]] = russian[i]
        }
        return map
    }()
    
    // German QWERTZ
    static let german: [Character: Character] = {
        let qwerty = Array("`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?")
        let german = Array("^1234567890ß´qwertzuiopü+#asdfghjklöäyxcvbnm,.-°!\"§$%&/()=?`QWERTZUIOPÜ*'ASDFGHJKLÖÄYXCVBNM;:_")
        var map: [Character: Character] = [:]
        for i in 0..<min(qwerty.count, german.count) {
            map[qwerty[i]] = german[i]
        }
        return map
    }()
    
    // French AZERTY
    static let french: [Character: Character] = {
        let qwerty = Array("`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?")
        let french = Array("²&é\"'(-è_çà)=azertyuiop^$*qsdfghjklmùwxcvbn,;:!³1234567890°+AZERTYUIOP¨£µQSDFGHJKLM%WXCVBN?./§")
        var map: [Character: Character] = [:]
        for i in 0..<min(qwerty.count, french.count) {
            map[qwerty[i]] = french[i]
        }
        return map
    }()
    
    // Ukrainian
    static let ukrainian: [Character: Character] = {
        let qwerty = Array("`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?")
        let ukr    = Array("'1234567890-=йцукенгшщзхї\\фівапролджєячсмитьбю.₴!\"№;%:?*()_+ЙЦУКЕНГШЩЗХЇ/ФІВАПРОЛДЖЄЯЧСМИТЬБЮ,")
        var map: [Character: Character] = [:]
        for i in 0..<min(qwerty.count, ukr.count) {
            map[qwerty[i]] = ukr[i]
        }
        return map
    }()
    
    // Spanish
    static let spanish: [Character: Character] = {
        let qwerty  = Array("`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?")
        let spanish = Array("º1234567890'¡qwertyuiop`+çasdfghjklñ´zxcvbnm,.-ª!\"·$%&/()=?¿QWERTYUIOP^*ÇASDFGHJKLÑ¨ZXCVBNM;:_")
        var map: [Character: Character] = [:]
        for i in 0..<min(qwerty.count, spanish.count) {
            map[qwerty[i]] = spanish[i]
        }
        return map
    }()
    
    // Polish Pro ("Polish" on modern macOS, id com.apple.keylayout.PolishPro)
    // QWERTY base identical to US — unmodified keys produce the same characters.
    // Polish diacritics (ą ć ę ł ń ó ś ź ż) live on the Option layer.
    // Base conversion therefore reuses the US QWERTY mapping.
    static let polishPro: [Character: Character] = {
        let qwerty = Array("`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?")
        var map: [Character: Character] = [:]
        for c in qwerty {
            map[c] = c
        }
        return map
    }()
    
    // Polish QWERTZ ("Polish – QWERTZ", id com.apple.keylayout.Polish)
    // Traditional QWERTZ variant: y↔z swapped vs QWERTY, rest of base identical.
    static let polishQWERTZ: [Character: Character] = {
        let qwerty = Array("`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?")
        let polish = Array("`1234567890-=qwertzuiop[]\\asdfghjkl;'yxcvbnm,./~!@#$%^&*()_+QWERTZUIOP{}|ASDFGHJKL:\"YXCVBNM<>?")
        var map: [Character: Character] = [:]
        for i in 0..<min(qwerty.count, polish.count) {
            map[qwerty[i]] = polish[i]
        }
        return map
    }()
    
    // Polish Option-layer diacritics → QWERTY base key.
    static let polishDiacriticBases: [Character: Character] = [
        "ą": "a", "ć": "c", "ę": "e", "ł": "l", "ń": "n",
        "ó": "o", "ś": "s", "ź": "x", "ż": "z",
        "Ą": "A", "Ć": "C", "Ę": "E", "Ł": "L", "Ń": "N",
        "Ó": "O", "Ś": "S", "Ź": "X", "Ż": "Z",
    ]
    
    // Ukrainian-PC Option layer — letter keys a–z (real extraction).
    static let ukrainianOption: [Character: Character] = [
        "a": "ƒ", "b": "и", "c": "≠", "d": "ћ", "e": "ќ", "f": "÷", "g": "©",
        "h": "}", "i": "ѕ", "j": "°", "k": "љ", "l": "∆", "m": "~", "n": "™",
        "o": "ў", "p": "‘", "q": "ј", "r": "®", "s": "ы", "t": "ё", "u": "ґ",
        "v": "µ", "w": "џ", "x": "≈", "y": "њ", "z": "ђ",
    ]
    
    // Polish Pro Option-layer diacritics as a forward physical-key map.
    static let polishProOption: [Character: Character] = {
        var map: [Character: Character] = [:]
        for (diacritic, base) in polishDiacriticBases where diacritic.isLowercase {
            map[base] = diacritic
        }
        return map
    }()
    
    // Option-layer maps keyed by layout identifier pattern.
    static let optionMaps: [(pattern: String, map: [Character: Character])] = [
        ("ukrainian", ukrainianOption),
        ("polishpro", polishProOption),
    ]
    
    /// Get the Option-layer (⌥) character map for a given layout identifier.
    static func optionCharacterMap(for layoutID: String) -> [Character: Character]? {
        let lowered = layoutID.lowercased()
        for (pattern, map) in optionMaps where lowered.contains(pattern) {
            return map
        }
        return nil
    }
    
    // Map of layout identifier patterns to their character maps
    // IMPORTANT: Order matters! More specific patterns must come BEFORE less specific ones.
    // e.g., "russian" must come before "us" because "russian" contains "us" as substring.
    // e.g., "polishpro" must come before "polish" because "polishpro" contains "polish".
    static let allMaps: [(pattern: String, map: [Character: Character])] = [
        ("russian", russian),
        ("ukrainian", ukrainian),
        ("german", german),
        ("french", french),
        ("spanish", spanish),
        ("polishpro", polishPro),
        ("polish", polishQWERTZ),
        ("british", qwertyUS),    // Close enough for conversion
        ("abc", qwertyUS),        // ABC keyboard is same as US
        ("us", qwertyUS),         // Must be LAST among Latin layouts — "us" is substring of "russian" etc.
    ]
    
    /// Get character map for a given layout identifier
    static func characterMap(for layoutID: String) -> [Character: Character]? {
        let lowered = layoutID.lowercased()
        for (pattern, map) in allMaps {
            if lowered.contains(pattern) {
                NSLog("[LangSwitcher] characterMap: '\(layoutID)' matched pattern '\(pattern)'")
                return map
            }
        }
        NSLog("[LangSwitcher] characterMap: no match for '\(layoutID)'")
        return nil
    }
}
