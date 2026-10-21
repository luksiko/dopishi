import Foundation

// MARK: - Terminal Prompt Extractor
// Cleans terminal and TUI text buffers, slices split panes, filters status lines,
// and extracts active command line prompts from Terminal, iTerm2, Ghostty, Warp, and VS Code.

struct TerminalPromptExtractor {
    
    // MARK: - Models
    
    struct PaneRange: Equatable {
        let start: Int
        let end: Int
    }
    
    struct TerminalExtractionResult: Equatable {
        let currentCommand: String?
        let recentCommands: [String]
        let cleanedLines: [String]
    }
    
    // Common prompt markers
    private static let arrowMarkers: Set<Character> = ["❯", "➜", "›", ">", "»", "→"]
    private static let paneBorders: Set<Character> = ["│", "┃", "║", "|", "▌", "▐", "▏", "▕"]
    private static let boxDividerCharacters: Set<Character> = Set("─━═-=—_╭╮╰╯┌┐└┘")
    
    // Common status line fragments (Claude Code, modern shells, build tools)
    private static let statusLineFragments: [String] = [
        "esc to", "ctrl+c", "ctrl+", "enter to", "? for shortcuts",
        "tokens used", "tokens remaining", "context window",
        "building for debugging", "build complete!", "built: /",
        "auto mode on", " = menu"
    ]
    
    // Status regexes for CLI execution time and environment indicators
    private static let timingIndicatorRegex = try? NSRegularExpression(pattern: #"\b(?:took\s+\d+(?:\.\d+)?\s*(?:ms|[smh])|\[\d+(?:\.\d+)?\s*(?:ms|[smh])\])\b"#, options: .caseInsensitive)
    private static let viaEnvRegex = try? NSRegularExpression(pattern: #"\bvia\s+(?:python|node|ruby|go|rust|java|php|v?\d+\.\d+)"#, options: .caseInsensitive)
    
    // Shell prompt regex: matches user@host:path$, (venv) $, git:(branch) $, etc.
    private static let shellPromptRegex: NSRegularExpression? = {
        let pattern = #"^(?:(?:\([A-Za-z0-9_.-]+\)\s*)?(?:[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+:[^$#%]*|[^$#%\n]*git:\([^)]+\)|[A-Za-z0-9_.-]+:[^$#%]*)\s*[$#%]\s*|[$#%]\s+)"#
        return try? NSRegularExpression(pattern: pattern)
    }()

    // Shell prompt search regex (anywhere in line, for pane column detection)
    private static let shellPromptSearchRegex: NSRegularExpression? = {
        let pattern = #"(?:(?:\([A-Za-z0-9_.-]+\)\s*)?(?:[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+:[^$#%]*|[^$#%\n]*git:\([^)]+\)|[A-Za-z0-9_.-]+:[^$#%]*)\s*[$#%]\s*|[$#%]\s+)"#
        return try? NSRegularExpression(pattern: pattern)
    }()

    // MARK: - Public API
    
    /// Parses a raw terminal screen buffer or visible text, returning the active command,
    /// recent commands, and cleaned lines without box-drawing borders or status noise.
    static func parseTerminalBuffer(_ rawText: String) -> TerminalExtractionResult {
        let rawLines = rawText.components(separatedBy: .newlines).map { trimRight($0) }
        var cleanedLines: [String] = []
        var recentCommands: [String] = []
        var currentCommand: String?
        
        // Find if there is an active bottom prompt marker (arrow or shell prompt)
        var bottomPromptIndex: Int?
        for i in rawLines.indices.reversed() {
            let line = rawLines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || isDividerLine(trimmed) || isStatusLine(trimmed) {
                continue
            }
            if containsPromptMarker(line) || isShellPromptLine(trimmed) {
                bottomPromptIndex = i
                break
            }
        }
        
        // Determine active pane column range from bottom prompt if inside split panes
        let paneRange: PaneRange?
        if let idx = bottomPromptIndex {
            paneRange = findPaneRange(for: rawLines[idx])
        } else {
            paneRange = nil
        }
        
        for (idx, line) in rawLines.enumerated() {
            let sliced = slice(line: line, range: paneRange)
            let trimmed = sliced.trimmingCharacters(in: .whitespaces)
            
            if trimmed.isEmpty || isDividerLine(trimmed) || isStatusLine(trimmed) {
                continue
            }
            
            // Check for prompt
            if let command = stripPromptPrefix(from: trimmed) {
                if !command.isEmpty {
                    if idx == bottomPromptIndex {
                        currentCommand = command
                    } else {
                        recentCommands.append(command)
                    }
                    cleanedLines.append(command)
                }
            } else {
                // Regular terminal output line
                let cleanedOutput = cleanBorders(from: sliced)
                if !cleanedOutput.isEmpty && !isStatusLine(cleanedOutput) {
                    cleanedLines.append(cleanedOutput)
                }
            }
        }
        
        // Fallback: If no prompt marker was detected, but the last line is a single non-empty command
        if currentCommand == nil, let last = cleanedLines.last, last.count <= 120 {
            currentCommand = last
        }
        
        return TerminalExtractionResult(
            currentCommand: currentCommand,
            recentCommands: recentCommands,
            cleanedLines: cleanedLines
        )
    }
    
    /// Strips shell or TUI prompt prefix from a single line, returning the command if present.
    static func stripPromptPrefix(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        
        // 1. Arrow markers (❯, ➜, ›, >, », →)
        if let first = trimmed.first, arrowMarkers.contains(first) {
            let rest = trimmed.dropFirst()
            if rest.first?.isWhitespace == true {
                return String(rest).trimmingCharacters(in: .whitespaces)
            }
        }
        
        // Double-character arrows like ">> " or "-> "
        if trimmed.hasPrefix(">> ") || trimmed.hasPrefix("-> ") || trimmed.hasPrefix("=> ") {
            return String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        }
        
        // 2. Shell prompt regex (user@host:path$ command)
        if let regex = shellPromptRegex {
            let range = NSRange(location: 0, length: trimmed.utf16.count)
            if let match = regex.firstMatch(in: trimmed, range: range) {
                let matchLength = match.range.length
                let commandStart = trimmed.index(trimmed.startIndex, offsetBy: matchLength, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
                return String(trimmed[commandStart...]).trimmingCharacters(in: .whitespaces)
            }
        }
        
        // 3. Fallback: single $, %, or # prompt
        if trimmed.hasPrefix("$ ") || trimmed.hasPrefix("% ") || trimmed.hasPrefix("# ") {
            return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        
        return nil
    }
    
    /// Checks if a line contains prompt markers like ❯, ➜, ›, >.
    static func containsPromptMarker(_ line: String) -> Bool {
        let chars = Array(line)
        guard chars.count >= 2 else { return false }
        for i in 0..<(chars.count - 1) where chars[i + 1].isWhitespace {
            if arrowMarkers.contains(chars[i]) {
                return true
            }
        }
        return false
    }
    
    /// Checks if a line looks like a shell prompt line.
    static func isShellPromptLine(_ line: String) -> Bool {
        if stripPromptPrefix(from: line) != nil {
            return true
        }
        let cleaned = cleanBorders(from: line)
        return stripPromptPrefix(from: cleaned) != nil
    }
    
    /// Checks if a line is a box-drawing divider or separator.
    static func isDividerLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 6 else { return false }
        let count = trimmed.filter { boxDividerCharacters.contains($0) }.count
        return Double(count) / Double(trimmed.count) >= 0.40
    }
    
    /// Checks if a line is status or metadata noise.
    static func isStatusLine(_ line: String) -> Bool {
        let lower = line.trimmingCharacters(in: .whitespaces).lowercased()
        guard !lower.isEmpty else { return false }
        
        for frag in statusLineFragments {
            if lower.contains(frag) {
                return true
            }
        }
        
        let range = NSRange(location: 0, length: lower.utf16.count)
        if let timingRegex = timingIndicatorRegex, timingRegex.firstMatch(in: lower, range: range) != nil {
            return true
        }
        if let envRegex = viaEnvRegex, envRegex.firstMatch(in: lower, range: range) != nil {
            return true
        }
        if lower.hasPrefix("workspace-") {
            return true
        }
        
        return false
    }
    
    // MARK: - Split Pane Helpers
    
    /// Locates the column boundaries of a split pane enclosing the prompt arrow or shell prompt.
    static func findPaneRange(for line: String) -> PaneRange? {
        let chars = Array(line)
        var promptCol: Int?
        
        if let arrow = chars.indices.first(where: { i in
            i < chars.count - 1 && arrowMarkers.contains(chars[i]) && chars[i + 1].isWhitespace
        }) {
            promptCol = arrow
        } else if let regex = shellPromptRegex {
            let range = NSRange(location: 0, length: line.utf16.count)
            if let match = regex.firstMatch(in: line, range: range) {
                promptCol = match.range.location + match.range.length
            }
        }
        
        guard let col = promptCol else {
            return nil
        }
        
        let leftBorder = (0..<min(col, chars.count)).reversed().first { paneBorders.contains(chars[$0]) }
        let rightBorder = (min(col, chars.count)..<chars.count).first { paneBorders.contains(chars[$0]) }
        
        guard leftBorder != nil || rightBorder != nil else {
            return nil
        }
        
        return PaneRange(
            start: leftBorder.map { $0 + 1 } ?? 0,
            end: rightBorder ?? Int.max
        )
    }
    
    /// Slices a line to the column bounds of a pane.
    static func slice(line: String, range: PaneRange?) -> String {
        guard let range = range else { return line }
        let chars = Array(line)
        let lo = min(range.start, chars.count)
        let hi = min(range.end, chars.count)
        guard lo < hi else { return "" }
        return String(chars[lo..<hi])
    }
    
    /// Removes vertical border characters from output lines.
    static func cleanBorders(from line: String) -> String {
        line.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "│┃║|▌▐▏▕"))
            .trimmingCharacters(in: .whitespaces)
    }
    
    private static func trimRight(_ str: String) -> String {
        String(str.reversed().drop(while: { $0.isWhitespace }).reversed())
    }
}
