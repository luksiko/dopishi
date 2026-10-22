import XCTest
@testable import LangSwitcher

@MainActor
final class EditorFontCustomizerTests: XCTestCase {

    func testParseGhosttyConfigStandard() {
        let config = """
        # Ghostty configuration
        font-family = "JetBrains Mono"
        font-size = 15.5
        cursor-style = bar
        """
        let parsed = EditorFontCustomizer.parseGhosttyConfig(content: config)
        XCTAssertEqual(parsed.family, "JetBrains Mono")
        XCTAssertEqual(parsed.size, 15.5)
    }

    func testParseGhosttyConfigUnquotedAndSingleQuoted() {
        let config = """
        font-family = 'Fira Code'
        font-size = 14
        """
        let parsed = EditorFontCustomizer.parseGhosttyConfig(content: config)
        XCTAssertEqual(parsed.family, "Fira Code")
        XCTAssertEqual(parsed.size, 14.0)
    }

    func testParseGhosttyConfigEmpty() {
        let parsed = EditorFontCustomizer.parseGhosttyConfig(content: "# only comments\n\n")
        XCTAssertNil(parsed.family)
        XCTAssertNil(parsed.size)
    }

    func testParseVSCodeSettingsStandard() {
        let json = """
        {
            "editor.fontFamily": "'JetBrains Mono', Menlo, Monaco, monospace",
            "editor.fontSize": 14,
            "editor.tabSize": 4
        }
        """
        let parsed = EditorFontCustomizer.parseVSCodeSettings(jsonString: json)
        XCTAssertEqual(parsed.family, "JetBrains Mono")
        XCTAssertEqual(parsed.size, 14.0)
    }

    func testParseVSCodeSettingsWithComments() {
        let json = """
        {
            // My coding font
            "editor.fontFamily": "Fira Code, monospace",
            /* Font size setting */
            "editor.fontSize": 16.0
        }
        """
        let parsed = EditorFontCustomizer.parseVSCodeSettings(jsonString: json)
        XCTAssertEqual(parsed.family, "Fira Code")
        XCTAssertEqual(parsed.size, 16.0)
    }

    func testParseITermFontString() {
        let res1 = EditorFontCustomizer.parseITermFontString("JetBrainsMono-Regular 14")
        XCTAssertEqual(res1.family, "JetBrainsMono")
        XCTAssertEqual(res1.size, 14.0)

        let res2 = EditorFontCustomizer.parseITermFontString("Monaco 12")
        XCTAssertEqual(res2.family, "Monaco")
        XCTAssertEqual(res2.size, 12.0)
    }

    func testFontResolutionForGhosttyWithOverride() {
        let customizer = EditorFontCustomizer()
        customizer.ghosttyConfigOverride = """
        font-family = "Menlo"
        font-size = 13.0
        """

        let font = customizer.font(for: "com.mitchellh.ghostty", caretHeight: 18.0)
        XCTAssertNotNil(font)
        XCTAssertEqual(font?.pointSize, 13.0)
    }

    func testFontResolutionForVSCodeWithOverride() {
        let customizer = EditorFontCustomizer()
        customizer.vscodeSettingsOverride = """
        {
            "editor.fontFamily": "Menlo",
            "editor.fontSize": 15
        }
        """

        let font = customizer.font(for: "com.microsoft.VSCode", caretHeight: 20.0)
        XCTAssertNotNil(font)
        XCTAssertEqual(font?.pointSize, 15.0)
    }

    func testFontResolutionForUnknownAppReturnsNil() {
        let customizer = EditorFontCustomizer()
        let font = customizer.font(for: "com.unknown.calculator", caretHeight: 20.0)
        XCTAssertNil(font)
    }
}
