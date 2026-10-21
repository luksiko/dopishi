import XCTest
@testable import LangSwitcher

final class TerminalPromptExtractorTests: XCTestCase {

    func testStripArrowPromptPrefixes() {
        XCTAssertEqual(TerminalPromptExtractor.stripPromptPrefix(from: "❯ git status"), "git status")
        XCTAssertEqual(TerminalPromptExtractor.stripPromptPrefix(from: "➜  dopishi git push"), "dopishi git push")
        XCTAssertEqual(TerminalPromptExtractor.stripPromptPrefix(from: "› npm run dev"), "npm run dev")
        XCTAssertEqual(TerminalPromptExtractor.stripPromptPrefix(from: "> python main.py"), "python main.py")
        XCTAssertEqual(TerminalPromptExtractor.stripPromptPrefix(from: ">> cargo build"), "cargo build")
    }

    func testStripShellPromptPrefixes() {
        XCTAssertEqual(TerminalPromptExtractor.stripPromptPrefix(from: "$ ls -la"), "ls -la")
        XCTAssertEqual(TerminalPromptExtractor.stripPromptPrefix(from: "% cd .."), "cd ..")
        XCTAssertEqual(TerminalPromptExtractor.stripPromptPrefix(from: "# whoami"), "whoami")
        XCTAssertEqual(TerminalPromptExtractor.stripPromptPrefix(from: "alex@MacBook:~/Sites$ git pull"), "git pull")
        XCTAssertEqual(TerminalPromptExtractor.stripPromptPrefix(from: "(venv) user@host:~/app$ pytest"), "pytest")
        XCTAssertEqual(TerminalPromptExtractor.stripPromptPrefix(from: "user@host: ~/dev % make test"), "make test")
    }

    func testIsDividerLine() {
        XCTAssertTrue(TerminalPromptExtractor.isDividerLine("───────────────────────────────"))
        XCTAssertTrue(TerminalPromptExtractor.isDividerLine("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"))
        XCTAssertTrue(TerminalPromptExtractor.isDividerLine("==============================="))
        XCTAssertTrue(TerminalPromptExtractor.isDividerLine("-------------------------------"))
        XCTAssertTrue(TerminalPromptExtractor.isDividerLine("╭─────────────────────────────╮"))
        XCTAssertTrue(TerminalPromptExtractor.isDividerLine("╰─────────────────────────────╯"))
        
        XCTAssertFalse(TerminalPromptExtractor.isDividerLine("echo 'hello-world'"))
        XCTAssertFalse(TerminalPromptExtractor.isDividerLine("git log --oneline -n 5"))
    }

    func testIsStatusLine() {
        XCTAssertTrue(TerminalPromptExtractor.isStatusLine("esc to exit | ctrl+c to cancel"))
        XCTAssertTrue(TerminalPromptExtractor.isStatusLine("150 tokens used (1200 remaining)"))
        XCTAssertTrue(TerminalPromptExtractor.isStatusLine("context window 8192"))
        XCTAssertTrue(TerminalPromptExtractor.isStatusLine("building for debugging..."))
        XCTAssertTrue(TerminalPromptExtractor.isStatusLine("build complete! (took 3.2s)"))
        XCTAssertTrue(TerminalPromptExtractor.isStatusLine("workspace-main = menu"))

        XCTAssertFalse(TerminalPromptExtractor.isStatusLine("git commit -m 'feat: add status'"))
        XCTAssertFalse(TerminalPromptExtractor.isStatusLine("echo 'hello'"))
    }

    func testParseTerminalBufferExtractsCleanCommandsAndOutput() {
        let buffer = """
        Last login: Wed Oct 21 21:00:00 on ttys000
        ─────────────────────────────────────────────
        alex@MacBook:~/Sites$ git status
        On branch main
        nothing to commit, working tree clean
        ─────────────────────────────────────────────
        esc to exit | 240 tokens used
        ❯ ghbdtn
        """
        
        let result = TerminalPromptExtractor.parseTerminalBuffer(buffer)
        
        XCTAssertEqual(result.currentCommand, "ghbdtn")
        XCTAssertTrue(result.recentCommands.contains("git status"))
        XCTAssertTrue(result.cleanedLines.contains("On branch main"))
        XCTAssertFalse(result.cleanedLines.contains(where: { $0.contains("─────") }))
        XCTAssertFalse(result.cleanedLines.contains(where: { $0.contains("tokens used") }))
    }

    func testSplitPaneSlicing() {
        let splitBuffer = """
        │ ❯ git checkout main    │ vim README.md          │
        │ Switched to branch main│ ~                      │
        │ ❯ ghbdtn               │ ~                      │
        """
        
        let result = TerminalPromptExtractor.parseTerminalBuffer(splitBuffer)
        XCTAssertEqual(result.currentCommand, "ghbdtn")
        XCTAssertTrue(result.recentCommands.contains("git checkout main"))
        XCTAssertFalse(result.cleanedLines.contains(where: { $0.contains("vim README.md") }))
    }
}
