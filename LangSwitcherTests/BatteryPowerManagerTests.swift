import XCTest
@testable import LangSwitcher

@MainActor
final class BatteryPowerManagerTests: XCTestCase {

    func testDebounceCalculationOnACPower() {
        let manager = BatteryPowerManager()
        manager.batteryStateOverride = false
        manager.lowPowerModeOverride = false

        for policy in BatteryPowerPolicy.allCases {
            let delay = manager.effectiveDebounceDelay(
                baseDelay: 0.150,
                isOnBattery: false,
                isLowPower: false,
                policy: policy
            )
            XCTAssertEqual(delay, 0.150, accuracy: 0.001)
        }
    }

    func testDebounceCalculationOnBatteryPower() {
        let manager = BatteryPowerManager()
        manager.batteryStateOverride = true
        manager.lowPowerModeOverride = false

        let ecoDelay = manager.effectiveDebounceDelay(
            baseDelay: 0.150,
            isOnBattery: true,
            isLowPower: false,
            policy: .adaptiveEco
        )
        XCTAssertEqual(ecoDelay, 0.350, accuracy: 0.001)

        let throttleDelay = manager.effectiveDebounceDelay(
            baseDelay: 0.150,
            isOnBattery: true,
            isLowPower: false,
            policy: .throttleOnly
        )
        XCTAssertEqual(throttleDelay, 0.350, accuracy: 0.001)

        let unresDelay = manager.effectiveDebounceDelay(
            baseDelay: 0.150,
            isOnBattery: true,
            isLowPower: false,
            policy: .unrestricted
        )
        XCTAssertEqual(unresDelay, 0.150, accuracy: 0.001)
    }

    func testLowPowerModeForcesDebounceThrottle() {
        let manager = BatteryPowerManager()
        manager.batteryStateOverride = false
        manager.lowPowerModeOverride = true

        let delay = manager.effectiveDebounceDelay(
            baseDelay: 0.120,
            isOnBattery: false,
            isLowPower: true,
            policy: .unrestricted
        )
        XCTAssertEqual(delay, 0.350, accuracy: 0.001)
    }

    func testShouldUseEcoModel() {
        let manager = BatteryPowerManager()
        let largerModel = RecommendedAIModel.allModels.first(where: { $0.id != "qwen2.5-0.5b" })!
        let qwen05 = RecommendedAIModel.allModels.first(where: { $0.id == "qwen2.5-0.5b" })!

        // On battery with adaptiveEco -> downgrade larger model to eco model
        XCTAssertTrue(manager.shouldUseEcoModel(currentModel: largerModel, isOnBattery: true, policy: .adaptiveEco))
        // Already smallest -> do not downgrade
        XCTAssertFalse(manager.shouldUseEcoModel(currentModel: qwen05, isOnBattery: true, policy: .adaptiveEco))
        // On AC -> do not downgrade
        XCTAssertFalse(manager.shouldUseEcoModel(currentModel: largerModel, isOnBattery: false, policy: .adaptiveEco))
        // Policy is throttleOnly -> do not downgrade
        XCTAssertFalse(manager.shouldUseEcoModel(currentModel: largerModel, isOnBattery: true, policy: .throttleOnly))
    }

    func testSettingsManagerIsAIAllowedWithPolicies() {
        let settings = SettingsManager.shared
        let savedEnabled = settings.aiPredictiveEnabled
        let savedBatteryMode = settings.aiBatteryModeEnabled
        let savedPolicy = settings.aiBatteryPolicy

        defer {
            settings.aiPredictiveEnabled = savedEnabled
            settings.aiBatteryModeEnabled = savedBatteryMode
            settings.aiBatteryPolicy = savedPolicy
        }

        settings.aiPredictiveEnabled = true
        settings.aiBatteryModeEnabled = true

        // When policy is .adaptiveEco -> AI is allowed
        settings.aiBatteryPolicy = .adaptiveEco
        XCTAssertTrue(settings.isAIAllowed)

        // When policy is .throttleOnly -> AI is allowed
        settings.aiBatteryPolicy = .throttleOnly
        XCTAssertTrue(settings.isAIAllowed)

        // When policy is .unrestricted -> AI is allowed
        settings.aiBatteryPolicy = .unrestricted
        XCTAssertTrue(settings.isAIAllowed)
    }
}
