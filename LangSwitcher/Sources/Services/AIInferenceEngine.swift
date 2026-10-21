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
    @Published private(set) var isStarting: Bool = false
    private let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3.0
        config.timeoutIntervalForResource = 4.0
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
            "--ctx-size", "4096",
            "-cb",
            "-lv", "1" // retain errors without logging prompts or routine output
        ]
        
        // Set environment with Frameworks paths if running from bundle
        var env = ProcessInfo.processInfo.environment
        let frameworksPath = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks").path
        env["DYLD_FRAMEWORK_PATH"] = frameworksPath
        env["DYLD_LIBRARY_PATH"] = frameworksPath
        proc.environment = env
        
        // Silence stdout/stderr to avoid blocking on unread pipe buffers
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.standardError
        
        do {
            NSLog("[LangSwitcher] AIInferenceEngine: starting %@ on port %d", modelPath, port)
            try proc.run()
            self.process = proc
            
            // Wait up to 5 seconds for health check to pass
            let healthURL = URL(string: "http://127.0.0.1:\(port)/health")!
            var isHealthy = false
            for _ in 0..<25 {
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                if !proc.isRunning {
                    break
                }
                var request = URLRequest(url: healthURL)
                request.timeoutInterval = 0.5
                if let (_, response) = try? await URLSession.shared.data(for: request),
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
                NSLog("[LangSwitcher] AIInferenceEngine: health check failed (running=%@, status=%d)", proc.isRunning.description, proc.isRunning ? -1 : proc.terminationStatus)
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
        metadataCacheRevision &+= 1
        cachedTemplateModel = nil
        cachedUsesChatTemplate = true
    }
    
    static let defaultSystemPromptEn = "Continue the immediate thought naturally with a few words (up to 4 words). Maintain the existing context, language and style. Do not invent new unrelated topics, quotes, proper nouns or random questions. Do not explain."
    static let defaultSystemPromptRu = "Продолжи начатую мысль естественно несколькими словами (до 4 слов). Сохраняй контекст, язык и стиль. Не придумывай новые несвязанные темы, имена, названия в кавычках или вопросы. Не добавляй пояснений."
    static var defaultSystemPrompt: String { defaultSystemPromptEn }

    static func containsCyrillic(_ text: String) -> Bool {
        text.contains { ("\u{0400}"..."\u{04FF}").contains($0) }
    }

    /// Earlier paragraphs may be in a different language from the current text.
    static func activeParagraph(in context: String) -> String {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.components(separatedBy: .newlines).last ?? trimmed
    }

    static func strippingGeneratedMarkup(_ text: String) -> String {
        // Remove only paired, known formatting tags. A bare <String>, <T> or
        // <b> can be a generic argument and must survive unchanged.
        let pattern = "<(code|strong|em|b|i|u|s|span|p|div|a|pre)(?:\\s+[^<>]*?)?>([\\s\\S]*?)</\\1\\s*>"
        var result = text
        while true {
            let cleaned = result.replacingOccurrences(of: pattern, with: "$2", options: .regularExpression)
            if cleaned == result { break }
            result = cleaned
        }
        return result.replacingOccurrences(of: "<br\\s*/?>", with: " ", options: .regularExpression)
    }

    static func completionMessages(
        context: String,
        afterCaret: String,
        instructions: String?,
        screenContext: String? = nil,
        hasPendingQuestion: Bool = false
    ) -> [[String: String]] {
        let isCyrillic = containsCyrillic(activeParagraph(in: context))
        var system = isCyrillic ? defaultSystemPromptRu : defaultSystemPromptEn
        let extra = instructions?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !extra.isEmpty { system += "\n" + extra }
        if let screenContext = screenContext?.trimmingCharacters(in: .whitespacesAndNewlines), !screenContext.isEmpty {
            system += "\n" + screenContext + "\nStay strictly grounded in the conversation context. Never introduce unrelated topics, books, or quotes."
        }
        if hasPendingQuestion {
            let qaPrompt = isCyrillic
                ? "Собеседник задал вопрос. Кратко и естественно ответь на него от первого лица в 2-4 слова."
                : "The partner asked a question. Answer it concisely and naturally in first person in 2-4 words."
            system += "\n" + qaPrompt
        }
        if !afterCaret.isEmpty {
            let data = try! JSONSerialization.data(withJSONObject: ["after": afterCaret], options: [.sortedKeys])
            system += "\nInsert before the following existing suffix, without repeating it: " + String(decoding: data, as: UTF8.self)
        }
        return [["role": "system", "content": system], ["role": "user", "content": context]]
    }

    static func continuationPrefix(_ context: String) -> String {
        // A standalone trailing-space token biases BPE models toward numbers.
        // Let the model generate its own leading word separator, then reconcile it.
        context.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
    }

    static func healedContinuation(_ raw: String, wordBuffer: String) -> String? {
        let trimmed = raw.drop(while: { $0.isWhitespace })
        guard trimmed.lowercased().hasPrefix(wordBuffer.lowercased()) else { return nil }
        return String(trimmed.dropFirst(wordBuffer.count))
    }

    static func predictionTokenBudget(context: String, maxWords: Int) -> Int {
        min(96, max(24, maxWords * 8))
    }

    /// Read metadata, never the tensors. A base model without a chat template
    /// must receive a raw prefix, not llama-server's fallback ChatML template.
    nonisolated static func embeddedChatTemplate(at path: String) -> Bool? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped),
              data.count >= 24, data.prefix(4) == Data("GGUF".utf8) else { return nil }
        var offset = 4
        func integer(_ bytes: Int) -> UInt64? {
            guard bytes >= 0, offset <= data.count - bytes else { return nil }
            var result: UInt64 = 0
            for i in 0..<bytes { result |= UInt64(data[offset + i]) << (i * 8) }
            offset += bytes
            return result
        }
        func string(read: Bool) -> String? {
            guard let size = integer(8), size <= UInt64(data.count - offset) else { return nil }
            let count = Int(size)
            defer { offset += count }
            return read ? String(data: data[offset..<(offset + count)], encoding: .utf8) : ""
        }
        func skip(_ type: UInt64, depth: Int = 0) -> Bool {
            let sizes: [UInt64: Int] = [0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8]
            if let size = sizes[type] { return integer(size) != nil }
            if type == 8 { return string(read: false) != nil }
            guard type == 9, depth < 4, let subtype = integer(4), let count = integer(8) else { return false }
            if let size = sizes[subtype] {
                guard count <= UInt64((data.count - offset) / size) else { return false }
                offset += Int(count) * size
                return true
            }
            guard count <= UInt64(data.count - offset) else { return false }
            for _ in 0..<count { if !skip(subtype, depth: depth + 1) { return false } }
            return true
        }
        guard let version = integer(4), [2, 3].contains(version), integer(8) != nil,
              let count = integer(8), count <= 100_000 else { return nil }
        var found = false
        for _ in 0..<count {
            guard let key = string(read: true), let type = integer(4) else { return nil }
            if key == "tokenizer.chat_template", type == 8 {
                guard let template = string(read: true) else { return nil }
                found = !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } else if !skip(type) { return nil }
        }
        return found
    }

    private var cachedTemplateModel: String?
    private var cachedUsesChatTemplate = true
    private var metadataCacheRevision = 0

    func modelUsesChatTemplate(at path: String) async -> Bool? {
        if cachedTemplateModel == path { return cachedUsesChatTemplate }
        let revision = metadataCacheRevision
        let detected = await Task.detached(priority: .utility) { Self.embeddedChatTemplate(at: path) }.value
        // A restart may replace the file at the same path while metadata is read.
        guard !Task.isCancelled, revision == metadataCacheRevision, let detected else { return nil }
        cachedTemplateModel = path
        cachedUsesChatTemplate = detected
        return detected
    }

    func predictContinuation(
        context: String,
        afterCaret: String = "",
        wordBuffer: String = "",
        maxWords: Int = 4,
        customInstructions: String? = nil,
        screenContext: String? = nil,
        hasPendingQuestion: Bool = false
    ) async -> String? {
        await predictContinuationStream(
            context: context,
            afterCaret: afterCaret,
            wordBuffer: wordBuffer,
            maxWords: maxWords,
            customInstructions: customInstructions,
            screenContext: screenContext,
            hasPendingQuestion: hasPendingQuestion,
            onToken: nil
        )
    }

    func predictContinuationStream(
        context: String,
        afterCaret: String = "",
        wordBuffer: String = "",
        maxWords: Int = 4,
        customInstructions: String? = nil,
        screenContext: String? = nil,
        hasPendingQuestion: Bool = false,
        onToken: (@MainActor @Sendable (String) -> Void)? = nil
    ) async -> String? {
        guard !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, maxWords > 0 else { return nil }
        if !isRunning { guard await ensureRunning() else { return nil } }
        guard !Task.isCancelled, let model = currentLoadedModelPath else { return nil }
        guard let usesTemplate = await modelUsesChatTemplate(at: model),
              !Task.isCancelled, currentLoadedModelPath == model else { return nil }
        // Base checkpoints cannot condition on a suffix without a supported FIM
        // format. Abstain in the middle of text rather than guess over it.
        guard usesTemplate || afterCaret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let url = URL(string: "http://127.0.0.1:\(serverPort)/completion") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Back up to the word boundary so tokenization never locks an unfinished
        // subword into the wrong token. Only accept a generated word matching it.
        let healsWord = !wordBuffer.isEmpty && context.hasSuffix(wordBuffer)
        let generationContext = healsWord ? String(context.dropLast(wordBuffer.count)) : context
        guard !generationContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var prompt = Self.continuationPrefix(generationContext)
        if usesTemplate {
            var templateRequest = URLRequest(url: URL(string: "http://127.0.0.1:\(serverPort)/apply-template")!)
            templateRequest.httpMethod = "POST"
            templateRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            templateRequest.httpBody = try? JSONSerialization.data(withJSONObject: [
                "messages": Self.completionMessages(
                    context: context,
                    afterCaret: afterCaret,
                    instructions: customInstructions,
                    screenContext: screenContext,
                    hasPendingQuestion: hasPendingQuestion
                )])
            do {
                let (data, response) = try await session.data(for: templateRequest)
                guard !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200,
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let rendered = json["prompt"] as? String else { return nil }
                // Prefill the assistant with the current paragraph. This makes
                // generation continue text instead of answering or echoing it.
                let paragraph = prompt.components(separatedBy: .newlines).last ?? prompt
                prompt = rendered + String(paragraph.suffix(512))
            } catch { return nil }
        }
        let isStreaming = onToken != nil
        let payload: [String: Any] = [
            "temperature": 0.2,
            "seed": 42,
            "stream": isStreaming,
            "prompt": prompt,
            "n_predict": Self.predictionTokenBudget(context: context, maxWords: maxWords),
            "stop": ["<|im_end|>", "<|im_start|>", "<end_of_turn>", "<start_of_turn>", "<eos>"]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        let started = Date()
        
        if isStreaming {
            do {
                let (asyncBytes, response) = try await session.bytes(for: request)
                guard !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                
                var accumulatedRaw = ""
                var lastCleanedSuffix: String?
                
                for try await line in asyncBytes.lines {
                    guard !Task.isCancelled else { break }
                    guard line.hasPrefix("data: ") else { continue }
                    let jsonText = String(line.dropFirst(6))
                    guard let data = jsonText.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    
                    if let chunk = json["content"] as? String {
                        accumulatedRaw += chunk
                        
                        var currentRaw = accumulatedRaw
                        if healsWord {
                            if let healed = Self.healedContinuation(currentRaw, wordBuffer: wordBuffer) {
                                currentRaw = healed
                            } else {
                                continue
                            }
                        }
                        
                        if let cleaned = Self.cleanAndTrimContinuation(
                            raw: currentRaw,
                            context: context,
                            wordBuffer: healsWord ? "" : wordBuffer,
                            maxWords: maxWords,
                            afterCaret: afterCaret,
                            screenContext: screenContext
                        ) {
                            let formatted = context.last?.isWhitespace == true ? cleaned.trimmingCharacters(in: .whitespaces) : cleaned
                            if formatted != lastCleanedSuffix && !formatted.isEmpty {
                                lastCleanedSuffix = formatted
                                onToken?(formatted)
                            }
                            
                            let wordCount = cleaned.split(separator: " ").count
                            if wordCount >= maxWords && (chunk.hasSuffix(" ") || chunk.hasSuffix("\n") || chunk.contains(".")) {
                                break
                            }
                        }
                    }
                    
                    if json["stop"] as? Bool == true {
                        break
                    }
                }
                if lastCleanedSuffix == nil, !accumulatedRaw.isEmpty {
                    var currentRaw = accumulatedRaw
                    if healsWord, let healed = Self.healedContinuation(currentRaw, wordBuffer: wordBuffer) {
                        currentRaw = healed
                    }
                    if let cleaned = Self.cleanAndTrimContinuation(
                        raw: currentRaw,
                        context: context,
                        wordBuffer: healsWord ? "" : wordBuffer,
                        maxWords: maxWords,
                        afterCaret: afterCaret,
                        screenContext: screenContext
                    ) {
                        let final = context.last?.isWhitespace == true ? cleaned.trimmingCharacters(in: .whitespaces) : cleaned
                        lastCleanedSuffix = final
                        if !final.isEmpty {
                            onToken?(final)
                        }
                    }
                }
                guard !Task.isCancelled else { return nil }
                return lastCleanedSuffix
            } catch {
                if !Task.isCancelled {
                    NSLog("[LangSwitcher] AI streaming inference failed after %.2fs: %@", Date().timeIntervalSince(started), error.localizedDescription)
                }
                return nil
            }
        } else {
            do {
                let (data, response) = try await session.data(for: request)
                guard !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200,
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
                guard var raw = json["content"] as? String else { return nil }
                if healsWord {
                    guard let healed = Self.healedContinuation(raw, wordBuffer: wordBuffer) else { return nil }
                    raw = healed
                }
                guard let cleaned = Self.cleanAndTrimContinuation(raw: raw, context: context,
                    wordBuffer: healsWord ? "" : wordBuffer, maxWords: maxWords, afterCaret: afterCaret,
                    screenContext: screenContext) else { return nil }
                return context.last?.isWhitespace == true ? cleaned.trimmingCharacters(in: .whitespaces) : cleaned
            } catch {
                if !Task.isCancelled {
                    NSLog("[LangSwitcher] AI inference failed after %.2fs: %@", Date().timeIntervalSince(started), error.localizedDescription)
                }
                return nil
            }
        }
    }

    /// Clean generated content and extract accurate completion tail
    static func cleanAndTrimContinuation(
        raw: String,
        context: String,
        wordBuffer: String,
        maxWords: Int,
        afterCaret: String = "",
        screenContext: String? = nil
    ) -> String? {
        guard maxWords > 0 else { return nil }
        var text = raw
        
        // Strip <think>...</think> if any
        if let thinkEnd = text.range(of: "</think>") {
            text = String(text[thinkEnd.upperBound...])
        } else if text.contains("<think>") {
            return nil
        }
        
        // Stop at ChatML control tags
        for tag in ["<|im_end|>", "<|endoftext|>", "<|im_start|>", "<end_of_turn>", "<start_of_turn>", "<eos>"] {
            if let idx = text.range(of: tag) {
                text = String(text[..<idx.lowerBound])
            }
        }
        
        // Strip leading newlines/carriage returns that the model generated after <|im_start|>assistant
        while text.hasPrefix("\n") || text.hasPrefix("\r") {
            text = String(text.dropFirst())
        }
        
        // Take the first line of content (if multiple lines were generated)
        if let newlineIdx = text.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
            text = String(text[..<newlineIdx])
        }
        
        // Strip repeated context prefix if the model echoed the user prompt
        let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix(context) {
            text = String(text.dropFirst(context.count))
        } else if text.hasPrefix(trimmedContext) {
            text = String(text.dropFirst(trimmedContext.count))
        } else if !wordBuffer.isEmpty {
            let contextWithoutBuffer = String(context.dropLast(wordBuffer.count))
            let trimmedWithoutBuffer = contextWithoutBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedWithoutBuffer.isEmpty && text.hasPrefix(trimmedWithoutBuffer) {
                text = String(text.dropFirst(trimmedWithoutBuffer.count))
                let trimmedLeading = text.trimmingCharacters(in: .whitespaces)
                if trimmedLeading.lowercased().hasPrefix(wordBuffer.lowercased()) {
                    text = String(trimmedLeading.dropFirst(wordBuffer.count))
                }
            }
        }
        
        guard text.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }

        // If text still starts with wordBuffer (e.g. model output "программистами" when wordBuffer was "п"):
        if !wordBuffer.isEmpty && text.lowercased().hasPrefix(wordBuffer.lowercased()) {
            text = String(text.dropFirst(wordBuffer.count))
        }
        
        guard !text.isEmpty else { return nil }
        
        // Base checkpoints may emit web formatting. Preserve the words, not tags.
        text = strippingGeneratedMarkup(text)

        // Clean up malformed punctuation combinations emitted by small models (e.g. ", ?", ", !", "» ,", "» , ?")
        text = text.replacingOccurrences(of: ",\\s*\\?", with: "?", options: .regularExpression)
        text = text.replacingOccurrences(of: ",\\s*!", with: "!", options: .regularExpression)
        text = text.replacingOccurrences(of: ",\\s*\\.", with: ".", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\?\\s*,", with: "?", options: .regularExpression)
        text = text.replacingOccurrences(of: "!\\s*,", with: "!", options: .regularExpression)
        text = text.replacingOccurrences(of: "»\\s*,\\s*\\?", with: "»?", options: .regularExpression)

        // Reject unprompted quoted entities/titles (e.g. «Охотнике») that were never in the prompt or screen context
        let contextHasCyrillicQuotes = context.contains("«") || context.contains("»") || (screenContext?.contains("«") == true)
        if !contextHasCyrillicQuotes && (text.contains("«") || text.contains("»")) {
            return nil
        }
        let contextHasStraightQuotes = context.contains("\"") || (screenContext?.contains("\"") == true)
        if !contextHasStraightQuotes && text.contains("\"") && !wordBuffer.contains("\"") {
            return nil
        }

        // On short prefixes (<= 2 words), reject generic essay/discussion questions (e.g. "можно сказать о...", "вы думаете о...")
        let trimmedWords = context.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        if trimmedWords.count <= 2 {
            let lowerText = text.lowercased()
            let essayPatterns = [
                "можно сказать о", "вы думаете о", "ты думаешь о", "ваше мнение",
                "известно о", "считаете по поводу", "скажете о", "can be said about",
                "do you think about", "what is your opinion"
            ]
            for pattern in essayPatterns {
                if lowerText.contains(pattern) {
                    return nil
                }
            }
        }
        // If generation ended inside a known HTML wrapper, abstain rather than
        // showing the tag. Attached generic arguments such as Array<b> stay intact.
        let danglingMarkup = "(?:^|\\s)</?(?:code|strong|em|b|i|u|s|span|p|div|a|pre)(?:\\s+[^<>]*?)?\\s*>"
        guard text.range(of: danglingMarkup, options: .regularExpression) == nil else { return nil }
        guard !text.contains("<|"), !text.contains("```"), !text.contains("<unused") else { return nil }
        if !afterCaret.isEmpty, let overlap = text.range(of: afterCaret), overlap.lowerBound != text.startIndex {
            text = String(text[..<overlap.lowerBound])
        } else if !afterCaret.isEmpty && text.hasPrefix(afterCaret) { return nil }

        // Tokenize into words, respecting whether the first token has a leading space
        let hasLeadingSpace = text.hasPrefix(" ")
        let tokens = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !tokens.isEmpty else { return nil }
        
        let selected = Array(tokens.prefix(maxWords)).joined(separator: " ")
        
        // Reject an apparent translated sentence, while allowing terms like null,
        // Swift or API at the start of an otherwise Russian continuation.
        if containsCyrillic(activeParagraph(in: context)), !containsCyrillic(selected) {
            let englishFunctionWords = Set(["i", "you", "we", "they", "the", "is", "are", "a", "to", "it", "this", "very"])
            let matches = tokens.prefix(6).filter { englishFunctionWords.contains($0.lowercased()) }.count
            if matches >= 2 { return nil }
        }

        return (hasLeadingSpace ? " " : "") + selected
    }
}
