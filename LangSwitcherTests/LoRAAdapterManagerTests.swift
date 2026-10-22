import XCTest
@testable import LangSwitcher

@MainActor
final class LoRAAdapterManagerTests: XCTestCase {

    func testBuiltInAdapters() {
        let manager = LoRAAdapterManager.shared
        XCTAssertFalse(manager.builtInAdapters.isEmpty)
        XCTAssertTrue(manager.builtInAdapters.contains(where: { $0.id == "engineering" }))
        XCTAssertTrue(manager.builtInAdapters.contains(where: { $0.id == "legal" }))
        XCTAssertTrue(manager.builtInAdapters.contains(where: { $0.id == "casual" }))
    }

    func testPersonaPromptGeneration() {
        let manager = LoRAAdapterManager.shared
        manager.activeAdapterId = "engineering"

        let ruPrompt = manager.personaPrompt(for: true)
        XCTAssertNotNil(ruPrompt)
        XCTAssertTrue(ruPrompt!.contains("Разработка ПО"))

        let enPrompt = manager.personaPrompt(for: false)
        XCTAssertNotNil(enPrompt)
        XCTAssertTrue(enPrompt!.contains("Software Engineering"))
    }

    func testEffectiveTemperature() {
        let manager = LoRAAdapterManager.shared
        manager.activeAdapterId = "legal"
        XCTAssertEqual(manager.effectiveTemperature(), 0.15, accuracy: 0.01)

        manager.activeAdapterId = "casual"
        XCTAssertEqual(manager.effectiveTemperature(), 0.6, accuracy: 0.01)
    }

    func testCustomAdapterLifecycle() {
        let manager = LoRAAdapterManager.shared
        let custom = LoRAAdapterDescriptor(
            id: "medical_test",
            name: "Medical Clinic",
            icon: "cross.fill",
            systemPromptRu: "Медицинская терминология",
            systemPromptEn: "Medical terminology",
            temperature: 0.1
        )

        manager.addCustomAdapter(custom)
        XCTAssertTrue(manager.allAdapters.contains(where: { $0.id == "medical_test" }))

        manager.activeAdapterId = "medical_test"
        XCTAssertEqual(manager.activeAdapter?.name, "Medical Clinic")

        manager.removeCustomAdapter(id: "medical_test")
        XCTAssertFalse(manager.allAdapters.contains(where: { $0.id == "medical_test" }))
    }
}
