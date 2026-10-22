import XCTest
@testable import LangSwitcher

@MainActor
final class PerAppAISettingsTests: XCTestCase {
    
    func testAppAISettingsEncodingAndDecoding() throws {
        let original = AppAISettings(
            bundleID: "com.apple.dt.Xcode",
            appName: "Xcode",
            customInstructions: "Use Swift terms and stay concise",
            customVocabulary: ["struct", "enum", "MainActor"],
            isAIEnabled: true
        )
        
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppAISettings.self, from: data)
        
        XCTAssertEqual(decoded.bundleID, "com.apple.dt.Xcode")
        XCTAssertEqual(decoded.appName, "Xcode")
        XCTAssertEqual(decoded.customInstructions, "Use Swift terms and stay concise")
        XCTAssertEqual(decoded.customVocabulary, ["struct", "enum", "MainActor"])
        XCTAssertTrue(decoded.isAIEnabled)
        XCTAssertEqual(original, decoded)
    }
    
    func testSettingsManagerCombinesGlobalAndAppInstructions() {
        let settings = SettingsManager.shared
        let originalGlobal = settings.aiCustomInstructions
        defer { settings.aiCustomInstructions = originalGlobal }
        
        settings.aiCustomInstructions = "Global coder instructions."
        
        let app = AppAISettings(
            bundleID: "test.bundle.slack",
            appName: "Slack",
            customInstructions: "Casual friendly tone.",
            customVocabulary: ["deploy", "PR"],
            isAIEnabled: true
        )
        settings.setAppAISettings(app)
        defer { settings.removeAppAISettings(bundleID: "test.bundle.slack") }
        
        let instructions = settings.aiInstructions(for: "test.bundle.slack")
        XCTAssertTrue(instructions.contains("Global coder instructions."))
        XCTAssertTrue(instructions.contains("Casual friendly tone."))
        XCTAssertTrue(instructions.contains("Preferred terminology: deploy, PR"))
        
        let unknownInstructions = settings.aiInstructions(for: "test.unknown.app")
        XCTAssertEqual(unknownInstructions, "Global coder instructions.")
    }
    
    func testAppDisabledAIOverridesGlobalAllowed() {
        let settings = SettingsManager.shared
        let savedPredictive = settings.aiPredictiveEnabled
        let savedBattery = settings.aiBatteryModeEnabled
        defer {
            settings.aiPredictiveEnabled = savedPredictive
            settings.aiBatteryModeEnabled = savedBattery
        }
        settings.aiPredictiveEnabled = true
        settings.aiBatteryModeEnabled = false

        let app = AppAISettings(
            bundleID: "test.disabled.app",
            appName: "DisabledApp",
            isAIEnabled: false
        )
        settings.setAppAISettings(app)
        defer { settings.removeAppAISettings(bundleID: "test.disabled.app") }
        
        XCTAssertFalse(settings.isAIEnabled(for: "test.disabled.app"))
        XCTAssertTrue(settings.isAIEnabled(for: "com.apple.Safari"))
    }
    
    func testAutocompletionEngineSuggestsAppVocabulary() {
        let settings = SettingsManager.shared
        let app = AppAISettings(
            bundleID: "test.terminal.app",
            appName: "Terminal",
            customVocabulary: ["docker-compose", "kubernetes"]
        )
        settings.setAppAISettings(app)
        defer { settings.removeAppAISettings(bundleID: "test.terminal.app") }
        
        let engine = AutocompletionEngine()
        let usLayout = KeyboardLayout(id: "com.apple.keylayout.US", localizedName: "U.S.", languageCode: "en")
        
        // Query with matching prefix "doc" and app's bundleID
        let suggestionsWithApp = engine.suggest(
            for: "doc",
            activeLayoutID: "com.apple.keylayout.US",
            enabledLayouts: [usLayout],
            bundleID: "test.terminal.app"
        )
        XCTAssertTrue(suggestionsWithApp.contains { $0.word == "docker-compose" })
        XCTAssertEqual(suggestionsWithApp.first?.word, "docker-compose")
        
        // Query without bundleID should not contain custom term
        let suggestionsWithoutApp = engine.suggest(
            for: "doc",
            activeLayoutID: "com.apple.keylayout.US",
            enabledLayouts: [usLayout],
            bundleID: nil
        )
        XCTAssertFalse(suggestionsWithoutApp.contains { $0.word == "docker-compose" })
    }
}
