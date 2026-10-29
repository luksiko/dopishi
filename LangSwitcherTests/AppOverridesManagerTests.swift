import XCTest
@testable import LangSwitcher

@MainActor
final class AppOverridesManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clear test entries
        SettingsManager.shared.removeAppAISettings(bundleID: "test.dev.ide")
        SettingsManager.shared.removeAppAISettings(bundleID: "test.game.fps")
        SettingsManager.shared.removeAppAISettings(bundleID: "test.regular.app")
    }

    override func tearDown() {
        SettingsManager.shared.removeAppAISettings(bundleID: "test.dev.ide")
        SettingsManager.shared.removeAppAISettings(bundleID: "test.game.fps")
        SettingsManager.shared.removeAppAISettings(bundleID: "test.regular.app")
        super.tearDown()
    }

    func testDefaultCompletionModeForRegularAppIsAutomatic() {
        let manager = AppOverridesManager.shared
        XCTAssertEqual(manager.completionMode(for: "test.regular.app"), .automatic)
        XCTAssertTrue(manager.shouldAutoTrigger(for: "test.regular.app"))
        XCTAssertTrue(manager.isAllowed(for: "test.regular.app", isManualTrigger: false))
        XCTAssertTrue(manager.isAllowed(for: "test.regular.app", isManualTrigger: true))
    }

    func testKnownGamingAppsAreDisabledByDefault() {
        let manager = AppOverridesManager.shared
        let steamBundleID = "com.valvesoftware.steam"
        XCTAssertTrue(manager.isGamingOrVirtualizationApp(bundleID: steamBundleID))
        XCTAssertEqual(manager.completionMode(for: steamBundleID), .disabled)
        XCTAssertFalse(manager.shouldAutoTrigger(for: steamBundleID))
        XCTAssertFalse(manager.isAllowed(for: steamBundleID, isManualTrigger: false))
        XCTAssertFalse(manager.isAllowed(for: steamBundleID, isManualTrigger: true))
    }

    func testKnownDevelopmentAppsRecognition() {
        let manager = AppOverridesManager.shared
        XCTAssertTrue(manager.isDevelopmentApp(bundleID: "com.apple.dt.Xcode"))
        XCTAssertTrue(manager.isDevelopmentApp(bundleID: "com.microsoft.VSCode"))
        XCTAssertTrue(manager.isDevelopmentApp(bundleID: "com.todesktop.230313mzl4w4u92"))
        XCTAssertTrue(manager.isDevelopmentApp(bundleID: "com.jetbrains.intellij"))
        XCTAssertFalse(manager.isDevelopmentApp(bundleID: "com.apple.Safari"))
    }

    func testUserCanOverrideAppToManualOnly() {
        let manager = AppOverridesManager.shared
        let bundleID = "test.dev.ide"

        manager.setCompletionMode(.manualOnly, for: bundleID, appName: "TestIDE")

        XCTAssertEqual(manager.completionMode(for: bundleID), .manualOnly)
        // Automatic background typing debounce must NOT trigger
        XCTAssertFalse(manager.shouldAutoTrigger(for: bundleID))
        XCTAssertFalse(manager.isAllowed(for: bundleID, isManualTrigger: false))
        // Explicit manual shortcut invocation MUST be allowed
        XCTAssertTrue(manager.isAllowed(for: bundleID, isManualTrigger: true))
    }

    func testUserCanOverrideAppToDisabled() {
        let manager = AppOverridesManager.shared
        let bundleID = "test.game.fps"

        manager.setCompletionMode(.disabled, for: bundleID, appName: "Game")

        XCTAssertEqual(manager.completionMode(for: bundleID), .disabled)
        XCTAssertFalse(manager.shouldAutoTrigger(for: bundleID))
        XCTAssertFalse(manager.isAllowed(for: bundleID, isManualTrigger: false))
        XCTAssertFalse(manager.isAllowed(for: bundleID, isManualTrigger: true))
    }

    func testUserCanReenableGamingAppToAutomatic() {
        let manager = AppOverridesManager.shared
        let steam = "com.valvesoftware.steam"

        // Default: disabled
        XCTAssertEqual(manager.completionMode(for: steam), .disabled)

        // Explicit user override: automatic
        manager.setCompletionMode(.automatic, for: steam, appName: "Steam")
        defer { SettingsManager.shared.removeAppAISettings(bundleID: steam) }

        XCTAssertEqual(manager.completionMode(for: steam), .automatic)
        XCTAssertTrue(manager.shouldAutoTrigger(for: steam))
        XCTAssertTrue(manager.isAllowed(for: steam, isManualTrigger: false))
    }

    func testNilOrEmptyBundleIDDefaultsToAutomatic() {
        let manager = AppOverridesManager.shared
        XCTAssertEqual(manager.completionMode(for: nil), .automatic)
        XCTAssertEqual(manager.completionMode(for: ""), .automatic)
        XCTAssertTrue(manager.shouldAutoTrigger(for: nil))
        XCTAssertTrue(manager.isAllowed(for: nil, isManualTrigger: false))
    }
}
