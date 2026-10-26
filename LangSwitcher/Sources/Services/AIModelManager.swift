import Foundation

// MARK: - AI Model State

enum AIModelState: Equatable {
    case notDownloaded
    case downloading(progress: Double, bytesWritten: Int64, totalBytes: Int64)
    case ready(modelPath: String, fileSize: Int64)
    case error(message: String)
    
    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
    
    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}

// MARK: - AI Model Manager
// Manages local weights download, storage, status, and deletion for LangSwitcher's AI engine.

@MainActor
final class AIModelManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    
    static let shared = AIModelManager()
    
    static var defaultModelFileName: String {
        RecommendedAIModel.model(for: RecommendedAIModel.defaultModelID).fileName
    }
    
    static var defaultModelName: String {
        RecommendedAIModel.model(for: RecommendedAIModel.defaultModelID).name
    }
    
    @Published private(set) var state: AIModelState = .notDownloaded
    @Published private(set) var downloadSpeed: String = ""
    @Published private(set) var currentModel: RecommendedAIModel = RecommendedAIModel.model(for: RecommendedAIModel.defaultModelID)
    
    private var downloadTask: URLSessionDownloadTask?
    private var urlSession: URLSession?
    private var lastSpeedCheckTime: Date?
    private var lastBytesWritten: Int64 = 0
    private var activeDownloadingModel: RecommendedAIModel?
    
    private let customModelsDirectory: URL?
    
    init(modelsDirectory: URL? = nil) {
        self.customModelsDirectory = modelsDirectory
        super.init()
        discoverAndLinkLocalModels()
        let selectedID = SettingsManager.shared.selectedModelId
        self.currentModel = RecommendedAIModel.model(for: selectedID)
        checkExistingModel()
    }
    
    /// Discovers existing models from local apps (e.g. Cotypist) and links them into Dopishi/Models
    @discardableResult
    func discoverAndLinkLocalModels(sourceDirectories: [URL]? = nil) -> Bool {
        let fileManager = FileManager.default
        let destDir = modelsDirectoryURL
        
        do {
            try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
        } catch {
            NSLog("[LangSwitcher] AIModelManager: failed to create models directory at %@: %@", destDir.path, error.localizedDescription)
            return false
        }
        
        let discoverySourceDirs: [URL]
        if let customSources = sourceDirectories {
            discoverySourceDirs = customSources
        } else if customModelsDirectory == nil, let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            discoverySourceDirs = [
                appSupport.appendingPathComponent("app.cotypist.Cotypist/Models", isDirectory: true),
                appSupport.appendingPathComponent("LangSwitcher/Models", isDirectory: true)
            ]
        } else {
            discoverySourceDirs = []
        }
        
        var linkedAny = false
        
        for sourceDir in discoverySourceDirs {
            guard fileManager.fileExists(atPath: sourceDir.path) else { continue }
            
            for model in RecommendedAIModel.allModels {
                guard model.id != RecommendedAIModel.customModelID else { continue }
                let sourceFile = sourceDir.appendingPathComponent(model.fileName)
                let destFile = destDir.appendingPathComponent(model.fileName)
                
                // If destination already exists, no need to link
                if fileManager.fileExists(atPath: destFile.path) {
                    continue
                }
                
                // Check if source file exists, is valid GGUF and has sufficient size
                guard fileManager.fileExists(atPath: sourceFile.path),
                      Self.hasGGUFHeader(at: sourceFile.path),
                      let size = Self.fileSize(at: sourceFile.path), size > 10_000_000 else {
                    continue
                }
                
                // Try creating symbolic link first (remove stale/broken symlink if present to prevent EEXIST)
                try? fileManager.removeItem(at: destFile)
                do {
                    try fileManager.createSymbolicLink(at: destFile, withDestinationURL: sourceFile)
                    NSLog("[LangSwitcher] AIModelManager: linked model %@ from %@", model.fileName, sourceFile.path)
                    linkedAny = true
                } catch {
                    NSLog("[LangSwitcher] AIModelManager: symlink failed (%@), attempting copy...", error.localizedDescription)
                    do {
                        try fileManager.copyItem(at: sourceFile, to: destFile)
                        NSLog("[LangSwitcher] AIModelManager: copied model %@ from %@", model.fileName, sourceFile.path)
                        linkedAny = true
                    } catch {
                        NSLog("[LangSwitcher] AIModelManager: failed to copy model %@: %@", model.fileName, error.localizedDescription)
                    }
                }
            }
        }
        
        return linkedAny
    }
    
    nonisolated var modelsDirectoryURL: URL {
        if let custom = customModelsDirectory {
            return custom
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Dopishi/Models", isDirectory: true)
        let legacyDir = appSupport.appendingPathComponent("LangSwitcher/Models", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) && FileManager.default.fileExists(atPath: legacyDir.path) {
            try? FileManager.default.copyItem(at: legacyDir, to: dir)
        }
        return dir
    }
    
    nonisolated func modelFileURL(for model: RecommendedAIModel) -> URL {
        if model.id == RecommendedAIModel.customModelID {
            return URL(fileURLWithPath: model.fileName)
        }
        return modelsDirectoryURL.appendingPathComponent(model.fileName)
    }
    
    var modelFileURL: URL {
        let selectedID = SettingsManager.shared.selectedModelId
        let model = RecommendedAIModel.model(for: selectedID)
        return modelFileURL(for: model)
    }
    
    /// A .gguf extension alone does not establish compatibility (some apps
    /// store private/encrypted model data under that extension).
    nonisolated static func hasGGUFHeader(at path: String) -> Bool {
        guard let file = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? file.close() }
        return (try? file.read(upToCount: 4)) == Data("GGUF".utf8)
    }

    /// Resolves symlinks and returns the size of the target file
    nonisolated static func fileSize(at path: String) -> Int64? {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: resolved) else { return nil }
        return attrs[.size] as? Int64
    }

    /// Switch active model
    func selectModel(_ model: RecommendedAIModel) {
        currentModel = model
        SettingsManager.shared.selectedModelId = model.id
        checkExistingModel()
    }
    
    /// Select user's custom local GGUF file
    func selectCustomModel(path: String) {
        SettingsManager.shared.customModelPath = path
        let custom = RecommendedAIModel.customModel(for: path)
        selectModel(custom)
    }
    
    /// Path to current active model if downloaded and ready, taking into account adaptive battery policy
    var activeModelPath: String? {
        let targetModel = BatteryPowerManager.shared.effectiveModel(standardModel: currentModel)
        if targetModel.id == currentModel.id {
            if case .ready(let path, _) = state {
                return path
            }
            return modelPath(for: currentModel)
        }
        return modelPath(for: targetModel) ?? modelPath(for: currentModel)
    }
    
    /// Candidate paths on disk to search for model weights
    private func candidatePaths(for model: RecommendedAIModel) -> [String] {
        if model.id == RecommendedAIModel.customModelID {
            let custom = SettingsManager.shared.customModelPath
            return custom.isEmpty ? [] : [custom]
        }
        var paths = [modelFileURL(for: model).path]
        if customModelsDirectory == nil {
            let cwdPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("models/\(model.fileName)").path
            paths.append(cwdPath)
            
            // Auto-detect existing local model from legacy LangSwitcher, Cotypist or common local model caches
            if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let legacyPath = appSupport.appendingPathComponent("LangSwitcher/Models/\(model.fileName)").path
                paths.append(legacyPath)
                let cotypistPath = appSupport.appendingPathComponent("app.cotypist.Cotypist/Models/\(model.fileName)").path
                paths.append(cotypistPath)
            }
        }
        return paths
    }

    /// Check whether a specific model is already downloaded or accessible
    func isDownloaded(model: RecommendedAIModel) -> Bool {
        let fileManager = FileManager.default
        let standardPath = modelFileURL(for: model).path
        if fileManager.fileExists(atPath: standardPath),
           let size = Self.fileSize(at: standardPath), size > (model.id == RecommendedAIModel.customModelID ? 1_000_000 : 10_000_000) {
            return model.id == RecommendedAIModel.customModelID ? Self.hasGGUFHeader(at: standardPath) : true
        }
        for path in candidatePaths(for: model) {
            if path != standardPath, fileManager.fileExists(atPath: path),
               Self.hasGGUFHeader(at: path),
               let size = Self.fileSize(at: path), size > 10_000_000 {
                return true
            }
        }
        return false
    }
    
    /// Get path to downloaded model file if available
    func modelPath(for model: RecommendedAIModel) -> String? {
        let fileManager = FileManager.default
        let standardPath = modelFileURL(for: model).path
        if fileManager.fileExists(atPath: standardPath) {
            if model.id == RecommendedAIModel.customModelID {
                return Self.hasGGUFHeader(at: standardPath) ? standardPath : nil
            }
            return standardPath
        }
        for path in candidatePaths(for: model) {
            if path != standardPath, fileManager.fileExists(atPath: path), Self.hasGGUFHeader(at: path) {
                return path
            }
        }
        return nil
    }
    
    /// Check whether the active model file exists on disk
    func checkExistingModel() {
        let fileManager = FileManager.default
        discoverAndLinkLocalModels()
        if currentModel.id != SettingsManager.shared.selectedModelId {
            self.currentModel = RecommendedAIModel.model(for: SettingsManager.shared.selectedModelId)
        }
        
        if currentModel.id == RecommendedAIModel.customModelID {
            let customPath = SettingsManager.shared.customModelPath
            if !customPath.isEmpty && fileManager.fileExists(atPath: customPath) {
                guard Self.hasGGUFHeader(at: customPath) else {
                    self.state = .error(message: LocalizationManager.shared.t("ai.model.invalidGGUF"))
                    return
                }
                if let size = Self.fileSize(at: customPath), size > 1_000_000 {
                    self.state = .ready(modelPath: customPath, fileSize: size)
                    return
                }
            }
            self.state = .notDownloaded
            return
        }
        
        let targetURL = modelFileURL(for: currentModel)
        
        // 1. Check primary Application Support path
        if fileManager.fileExists(atPath: targetURL.path) {
            if let size = Self.fileSize(at: targetURL.path), size > 10_000_000 {
                self.state = .ready(modelPath: targetURL.path, fileSize: size)
                return
            }
        }
        
        // 2. Check candidate paths (workspace models/ folder, Cotypist, other local caches)
        for path in candidatePaths(for: currentModel) {
            if path != targetURL.path, fileManager.fileExists(atPath: path),
               Self.hasGGUFHeader(at: path),
               let size = Self.fileSize(at: path), size > 10_000_000 {
                self.state = .ready(modelPath: path, fileSize: size)
                return
            }
        }
        
        if case .downloading = state {
            return
        }
        self.state = .notDownloaded
    }
    
    /// Start 1-click download of the model weights
    func startDownload(model: RecommendedAIModel? = nil) {
        let targetModel = model ?? currentModel
        guard targetModel.id != RecommendedAIModel.customModelID else { return }
        if targetModel.id != currentModel.id {
            selectModel(targetModel)
        }
        guard !state.isDownloading else { return }
        
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)
        } catch {
            self.state = .error(message: error.localizedDescription)
            return
        }
        
        self.activeDownloadingModel = targetModel
        self.state = .downloading(progress: 0.0, bytesWritten: 0, totalBytes: targetModel.estimatedSizeBytes)
        self.downloadSpeed = ""
        self.lastSpeedCheckTime = Date()
        self.lastBytesWritten = 0
        
        downloadTask?.cancel()
        downloadTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.urlSession = session
        
        let task = session.downloadTask(with: targetModel.downloadURL)
        task.taskDescription = targetModel.id
        self.downloadTask = task
        task.resume()
    }
    
    /// Cancel in-progress download
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        activeDownloadingModel = nil
        checkExistingModel()
    }
    
    /// Delete downloaded model weights or disconnect custom model
    func deleteModel(model: RecommendedAIModel? = nil) {
        let targetModel = model ?? currentModel
        if targetModel.id == RecommendedAIModel.customModelID {
            let path = SettingsManager.shared.customModelPath
            if AIInferenceEngine.shared.currentLoadedModelPath == path {
                AIInferenceEngine.shared.stop()
            }
            SettingsManager.shared.customModelPath = ""
            selectModel(RecommendedAIModel.model(for: RecommendedAIModel.defaultModelID))
            return
        }
        let path = modelFileURL(for: targetModel).path
        if AIInferenceEngine.shared.currentLoadedModelPath == path {
            AIInferenceEngine.shared.stop()
        }
        cancelDownload()
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: path) {
            try? fileManager.removeItem(atPath: path)
        }
        if targetModel.id == currentModel.id {
            self.state = .notDownloaded
        }
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let modelID = downloadTask.taskDescription ?? RecommendedAIModel.defaultModelID
        let fallbackSize = RecommendedAIModel.model(for: modelID).estimatedSizeBytes
        
        Task { @MainActor in
            let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : fallbackSize
            let progress = min(1.0, max(0.0, Double(totalBytesWritten) / Double(expected)))
            
            guard self.state.isDownloading else { return }
            self.state = .downloading(progress: progress, bytesWritten: totalBytesWritten, totalBytes: expected)
            
            let now = Date()
            if let lastTime = self.lastSpeedCheckTime, now.timeIntervalSince(lastTime) >= 1.0 {
                let interval = now.timeIntervalSince(lastTime)
                let bytesInInterval = totalBytesWritten - self.lastBytesWritten
                let bytesPerSec = Double(bytesInInterval) / interval
                let mbPerSec = bytesPerSec / (1024 * 1024)
                self.downloadSpeed = String(format: "%.1f MB/s", mbPerSec)
                self.lastSpeedCheckTime = now
                self.lastBytesWritten = totalBytesWritten
            }
        }
    }
    
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let fileManager = FileManager.default
        let modelID = downloadTask.taskDescription ?? RecommendedAIModel.defaultModelID
        let model = RecommendedAIModel.model(for: modelID)
        let destination = self.modelFileURL(for: model)
        var moveError: Error?
        let destURL: URL = destination
        
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: location, to: destination)
        } catch {
            moveError = error
        }
        
        session.finishTasksAndInvalidate()
        Task { @MainActor in
            self.activeDownloadingModel = nil
            self.downloadTask = nil
            if self.urlSession === session {
                self.urlSession = nil
            }
            if let error = moveError {
                self.state = .error(message: error.localizedDescription)
            } else {
                self.checkExistingModel()
                // Warm up engine as soon as download finishes
                _ = await AIInferenceEngine.shared.start(modelPath: destURL.path)
            }
        }
    }
    
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            session.finishTasksAndInvalidate()
            Task { @MainActor in
                self.activeDownloadingModel = nil
                self.downloadTask = nil
                if self.urlSession === session {
                    self.urlSession = nil
                }
                let nsError = error as NSError
                if nsError.code != NSURLErrorCancelled {
                    self.state = .error(message: error.localizedDescription)
                }
            }
        }
    }
}
