import XCTest
@testable import LangSwitcher

@MainActor
final class AttentionCenterTests: XCTestCase {

    func testSeverityComparison() {
        XCTAssertTrue(AttentionIssueSeverity.info < AttentionIssueSeverity.warning)
        XCTAssertTrue(AttentionIssueSeverity.warning < AttentionIssueSeverity.critical)
        XCTAssertFalse(AttentionIssueSeverity.critical < AttentionIssueSeverity.info)
    }

    func testRefreshDetectsAccessibilityPermissionIssue() {
        let center = AttentionCenter()
        center.refreshIssues(
            isAccessibilityTrusted: { false },
            isInlinePredictionEnabled: { false },
            hasInstalledModels: { true },
            hasScreenRecordingPermission: { true }
        )

        XCTAssertTrue(center.hasActiveIssues)
        XCTAssertTrue(center.hasWarningOrCriticalIssues)
        XCTAssertEqual(center.maxSeverity, .critical)
        XCTAssertTrue(center.activeIssues.contains { $0.id == .accessibilityPermission })
    }

    func testRefreshDetectsInlinePredictionConflict() {
        let center = AttentionCenter()
        center.refreshIssues(
            isAccessibilityTrusted: { true },
            isInlinePredictionEnabled: { true },
            hasInstalledModels: { true },
            hasScreenRecordingPermission: { true }
        )

        XCTAssertTrue(center.hasActiveIssues)
        XCTAssertEqual(center.maxSeverity, .warning)
        XCTAssertTrue(center.activeIssues.contains { $0.id == .inlinePredictionConflict })
    }

    func testNoActiveIssuesWhenAllHealthy() {
        let center = AttentionCenter()
        let savedAIPredictive = SettingsManager.shared.aiPredictiveEnabled
        let savedScreenContext = SettingsManager.shared.aiScreenContextEnabled
        defer {
            SettingsManager.shared.aiPredictiveEnabled = savedAIPredictive
            SettingsManager.shared.aiScreenContextEnabled = savedScreenContext
        }
        SettingsManager.shared.aiPredictiveEnabled = false
        SettingsManager.shared.aiScreenContextEnabled = false

        center.refreshIssues(
            isAccessibilityTrusted: { true },
            isInlinePredictionEnabled: { false },
            hasInstalledModels: { true },
            hasScreenRecordingPermission: { true }
        )

        XCTAssertFalse(center.hasActiveIssues)
        XCTAssertFalse(center.hasWarningOrCriticalIssues)
        XCTAssertNil(center.maxSeverity)
    }

    func testInlinePredictionManagerPropertyReadDoesNotCrash() {
        _ = InlinePredictionManager.isAutomaticInlinePredictionEnabled
    }
}
