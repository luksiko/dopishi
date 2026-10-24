import Foundation
import AppKit

// MARK: - Downloadable Dictionary Model

struct DownloadableDictionary: Identifiable, Equatable {
    let id: String              // e.g. "tg", "kk"
    let languageCode: String    // base language code
    let displayName: String     // e.g. "Таҷикӣ (Tajik)"
    let affURL: URL
    let dicURL: URL
    let affFileName: String
    let dicFileName: String
    let approximateSizeMB: Double
}

// MARK: - Dictionary Status

enum DictionaryStatus: Equatable {
    case systemProvided
    case installed(files: [String])
    case availableForDownload(DownloadableDictionary)
    case unsupported
}

// MARK: - Download State

enum DictionaryDownloadState: Equatable {
    case idle
    case downloading(progress: Double)
    case completed
    case failed(error: String)
}

// MARK: - Custom Dictionary Store
// Loads and manages in-memory wordsets from ~/Library/Spelling/*.dic files.
// Used by SpellCheckService, LanguageWordlists, and AutocompletionEngine to provide
// accurate verification and suggestions for languages not natively supported by macOS AppleSpell.

final class CustomDictionaryStore {
    static let shared = CustomDictionaryStore()

    private let queue = DispatchQueue(label: "com.dopishi.customdictionary", attributes: .concurrent)
    private var loadedWords: [String: Set<String>] = [:]
    private var loadedPrefixes: [String: [String]] = [:]

    private init() {
        loadAllInstalledDictionaries()
    }

    /// Scan ~/Library/Spelling for installed .dic files and load them
    func loadAllInstalledDictionaries() {
        let spellingDir = DictionaryDownloadManager.spellingDirectoryURL
        guard let files = try? FileManager.default.contentsOfDirectory(at: spellingDir, includingPropertiesForKeys: nil) else { return }

        for file in files where file.pathExtension.lowercased() == "dic" {
            let baseName = file.deletingPathExtension().lastPathComponent
            let lang = baseName.components(separatedBy: CharacterSet(charactersIn: "-_")).first?.lowercased() ?? baseName.lowercased()
            // Do not override core macOS native dictionary languages
            if !["en", "ru", "uk", "de", "fr", "es"].contains(lang) {
                loadDictionary(at: file, forLanguage: lang)
            }
        }
    }

    /// Parse a Hunspell .dic file and store words
    func loadDictionary(at url: URL, forLanguage lang: String) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            NSLog("[LangSwitcher] CustomDictionaryStore: failed to read %@", url.path)
            return
        }

        var words = Set<String>()
        var wordList: [String] = []

        content.enumerateLines { line, _ in
            let word = line.split(separator: "/").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            if !word.isEmpty && !word.allSatisfy({ $0.isNumber }) {
                let lower = word.lowercased()
                words.insert(lower)
                wordList.append(lower)
            }
        }

        queue.async(flags: .barrier) {
            self.loadedWords[lang] = words
            self.loadedPrefixes[lang] = wordList.sorted()
        }

        NSLog("[LangSwitcher] CustomDictionaryStore: loaded %d words for '%@' from %@", words.count, lang, url.lastPathComponent)
    }

    /// Check if in-memory dictionary words are loaded for a language
    func hasDictionary(for language: String) -> Bool {
        let lang = language.lowercased()
        return queue.sync {
            guard let set = loadedWords[lang] else { return false }
            return !set.isEmpty
        }
    }

    /// Validate whether a word belongs to the language dictionary (with inflection suffix handling)
    func isValidWord(_ word: String, language: String) -> Bool {
        let lang = language.lowercased()
        let lower = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return false }

        return queue.sync {
            guard let set = loadedWords[lang] else { return false }
            if set.contains(lower) { return true }

            // Inflection suffix rules for languages lacking built-in AppleSpell
            switch lang {
            case "tg":
                // Tajik noun/verb suffixes (-ҳо, -ӣ, -ро, -он, -ам, -ат, -аш, -а, -е, -ем, -ед, -анд)
                let suffixes = ["ҳо", "ӣ", "ро", "он", "ам", "ат", "аш", "а", "е", "ем", "ед", "анд", "гон", "ён", "вон"]
                for sfx in suffixes where lower.hasSuffix(sfx) && lower.count > sfx.count + 2 {
                    let stem = String(lower.dropLast(sfx.count))
                    if set.contains(stem) { return true }
                }
            case "kk":
                // Kazakh agglutinative suffixes (plural, case, possessive)
                let suffixes = ["лар", "лер", "дар", "дер", "тар", "тер", "дың", "дің", "ның", "нің", "ты", "ті", "ды", "ді", "ға", "ге", "қа", "ке", "да", "де", "та", "те", "нан", "нен", "дан", "ден", "тан", "тен"]
                for sfx in suffixes where lower.hasSuffix(sfx) && lower.count > sfx.count + 2 {
                    let stem = String(lower.dropLast(sfx.count))
                    if set.contains(stem) { return true }
                }
            case "be":
                // Belarusian common endings
                let suffixes = ["аў", "яў", "ей", "ам", "ям", "амі", "ямі", "ах", "ях", "ы", "і", "е", "у", "ю", "а", "я"]
                for sfx in suffixes where lower.hasSuffix(sfx) && lower.count > sfx.count + 2 {
                    let stem = String(lower.dropLast(sfx.count))
                    if set.contains(stem) { return true }
                }
            default:
                break
            }

            return false
        }
    }

    /// Retrieve all words for script union / veto checks
    func allWords(for language: String) -> Set<String> {
        let lang = language.lowercased()
        return queue.sync {
            return loadedWords[lang] ?? []
        }
    }

    /// Autocompletion candidates matching given prefix
    func candidateCompletions(prefix: String, language: String, limit: Int = 5) -> [String] {
        let lang = language.lowercased()
        let lower = prefix.lowercased()
        guard !lower.isEmpty else { return [] }

        return queue.sync {
            guard let list = loadedPrefixes[lang] else { return [] }
            var results: [String] = []
            for w in list {
                if w.hasPrefix(lower) && w != lower {
                    results.append(w)
                    if results.count >= limit { break }
                }
            }
            return results
        }
    }
}

// MARK: - Dictionary Download Manager
// Downloads, places, and manages Hunspell dictionaries in ~/Library/Spelling/.

@MainActor
final class DictionaryDownloadManager: ObservableObject {
    static let shared = DictionaryDownloadManager()

    @Published var downloadStates: [String: DictionaryDownloadState] = [:]
    @Published var refreshCounter: Int = 0

    /// Known downloadable Hunspell dictionaries catalog
    static let catalog: [String: DownloadableDictionary] = [
        "tg": DownloadableDictionary(
            id: "tg",
            languageCode: "tg",
            displayName: "Таҷикӣ (Tajik)",
            affURL: URL(string: "https://raw.githubusercontent.com/karl-sjogren/hunspell_dictionaries/master/tg_TG.aff")!,
            dicURL: URL(string: "https://raw.githubusercontent.com/karl-sjogren/hunspell_dictionaries/master/tg_TG.dic")!,
            affFileName: "tg_TG.aff",
            dicFileName: "tg_TG.dic",
            approximateSizeMB: 1.7
        ),
        "kk": DownloadableDictionary(
            id: "kk",
            languageCode: "kk",
            displayName: "Қазақша (Kazakh)",
            affURL: URL(string: "https://raw.githubusercontent.com/kergalym/myspell-kk/master/kk_KZ.aff")!,
            dicURL: URL(string: "https://raw.githubusercontent.com/kergalym/myspell-kk/master/kk_KZ.dic")!,
            affFileName: "kk_KZ.aff",
            dicFileName: "kk_KZ.dic",
            approximateSizeMB: 1.5
        ),
        "be": DownloadableDictionary(
            id: "be",
            languageCode: "be",
            displayName: "Беларуская (Belarusian)",
            affURL: URL(string: "https://raw.githubusercontent.com/LibreOffice/dictionaries/master/be_BY/be-official.aff")!,
            dicURL: URL(string: "https://raw.githubusercontent.com/LibreOffice/dictionaries/master/be_BY/be-official.dic")!,
            affFileName: "be_BY.aff",
            dicFileName: "be_BY.dic",
            approximateSizeMB: 3.2
        ),
        "hy": DownloadableDictionary(
            id: "hy",
            languageCode: "hy",
            displayName: "Հայերեն (Armenian)",
            affURL: URL(string: "https://raw.githubusercontent.com/karl-sjogren/hunspell_dictionaries/master/hy.aff")!,
            dicURL: URL(string: "https://raw.githubusercontent.com/karl-sjogren/hunspell_dictionaries/master/hy.dic")!,
            affFileName: "hy.aff",
            dicFileName: "hy.dic",
            approximateSizeMB: 1.2
        )
    ]

    /// macOS user spelling directory
    nonisolated static var spellingDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Spelling", isDirectory: true)
    }

    private init() {}

    /// Determine dictionary status for a given language code
    func status(for languageCode: String) -> DictionaryStatus {
        _ = refreshCounter
        let code = languageCode.lowercased()

        // 1. Is it supported by macOS built-in NSSpellChecker?
        if isSystemSupported(code) {
            return .systemProvided
        }

        // 2. Is it installed in ~/Library/Spelling/?
        let installedFiles = findInstalledFiles(for: code)
        if !installedFiles.isEmpty {
            return .installed(files: installedFiles)
        }

        // 3. Is there a catalog entry available to download?
        if let dict = Self.catalog[code] {
            return .availableForDownload(dict)
        }

        return .unsupported
    }

    /// Check if NSSpellChecker has built-in support for the language
    func isSystemSupported(_ code: String) -> Bool {
        let available = NSSpellChecker.shared.availableLanguages
        return available.contains { lang in
            let lower = lang.lowercased()
            return lower == code || lower.hasPrefix("\(code)_") || lower.hasPrefix("\(code)-")
        }
    }

    /// Look for .dic/.aff files matching this language code in ~/Library/Spelling/
    func findInstalledFiles(for code: String) -> [String] {
        let dir = Self.spellingDirectoryURL
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return []
        }

        return contents.filter { file in
            let lower = file.lowercased()
            guard lower.hasSuffix(".dic") || lower.hasSuffix(".aff") else { return false }
            let base = file.components(separatedBy: ".").first?.lowercased() ?? ""
            return base == code || base.hasPrefix("\(code)_") || base.hasPrefix("\(code)-")
        }
    }

    /// Download dictionary files asynchronously and install into ~/Library/Spelling/
    func downloadDictionary(for dict: DownloadableDictionary) async {
        let code = dict.languageCode
        downloadStates[code] = .downloading(progress: 0.1)

        do {
            let spellingDir = Self.spellingDirectoryURL
            try FileManager.default.createDirectory(at: spellingDir, withIntermediateDirectories: true)

            // Download .aff file
            downloadStates[code] = .downloading(progress: 0.25)
            let (affData, affResp) = try await URLSession.shared.data(from: dict.affURL)
            guard (affResp as? HTTPURLResponse)?.statusCode == 200 else {
                throw NSError(domain: "DictionaryDownloadManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to download affix file"])
            }
            let affTarget = spellingDir.appendingPathComponent(dict.affFileName)
            try affData.write(to: affTarget, options: .atomic)

            // Download .dic file
            downloadStates[code] = .downloading(progress: 0.6)
            let (dicData, dicResp) = try await URLSession.shared.data(from: dict.dicURL)
            guard (dicResp as? HTTPURLResponse)?.statusCode == 200 else {
                throw NSError(domain: "DictionaryDownloadManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to download dictionary file"])
            }
            let dicTarget = spellingDir.appendingPathComponent(dict.dicFileName)
            try dicData.write(to: dicTarget, options: .atomic)

            // Special compatibility alias for Tajik: write both tg_TG and tg_TJ
            if code == "tg" {
                let tjAff = spellingDir.appendingPathComponent("tg_TJ.aff")
                let tjDic = spellingDir.appendingPathComponent("tg_TJ.dic")
                try? affData.write(to: tjAff, options: .atomic)
                try? dicData.write(to: tjDic, options: .atomic)
            }

            // Immediately load into CustomDictionaryStore
            CustomDictionaryStore.shared.loadDictionary(at: dicTarget, forLanguage: code)

            downloadStates[code] = .completed
            refreshCounter += 1
            NSLog("[LangSwitcher] Successfully installed dictionary for '%@' into %@", code, spellingDir.path)
        } catch {
            NSLog("[LangSwitcher] Dictionary download failed for '%@': %@", code, error.localizedDescription)
            downloadStates[code] = .failed(error: error.localizedDescription)
        }
    }

    /// Open ~/Library/Spelling in Finder
    func openSpellingDirectory() {
        let url = Self.spellingDirectoryURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }
}
