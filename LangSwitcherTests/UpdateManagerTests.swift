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

    func testCheckForUpdatesSafeInTestEnvironment() {
        let manager = UpdateManager.shared
        // In test host environment, this should safely execute without crashing
        manager.checkForUpdates()
    }
}
