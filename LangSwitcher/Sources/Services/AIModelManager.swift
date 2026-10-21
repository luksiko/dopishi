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
        RecommendedAIModel.allModels[0].fileName
    }
    
    static var defaultModelName: String {
        RecommendedAIModel.allModels[0].name
    }
    
    @Published private(set) var state: AIModelState = .notDownloaded
    @Published private(set) var downloadSpeed: String = ""
    @Published private(set) var currentModel: RecommendedAIModel = RecommendedAIModel.allModels[0]
    
    private var downloadTask: URLSessionDownloadTask?
    private var urlSession: URLSession?
    private var lastSpeedCheckTime: Date?
    private var lastBytesWritten: Int64 = 0
    private var activeDownloadingModel: RecommendedAIModel?
    
    private let customModelsDirectory: URL?
    
    init(modelsDirectory: URL? = nil) {
        self.customModelsDirectory = modelsDirectory
        super.init()
        let selectedID = SettingsManager.shared.selectedModelId
        self.currentModel = RecommendedAIModel.model(for: selectedID)
        checkExistingModel()
    }
    
    nonisolated var modelsDirectoryURL: URL {
        if let custom = customModelsDirectory {
            return custom
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("LangSwitcher/Models", isDirectory: true)
    }
    
    nonisolated func modelFileURL(for model: RecommendedAIModel) -> URL {
        modelsDirectoryURL.appendingPathComponent(model.fileName)
    }
    
    var modelFileURL: URL {
        let selectedID = SettingsManager.shared.selectedModelId
        let model = RecommendedAIModel.model(for: selectedID)
        return modelFileURL(for: model)
    }
    
    /// Switch active model
    func selectModel(_ model: RecommendedAIModel) {
        currentModel = model
        SettingsManager.shared.selectedModelId = model.id
        checkExistingModel()
    }
    
    /// Path to current active model if downloaded and ready
    var activeModelPath: String? {
        if case .ready(let path, _) = state {
            return path
        }
        return modelPath(for: currentModel)
    }
    
    /// Check whether a specific model is already downloaded
    func isDownloaded(model: RecommendedAIModel) -> Bool {
        let fileManager = FileManager.default
        let path = modelFileURL(for: model).path
        if fileManager.fileExists(atPath: path),
           let attrs = try? fileManager.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int64, size > 10_000_000 {
            return true
        }
        // Also check repo models/ folder
        if customModelsDirectory == nil {
            let cwdPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("models/\(model.fileName)").path
            if fileManager.fileExists(atPath: cwdPath),
               let attrs = try? fileManager.attributesOfItem(atPath: cwdPath),
               let size = attrs[.size] as? Int64, size > 10_000_000 {
                return true
            }
        }
        return false
    }
    
    /// Get path to downloaded model file if available
    func modelPath(for model: RecommendedAIModel) -> String? {
        let fileManager = FileManager.default
        let path = modelFileURL(for: model).path
        if fileManager.fileExists(atPath: path) {
            return path
        }
        if customModelsDirectory == nil {
            let cwdPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("models/\(model.fileName)").path
            if fileManager.fileExists(atPath: cwdPath) {
                return cwdPath
            }
        }
        return nil
    }
    
    /// Check whether the active model file exists on disk
    func checkExistingModel() {
        let fileManager = FileManager.default
        let targetURL = modelFileURL(for: currentModel)
        
        // 1. Check primary Application Support path
        if fileManager.fileExists(atPath: targetURL.path) {
            if let attrs = try? fileManager.attributesOfItem(atPath: targetURL.path),
               let size = attrs[.size] as? Int64, size > 10_000_000 {
                self.state = .ready(modelPath: targetURL.path, fileSize: size)
                return
            }
        }
        
        // 2. Check workspace models/ folder (convenience for development)
        if customModelsDirectory == nil {
            let cwdModelsURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("models/\(currentModel.fileName)")
            if fileManager.fileExists(atPath: cwdModelsURL.path) {
                if let attrs = try? fileManager.attributesOfItem(atPath: cwdModelsURL.path),
                   let size = attrs[.size] as? Int64, size > 10_000_000 {
                    self.state = .ready(modelPath: cwdModelsURL.path, fileSize: size)
                    return
                }
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
    
    /// Delete downloaded model weights
    func deleteModel(model: RecommendedAIModel? = nil) {
        let targetModel = model ?? currentModel
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
        
        Task { @MainActor in
            self.activeDownloadingModel = nil
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
            Task { @MainActor in
                let nsError = error as NSError
                if nsError.code != NSURLErrorCancelled {
                    self.state = .error(message: error.localizedDescription)
                }
            }
        }
    }
}
