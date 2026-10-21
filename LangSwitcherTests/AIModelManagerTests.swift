import XCTest
@testable import LangSwitcher

@MainActor
final class AIModelManagerTests: XCTestCase {
    
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        SettingsManager.shared.selectedModelId = RecommendedAIModel.defaultModelID
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LangSwitcherModelTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        SettingsManager.shared.selectedModelId = RecommendedAIModel.defaultModelID
        if let temp = tempDirectory {
            try? FileManager.default.removeItem(at: temp)
        }
        super.tearDown()
    }
    
    func testModelNotDownloadedInitiallyInEmptyDir() {
        let manager = AIModelManager(modelsDirectory: tempDirectory)
        XCTAssertEqual(manager.state, .notDownloaded)
        XCTAssertFalse(manager.state.isReady)
        XCTAssertFalse(manager.state.isDownloading)
    }
    
    func testModelDetectedWhenFileExists() {
        let modelFile = tempDirectory.appendingPathComponent(AIModelManager.defaultModelFileName)
        // Create dummy file > 10MB
        let dummyData = Data(count: 11_000_000)
        FileManager.default.createFile(atPath: modelFile.path, contents: dummyData)
        
        let manager = AIModelManager(modelsDirectory: tempDirectory)
        XCTAssertTrue(manager.state.isReady)
        if case .ready(let path, let size) = manager.state {
            XCTAssertEqual(path, modelFile.path)
            XCTAssertEqual(size, 11_000_000)
        } else {
            XCTFail("Expected ready state")
        }
    }
    
    func testDeleteModelRemovesFile() {
        let modelFile = tempDirectory.appendingPathComponent(AIModelManager.defaultModelFileName)
        let dummyData = Data(count: 11_000_000)
        FileManager.default.createFile(atPath: modelFile.path, contents: dummyData)
        
        let manager = AIModelManager(modelsDirectory: tempDirectory)
        XCTAssertTrue(manager.state.isReady)
        
        manager.deleteModel()
        XCTAssertEqual(manager.state, .notDownloaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: modelFile.path))
    }
    
    func testRecommendedAIModelCatalog() {
        XCTAssertFalse(RecommendedAIModel.allModels.isEmpty)
        XCTAssertTrue(RecommendedAIModel.allModels.contains(where: { $0.id == "qwen2.5-0.5b" }))
        XCTAssertTrue(RecommendedAIModel.allModels.contains(where: { $0.id == "smollm2-360m" }))
        XCTAssertTrue(RecommendedAIModel.allModels.contains(where: { $0.id == "qwen2.5-1.5b" }))
        XCTAssertTrue(RecommendedAIModel.allModels.contains(where: { $0.id == "llama-3.2-1b" }))
        
        // Fallback for unknown model id
        let fallback = RecommendedAIModel.model(for: "non-existent-model")
        XCTAssertEqual(fallback.id, RecommendedAIModel.defaultModelID)
    }
    
    func testSwitchModelUpdatesState() {
        let manager = AIModelManager(modelsDirectory: tempDirectory)
        let smollm = RecommendedAIModel.model(for: "smollm2-360m")
        manager.selectModel(smollm)
        XCTAssertEqual(manager.currentModel.id, "smollm2-360m")
        XCTAssertEqual(SettingsManager.shared.selectedModelId, "smollm2-360m")
    }
    
    func testExtendedStatisticsTracking() {
        let settings = SettingsManager.shared
        settings.resetStatistics()
        XCTAssertEqual(settings.savedCharactersCount, 0)
        XCTAssertEqual(settings.savedClicksCount, 0)
        
        // Simulate autocomplete candidate accept: 15 chars inserted, 3 typed
        settings.recordSavedText(inserted: 15, typed: 3)
        XCTAssertEqual(settings.savedCharactersCount, 12)
        XCTAssertEqual(settings.savedClicksCount, 12)
        
        // Simulate autocorrection: 5 chars word corrected
        settings.recordAutoCorrection(charCount: 5)
        XCTAssertEqual(settings.savedCharactersCount, 17)
        XCTAssertEqual(settings.savedClicksCount, 22) // 12 + 5*2
        
        settings.resetStatistics()
        XCTAssertEqual(settings.savedCharactersCount, 0)
        XCTAssertEqual(settings.savedClicksCount, 0)
    }
}
