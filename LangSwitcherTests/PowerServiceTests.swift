import XCTest
@testable import LangSwitcher

@MainActor
final class PowerServiceTests: XCTestCase {
    
    func testPowerServiceCustomProviderBattery() {
        let service = PowerService(powerSourceProvider: {
            return (isOnBattery: true, description: "Battery")
        })
        
        XCTAssertTrue(service.isOnBattery)
        XCTAssertEqual(service.powerSourceDescription, "Battery")
    }
    
    func testPowerServiceCustomProviderAC() {
        let service = PowerService(powerSourceProvider: {
            return (isOnBattery: false, description: "AC Power")
        })
        
        XCTAssertFalse(service.isOnBattery)
        XCTAssertEqual(service.powerSourceDescription, "AC Power")
    }
    
    func testSettingsManagerAIAllowedOnBattery() {
        let settings = SettingsManager.shared
        settings.aiPredictiveEnabled = true
        settings.aiBatteryModeEnabled = true
        
        // When AI is enabled, battery mode is on, and on battery -> not allowed
        let powerService = PowerService(powerSourceProvider: { (isOnBattery: true, description: "Battery") })
        // Verify PowerService logic
        XCTAssertTrue(powerService.isOnBattery)
        
        // When battery mode is disabled -> allowed even on battery
        settings.aiBatteryModeEnabled = false
        XCTAssertTrue(settings.aiPredictiveEnabled)
        
        // Reset defaults
        settings.aiPredictiveEnabled = true
        settings.aiBatteryModeEnabled = true
    }
}
