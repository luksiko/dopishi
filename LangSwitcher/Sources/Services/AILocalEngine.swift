import Foundation
import LlamaSwift

// MARK: - AI Local Engine Errors

public enum AILocalEngineError: LocalizedError, Equatable {
    case modelNotFound(String)
    case modelLoadFailed(String)
    case contextInitFailed
    case batchInitFailed
    case decodeFailed(Int32)
    case tokenizationFailed
    case executionCancelled
    case notLoaded

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "Model file not found at \(path)"
        case .modelLoadFailed(let path):
            return "Failed to load GGUF model from \(path)"
        case .contextInitFailed:
            return "Failed to initialize llama context"
        case .batchInitFailed:
            return "Failed to allocate llama batch"
        case .decodeFailed(let code):
            return "Llama decode returned error code \(code)"
        case .tokenizationFailed:
            return "Failed to tokenize prompt"
        case .executionCancelled:
            return "Generation was cancelled"
        case .notLoaded:
            return "Local AI model is not loaded"
        }
    }
}

// MARK: - Token Stitch Session
// Tracks in-flight or accepted suggestions, allowing instant continuation
// when the user types matching characters without re-querying the model.

public struct TokenStitchSession: Equatable {
    public let prompt: String
    public let fullSuggestion: String
    public private(set) var remainingSuggestion: String
    public private(set) var typedChars: String = ""

    public init(prompt: String, fullSuggestion: String) {
        self.prompt = prompt
        self.fullSuggestion = fullSuggestion
        self.remainingSuggestion = fullSuggestion
    }

    /// Advances the stitch session by a single typed character.
    /// Returns the updated remaining suggestion if matching, or nil if divergent.
    public mutating func advance(with character: Character) -> String? {
        guard let first = remainingSuggestion.first else { return nil }
        if first == character || first.lowercased() == character.lowercased() {
            remainingSuggestion.removeFirst()
            typedChars.append(character)
            return remainingSuggestion
        }
        return nil
    }

    /// Advances the stitch session with typed string segment.
    /// Transactional: if any character mismatches, state remains unchanged.
    public mutating func advance(with string: String) -> String? {
        var copy = self
        for char in string {
            guard copy.advance(with: char) != nil else { return nil }
        }
        self = copy
        return remainingSuggestion
    }
}

// MARK: - Native In-Process llama.cpp Engine (Apple Silicon Metal)

public actor AILocalEngine {
    public static let shared = AILocalEngine()

    private var model: OpaquePointer?                          // llama_model*
    private var context: OpaquePointer?                        // llama_context*
    private var vocab: OpaquePointer?                          // const llama_vocab*
    private var sampler: UnsafeMutablePointer<llama_sampler>?  // llama_sampler*
    private var batch: llama_batch?

    public private(set) var currentModelPath: String?
    public private(set) var isLoaded: Bool = false
    public private(set) var activeStitchSession: TokenStitchSession?
    public private(set) var prefixCacheHitCount: Int = 0
    private var cachedPromptTokens: [llama_token] = []

    private static let backendInitialized: Void = {
        llama_backend_init()
    }()

    public init() {
        _ = Self.backendInitialized
    }

    deinit {
        unload()
    }

    /// Load a GGUF model file into Metal GPU memory.
    public func loadModel(path: String, contextSize: UInt32 = 2048, nGpuLayers: Int32 = 99) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw AILocalEngineError.modelNotFound(path)
        }

        if isLoaded && currentModelPath == path {
            return
        }

        unload()

        // 1. Model parameters with full Metal GPU offload
        var mparams = llama_model_default_params()
        mparams.n_gpu_layers = nGpuLayers // Offload layers to Metal

        guard let loadedModel = llama_model_load_from_file(path, mparams) else {
            throw AILocalEngineError.modelLoadFailed(path)
        }
        self.model = loadedModel

        // 2. Vocabulary
        guard let modelVocab = llama_model_get_vocab(loadedModel) else {
            unload()
            throw AILocalEngineError.modelLoadFailed(path)
        }
        self.vocab = modelVocab

        // 3. Context parameters
        var cparams = llama_context_default_params()
        cparams.n_ctx = contextSize
        cparams.n_batch = 512
        cparams.n_ubatch = 512
        cparams.n_threads = max(1, Int32(ProcessInfo.processInfo.activeProcessorCount - 2))

        guard let loadedContext = llama_init_from_model(loadedModel, cparams) else {
            unload()
            throw AILocalEngineError.contextInitFailed
        }
        self.context = loadedContext

        // 4. Batch buffer
        self.batch = llama_batch_init(512, 0, 1)

        // 5. Sampler chain
        let sparams = llama_sampler_chain_default_params()
        guard let chain = llama_sampler_chain_init(sparams) else {
            unload()
            throw AILocalEngineError.contextInitFailed
        }
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(0.2))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(42))
        self.sampler = chain

        self.currentModelPath = path
        self.isLoaded = true
    }

    /// Unload model and free all C/Metal memory buffers.
    public func unload() {
        if let b = batch {
            llama_batch_free(b)
            self.batch = nil
        }
        if let s = sampler {
            llama_sampler_free(s)
            self.sampler = nil
        }
        if let c = context {
            llama_free(c)
            self.context = nil
        }
        if let m = model {
            llama_model_free(m)
            self.model = nil
        }
        self.vocab = nil
        self.currentModelPath = nil
        self.isLoaded = false
        self.activeStitchSession = nil
        self.cachedPromptTokens.removeAll()
        self.prefixCacheHitCount = 0
    }

    /// Clears the prompt prefix cache and KV cache memory.
    public func clearPrefixCache() {
        self.cachedPromptTokens.removeAll()
        if let c = context, let memory = llama_get_memory(c) {
            llama_memory_clear(memory, true)
        }
    }

    // MARK: - Tokenization

    public func tokenize(text: String, addSpecial: Bool = true, parseSpecial: Bool = true) -> [llama_token] {
        guard let v = vocab else { return [] }
        let utf8 = Array(text.utf8)
        guard !utf8.isEmpty else { return [] }
        let count = Int32(utf8.count)

        var tokens = [llama_token](repeating: 0, count: max(32, utf8.count + 8))
        let n = text.withCString { cStr in
            llama_tokenize(v, cStr, count, &tokens, Int32(tokens.count), addSpecial, parseSpecial)
        }
        if n >= 0 {
            return Array(tokens.prefix(Int(n)))
        }

        let needed = -n
        tokens = [llama_token](repeating: 0, count: Int(needed))
        let n2 = text.withCString { cStr in
            llama_tokenize(v, cStr, count, &tokens, Int32(tokens.count), addSpecial, parseSpecial)
        }
        if n2 >= 0 {
            return Array(tokens.prefix(Int(n2)))
        }
        return []
    }

    public func tokenToBytes(token: llama_token) -> [UInt8] {
        guard let v = vocab else { return [] }
        var buf = [CChar](repeating: 0, count: 256)
        let n = llama_token_to_piece(v, token, &buf, Int32(buf.count), 0, false)
        if n > 0 {
            return buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }
        } else if n < 0 {
            var large = [CChar](repeating: 0, count: Int(-n) + 1)
            let n2 = llama_token_to_piece(v, token, &large, Int32(large.count), 0, false)
            if n2 > 0 {
                return large.prefix(Int(n2)).map { UInt8(bitPattern: $0) }
            }
        }
        return []
    }

    public func tokenToPiece(token: llama_token) -> String {
        let bytes = tokenToBytes(token: token)
        guard !bytes.isEmpty else { return "" }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - Generation

    /// Generates predictive continuation for the given prompt context.
    public func generateContinuation(
        prompt: String,
        maxTokens: Int = 16,
        stopSequences: [String] = ["<|im_end|>", "<|endoftext|>", "<|im_start|>", "<eos>", "\n"],
        onToken: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        guard isLoaded, let ctx = context, let v = vocab, let smpl = sampler, var b = batch else {
            throw AILocalEngineError.notLoaded
        }

        guard !Task.isCancelled else {
            throw AILocalEngineError.executionCancelled
        }

        // 1. Tokenize prompt
        let rawPromptTokens = tokenize(text: prompt, addSpecial: true, parseSpecial: true)
        guard !rawPromptTokens.isEmpty else {
            throw AILocalEngineError.tokenizationFailed
        }

        // Keep prompt within safe context bounds (leave headroom for generated tokens)
        let maxPromptTokens = 1536
        let promptTokens = rawPromptTokens.count > maxPromptTokens
            ? Array(rawPromptTokens.suffix(maxPromptTokens))
            : rawPromptTokens

        // 2. Prefix Caching: compute matching prefix with previous KV state
        guard let memory = llama_get_memory(ctx) else {
            throw AILocalEngineError.contextInitFailed
        }

        var prefixLen = 0
        while prefixLen < cachedPromptTokens.count &&
              prefixLen < promptTokens.count &&
              cachedPromptTokens[prefixLen] == promptTokens[prefixLen] {
            prefixLen += 1
        }

        // Leave at least 1 token to decode so logits for the prompt tail are available for sampling
        if prefixLen == promptTokens.count && prefixLen > 0 {
            prefixLen -= 1
        }

        if prefixLen > 0 {
            prefixCacheHitCount += 1
            _ = llama_memory_seq_rm(memory, 0, llama_pos(prefixLen), -1)
        } else {
            llama_memory_clear(memory, true)
        }
        llama_sampler_reset(smpl)

        // 3. Feed delta tokens into batch
        b.n_tokens = 0
        let totalPromptTokens = promptTokens.count
        for i in prefixLen..<totalPromptTokens {
            let isLast = (i == totalPromptTokens - 1)
            let token = promptTokens[i]
            let idx = Int(b.n_tokens)
            b.token[idx] = token
            b.pos[idx] = llama_pos(i)
            b.n_seq_id[idx] = 1
            b.seq_id[idx]?[0] = 0
            b.logits[idx] = isLast ? 1 : 0
            b.n_tokens += 1

            if b.n_tokens == 512 || isLast {
                let decodeStatus = llama_decode(ctx, b)
                if decodeStatus != 0 {
                    cachedPromptTokens.removeAll()
                    llama_memory_clear(memory, true)
                    throw AILocalEngineError.decodeFailed(decodeStatus)
                }
                b.n_tokens = 0
            }
        }

        // 4. Autoregressive token sampling loop
        var generatedTokens: [llama_token] = []
        var accumulatedBytes: [UInt8] = []
        var accumulatedText = ""
        var decodedStep = 0

        for step in 0..<maxTokens {
            if Task.isCancelled {
                break
            }

            let nextTok = llama_sampler_sample(smpl, ctx, -1)
            llama_sampler_accept(smpl, nextTok)

            if llama_vocab_is_eog(v, nextTok) {
                break
            }

            let pieceBytes = tokenToBytes(token: nextTok)
            accumulatedBytes.append(contentsOf: pieceBytes)
            accumulatedText = String(decoding: accumulatedBytes, as: UTF8.self)
            generatedTokens.append(nextTok)

            let validText = accumulatedText.replacingOccurrences(of: "\u{FFFD}", with: "")
            if !validText.isEmpty {
                onToken?(validText)
            }

            // Check stop sequences
            var shouldStop = false
            for stop in stopSequences {
                if accumulatedText.contains(stop) {
                    if let range = accumulatedText.range(of: stop) {
                        accumulatedText = String(accumulatedText[..<range.lowerBound])
                    }
                    shouldStop = true
                    break
                }
            }
            if shouldStop {
                break
            }

            // Decode next token
            b.n_tokens = 0
            b.token[0] = nextTok
            b.pos[0] = llama_pos(totalPromptTokens + step)
            b.n_seq_id[0] = 1
            b.seq_id[0]?[0] = 0
            b.logits[0] = 1
            b.n_tokens = 1

            let decodeStatus = llama_decode(ctx, b)
            if decodeStatus != 0 {
                break
            }
            decodedStep = step + 1
        }

        self.batch = b

        // Update cached prompt tokens with the current prompt and decoded tokens
        var inKVCache = promptTokens
        if decodedStep > 0 {
            inKVCache.append(contentsOf: generatedTokens.prefix(decodedStep))
        }
        self.cachedPromptTokens = inKVCache

        if accumulatedText.hasSuffix("\u{FFFD}") {
            accumulatedText = accumulatedText.replacingOccurrences(of: "\u{FFFD}", with: "")
        }

        // Start stitch session for the generated result
        self.activeStitchSession = TokenStitchSession(prompt: prompt, fullSuggestion: accumulatedText)
        return accumulatedText
    }

    // MARK: - Token Stitching

    /// Formats an array of chat messages using the model's embedded Jinja chat template.
    /// Returns the formatted prompt string, or nil if no template is present or formatting fails.
    public func applyChatTemplate(messages: [(role: String, content: String)], addAssistant: Bool = true) -> String? {
        guard let m = model else { return nil }
        guard let tmpl = llama_model_chat_template(m, nil) else { return nil }

        var cMessages: [llama_chat_message] = []
        var allocatedPointers: [UnsafeMutablePointer<CChar>] = []
        defer {
            for ptr in allocatedPointers {
                free(ptr)
            }
        }

        for msg in messages {
            guard let r = strdup(msg.role) else { return nil }
            allocatedPointers.append(r)
            guard let c = strdup(msg.content) else { return nil }
            allocatedPointers.append(c)
            cMessages.append(llama_chat_message(role: r, content: c))
        }

        var buf = [CChar](repeating: 0, count: 4096)
        let n = llama_chat_apply_template(tmpl, cMessages, cMessages.count, addAssistant, &buf, Int32(buf.count))
        if n >= 0 && n <= buf.count {
            return String(cString: buf)
        } else if n > buf.count {
            var largeBuf = [CChar](repeating: 0, count: Int(n) + 16)
            let n2 = llama_chat_apply_template(tmpl, cMessages, cMessages.count, addAssistant, &largeBuf, Int32(largeBuf.count))
            if n2 >= 0 {
                return String(cString: largeBuf)
            }
        }
        return nil
    }

    /// Attempts to advance the current stitch session without re-inferring.
    public func attemptStitch(typedText: String) -> String? {
        guard var session = activeStitchSession else { return nil }
        guard let remaining = session.advance(with: typedText) else {
            self.activeStitchSession = nil
            return nil
        }
        self.activeStitchSession = session
        return remaining
    }

    /// Resets the current stitch session.
    public func resetStitch() {
        self.activeStitchSession = nil
    }
}
