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
        XCTAssertTrue(RecommendedAIModel.allModels.contains(where: { $0.id == "llama-3.2-1b" }))
        XCTAssertTrue(RecommendedAIModel.allModels.contains(where: { $0.id == "qwen2.5-coder-1.5b" }))
        XCTAssertTrue(RecommendedAIModel.allModels.contains(where: { $0.id == "smollm2-1.7b" }))
        XCTAssertTrue(RecommendedAIModel.allModels.contains(where: { $0.id == "qwen2.5-1.5b" }))
        XCTAssertTrue(RecommendedAIModel.allModels.contains(where: { $0.id == "gemma-2-2b" }))
        XCTAssertTrue(RecommendedAIModel.allModels.contains(where: { $0.id == "gemma-4-e2b" }))
        let gemma4 = RecommendedAIModel.model(for: "gemma-4-e2b")
        XCTAssertTrue(gemma4.downloadURL.absoluteString.contains("mradermacher/gemma-4-E2B-i1-GGUF"))
        XCTAssertTrue(gemma4.isDefault)
        XCTAssertEqual(RecommendedAIModel.defaultModelID, "gemma-4-e2b")
        XCTAssertTrue(RecommendedAIModel.allModels.contains(where: { $0.id == "qwen2.5-3b" }))
        
        // Fallback for unknown model id
        let fallback = RecommendedAIModel.model(for: "non-existent-model")
        XCTAssertEqual(fallback.id, RecommendedAIModel.defaultModelID)
    }
    
    func testRecommendedAIModelLocalizedSize() {
        let qwen05 = RecommendedAIModel.model(for: "qwen2.5-0.5b")
        let smollm = RecommendedAIModel.model(for: "smollm2-360m")
        let qwen15 = RecommendedAIModel.model(for: "qwen2.5-1.5b")
        let llama = RecommendedAIModel.model(for: "llama-3.2-1b")
        
        // English
        XCTAssertEqual(qwen05.localizedSize(language: "en"), "~390 MB")
        XCTAssertEqual(smollm.localizedSize(language: "en"), "~229 MB")
        XCTAssertEqual(qwen15.localizedSize(language: "en"), "~986 MB")
        XCTAssertEqual(llama.localizedSize(language: "en"), "~770 MB")
        
        // Russian
        XCTAssertEqual(qwen05.localizedSize(language: "ru"), "~390 МБ")
        XCTAssertEqual(smollm.localizedSize(language: "ru"), "~229 МБ")
        XCTAssertEqual(qwen15.localizedSize(language: "ru"), "~986 МБ")
        XCTAssertEqual(llama.localizedSize(language: "ru"), "~770 МБ")
        
        // Download button string formatting with model sizes
        let l10n = LocalizationManager.shared
        l10n.currentLanguage = "ru"
        let ruButtonFormat = l10n.t("ai.model.downloadButton")
        XCTAssertEqual(String(format: ruButtonFormat, smollm.localizedSize(using: l10n)), "Загрузить модель (~229 МБ)")
        XCTAssertEqual(String(format: ruButtonFormat, qwen15.localizedSize(using: l10n)), "Загрузить модель (~986 МБ)")
        XCTAssertEqual(String(format: ruButtonFormat, llama.localizedSize(using: l10n)), "Загрузить модель (~770 МБ)")
        
        l10n.currentLanguage = "en"
        let enButtonFormat = l10n.t("ai.model.downloadButton")
        XCTAssertEqual(String(format: enButtonFormat, smollm.localizedSize(using: l10n)), "Download Model (~229 MB)")
    }
    
    func testSwitchModelUpdatesState() {
        let manager = AIModelManager(modelsDirectory: tempDirectory)
        let smollm = RecommendedAIModel.model(for: "smollm2-360m")
        manager.selectModel(smollm)
        XCTAssertEqual(manager.currentModel.id, "smollm2-360m")
        XCTAssertEqual(SettingsManager.shared.selectedModelId, "smollm2-360m")
    }
    
    func testCustomModelSelectionAndLifecycle() {
        let manager = AIModelManager(modelsDirectory: tempDirectory)
        let customFile = tempDirectory.appendingPathComponent("gemma-4-E2B-Q4_C.gguf")
        var dummyData = Data("GGUF".utf8)
        dummyData.append(Data(count: 15_000_000 - dummyData.count)) // ~15 MB
        FileManager.default.createFile(atPath: customFile.path, contents: dummyData)
        
        manager.selectCustomModel(path: customFile.path)
        XCTAssertEqual(manager.currentModel.id, RecommendedAIModel.customModelID)
        XCTAssertEqual(manager.currentModel.name, "gemma-4-E2B-Q4_C.gguf")
        XCTAssertTrue(manager.currentModel.isCustom)
        XCTAssertEqual(SettingsManager.shared.customModelPath, customFile.path)
        XCTAssertEqual(SettingsManager.shared.selectedModelId, RecommendedAIModel.customModelID)
        XCTAssertTrue(manager.isDownloaded(model: manager.currentModel))
        XCTAssertEqual(manager.activeModelPath, customFile.path)
        XCTAssertTrue(manager.state.isReady)
        
        // Disconnecting / deleting custom model clears path and restores default model
        manager.deleteModel(model: manager.currentModel)
        XCTAssertEqual(SettingsManager.shared.customModelPath, "")
        XCTAssertEqual(manager.currentModel.id, RecommendedAIModel.defaultModelID)
        // Verify user's original custom file on disk was NOT deleted
        XCTAssertTrue(FileManager.default.fileExists(atPath: customFile.path))
    }
    
    func testCustomModelWithNonGGUFContentsIsNotReady() {
        let manager = AIModelManager(modelsDirectory: tempDirectory)
        let file = tempDirectory.appendingPathComponent("private-model.gguf")
        FileManager.default.createFile(atPath: file.path, contents: Data(count: 1_100_000))
        manager.selectCustomModel(path: file.path)
        XCTAssertFalse(manager.state.isReady)
        XCTAssertFalse(manager.isDownloaded(model: manager.currentModel))
        XCTAssertNil(manager.activeModelPath)
        guard case .error = manager.state else { return XCTFail("Invalid GGUF should explain its format error") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
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

    func testDiscoverAndLinkLocalModels() {
        SettingsManager.shared.selectedModelId = "gemma-4-e2b"
        let manager = AIModelManager(modelsDirectory: tempDirectory)
        
        let externalDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CotypistModels_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: externalDir) }
        
        let gemmaFile = externalDir.appendingPathComponent("gemma-4-E2B-i1-Q4_K_M.gguf")
        var dummyData = Data("GGUF".utf8)
        dummyData.append(Data(count: 12_000_000 - dummyData.count))
        FileManager.default.createFile(atPath: gemmaFile.path, contents: dummyData)
        
        // Before discovery: gemma is not in tempDirectory
        let destFile = tempDirectory.appendingPathComponent("gemma-4-E2B-i1-Q4_K_M.gguf")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destFile.path))
        
        // Run discovery targeting externalDir
        let linked = manager.discoverAndLinkLocalModels(sourceDirectories: [externalDir])
        XCTAssertTrue(linked)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destFile.path))
        
        // Calling checkExistingModel should recognize it as ready
        manager.checkExistingModel()
        XCTAssertEqual(SettingsManager.shared.selectedModelId, "gemma-4-e2b")
        XCTAssertEqual(manager.currentModel.id, "gemma-4-e2b")
        XCTAssertTrue(manager.state.isReady)

        // If user manually selects custom model, checkExistingModel does not overwrite it
        SettingsManager.shared.selectedModelId = RecommendedAIModel.customModelID
        manager.checkExistingModel()
        XCTAssertEqual(SettingsManager.shared.selectedModelId, RecommendedAIModel.customModelID)
    }

    func testQwenModelNotOverwrittenByCheckExistingModel() {
        let manager = AIModelManager(modelsDirectory: tempDirectory)
        
        let gemmaFile = tempDirectory.appendingPathComponent("gemma-4-E2B-i1-Q4_K_M.gguf")
        var dummyData = Data("GGUF".utf8)
        dummyData.append(Data(count: 12_000_000 - dummyData.count))
        FileManager.default.createFile(atPath: gemmaFile.path, contents: dummyData)
        
        SettingsManager.shared.selectedModelId = "qwen2.5-0.5b"
        manager.selectModel(RecommendedAIModel.model(for: "qwen2.5-0.5b"))
        
        manager.checkExistingModel()
        XCTAssertEqual(SettingsManager.shared.selectedModelId, "qwen2.5-0.5b")
        XCTAssertEqual(manager.currentModel.id, "qwen2.5-0.5b")
    }

    func testMigrateSelectedModelFromQwenIfGemmaAvailable() {
        let settings = SettingsManager.shared
        settings.hasMigratedDefaultModelToGemma = false
        settings.selectedModelId = "qwen2.5-0.5b"
        
        let fakeGemmaPath = tempDirectory.appendingPathComponent("gemma-4-E2B-i1-Q4_K_M.gguf")
        
        // Without file -> does not migrate
        settings.migrateSelectedModelFromQwenIfGemmaAvailable(candidatePaths: [fakeGemmaPath.path])
        XCTAssertEqual(settings.selectedModelId, "qwen2.5-0.5b")
        XCTAssertFalse(settings.hasMigratedDefaultModelToGemma)
        
        // With file > 10MB -> migrates to gemma-4-e2b and sets flag
        var dummyData = Data("GGUF".utf8)
        dummyData.append(Data(count: 12_000_000 - dummyData.count))
        FileManager.default.createFile(atPath: fakeGemmaPath.path, contents: dummyData)
        
        settings.migrateSelectedModelFromQwenIfGemmaAvailable(candidatePaths: [fakeGemmaPath.path])
        XCTAssertEqual(settings.selectedModelId, "gemma-4-e2b")
        XCTAssertTrue(settings.hasMigratedDefaultModelToGemma)
        
        // User later chooses Qwen -> second migration check does nothing because flag is true
        settings.selectedModelId = "qwen2.5-0.5b"
        settings.migrateSelectedModelFromQwenIfGemmaAvailable(candidatePaths: [fakeGemmaPath.path])
        XCTAssertEqual(settings.selectedModelId, "qwen2.5-0.5b")
    }

    func testDiscoverAndLinkLocalModelsOverwritesBrokenSymlink() {
        let manager = AIModelManager(modelsDirectory: tempDirectory)
        
        let externalDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CotypistModels_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: externalDir) }
        
        let gemmaFile = externalDir.appendingPathComponent("gemma-4-E2B-i1-Q4_K_M.gguf")
        var dummyData = Data("GGUF".utf8)
        dummyData.append(Data(count: 12_000_000 - dummyData.count))
        FileManager.default.createFile(atPath: gemmaFile.path, contents: dummyData)
        
        // Create a broken symlink in tempDirectory pointing to a non-existent path
        let destFile = tempDirectory.appendingPathComponent("gemma-4-E2B-i1-Q4_K_M.gguf")
        let nonExistentTarget = tempDirectory.appendingPathComponent("deleted_target.gguf")
        try? FileManager.default.createSymbolicLink(at: destFile, withDestinationURL: nonExistentTarget)
        
        // fileExists at path returns false because target does not exist
        XCTAssertFalse(FileManager.default.fileExists(atPath: destFile.path))
        
        // Running discovery must safely remove the broken symlink and establish a valid link
        let linked = manager.discoverAndLinkLocalModels(sourceDirectories: [externalDir])
        XCTAssertTrue(linked)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destFile.path))
    }

    func testMigrateAutoCompletionDelayFromOldDefault() {
        let settings = SettingsManager.shared
        // Set old default value 0.035 in defaults and property
        UserDefaults.standard.set(0.035, forKey: "autoCompletionDelay")
        settings.autoCompletionDelay = 0.035
        
        settings.migrateAutoCompletionDelayIfNeeded()
        XCTAssertEqual(settings.autoCompletionDelay, 0.150, accuracy: 0.0001)
        XCTAssertEqual(UserDefaults.standard.double(forKey: "autoCompletionDelay"), 0.150, accuracy: 0.0001)
        
        // Custom value (e.g. 0.250) must not be overwritten
        UserDefaults.standard.set(0.250, forKey: "autoCompletionDelay")
        settings.autoCompletionDelay = 0.250
        settings.migrateAutoCompletionDelayIfNeeded()
        XCTAssertEqual(settings.autoCompletionDelay, 0.250, accuracy: 0.0001)
    }
}
