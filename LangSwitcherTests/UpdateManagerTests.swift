import XCTest
@testable import LangSwitcher

@MainActor
final class UpdateManagerTests: XCTestCase {

    func testUpdateManagerInitialState() {
        let manager = UpdateManager.shared
        XCTAssertNotNil(manager)
        // Automatically checks for updates should be true by default
        XCTAssertTrue(manager.automaticallyChecksForUpdates)
    }

    func testToggleAutomaticallyChecksForUpdates() {
        let manager = UpdateManager.shared
        let original = manager.automaticallyChecksForUpdates
        manager.automaticallyChecksForUpdates = false
        XCTAssertFalse(manager.automaticallyChecksForUpdates)
        manager.automaticallyChecksForUpdates = original
        XCTAssertEqual(manager.automaticallyChecksForUpdates, original)
    }

    func testToggleAutomaticallyDownloadsUpdates() {
        let manager = UpdateManager.shared
        let original = manager.automaticallyDownloadsUpdates
        manager.automaticallyDownloadsUpdates = false
        XCTAssertFalse(manager.automaticallyDownloadsUpdates)
        manager.automaticallyDownloadsUpdates = original
        XCTAssertEqual(manager.automaticallyDownloadsUpdates, original)
    }

    func testCheckForUpdatesSafeInTestEnvironment() {
        let manager = UpdateManager.shared
        // In test host environment, this should safely execute without crashing
        manager.checkForUpdates()
        manager.refreshStatus()
    }
}

@MainActor
final class LaunchAtLoginHelperTests: XCTestCase {

    func testLaunchAtLoginHelperStatusQuery() {
        // Should query without crashing in test environment
        _ = LaunchAtLoginHelper.isEnabled
        _ = LaunchAtLoginHelper.requiresApproval
        _ = LaunchAtLoginHelper.status
    }

    func testSettingsManagerLaunchAtLoginToggle() {
        let settings = SettingsManager.shared
        let original = settings.launchAtLogin
        defer {
            settings.launchAtLogin = original
        }

        settings.launchAtLogin = true
        XCTAssertTrue(settings.launchAtLogin)
        settings.launchAtLogin = false
        XCTAssertFalse(settings.launchAtLogin)
    }

    func testLaunchAtLoginSyncStatusSafeInTestEnvironment() {
        // Safe to call syncStatus without throwing or crashing
        LaunchAtLoginHelper.syncStatus(preferenceEnabled: false)
        LaunchAtLoginHelper.syncStatus(preferenceEnabled: true)
    }
}
