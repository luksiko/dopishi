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
    private var engineGeneration: Int = 0
    
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
    
    /// Check if the inference engine is available (native Metal is bundled, fallback to binary)
    var isBinaryAvailable: Bool {
        true
    }
    
    /// Ensure the engine is running with the current active model
    @discardableResult
    func ensureRunning() async -> Bool {
        guard let activePath = AIModelManager.shared.activeModelPath else {
            return false
        }
        let isEngineAlive: Bool
        if await AILocalEngine.shared.isLoaded {
            isEngineAlive = true
        } else if let p = process, p.isRunning {
            isEngineAlive = true
        } else {
            isEngineAlive = false
        }

        if isRunning && isEngineAlive && currentLoadedModelPath == activePath {
            return true
        }
        // Process died, was never started, or model path changed -> restart
        isRunning = false
        terminateExternalProcess()
        return await start(modelPath: activePath)
    }
    
    /// Start the inference engine with the specified model
    func start(modelPath: String) async -> Bool {
        guard !isRunning, !isStarting else { return isRunning }
        guard FileManager.default.fileExists(atPath: modelPath) else {
            NSLog("[LangSwitcher] AIInferenceEngine: model file not found at %@", modelPath)
            return false
        }
        
        engineGeneration &+= 1
        isStarting = true
        defer { isStarting = false }
        
        terminateExternalProcess()
        
        // 1. First attempt native in-process Metal inference via AILocalEngine
        do {
            try await AILocalEngine.shared.loadModel(path: modelPath)
            self.isRunning = true
            self.currentLoadedModelPath = modelPath
            NSLog("[LangSwitcher] AIInferenceEngine: loaded natively via in-process Metal engine: %@", (modelPath as NSString).lastPathComponent)
            Task { [weak self] in
                _ = await self?.modelUsesChatTemplate(at: modelPath)
            }
            return true
        } catch {
            NSLog("[LangSwitcher] AIInferenceEngine: in-process Metal load failed (%@), attempting fallback to llama-server", error.localizedDescription)
        }

        // 2. Fallback to external llama-server daemon if binary is available
        guard let binaryURL = findEngineBinary() else {
            NSLog("[LangSwitcher] AIInferenceEngine: neither native Metal nor llama-server binary available")
            return false
        }
        
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
            proc.terminationHandler = { [weak self] p in
                Task { @MainActor [weak self] in
                    guard let self = self, self.process === p else { return }
                    NSLog("[LangSwitcher] AIInferenceEngine: daemon process terminated with status %d", p.terminationStatus)
                    self.isRunning = false
                    self.process = nil
                    self.currentLoadedModelPath = nil
                }
            }
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
                Task { [weak self] in
                    _ = await self?.modelUsesChatTemplate(at: modelPath)
                }
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
    
    private func terminateExternalProcess() {
        if let p = process {
            p.terminationHandler = nil
            if p.isRunning {
                p.terminate()
            }
            process = nil
        }
    }

    /// Stop the inference engine
    func stop() {
        engineGeneration &+= 1
        let stopGen = engineGeneration
        terminateExternalProcess()
        isRunning = false
        currentLoadedModelPath = nil
        inFlightTemplateTask?.task.cancel()
        inFlightTemplateTask = nil
        metadataCacheRevision &+= 1
        cachedTemplateModel = nil
        cachedUsesChatTemplate = true
        Task { @MainActor [weak self] in
            guard let self, self.engineGeneration == stopGen, !self.isStarting, !self.isRunning else { return }
            await AILocalEngine.shared.unload()
        }
    }

    private func checkAndRecoverProcess(error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && (nsError.code == NSURLErrorCannotConnectToHost || nsError.code == NSURLErrorNetworkConnectionLost) {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if !(await AILocalEngine.shared.isLoaded) {
                    NSLog("[LangSwitcher] AIInferenceEngine: server connection failed (%d), resetting running state", nsError.code)
                    self.isRunning = false
                    self.process = nil
                    self.currentLoadedModelPath = nil
                }
            }
        }
    }
    
    nonisolated static let defaultSystemPromptEn = "You are a text completion engine. Continue the immediate text naturally with 2-3 words. Maintain context, language and tone. Output only the direct continuation. Never act as a conversational chatbot, never output greetings or conversational replies, do not repeat the prompt, and do not explain."
    nonisolated static let defaultSystemPromptRu = "Ты — сервис автодополнения текста. Продолжи начатую мысль естественно 2-3 словами. Сохраняй контекст, язык и стиль. Выводи только прямое продолжение. Не отвечай как собеседник в чате, не используй приветствия, не повторяй ввод и не добавляй пояснений."
    nonisolated static var defaultSystemPrompt: String { defaultSystemPromptEn }

    nonisolated static func containsCyrillic(_ text: String) -> Bool {
        text.contains { ("\u{0400}"..."\u{04FF}").contains($0) }
    }

    /// Earlier paragraphs may be in a different language from the current text.
    nonisolated static func activeParagraph(in context: String) -> String {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.components(separatedBy: .newlines).last ?? trimmed
    }

    nonisolated static func strippingGeneratedMarkup(_ text: String) -> String {
        // Remove only paired, known formatting tags. A bare <String>, <T> or
        // <b> can be a generic argument and must survive unchanged.
        let pattern = "<(code|strong|em|b|i|u|s|span|p|div|a|pre)(?:\\s+[^<>]*?)?>([\\s\\S]*?)</\\1\\s*>"
        var result = text
        while true {
            let cleaned = result.replacingOccurrences(of: pattern, with: "$2", options: .regularExpression)
            if cleaned == result { break }
            result = cleaned
        }
        result = result.replacingOccurrences(of: "<br\\s*/?>", with: " ", options: .regularExpression)
        // Strip standalone void/form HTML tags (e.g. <input>, <button>, <kbd>) that models emit inside code snippets
        result = result.replacingOccurrences(
            of: "</?(?:input|button|select|textarea|form|label|option|img|hr|wbr|kbd)(?:\\s+[^<>]*?)?/?>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return result
    }

    nonisolated static func userContinuationDirective(for context: String) -> String {
        let isCyrillic = containsCyrillic(activeParagraph(in: context))
        if isCyrillic {
            return "Продолжи начатый текст (выведи только следующие 2-3 слова продолжения, без приветствий, без повтора фразы и без ответов на вопросы):\n\n\(context)"
        } else {
            return "Continue the following text (output only the next 2-3 words of continuation, no greetings, no repeating the prompt, and no answering questions):\n\n\(context)"
        }
    }

    nonisolated static func completionMessages(
        context: String,
        afterCaret: String,
        instructions: String?,
        screenContext: String? = nil,
        hasPendingQuestion: Bool = false,
        appName: String? = nil,
        windowTitle: String? = nil,
        webDomain: String? = nil,
        allowProfanity: Bool = false,
        frameUserDirective: Bool = false
    ) -> [[String: String]] {
        let isCyrillic = containsCyrillic(activeParagraph(in: context))
        var system = isCyrillic ? defaultSystemPromptRu : defaultSystemPromptEn
        if !allowProfanity {
            let profanityPrompt = isCyrillic
                ? "Ни при каких обстоятельствах не используй ненормативную лексику, мат, ругательства, грубые или оскорбительные выражения."
                : "Never use profanity, vulgarity, obscenities, or offensive language under any circumstances."
            system += "\n" + profanityPrompt
        }
        if let app = appName?.trimmingCharacters(in: .whitespacesAndNewlines), !app.isEmpty {
            let appPrompt = isCyrillic
                ? "Активное приложение: \(app)."
                : "Active application: \(app)."
            system += "\n" + appPrompt
        }
        if let title = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            let titlePrompt = isCyrillic
                ? "Контекст/тема окна: \"\(title)\"."
                : "Window context: \"\(title)\"."
            system += "\n" + titlePrompt
        }
        if let domain = webDomain?.trimmingCharacters(in: .whitespacesAndNewlines), !domain.isEmpty {
            let domainPrompt = isCyrillic
                ? "Веб-домен / сайт: \(domain)."
                : "Web domain / site: \(domain)."
            system += "\n" + domainPrompt

            if domain.contains("github.com") || domain.contains("gitlab.com") || domain.contains("stackoverflow.com") {
                let codePrompt = isCyrillic
                    ? "Контекст: разработка ПО, Git и код. Отдавай предпочтение техническим терминам, именам веток, Markdown и коммитам."
                    : "Context: software engineering, Git, and code. Prefer technical terminology, branch names, Markdown, and commit messages."
                system += "\n" + codePrompt
            } else if domain.contains("jira") || domain.contains("linear.app") || domain.contains("asana.com") {
                let taskPrompt = isCyrillic
                    ? "Контекст: трекер задач / тикеты. Отдавай предпочтение описанию задач, баг-репортам и лаконичным заметкам."
                    : "Context: issue tracking. Prefer concise task descriptions, bug reports, and acceptance criteria."
                system += "\n" + taskPrompt
            } else if domain.contains("docs.google.com") || domain.contains("notion.so") {
                let docPrompt = isCyrillic
                    ? "Контекст: текстовый документ. Продолжай связными, естественными предложениями делового или публицистического стиля."
                    : "Context: document editing. Continue with coherent, natural sentences in professional or editorial style."
                system += "\n" + docPrompt
            }
        }
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
        if !afterCaret.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: ["after": afterCaret], options: [.sortedKeys]) {
            system += "\nInsert before the following existing suffix, without repeating it: " + String(decoding: data, as: UTF8.self)
        }
        let userContent = frameUserDirective ? userContinuationDirective(for: context) : context
        return [["role": "system", "content": system], ["role": "user", "content": userContent]]
    }

    nonisolated static func baseModelContextPrefix(
        context: String,
        instructions: String?,
        screenContext: String?,
        appName: String?,
        windowTitle: String?,
        webDomain: String?,
        persona: String? = nil,
        allowProfanity: Bool = false
    ) -> String {
        var prefix = ""
        let isCyr = containsCyrillic(activeParagraph(in: context))

        if let screen = screenContext?.trimmingCharacters(in: .whitespacesAndNewlines), !screen.isEmpty {
            prefix += (isCyr ? "Контекст диалога:\n" : "Conversation context:\n") + screen + "\n\n"
        } else if let title = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            prefix += (isCyr ? "Тема: " : "Topic: ") + title + "\n\n"
        }

        var styleItems = [instructions, persona].compactMap { $0 }.filter { !$0.isEmpty }
        if !allowProfanity {
            styleItems.append(isCyr ? "Без ненормативной лексики и мата." : "No profanity or vulgar language.")
        }
        let combined = styleItems.joined(separator: "\n")
        if !combined.isEmpty {
            prefix += (isCyr ? "Стиль и правила:\n" : "Style and instructions:\n") + combined + "\n\n"
        }
        return prefix
    }

    nonisolated static func continuationPrefix(_ context: String) -> String {
        // A standalone trailing-space token biases BPE models toward numbers.
        // Let the model generate its own leading word separator, then reconcile it.
        context.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
    }

    nonisolated static func healedContinuation(_ raw: String, wordBuffer: String) -> String? {
        let trimmed = raw.drop(while: { $0.isWhitespace })
        guard trimmed.lowercased().hasPrefix(wordBuffer.lowercased()) else { return nil }
        return String(trimmed.dropFirst(wordBuffer.count))
    }

    nonisolated static func predictionTokenBudget(context: String, maxWords: Int) -> Int {
        min(96, max(24, maxWords * 8))
    }

    /// Read metadata, never the tensors. A base model without a chat template
    /// must receive a raw prefix, not llama-server's fallback ChatML template.
    nonisolated static func embeddedChatTemplate(at path: String) -> Bool? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped),
              data.count >= 24 else { return nil }
        return data.withUnsafeBytes { raw -> Bool? in
            guard raw.count >= 24,
                  let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self),
                  base[0] == 0x47, base[1] == 0x47, base[2] == 0x55, base[3] == 0x46 else { return nil }
            var offset = 4
            let total = raw.count
            @inline(__always)
            func readUInt32() -> UInt32? {
                guard offset <= total - 4 else { return nil }
                let val = raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
                offset += 4
                return val
            }
            @inline(__always)
            func readUInt64() -> UInt64? {
                guard offset <= total - 8 else { return nil }
                let val = raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self).littleEndian
                offset += 8
                return val
            }
            @inline(__always)
            func skipBytes(_ count: Int) -> Bool {
                guard count >= 0, offset <= total - count else { return false }
                offset += count
                return true
            }
            @inline(__always)
            func readString(decode: Bool) -> String? {
                guard let size = readUInt64(), size <= UInt64(total - offset) else { return nil }
                let count = Int(size)
                let start = offset
                offset += count
                guard decode else { return "" }
                let buf = UnsafeBufferPointer(start: base.advanced(by: start), count: count)
                return String(bytes: buf, encoding: .utf8)
            }
            func skip(_ type: UInt32, depth: Int = 0) -> Bool {
                switch type {
                case 0, 1, 7: return skipBytes(1)
                case 2, 3:    return skipBytes(2)
                case 4, 5, 6: return skipBytes(4)
                case 10, 11, 12: return skipBytes(8)
                case 8:
                    guard let size = readUInt64(), size <= UInt64(total - offset) else { return false }
                    offset += Int(size)
                    return true
                case 9:
                    guard depth < 4, let subtype = readUInt32(), let count = readUInt64() else { return false }
                    let fixedSize: Int? = switch subtype {
                    case 0, 1, 7: 1
                    case 2, 3: 2
                    case 4, 5, 6: 4
                    case 10, 11, 12: 8
                    default: nil
                    }
                    if let size = fixedSize {
                        guard count <= UInt64((total - offset) / size) else { return false }
                        offset += Int(count) * size
                        return true
                    }
                    guard count <= UInt64(total - offset) else { return false }
                    for _ in 0..<count {
                        if !skip(subtype, depth: depth + 1) { return false }
                    }
                    return true
                default:
                    return false
                }
            }
            guard let version = readUInt32(), (version == 2 || version == 3),
                  readUInt64() != nil,
                  let count = readUInt64(), count <= 100_000 else { return nil }
            for _ in 0..<count {
                guard let key = readString(decode: true), let type = readUInt32() else { return nil }
                if key == "tokenizer.chat_template", type == 8 {
                    guard let template = readString(decode: true) else { return nil }
                    return !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                } else if !skip(type) {
                    return nil
                }
            }
            return false
        }
    }

    private var cachedTemplateModel: String?
    private var cachedUsesChatTemplate = true
    private var metadataCacheRevision = 0
    private var inFlightTemplateTask: (path: String, task: Task<Bool?, Never>)?

    func modelUsesChatTemplate(at path: String) async -> Bool? {
        if cachedTemplateModel == path { return cachedUsesChatTemplate }
        if await AILocalEngine.shared.isLoaded, await AILocalEngine.shared.currentModelPath == path {
            let detected = await AILocalEngine.shared.hasChatTemplate()
            cachedTemplateModel = path
            cachedUsesChatTemplate = detected
            return detected
        }
        if let current = inFlightTemplateTask, current.path == path {
            return await current.task.value
        }
        let revision = metadataCacheRevision
        let task = Task.detached(priority: .utility) {
            Self.embeddedChatTemplate(at: path)
        }
        inFlightTemplateTask = (path: path, task: task)
        let detected = await task.value
        inFlightTemplateTask = nil
        // Cache detection for this path even if caller task is cancelled,
        // so rapid typing doesn't repeatedly scan the model file.
        guard revision == metadataCacheRevision, let detected else { return nil }
        cachedTemplateModel = path
        cachedUsesChatTemplate = detected
        return detected
    }

    func predictContinuation(
        context: String,
        afterCaret: String = "",
        wordBuffer: String = "",
        maxWords: Int = 3,
        customInstructions: String? = nil,
        screenContext: String? = nil,
        hasPendingQuestion: Bool = false,
        appName: String? = nil,
        windowTitle: String? = nil,
        webDomain: String? = nil,
        allowProfanity: Bool = false
    ) async -> String? {
        await predictContinuationStream(
            context: context,
            afterCaret: afterCaret,
            wordBuffer: wordBuffer,
            maxWords: maxWords,
            customInstructions: customInstructions,
            screenContext: screenContext,
            hasPendingQuestion: hasPendingQuestion,
            appName: appName,
            windowTitle: windowTitle,
            webDomain: webDomain,
            allowProfanity: allowProfanity,
            onToken: nil
        )
    }

    func predictContinuationStream(
        context: String,
        afterCaret: String = "",
        wordBuffer: String = "",
        maxWords: Int = 3,
        customInstructions: String? = nil,
        screenContext: String? = nil,
        hasPendingQuestion: Bool = false,
        appName: String? = nil,
        windowTitle: String? = nil,
        webDomain: String? = nil,
        allowProfanity: Bool = false,
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
        // Keep the full context right up to caret including wordBuffer,
        // allowing the model to naturally complete both the word and subsequent words.
        let healsWord = !wordBuffer.isEmpty && context.hasSuffix(wordBuffer)
        let generationContext = context
        guard !generationContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let rawPrompt = Self.continuationPrefix(generationContext)
        var prompt = rawPrompt

        // Native Metal direct execution
        if await AILocalEngine.shared.isLoaded {
            var nativePrompt = rawPrompt
            let isCyr = Self.containsCyrillic(Self.activeParagraph(in: context))
            let persona = LoRAAdapterManager.shared.personaPrompt(for: isCyr)
            if usesTemplate {
                let combinedInstructions = [customInstructions, persona].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")

                let msgs = Self.completionMessages(
                    context: context,
                    afterCaret: afterCaret,
                    instructions: combinedInstructions.isEmpty ? nil : combinedInstructions,
                    screenContext: screenContext,
                    hasPendingQuestion: hasPendingQuestion,
                    appName: appName,
                    windowTitle: windowTitle,
                    webDomain: webDomain,
                    allowProfanity: allowProfanity,
                    frameUserDirective: true
                ).map { (role: $0["role"] ?? "user", content: $0["content"] ?? "") }

                if let formatted = await AILocalEngine.shared.applyChatTemplate(messages: msgs, addAssistant: true) {
                    nativePrompt = formatted
                } else {
                    var chatPrompt = ""
                    for msg in msgs {
                        chatPrompt += "<|im_start|>\(msg.role)\n\(msg.content)<|im_end|>\n"
                    }
                    nativePrompt = chatPrompt + "<|im_start|>assistant\n"
                }
            } else {
                let basePrefix = Self.baseModelContextPrefix(
                    context: context,
                    instructions: customInstructions,
                    screenContext: screenContext,
                    appName: appName,
                    windowTitle: windowTitle,
                    webDomain: webDomain,
                    persona: persona,
                    allowProfanity: allowProfanity
                )
                nativePrompt = basePrefix + rawPrompt
            }

            let started = Date()
            let effectiveTemp = LoRAAdapterManager.shared.effectiveTemperature(base: 0.2)
            do {
                let generated = try await AILocalEngine.shared.generateContinuation(
                    prompt: nativePrompt,
                    maxTokens: Self.predictionTokenBudget(context: context, maxWords: maxWords),
                    temperature: effectiveTemp
                ) { partial in
                    var currentRaw = partial
                    if healsWord, let healed = Self.healedContinuation(currentRaw, wordBuffer: wordBuffer) {
                        currentRaw = healed
                    }
                    if let cleaned = Self.cleanAndTrimContinuation(
                        raw: currentRaw,
                        context: context,
                        wordBuffer: healsWord ? "" : wordBuffer,
                        maxWords: maxWords,
                        afterCaret: afterCaret,
                        screenContext: screenContext,
                        allowProfanity: allowProfanity
                    ) {
                        let formatted = context.last?.isWhitespace == true ? cleaned.trimmingCharacters(in: .whitespaces) : cleaned
                        if !formatted.isEmpty {
                            Task { @MainActor in
                                onToken?(formatted)
                            }
                        }
                    }
                }
                var currentRaw = generated
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
                    let formatted = context.last?.isWhitespace == true ? cleaned.trimmingCharacters(in: .whitespaces) : cleaned
                    NSLog("[LangSwitcher] In-process Metal AI inference completed in %.3fs", Date().timeIntervalSince(started))
                    return formatted
                }
                return nil
            } catch {
                if !Task.isCancelled {
                    NSLog("[LangSwitcher] In-process Metal AI inference failed: %@", error.localizedDescription)
                }
                return nil
            }
        }

        let isCyr = Self.containsCyrillic(Self.activeParagraph(in: context))
        let persona = LoRAAdapterManager.shared.personaPrompt(for: isCyr)
        if usesTemplate {
            let combinedInstructions = [customInstructions, persona].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")

            var templateRequest = URLRequest(url: URL(string: "http://127.0.0.1:\(serverPort)/apply-template")!)
            templateRequest.httpMethod = "POST"
            templateRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            templateRequest.httpBody = try? JSONSerialization.data(withJSONObject: [
                "messages": Self.completionMessages(
                    context: context,
                    afterCaret: afterCaret,
                    instructions: combinedInstructions.isEmpty ? nil : combinedInstructions,
                    screenContext: screenContext,
                    hasPendingQuestion: hasPendingQuestion,
                    appName: appName,
                    windowTitle: windowTitle,
                    webDomain: webDomain,
                    allowProfanity: allowProfanity,
                    frameUserDirective: true
                )])
            do {
                let (data, response) = try await session.data(for: templateRequest)
                guard !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200,
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let rendered = json["prompt"] as? String else { return nil }
                prompt = rendered
            } catch {
                if !Task.isCancelled {
                    NSLog("[LangSwitcher] AIInferenceEngine: template request failed (%@)", error.localizedDescription)
                    checkAndRecoverProcess(error: error)
                }
                return nil
            }
        } else {
            let basePrefix = Self.baseModelContextPrefix(
                context: context,
                instructions: customInstructions,
                screenContext: screenContext,
                appName: appName,
                windowTitle: windowTitle,
                webDomain: webDomain,
                persona: persona,
                allowProfanity: allowProfanity
            )
            prompt = basePrefix + prompt
        }
        let isStreaming = onToken != nil
        let payload: [String: Any] = [
            "temperature": Double(LoRAAdapterManager.shared.effectiveTemperature(base: 0.2)),
            "top_k": 40,
            "top_p": 0.9,
            "repeat_penalty": 1.15,
            "repeat_last_n": 64,
            "presence_penalty": 0.2,
            "seed": 42,
            "stream": isStreaming,
            "prompt": prompt,
            "n_predict": Self.predictionTokenBudget(context: context, maxWords: maxWords),
            "stop": [
                "<|im_end|>", "<|endoftext|>", "<|im_start|>", "<end_of_turn>", "<start_of_turn>", "<eos>",
                "[User", "[user", "[USER", "User:", "user:", "USER:", "User [", "user [", "User 0", "user 0",
                "[Assistant", "[assistant", "[ASSISTANT", "Assistant:", "assistant:",
                "[Model", "[model", "[MODEL", "Model:", "model:", "MODEL:", "Model [", "model [",
                "\n[User", "\nUser", "\n[", "[00", "[0", "[User "
            ]
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
                        if healsWord, let healed = Self.healedContinuation(currentRaw, wordBuffer: wordBuffer) {
                            currentRaw = healed
                        }
                        
                        if let cleaned = Self.cleanAndTrimContinuation(
                            raw: currentRaw,
                            context: context,
                            wordBuffer: healsWord ? "" : wordBuffer,
                            maxWords: maxWords,
                            afterCaret: afterCaret,
                            screenContext: screenContext,
                            allowProfanity: allowProfanity
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
                        screenContext: screenContext,
                        allowProfanity: allowProfanity
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
                    checkAndRecoverProcess(error: error)
                }
                return nil
            }
        } else {
            do {
                let (data, response) = try await session.data(for: request)
                guard !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200,
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
                guard var raw = json["content"] as? String else { return nil }
                if healsWord, let healed = Self.healedContinuation(raw, wordBuffer: wordBuffer) {
                    raw = healed
                }
                guard let cleaned = Self.cleanAndTrimContinuation(raw: raw, context: context,
                    wordBuffer: healsWord ? "" : wordBuffer, maxWords: maxWords, afterCaret: afterCaret,
                    screenContext: screenContext, allowProfanity: allowProfanity) else { return nil }
                return context.last?.isWhitespace == true ? cleaned.trimmingCharacters(in: .whitespaces) : cleaned
            } catch {
                if !Task.isCancelled {
                    NSLog("[LangSwitcher] AI inference failed after %.2fs: %@", Date().timeIntervalSince(started), error.localizedDescription)
                    checkAndRecoverProcess(error: error)
                }
                return nil
            }
        }
    }

    /// Clean generated content and extract accurate completion tail
    nonisolated static func cleanAndTrimContinuation(
        raw: String,
        context: String,
        wordBuffer: String,
        maxWords: Int,
        afterCaret: String = "",
        screenContext: String? = nil,
        allowProfanity: Bool = false
    ) -> String? {
        guard maxWords > 0 else { return nil }
        var text = raw
        
        // Strip <think>...</think> if any
        if let thinkEnd = text.range(of: "</think>") {
            text = String(text[thinkEnd.upperBound...])
        } else if text.contains("<think>") {
            return nil
        }
        
        // Strip leading newlines/carriage returns that the model generated after <|im_start|>assistant
        while text.hasPrefix("\n") || text.hasPrefix("\r") {
            text = String(text.dropFirst())
        }

        // Stop at ChatML control tags and dialogue role tokens occurring in generation
        let stopTags = [
            "<|im_end|>", "<|endoftext|>", "<|im_start|>", "<end_of_turn>", "<start_of_turn>", "<eos>",
            "[User", "[user", "[USER", "User:", "user:", "USER:",
            "[Assistant", "[assistant", "[ASSISTANT", "Assistant:", "assistant:",
            "[Model", "[model", "[MODEL", "Model:", "model:", "MODEL:",
            "[System", "[system", "System:", "system:"
        ]
        for tag in stopTags {
            if let idx = text.range(of: tag) {
                text = String(text[..<idx.lowerBound])
            }
        }

        // Also stop at [User 001], User [002], [002], or any bracketed/numbered dialogue role tag
        if let roleMatch = text.range(of: #"(\[?\b(User|user|Assistant|assistant|Human|human|System|system|Model|model)\s*(\[?\d+\]?|:)|\[\s*\d{2,}\s*\])"#, options: .regularExpression) {
            text = String(text[..<roleMatch.lowerBound])
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

        // Filter leading conversational greetings, acknowledgments, or filler phrases
        let greetingRegex = #"^\s*(да,?\s+конечно|yes,?\s+of\s+course|здравствуйте|здравствуй|приветствую|привет|добрый\s+(день|вечер)|доброе\s+утро|доброго\s+времени\s+суток|hello|hi|hey|greetings|good\s+(morning|afternoon|evening)|конечно|sure|certainly|of\s+course)(?=[!.,:;\s]|$)[!.,:;\s]*"#
        var strippedGreeting = false
        while let match = text.range(of: greetingRegex, options: [.regularExpression, .caseInsensitive]), match.lowerBound == text.startIndex {
            strippedGreeting = true
            text.removeSubrange(match)
            while let f = text.first, (f.isWhitespace || [",", "!", ".", ":", ";", "-", "—"].contains(f)) {
                text.removeFirst()
            }
        }
        if strippedGreeting && !text.isEmpty {
            text = " " + text
        }

        // Filter explicit chatbot service phrases and assistant boilerplate
        let chatbotServiceRegexes = [
            // Russian chatbot service openings
            #"^\s*[!.,:;—\-]*\s*(?:я\s+)?готов[а]?\s+(?:вам|тебе)?\s*помочь"#,
            #"^\s*[!.,:;—\-]*\s*(?:я\s+)?могу\s+(?:вам|тебе)?\s*помочь"#,
            #"^\s*[!.,:;—\-]*\s*чем\s+(?:я\s+)?(?:могу\s+)?(?:вам|тебе)?\s*(?:помочь|быть\s+полез(?:ен|на))"#,
            #"^\s*[!.,:;—\-]*\s*как\s+(?:я\s+)?могу\s+(?:вам|тебе)?\s*помочь"#,
            #"^\s*[!.,:;—\-]*\s*я\s+(?:здесь|тут),?\s*чтобы\s+помочь"#,
            #"^\s*[!.,:;—\-]*\s*(?:всегда\s+|буду\s+)?рад[а]?\s+помочь"#,
            #"^\s*[!.,:;—\-]*\s*(?:я\s+)?с\s+радостью\s+помогу"#,
            #"^\s*[!.,:;—\-]*\s*(?:я\s+)?помогу\s+(?:вам|тебе)\b"#,
            #"^\s*[!.,:;—\-]*\s*вот\s+(?:продолжение|ваш\s+текст|твой\s+текст|ответ|вариант)"#,
            // English chatbot service openings
            #"^\s*[!.,:;—\-]*\s*how\s+(?:can|may)\s+i\s+(?:help|assist)"#,
            #"^\s*[!.,:;—\-]*\s*i\s+(?:am|'m)\s+(?:here|ready)\s+to\s+(?:help|assist)"#,
            #"^\s*[!.,:;—\-]*\s*(?:ready|happy|glad)\s+to\s+(?:help|assist)"#,
            #"^\s*[!.,:;—\-]*\s*i(?:'d|\s+would|\s+am)?\s*(?:be\s+)?happy\s+to\s+(?:help|assist)"#,
            #"^\s*[!.,:;—\-]*\s*feel\s+free\s+to\s+(?:ask|reach\s+out)"#,
            #"^\s*[!.,:;—\-]*\s*here(?:'s|\s+is)\s+(?:the\s+continuation|your\s+text)"#,
            #"^\s*[!.,:;—\-]*\s*i\s+can\s+(?:help|assist)\s+you\b"#
        ]
        for pattern in chatbotServiceRegexes {
            if text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return nil
            }
        }

        // Filter chatbot meta-commentary and identity disclosure
        let lowerText = text.lowercased()
        let chatbotIdentityPatterns = [
            "я языковая модель", "я большая языковая модель", "я искусственный интеллект", "я ии",
            "как языковая модель", "как искусственный интеллект", "как ии", "как виртуальный ассистент",
            "as an ai", "i am an ai", "i'm an ai", "as an ai language model", "as an ai assistant"
        ]
        if chatbotIdentityPatterns.contains(where: { lowerText.contains($0) }) {
            return nil
        }

        guard text.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        
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

        let candidateTrimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerCandidate = candidateTrimmed.lowercased()
        let lowerContext = context.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Direct echo check: reject if context already ends with this exact continuation
        if lowerContext.hasSuffix(lowerCandidate) {
            return nil
        }

        // 2. Prevent repetition loop if multi-word phrase already occurred in recent context window
        if tokens.count >= 2 && lowerCandidate.count >= 6 {
            let trailingContext = String(lowerContext.suffix(160))
            if trailingContext.contains(lowerCandidate) {
                return nil
            }
        }

        // 3. Punctuation continuity: do not suggest leading comma/semicolon if context already ends with terminal punctuation
        if let lastNonWhitespace = context.trimmingCharacters(in: .whitespaces).last,
           [".", "!", "?", "…"].contains(lastNonWhitespace),
           candidateTrimmed.hasPrefix(",") || candidateTrimmed.hasPrefix(";") {
            return nil
        }

        let result = (hasLeadingSpace ? " " : "") + selected
        if !allowProfanity && ProfanityFilter.isProfane(result) {
            return nil
        }
        return result
    }
}
