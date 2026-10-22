import Foundation

// MARK: - Emoji Shortcode Engine
// High-performance dual-language (English & Russian) emoji shortcode resolver
// with cross-layout tolerance (e.g. :fire: / :огонь: / :jujym: / :ашку: -> 🔥).

public struct EmojiShortcodeEngine {

    public struct EmojiCandidate: Equatable, Sendable {
        public let emoji: String
        public let displayKey: String
        public let shortcode: String
    }

    // Direct mapping from normalized keyword (without colons) to emoji
    private static let emojiDictionary: [String: String] = {
        var dict: [String: String] = [:]

        func add(_ emoji: String, _ keys: [String]) {
            for key in keys {
                let normalized = key.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                dict[normalized] = emoji
            }
        }

        // --- Faces & Emotions ---
        add("😀", ["grinning", "улыбка1", "лыба"])
        add("😃", ["smiley", "радость"])
        add("😄", ["smile", "улыбка", "смайл"])
        add("😁", ["grin", "ухмылка", "зубы"])
        add("😆", ["laughing", "смех", "хаха"])
        add("😅", ["sweat_smile", "пот"])
        add("🤣", ["rofl", "ржу", "рофл"])
        add("😂", ["joy", "слезырадости", "смехдослез", "лол"])
        add("🙂", ["slightly_smiling_face", "легкаяулыбка"])
        add("🙃", ["upside_down_face", "вверхногами"])
        add("😉", ["wink", "подмиг", "подмигивание"])
        add("😊", ["blush", "румянец"])
        add("😇", ["innocent", "ангел", "нимб"])
        add("🥰", ["smiling_face_with_3_hearts", "влюблен3"])
        add("😍", ["heart_eyes", "влюблен", "сердечки"])
        add("🤩", ["star_struck", "восторг", "звезды"])
        add("😘", ["kissing_heart", "поцелуй"])
        add("😋", ["yum", "вкусно", "ням"])
        add("😛", ["stuck_out_tongue", "язык"])
        add("😜", ["stuck_out_tongue_winking_eye", "языкподмиг"])
        add("🤪", ["zany_face", "безумие"])
        add("😝", ["stuck_out_tongue_closed_eyes", "языкглаза"])
        add("🤑", ["money_mouth_face", "деньгивглазах"])
        add("🤗", ["hugs", "обнимашки", "объятия"])
        add("🤭", ["hand_over_mouth", "хихи"])
        add("🤫", ["shushing_face", "тихо", "тсс"])
        add("🤔", ["thinking", "думаю", "хмм"])
        add("🤐", ["zipper_mouth_face", "ротназамке"])
        add("🤨", ["raised_eyebrow", "бровь"])
        add("😐", ["neutral_face", "нейтрально"])
        add("😑", ["expressionless", "безэмоций"])
        add("😶", ["no_mouth", "безрта"])
        add("😏", ["smirk", "ухмылка2"])
        add("😒", ["unamused", "недоволен"])
        add("🙄", ["roll_eyes", "закатилглаза"])
        add("😬", ["grimacing", "зубысжал"])
        add("🤥", ["lying_face", "буратино", "ложь"])
        add("😌", ["relieved", "облегчение"])
        add("😔", ["pensive", "грусть2"])
        add("😪", ["sleepy", "сонный"])
        add("🤤", ["drooling_face", "слюнки"])
        add("😴", ["sleeping", "спит", "сон"])
        add("😷", ["mask", "маска"])
        add("🤒", ["face_with_thermometer", "болею", "градусник"])
        add("🤕", ["face_with_head_bandage", "ранен", "бинт"])
        add("🤢", ["nauseated_face", "тошнит"])
        add("🤮", ["vomiting_face", "рвота"])
        add("🤧", ["sneezing_face", "чих"])
        add("🥵", ["hot_face", "жарко"])
        add("🥶", ["cold_face", "холодно"])
        add("🥴", ["woozy_face", "пьян"])
        add("😵", ["dizzy_face", "головокружение"])
        add("🤯", ["exploding_head", "mindblown", "взрывмозга"])
        add("🤠", ["cowboy_hat_face", "ковбой"])
        add("🥳", ["partying_face", "party", "праздник", "туса"])
        add("😎", ["sunglasses", "cool", "очки", "круто"])
        add("🤓", ["nerd_face", "ботаник", "задрот"])
        add("🧐", ["monocle_face", "монокль"])
        add("😕", ["confused", "замешательство"])
        add("😟", ["worried", "беспокойство"])
        add("🙁", ["slightly_frowning_face", "грустно"])
        add("😮", ["open_mouth", "о_о"])
        add("😲", ["astonished", "удивление"])
        add("😳", ["flushed", "смущение"])
        add("🥺", ["pleading_face", "умоляю", "жалобно"])
        add("😦", ["frowning", "нахмурен"])
        add("😨", ["fearful", "страх"])
        add("😰", ["cold_sweat", "холодныйпот"])
        add("😥", ["sad", "печаль"])
        add("😢", ["cry", "слезы", "плач"])
        add("😭", ["sob", "рыдаю"])
        add("😱", ["scream", "крик", "шок"])
        add("😖", ["confounded", "досада"])
        add("😣", ["persevere", "терплю"])
        add("😞", ["disappointed", "разочарование"])
        add("😓", ["sweat", "тяжело"])
        add("😩", ["weary", "устал"])
        add("😫", ["tired_face", "выдохся"])
        add("🥱", ["yawning_face", "зевок"])
        add("😤", ["triumph", "пар"])
        add("😡", ["rage", "гнев", "злость"])
        add("😠", ["angry", "сердит"])
        add("🤬", ["cursing", "мат", "ругань"])
        add("😈", ["smiling_imp", "чертенок"])
        add("👿", ["imp", "демон"])
        add("💀", ["skull", "череп"])
        add("💩", ["poop", "какашка"])
        add("🤡", ["clown_face", "clown", "клоун"])
        add("👻", ["ghost", "призрак"])
        add("👽", ["alien", "пришелец", "нло"])
        add("🤖", ["robot", "робот"])

        // --- Hand Gestures ---
        add("👋", ["wave", "привет", "пока", "машет"])
        add("🤚", ["raised_back_of_hand", "тыльнаясторона"])
        add("🖐️", ["hand_splayed", "ладонь"])
        add("✋", ["hand", "стоп"])
        add("🖖", ["vulcan_salute", "вулкан"])
        add("👌", ["ok_hand", "ok", "ок"])
        add("🤌", ["pinched_fingers", "италия", "жест"])
        add("🤏", ["pinching_hand", "чутьчуть", "щепотка"])
        add("✌️", ["v", "peace", "мир", "победа"])
        add("🤞", ["crossed_fingers", "удачи", "скрестилпальцы"])
        add("🤟", ["love_you_gesture", "люблю"])
        add("🤘", ["metal", "рок"])
        add("🤙", ["call_me_hand", "позвони"])
        add("👈", ["point_left", "влево"])
        add("👉", ["point_right", "вправо"])
        add("👆", ["point_up_2", "вверх2"])
        add("🖕", ["middle_finger", "фак"])
        add("👇", ["point_down", "вниз"])
        add("☝️", ["point_up", "вверх", "минутку"])
        add("👍", ["+1", "thumbsup", "лайк", "класс", "топ"])
        add("👎", ["-1", "thumbsdown", "дизлайк"])
        add("✊", ["fist", "кулак1"])
        add("👊", ["punch", "кулак", "удар"])
        add("🤛", ["left_facing_fist", "кулаквлево"])
        add("🤜", ["right_facing_fist", "кулаквправо"])
        add("👏", ["clap", "хлоп", "аплодисменты", "браво"])
        add("🙌", ["raised_hands", "ура2", "рукивверх"])
        add("👐", ["open_hands", "открытыеруки"])
        add("🤲", ["palms_up_together", "ладонивверх"])
        add("🤝", ["handshake", "рукопожатие", "сделка", "договорились"])
        add("🙏", ["pray", "молитва", "спасибо", "пожалуйста"])
        add("✍️", ["writing_hand", "пишу"])
        add("💅", ["nail_polish", "ногти"])
        add("🤳", ["selfie", "селфи"])
        add("💪", ["muscle", "мышцы", "сила"])

        // --- Symbols, Hearts & Objects ---
        add("❤️", ["heart", "сердце", "любовь"])
        add("🧡", ["orange_heart", "оранжевоесердце"])
        add("💛", ["yellow_heart", "желтоесердце"])
        add("💚", ["green_heart", "зеленоесердце"])
        add("💙", ["blue_heart", "синеесердце"])
        add("💜", ["purple_heart", "фиолетовоесердце"])
        add("🖤", ["black_heart", "черноесердце"])
        add("🤍", ["white_heart", "белоесердце"])
        add("🤎", ["brown_heart", "коричневоесердце"])
        add("💔", ["broken_heart", "разбитоесердце"])
        add("❣️", ["heavy_heart_exclamation", "сердцезнак"])
        add("💕", ["two_hearts", "двасердца"])
        add("💞", ["revolving_hearts", "крутящиесясердца"])
        add("💓", ["heartbeat", "биениесердца"])
        add("💗", ["heartpulse", "пульс"])
        add("💖", ["sparkling_heart", "блестящеесердце"])
        add("💘", ["cupid", "купидон"])
        add("💝", ["gift_heart", "сердцеподарок"])
        add("✨", ["sparkles", "искры", "магия", "блеск"])
        add("⭐", ["star", "звезда"])
        add("🌟", ["star2", "звезда2"])
        add("💫", ["dizzy", "звездочки"])
        add("🔥", ["fire", "огонь", "пламя", "пожар"])
        add("💥", ["boom", "взрыв", "бах"])
        add("☀️", ["sun", "солнце"])
        add("🌙", ["moon", "луна"])
        add("⚡", ["zap", "молния", "вспышка"])
        add("❄️", ["snowflake", "снежинка", "снег"])
        add("🌈", ["rainbow", "радуга"])
        add("☕", ["coffee", "кофе"])
        add("🍵", ["tea", "чай"])
        add("🍺", ["beer", "пиво"])
        add("🍻", ["beers", "пиво2"])
        add("🍷", ["wine_glass", "вино"])
        add("🍕", ["pizza", "пицца"])
        add("🍔", ["burger", "бургер"])
        add("🍟", ["fries", "картошка"])
        add("🍎", ["apple", "яблоко"])
        add("🎂", ["cake", "торт"])
        add("🍿", ["popcorn", "попкорн"])
        add("🚀", ["rocket", "ракета", "старт"])
        add("🚗", ["car", "машина", "авто"])
        add("✈️", ["airplane", "самолет"])
        add("🚢", ["ship", "корабль"])
        add("💡", ["bulb", "идея", "лампа"])
        add("💰", ["moneybag", "деньги", "бабло"])
        add("💎", ["gem", "алмаз", "кристалл"])
        add("🔒", ["lock", "замок"])
        add("🔓", ["unlock", "открыто"])
        add("🔑", ["key", "ключ"])
        add("🔨", ["hammer", "молоток"])
        add("🔧", ["wrench", "ключгаечный"])
        add("⚙️", ["gear", "шестеренка", "настройки"])
        add("💣", ["bomb", "бомба"])
        add("💊", ["pill", "таблетка"])
        add("🎈", ["balloon", "шарик"])
        add("🎉", ["tada", "ура", "тада"])
        add("🎁", ["gift", "подарок"])
        add("🏆", ["trophy", "кубок", "победа2"])
        add("🥇", ["first_place", "первоеместо", "золото"])
        add("🎯", ["dart", "цель", "мишень"])
        add("🎮", ["video_game", "игра", "геймпад"])
        add("📱", ["iphone", "телефон", "смартфон"])
        add("💻", ["computer", "ноутбук", "комп"])
        add("🖥️", ["desktop_computer", "монитор"])
        add("⌨️", ["keyboard", "клавиатура"])
        add("📦", ["package", "посылка", "коробка"])
        add("📝", ["memo", "заметка"])
        add("📌", ["pushpin", "булавка", "скрепка"])
        add("📎", ["paperclip", "скрепка2"])
        add("📅", ["calendar", "календарь"])
        add("📊", ["bar_chart", "график", "диаграмма"])
        add("📈", ["chart_with_upwards_trend", "рост"])
        add("📉", ["chart_with_downwards_trend", "падение"])
        add("⏳", ["hourglass", "песочныечасы", "время"])
        add("⌛", ["hourglass_done", "времявышло"])
        add("🔔", ["bell", "колокольчик", "звонок"])
        add("🔕", ["no_bell", "беззвука"])
        add("📢", ["loudspeaker", "мегафон", "объявление"])
        add("🔍", ["mag", "поиск", "лупа"])
        add("🏷️", ["label", "тег", "ярлык"])
        add("🚩", ["flag", "флаг"])
        add("✅", ["white_check_mark", "check", "галочка", "готово", "ок2"])
        add("❌", ["x", "cross", "крест", "отмена", "ошибка"])
        add("⚠️", ["warning", "внимание", "предупреждение"])
        add("⛔", ["no_entry", "кирпич", "стоп2"])
        add("🚫", ["prohibited", "запрещено"])
        add("💯", ["100", "сто", "сотка"])
        add("🆗", ["ok_button", "ок3"])
        add("🆙", ["up", "ап"])
        add("🆒", ["cool_button", "кул"])
        add("🆕", ["new", "новый"])
        add("🆓", ["free", "бесплатно"])
        add("ℹ️", ["information_source", "инфо"])
        add("❓", ["question", "вопрос"])
        add("❗", ["exclamation", "восклицание"])
        add("👀", ["eyes", "глаза", "смотрю"])
        add("🐱", ["cat", "кот", "котик"])
        add("🐶", ["dog", "собака", "пес"])
        add("🦊", ["fox", "лиса"])
        add("🐻", ["bear", "медведь"])
        add("🐼", ["panda", "панда"])
        add("🦁", ["lion", "лев"])
        add("🐵", ["monkey", "обезьяна"])
        add("🦄", ["unicorn", "единорог"])
        add("🐝", ["bee", "пчела"])
        add("🐛", ["bug", "баг", "жук"])
        add("🦋", ["butterfly", "бабочка"])

        return dict
    }()

    /// Resolves an emoji by raw shortcode name with cross-layout tolerance.
    public static func lookup(rawCode: String) -> String? {
        let code = rawCode.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        guard !code.isEmpty else { return nil }

        // 1. Direct match
        if let emoji = emojiDictionary[code] {
            return emoji
        }

        // 2. Cross-layout conversion: US -> Russian (e.g. "jujym" -> "огонь", "hfretn" -> "ракета")
        if let ruConverted = LayoutMapper.convert(text: code, from: "com.apple.keylayout.US", to: "com.apple.keylayout.Russian") {
            if let emoji = emojiDictionary[ruConverted.lowercased()] {
                return emoji
            }
        }

        // 3. Cross-layout conversion: Russian -> US (e.g. "ашку" -> "fire", "кщслуе" -> "rocket")
        if let enConverted = LayoutMapper.convert(text: code, from: "com.apple.keylayout.Russian", to: "com.apple.keylayout.US") {
            if let emoji = emojiDictionary[enConverted.lowercased()] {
                return emoji
            }
        }

        return nil
    }

    /// Checks if preceding text ends with a closed shortcode (e.g. ":fire:" or ":огонь:" or ":jujym:")
    /// and returns the replacement tuple if matched.
    public static func findColonReplacement(in text: String) -> (expected: String, replacement: String)? {
        guard text.hasSuffix(":") && text.count >= 3 else { return nil }

        // Look backwards for opening colon
        let droppedLast = text.dropLast() // drops the closing ':'
        guard let openingIndex = droppedLast.lastIndex(of: ":") else { return nil }

        let rawCode = String(droppedLast[droppedLast.index(after: openingIndex)...])
        guard !rawCode.isEmpty, rawCode.count <= 30 else { return nil }
        guard !rawCode.contains(" ") && !rawCode.contains("\n") && !rawCode.contains("\t") else { return nil }

        if let emoji = lookup(rawCode: rawCode) {
            let fullTrigger = ":\(rawCode):"
            return (expected: fullTrigger, replacement: emoji)
        }

        return nil
    }

    /// Checks if preceding text ends with an open shortcode followed by space (e.g. ":fire " or ":огонь ")
    /// and returns the replacement tuple if matched.
    public static func findSpaceReplacement(in text: String) -> (expected: String, replacement: String)? {
        guard text.hasSuffix(" ") && text.count >= 3 else { return nil }

        let droppedSpace = text.dropLast()
        guard let openingIndex = droppedSpace.lastIndex(of: ":") else { return nil }

        let rawCode = String(droppedSpace[droppedSpace.index(after: openingIndex)...])
        guard !rawCode.isEmpty, rawCode.count <= 30 else { return nil }
        guard !rawCode.contains(" ") && !rawCode.contains("\n") && !rawCode.contains("\t") else { return nil }

        if let emoji = lookup(rawCode: rawCode) {
            let fullTrigger = ":\(rawCode) "
            return (expected: fullTrigger, replacement: "\(emoji) ")
        }

        return nil
    }

    /// Provides matching candidates for a typed prefix (e.g. ":fi" or ":ог" or ":juj")
    public static func candidates(for query: String, limit: Int = 6) -> [EmojiCandidate] {
        let code = query.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        guard !code.isEmpty else { return [] }

        var results: [EmojiCandidate] = []
        var seenEmoji: Set<String> = []

        // Search direct matches
        for (key, emoji) in emojiDictionary where key.hasPrefix(code) {
            if !seenEmoji.contains(emoji) {
                seenEmoji.insert(emoji)
                results.append(EmojiCandidate(emoji: emoji, displayKey: key, shortcode: ":\(key):"))
                if results.count >= limit { return results }
            }
        }

        // Search cross-layout US -> RU
        if let ruConverted = LayoutMapper.convert(text: code, from: "com.apple.keylayout.US", to: "com.apple.keylayout.Russian") {
            let ruLower = ruConverted.lowercased()
            for (key, emoji) in emojiDictionary where key.hasPrefix(ruLower) {
                if !seenEmoji.contains(emoji) {
                    seenEmoji.insert(emoji)
                    results.append(EmojiCandidate(emoji: emoji, displayKey: key, shortcode: ":\(key):"))
                    if results.count >= limit { return results }
                }
            }
        }

        // Search cross-layout RU -> US
        if let enConverted = LayoutMapper.convert(text: code, from: "com.apple.keylayout.Russian", to: "com.apple.keylayout.US") {
            let enLower = enConverted.lowercased()
            for (key, emoji) in emojiDictionary where key.hasPrefix(enLower) {
                if !seenEmoji.contains(emoji) {
                    seenEmoji.insert(emoji)
                    results.append(EmojiCandidate(emoji: emoji, displayKey: key, shortcode: ":\(key):"))
                    if results.count >= limit { return results }
                }
            }
        }

        return results
    }
}
