import Foundation
import SQLite3

// MARK: - User Text Snippet Model

struct UserTextSnippet: Identifiable, Equatable {
    let id: Int64
    let timestamp: Date
    let bundleID: String
    let text: String
    let wordCount: Int
    let language: String
}

// MARK: - User Text History Store
// Privately records confirmed sentences and phrases typed by the user.
// Personalizes AI continuation models and feeds offline vocabulary learning.
// Data is stored purely locally in SQLite and never transmitted over the network.

@MainActor
final class UserTextHistoryStore: ObservableObject {
    
    static let shared = UserTextHistoryStore()
    
    @Published private(set) var totalSnippetCount: Int = 0
    
    static let maxHistorySnippets = 5000
    private var db: OpaquePointer?
    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    // Privacy sanitization patterns
    private static let creditCardRegex = try? NSRegularExpression(pattern: #"\b(?:\d[ -]*?){13,16}\b"#)
    private static let emailRegex = try? NSRegularExpression(pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#)
    private static let secretTokenRegex = try? NSRegularExpression(pattern: #"(?:ey[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+|ghp_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,})"#)
    
    init(databasePath: String? = nil) {
        openDatabase(at: databasePath ?? Self.defaultDatabasePath)
        createTableIfNeeded()
        updateSnippetCount()
    }
    
    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
    
    static var defaultDatabasePath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Dopishi", isDirectory: true)
        let legacyDir = appSupport.appendingPathComponent("LangSwitcher", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) && FileManager.default.fileExists(atPath: legacyDir.path) {
            try? FileManager.default.copyItem(at: legacyDir, to: dir)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("user_text_history.sqlite").path
    }
    
    // MARK: - Open Database & Migration
    
    private func openDatabase(at path: String) {
        if sqlite3_open(path, &db) != SQLITE_OK {
            let err = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            NSLog("[LangSwitcher] UserTextHistoryStore: failed to open database: %@", err)
            db = nil
        }
    }
    
    private func createTableIfNeeded() {
        guard let db = db else { return }
        let sql = """
        CREATE TABLE IF NOT EXISTS user_text_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL NOT NULL,
            bundle_id TEXT NOT NULL,
            text TEXT NOT NULL,
            word_count INTEGER NOT NULL,
            language TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_uth_bundle ON user_text_history(bundle_id);
        CREATE INDEX IF NOT EXISTS idx_uth_time ON user_text_history(timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_uth_bundle_lang ON user_text_history(bundle_id, language, timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_uth_lang ON user_text_history(language, timestamp DESC);
        """
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let err = errMsg.map { String(cString: $0) } ?? "unknown"
            NSLog("[LangSwitcher] UserTextHistoryStore: failed to create table: %@", err)
            sqlite3_free(errMsg)
        }
    }
    
    // MARK: - Privacy & Sanitization
    
    static func sanitize(text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return nil }
        
        let words = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard words.count >= 3 else { return nil }
        
        // Truncate to reasonable snippet size
        let cleanText = String(trimmed.prefix(400))
        let range = NSRange(location: 0, length: cleanText.utf16.count)
        
        // 1. Drop secret tokens / API keys / Bearer JWTs
        if let secretTokenRegex, secretTokenRegex.firstMatch(in: cleanText, range: range) != nil {
            return nil
        }
        
        // 2. Drop credit cards
        if let creditCardRegex, creditCardRegex.firstMatch(in: cleanText, range: range) != nil {
            return nil
        }
        
        // 3. Drop single passwords or verification codes
        if words.count <= 4 && words.allSatisfy({ $0.allSatisfy(\.isNumber) || ($0.count > 10 && $0.contains(where: \.isPunctuation)) }) {
            return nil
        }
        
        // 4. Redact emails
        var sanitized = cleanText
        if let emailRegex {
            sanitized = emailRegex.stringByReplacingMatches(in: sanitized, range: range, withTemplate: "[email]")
        }
        
        return sanitized
    }
    
    // MARK: - Insert & Learning
    
    func recordSnippet(text: String, bundleID: String) {
        guard let sanitized = Self.sanitize(text: text) else { return }
        
        let words = sanitized.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let isCyrillic = AIInferenceEngine.containsCyrillic(sanitized)
        let language = isCyrillic ? "ru" : "en"
        
        // Check if identical or prefix of the latest snippet for this app
        if let latest = fetchLatestSnippet(for: bundleID) {
            if latest.text == sanitized {
                return
            }
            if sanitized.hasPrefix(latest.text) && sanitized != latest.text {
                updateSnippet(id: latest.id, newText: sanitized, wordCount: words.count)
                feedAdaptiveStore(words: words)
                return
            }
        }
        
        insertSnippet(text: sanitized, bundleID: bundleID, wordCount: words.count, language: language)
        feedAdaptiveStore(words: words)
        pruneIfNeeded()
    }
    
    private func feedAdaptiveStore(words: [String]) {
        AutocompletionAdaptiveStore.shared.recordSentenceWords(words)
    }
    
    private func insertSnippet(text: String, bundleID: String, wordCount: Int, language: String) {
        guard let db = db else { return }
        let sql = "INSERT INTO user_text_history (timestamp, bundle_id, text, word_count, language) VALUES (?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        
        let now = Date().timeIntervalSince1970
        sqlite3_bind_double(stmt, 1, now)
        sqlite3_bind_text(stmt, 2, (bundleID as NSString).utf8String, -1, Self.SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, (text as NSString).utf8String, -1, Self.SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 4, Int32(wordCount))
        sqlite3_bind_text(stmt, 5, (language as NSString).utf8String, -1, Self.SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_DONE {
            totalSnippetCount += 1
        }
    }
    
    private func updateSnippet(id: Int64, newText: String, wordCount: Int) {
        guard let db = db else { return }
        let sql = "UPDATE user_text_history SET text = ?, word_count = ?, timestamp = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        
        let now = Date().timeIntervalSince1970
        sqlite3_bind_text(stmt, 1, (newText as NSString).utf8String, -1, Self.SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(wordCount))
        sqlite3_bind_double(stmt, 3, now)
        sqlite3_bind_int64(stmt, 4, id)
        
        _ = sqlite3_step(stmt)
    }
    
    // MARK: - Query & Style Prompt Generation
    
    func fetchLatestSnippet(for bundleID: String) -> UserTextSnippet? {
        fetchSnippets(for: bundleID, limit: 1).first
    }
    
    func fetchSnippets(for bundleID: String? = nil, language: String? = nil, limit: Int = 5) -> [UserTextSnippet] {
        guard let db = db else { return [] }
        var conditions: [String] = []
        if bundleID != nil {
            conditions.append("bundle_id = ?")
        }
        if language != nil {
            conditions.append("language = ?")
        }
        
        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        let sql = "SELECT id, timestamp, bundle_id, text, word_count, language FROM user_text_history \(whereClause) ORDER BY timestamp DESC LIMIT ?;"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        
        var paramIndex: Int32 = 1
        if let bundleID = bundleID {
            sqlite3_bind_text(stmt, paramIndex, (bundleID as NSString).utf8String, -1, Self.SQLITE_TRANSIENT)
            paramIndex += 1
        }
        if let language = language {
            sqlite3_bind_text(stmt, paramIndex, (language as NSString).utf8String, -1, Self.SQLITE_TRANSIENT)
            paramIndex += 1
        }
        sqlite3_bind_int(stmt, paramIndex, Int32(limit))
        
        var results: [UserTextSnippet] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let time = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
            let bid = String(cString: sqlite3_column_text(stmt, 2))
            let text = String(cString: sqlite3_column_text(stmt, 3))
            let wc = Int(sqlite3_column_int(stmt, 4))
            let lang = String(cString: sqlite3_column_text(stmt, 5))
            results.append(UserTextSnippet(id: id, timestamp: time, bundleID: bid, text: text, wordCount: wc, language: lang))
        }
        return results
    }
    
    /// Generates a compact few-shot style instruction matching the target language.
    func stylePrompt(for bundleID: String, language: String? = nil, limit: Int = 3) -> String? {
        var snippets = fetchSnippets(for: bundleID, language: language, limit: limit)
        if snippets.isEmpty && language != nil {
            snippets = fetchSnippets(for: bundleID, language: nil, limit: limit)
        }
        guard !snippets.isEmpty else { return nil }
        
        let samples = snippets.map { "- \"\($0.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces))\"" }
        return "User's personal writing style examples:\n" + samples.joined(separator: "\n") + "\nMatch the user's vocabulary, capitalization, and tone."
    }
    
    // MARK: - Pruning & Clear
    
    private func pruneIfNeeded() {
        guard let db = db, totalSnippetCount > Self.maxHistorySnippets else { return }
        let sql = "DELETE FROM user_text_history WHERE id IN (SELECT id FROM user_text_history ORDER BY timestamp ASC LIMIT 1000);"
        sqlite3_exec(db, sql, nil, nil, nil)
        updateSnippetCount()
    }
    
    func clearHistory() {
        guard let db = db else { return }
        sqlite3_exec(db, "DELETE FROM user_text_history;", nil, nil, nil)
        sqlite3_exec(db, "VACUUM;", nil, nil, nil)
        totalSnippetCount = 0
    }
    
    private func updateSnippetCount() {
        guard let db = db else {
            totalSnippetCount = 0
            return
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM user_text_history;", -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            totalSnippetCount = Int(sqlite3_column_int(stmt, 0))
        }
    }
}
