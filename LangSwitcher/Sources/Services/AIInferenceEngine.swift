import Foundation

// MARK: - AI Inference Engine
// Manages the embedded local LLM inference process (llama-server) and generates
// 2-4 word predictive text continuations.

@MainActor
final class AIInferenceEngine: ObservableObject {
    
    static let shared = AIInferenceEngine()
    
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var serverPort: Int = 18234
    @Published private(set) var currentLoadedModelPath: String?
    
    private var process: Process?
    private var isStarting: Bool = false
    private let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 0.8
        config.timeoutIntervalForResource = 1.0
        self.session = URLSession(configuration: config)
    }
    
    deinit {
        if let p = process, p.isRunning {
            p.terminate()
        }
    }
    
    /// Locate the inference engine binary (bundled in Contents/Helpers or fallback)
    func findEngineBinary() -> URL? {
        let fileManager = FileManager.default
        
        // 1. App Bundle Contents/Helpers/llama-server
        let bundleHelper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/llama-server")
        if fileManager.isExecutableFile(atPath: bundleHelper.path) {
            return bundleHelper
        }
        
        // 2. Auxiliary executable in Bundle
        if let auxURL = Bundle.main.url(forAuxiliaryExecutable: "llama-server"),
           fileManager.isExecutableFile(atPath: auxURL.path) {
            return auxURL
        }
        
        // 3. Fallbacks for development / testing environments
        let standardPaths = [
            "/opt/homebrew/bin/llama-server",
            "/usr/local/bin/llama-server",
            "/opt/homebrew/Cellar/llama.cpp/0.7.0/bin/llama-server"
        ]
        for path in standardPaths {
            if fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        
        return nil
    }
    
    /// Check if the engine binary is available
    var isBinaryAvailable: Bool {
        findEngineBinary() != nil
    }
    
    /// Ensure the engine is running with the current active model
    @discardableResult
    func ensureRunning() async -> Bool {
        guard let activePath = AIModelManager.shared.activeModelPath else {
            return false
        }
        if isRunning {
            if currentLoadedModelPath == activePath {
                return true
            }
            // Model path changed, restart with new model
            stop()
        }
        return await start(modelPath: activePath)
    }
    
    /// Start the inference daemon with the specified model
    func start(modelPath: String) async -> Bool {
        guard !isRunning, !isStarting else { return isRunning }
        guard let binaryURL = findEngineBinary() else {
            NSLog("[LangSwitcher] AIInferenceEngine: binary not found")
            return false
        }
        
        guard FileManager.default.fileExists(atPath: modelPath) else {
            NSLog("[LangSwitcher] AIInferenceEngine: model file not found at %@", modelPath)
            return false
        }
        
        isStarting = true
        defer { isStarting = false }
        
        stop() // Ensure previous instance is terminated
        
        // Select an ephemeral port
        let port = 18234 + Int.random(in: 0...50)
        self.serverPort = port
        
        let proc = Process()
        proc.executableURL = binaryURL
        proc.arguments = [
            "-m", modelPath,
            "--port", "\(port)",
            "--host", "127.0.0.1",
            "-ngl", "99",
            "--ctx-size", "2048",
            "-cb",
            "-lv", "0" // minimal logging
        ]
        
        // Set environment with Frameworks paths if running from bundle
        var env = ProcessInfo.processInfo.environment
        let frameworksPath = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks").path
        if let existing = env["DYLD_FRAMEWORK_PATH"] {
            env["DYLD_FRAMEWORK_PATH"] = "\(frameworksPath):\(existing)"
        } else {
            env["DYLD_FRAMEWORK_PATH"] = frameworksPath
        }
        proc.environment = env
        
        // Silence stdout/stderr to avoid noise
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        
        do {
            try proc.run()
            self.process = proc
            
            // Wait up to 3 seconds for health check to pass
            let healthURL = URL(string: "http://127.0.0.1:\(port)/health")!
            var isHealthy = false
            for _ in 0..<15 {
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                if !proc.isRunning {
                    break
                }
                if let (_, response) = try? await session.data(from: healthURL),
                   (response as? HTTPURLResponse)?.statusCode == 200 {
                    isHealthy = true
                    break
                }
            }
            
            if isHealthy {
                self.isRunning = true
                self.currentLoadedModelPath = modelPath
                NSLog("[LangSwitcher] AIInferenceEngine: started successfully on port %d with %@", port, (modelPath as NSString).lastPathComponent)
                return true
            } else {
                NSLog("[LangSwitcher] AIInferenceEngine: health check failed")
                stop()
                return false
            }
        } catch {
            NSLog("[LangSwitcher] AIInferenceEngine: failed to launch process: %@", error.localizedDescription)
            stop()
            return false
        }
    }
    
    /// Stop the background inference daemon
    func stop() {
        if let p = process {
            if p.isRunning {
                p.terminate()
            }
            process = nil
        }
        isRunning = false
        currentLoadedModelPath = nil
    }
    
    /// Formats prompt with optional custom instructions
    static func formatPrompt(context: String, instructions: String?) -> String {
        let trimmedInstructions = instructions?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedInstructions.isEmpty {
            return "[System: \(trimmedInstructions)]\n\(context)"
        }
        return context
    }
    
    /// Predict a 2-4 word continuation for the given typing context
    func predictContinuation(context: String, maxWords: Int = 4, customInstructions: String? = nil) async -> String? {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // If not running, attempt start if model is ready
        if !isRunning {
            let started = await ensureRunning()
            guard started else { return nil }
        }
        
        guard let url = URL(string: "http://127.0.0.1:\(serverPort)/completion") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = Self.formatPrompt(context: context, instructions: customInstructions)
        
        let payload: [String: Any] = [
            "prompt": prompt,
            "n_predict": max(6, maxWords * 3),
            "temperature": 0.2,
            "stop": ["\n", "\r", ".", "!", "?", "<|im_end|>", "<|endoftext|>"]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        request.httpBody = jsonData
        
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = json["content"] as? String {
                return cleanAndTrimContinuation(content, maxWords: maxWords)
            }
        } catch {
            // Request timed out or cancelled
            return nil
        }
        
        return nil
    }
    
    /// Clean generated content and limit to requested word count
    private func cleanAndTrimContinuation(_ raw: String, maxWords: Int) -> String? {
        var text = raw.replacingOccurrences(of: "\r", with: "")
        if let newlineIndex = text.firstIndex(of: "\n") {
            text = String(text[..<newlineIndex])
        }
        
        // Remove trailing or leading quotes/parentheses if unbalanced
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        
        let selectedWords = Array(words.prefix(maxWords))
        return selectedWords.joined(separator: " ")
    }
}
