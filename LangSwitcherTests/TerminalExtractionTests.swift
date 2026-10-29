import XCTest
@testable import LangSwitcher

final class TerminalExtractionTests: XCTestCase {
    
    func testTerminalApproachClassification() {
        XCTAssertTrue(AutoCorrectionGate.isTerminalApp(bundleID: "com.apple.Terminal"))
        XCTAssertTrue(AutoCorrectionGate.isTerminalApp(bundleID: "com.googlecode.iterm2"))
        XCTAssertTrue(AutoCorrectionGate.isTerminalApp(bundleID: "com.mitchellh.ghostty"))
        XCTAssertTrue(AutoCorrectionGate.isTerminalApp(bundleID: "io.alacritty"))
        XCTAssertTrue(AutoCorrectionGate.isTerminalApp(bundleID: "dev.warp.Warp-Main"))
        XCTAssertTrue(AutoCorrectionGate.isTerminalApp(bundleID: "dev.warp.Warp-GDK"))
        
        XCTAssertFalse(AutoCorrectionGate.isTerminalApp(bundleID: "com.apple.dt.Xcode"))
        XCTAssertFalse(AutoCorrectionGate.isTerminalApp(bundleID: "com.microsoft.VSCode"))
        XCTAssertFalse(AutoCorrectionGate.isTerminalApp(bundleID: "com.apple.TextEdit"))
    }
    
    func testAutoCorrectionGateAllowsCompletionsForTerminals() {
        // Silent layout auto-correction remains excluded for terminals
        XCTAssertFalse(AutoCorrectionGate.allowsAutoCorrection(
            role: "AXTextArea", subrole: nil, bundleID: "com.apple.Terminal"
        ))
        XCTAssertFalse(AutoCorrectionGate.allowsAutoCorrection(
            role: "AXScrollArea", subrole: nil, bundleID: "com.googlecode.iterm2"
        ))
        
        // Inline completions & ghost text ARE allowed for terminals
        XCTAssertTrue(AutoCorrectionGate.allowsCompletions(
            role: "AXTextArea", subrole: nil, bundleID: "com.apple.Terminal"
        ))
        XCTAssertTrue(AutoCorrectionGate.allowsCompletions(
            role: "AXScrollArea", subrole: nil, bundleID: "com.googlecode.iterm2"
        ))
        XCTAssertTrue(AutoCorrectionGate.allowsCompletions(
            role: "AXGroup", subrole: nil, bundleID: "com.mitchellh.ghostty"
        ))
        XCTAssertTrue(AutoCorrectionGate.allowsCompletions(
            role: "AXGenericElement", subrole: nil, bundleID: "io.alacritty"
        ))
        
        // Password fields and password managers fail closed even in allowsCompletions
        XCTAssertFalse(AutoCorrectionGate.allowsCompletions(
            role: "AXSecureTextField", subrole: nil, bundleID: "com.apple.Terminal"
        ))
        XCTAssertFalse(AutoCorrectionGate.allowsCompletions(
            role: "AXTextField", subrole: "AXSecureTextField", bundleID: "com.apple.Terminal"
        ))
        XCTAssertFalse(AutoCorrectionGate.allowsCompletions(
            role: "AXTextField", subrole: nil, bundleID: "com.1password.1password"
        ))
        XCTAssertFalse(AutoCorrectionGate.allowsCompletions(
            role: "AXTextField", subrole: nil, bundleID: "com.bitwarden.desktop"
        ))
    }
    
    func testTerminalPromptExtraction() {
        let buffer = """
        Last login: Thu Oct 29 14:00:00 on ttys001
        alex@MacBook:~/Sites/langSwitcher$ git status
        On branch main
        Your branch is up to date with 'origin/main'.
        alex@MacBook:~/Sites/langSwitcher$ cargo bui
        """
        
        let result = TerminalPromptExtractor.parseTerminalBuffer(buffer)
        XCTAssertEqual(result.currentCommand, "cargo bui")
        XCTAssertEqual(result.recentCommands, ["git status"])
        XCTAssertEqual(result.promptLineIndex, 4)
        XCTAssertEqual(result.totalLines, 5)
        XCTAssertEqual(result.cursorColumn, 44)
    }
    
    func testXtermGhosttyPromptExtraction() {
        let buffer = """
        ╭──────────────────────────────────────────────╮
        │ Dopishi Workspace                            │
        ╰──────────────────────────────────────────────╯
        ❯ pytest -v
        ==================== 1 passed ====================
        ❯ npm run dev
        """
        
        let result = TerminalPromptExtractor.parseTerminalBuffer(buffer)
        XCTAssertEqual(result.currentCommand, "npm run dev")
        XCTAssertEqual(result.recentCommands, ["pytest -v"])
        XCTAssertEqual(result.promptLineIndex, 5)
        XCTAssertEqual(result.cursorColumn, 13)
    }

    func testTerminalPromptAtTop() {
        let buffer = "alex@MacBook:~$ ls"
        let result = TerminalPromptExtractor.parseTerminalBuffer(buffer)
        XCTAssertEqual(result.currentCommand, "ls")
        XCTAssertEqual(result.promptLineIndex, 0)
        XCTAssertEqual(result.totalLines, 1)
        XCTAssertEqual(result.cursorColumn, 18)
    }
    
    func testTerminalCaretContextCreation() {
        let approach = TextExtractionApproach.terminalLastPage
        XCTAssertEqual(approach.rawValue, "terminalLastPage")
        
        let xtermApproach = TextExtractionApproach.xtermScreen
        XCTAssertEqual(xtermApproach.rawValue, "xtermScreen")
        
        let context = CaretContext(
            fieldIdentifier: "terminal:com.apple.Terminal:1234:5678",
            textBeforeCaret: "git push -u origin",
            textAfterCaret: "",
            selectedText: "",
            caretLocation: 18,
            fullTextLength: 18
        )
        
        XCTAssertTrue(context.hasUsablePredictionContext)
        XCTAssertEqual(context.caretLocation, 18)
        XCTAssertEqual(context.textBeforeCaret, "git push -u origin")
    }
}
