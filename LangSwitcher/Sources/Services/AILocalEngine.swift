import Foundation
import Accelerate
import LlamaSwift

// MARK: - Vectorized Sampler (Apple Accelerate vDSP)
// High-performance vectorized token sampling using Apple Silicon vector units (vDSP / NEON).
// Eliminates CPU heap allocations and vocab sorting of llama_sampler_chain.

public struct VectorizedSampler {
    public struct Candidate: Equatable {
        public let token: llama_token
        public let logit: Float

        public init(token: llama_token, logit: Float) {
            self.token = token
            self.logit = logit
        }
    }

    @inline(__always)
    private static func siftDown(_ heap: inout [Candidate], _ index: Int, _ count: Int) {
        var idx = index
        while true {
            let left = 2 * idx + 1
            let right = 2 * idx + 2
            var smallest = idx
            if left < count && heap[left].logit < heap[smallest].logit {
                smallest = left
            }
            if right < count && heap[right].logit < heap[smallest].logit {
                smallest = right
            }
            if smallest != idx {
                heap.swapAt(idx, smallest)
                idx = smallest
            } else {
                break
            }
        }
    }

    /// Finds top-K candidates using an efficient min-heap over the logits array.
    public static func topKCandidates(
        logits: UnsafePointer<Float>,
        count: Int,
        k: Int
    ) -> [Candidate] {
        guard count > 0, k > 0 else { return [] }
        let actualK = min(k, count)
        var heap = [Candidate]()
        heap.reserveCapacity(actualK)

        for i in 0..<actualK {
            let val = logits[i]
            let sanitized = val.isNaN ? -Float.infinity : val
            heap.append(Candidate(token: llama_token(i), logit: sanitized))
        }

        for i in stride(from: actualK / 2 - 1, through: 0, by: -1) {
            siftDown(&heap, i, actualK)
        }

        var minVal = heap[0].logit
        for i in actualK..<count {
            let val = logits[i]
            guard !val.isNaN else { continue }
            if val > minVal {
                heap[0] = Candidate(token: llama_token(i), logit: val)
                siftDown(&heap, 0, actualK)
                minVal = heap[0].logit
            }
        }

        heap.sort { $0.logit > $1.logit }
        return heap
    }

    /// Computes softmax probabilities on candidates using Apple Accelerate vDSP & vForce routines in-place.
    public static func computeSoftmax(
        candidates: [Candidate],
        temperature: Float
    ) -> [Float] {
        let count = candidates.count
        guard count > 0 else { return [] }
        if count == 1 { return [1.0] }

        // Allocate a single probability buffer initialized with candidate logits
        var probs = candidates.map { $0.logit }

        // 1. Shift by -maxLogit to prevent exp overflow
        var maxVal: Float = 0
        var maxIdx: vDSP_Length = 0
        vDSP_maxvi(probs, 1, &maxVal, &maxIdx, vDSP_Length(count))

        guard !maxVal.isNaN && !maxVal.isInfinite else {
            var fallback = [Float](repeating: 0, count: count)
            fallback[0] = 1.0
            return fallback
        }

        var negMax = -maxVal
        vDSP_vsadd(probs, 1, &negMax, &probs, 1, vDSP_Length(count))

        // 2. Scale by temperature (in-place)
        let safeTemp = (temperature.isNaN || temperature <= 0.001) ? 0.001 : temperature
        var invTemp: Float = 1.0 / safeTemp
        vDSP_vsmul(probs, 1, &invTemp, &probs, 1, vDSP_Length(count))

        // 3. Vector exp using vvexpf (in-place)
        var countInt32 = Int32(count)
        vvexpf(&probs, probs, &countInt32)

        // 4. Sum of exponents
        var sumExp: Float = 0
        vDSP_sve(probs, 1, &sumExp, vDSP_Length(count))

        guard sumExp > 0 && !sumExp.isNaN else {
            var fallback = [Float](repeating: 0, count: count)
            fallback[0] = 1.0
            return fallback
        }

        // 5. Normalize probabilities (in-place)
        vDSP_vsdiv(probs, 1, &sumExp, &probs, 1, vDSP_Length(count))
        return probs
    }

    /// Fast greedy sampling via vDSP_maxvi (O(1) vectorized execution on Apple Silicon).
    public static func sampleGreedy(
        logits: UnsafePointer<Float>,
        count: Int
    ) -> llama_token {
        guard count > 0 else { return 0 }
        var maxVal: Float = 0
        var maxIdx: vDSP_Length = 0
        vDSP_maxvi(logits, 1, &maxVal, &maxIdx, vDSP_Length(count))
        return llama_token(maxIdx)
    }

    /// Sample token using Accelerate routines with temperature, top-K, and top-P.
    public static func sample(
        logits: UnsafePointer<Float>,
        count: Int,
        temperature: Float = 0.2,
        topK: Int = 40,
        topP: Float = 0.9,
        randomValue: Float? = nil
    ) -> llama_token {
        guard count > 0 else { return 0 }

        if temperature <= 0.05 || temperature.isNaN || topK <= 1 {
            return sampleGreedy(logits: logits, count: count)
        }

        let candidates = topKCandidates(logits: logits, count: count, k: topK)
        guard !candidates.isEmpty else { return 0 }
        if candidates.count == 1 { return candidates[0].token }

        let probs = computeSoftmax(candidates: candidates, temperature: temperature)

        var cutoff = candidates.count
        let effectiveTopP = (topP.isNaN || topP <= 0.0) ? 0.0 : min(1.0, topP)
        if effectiveTopP < 1.0 {
            var cumProb: Float = 0
            for i in 0..<candidates.count {
                cumProb += probs[i]
                if cumProb >= effectiveTopP {
                    cutoff = i + 1
                    break
                }
            }
        }

        if cutoff <= 1 {
            return candidates[0].token
        }

        var activeSum: Float = 0
        vDSP_sve(probs, 1, &activeSum, vDSP_Length(cutoff))
        guard activeSum > 0 && !activeSum.isNaN else {
            return candidates[0].token
        }

        let rawR: Float
        if let r = randomValue, !r.isNaN {
            rawR = max(0.0, min(1.0, r))
        } else {
            rawR = Float.random(in: 0..<1)
        }
        let r = rawR * activeSum

        var acc: Float = 0
        for i in 0..<cutoff {
            acc += probs[i]
            if acc >= r {
                return candidates[i].token
            }
        }
        return candidates[cutoff - 1].token
    }

    // Convenience overloads for Swift arrays
    public static func sampleGreedy(logits: [Float]) -> llama_token {
        logits.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress, !buf.isEmpty else { return 0 }
            return sampleGreedy(logits: base, count: buf.count)
        }
    }

    public static func sample(
        logits: [Float],
        temperature: Float = 0.2,
        topK: Int = 40,
        topP: Float = 0.9,
        randomValue: Float? = nil
    ) -> llama_token {
        logits.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress, !buf.isEmpty else { return 0 }
            return sample(
                logits: base,
                count: buf.count,
                temperature: temperature,
                topK: topK,
                topP: topP,
                randomValue: randomValue
            )
        }
    }
}

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
        if let b = batch {
            llama_batch_free(b)
        }
        if let c = context {
            llama_free(c)
        }
        if let m = model {
            llama_model_free(m)
        }
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

        self.currentModelPath = path
        self.isLoaded = true

        // Background Metal GPU model warmup pass: compiles compute kernels, faults mmap pages,
        // and initializes KV-cache buffers to eliminate 2-4s freeze on first word completion.
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.performWarmup()
        }
    }

    /// Vectorized token sampling from model logits.
    /// Extracts raw logits pointer via llama_get_logits_ith(ctx, -1) and processes
    /// on Apple Silicon vector hardware (vDSP_maxvi for greedy, vDSP routines for temperature/top-k/top-p).
    public func sampleToken(
        temperature: Float = 0.2,
        topK: Int = 40,
        topP: Float = 0.9,
        repeatPenalty: Float = 1.15,
        recentTokens: [llama_token] = []
    ) -> llama_token? {
        guard let ctx = context, let v = vocab else { return nil }
        guard let logitsPtr = llama_get_logits_ith(ctx, -1) else { return nil }
        let vocabSize = Int(llama_vocab_n_tokens(v))
        guard vocabSize > 0 else { return nil }

        // Apply repetition penalty if specified
        var savedLogits: [(Int, Float)] = []
        if repeatPenalty > 1.0 && !repeatPenalty.isNaN && !repeatPenalty.isInfinite && !recentTokens.isEmpty {
            savedLogits.reserveCapacity(min(recentTokens.count, 64))
            var seen = Set<llama_token>()
            for tok in recentTokens.suffix(64) {
                guard seen.insert(tok).inserted else { continue }
                let idx = Int(tok)
                guard idx >= 0 && idx < vocabSize else { continue }
                let original = logitsPtr[idx]
                savedLogits.append((idx, original))
                logitsPtr[idx] = original > 0 ? original / repeatPenalty : original * repeatPenalty
            }
        }
        defer {
            for (idx, original) in savedLogits {
                logitsPtr[idx] = original
            }
        }

        if temperature <= 0.05 || temperature.isNaN {
            return VectorizedSampler.sampleGreedy(logits: logitsPtr, count: vocabSize)
        } else {
            return VectorizedSampler.sample(
                logits: logitsPtr,
                count: vocabSize,
                temperature: temperature,
                topK: topK,
                topP: topP
            )
        }
    }

    /// Unload model and free all C/Metal memory buffers.
    public func unload() {
        if let b = batch {
            llama_batch_free(b)
            self.batch = nil
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
        self.activeStitchSession = nil
        if let c = context, let memory = llama_get_memory(c) {
            llama_memory_clear(memory, true)
        }
    }

    /// Background Metal GPU model warmup pass: compiles compute kernels, faults mmap pages,
    /// and initializes KV-cache buffers to eliminate 2-4s freeze on first word completion.
    /// Combines warmup inference and prefix cache reset into an uninterrupted actor operation
    /// so concurrent requests cannot interleave between generation and cache clearing.
    public func performWarmup() {
        guard isLoaded else { return }
        _ = try? generateContinuation(prompt: "<bos>", maxTokens: 1)
        clearPrefixCache()
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

    // MARK: - KV Cache Prefix Matching

    /// Computes the longest common token prefix length between cached prompt tokens and current prompt tokens.
    /// Leaves at least 1 token to decode so logits for the prompt tail are available for sampling.
    public static func commonPrefixLength(cached: [llama_token], current: [llama_token]) -> Int {
        var prefixLen = 0
        while prefixLen < cached.count &&
              prefixLen < current.count &&
              cached[prefixLen] == current[prefixLen] {
            prefixLen += 1
        }
        if prefixLen == current.count && prefixLen > 0 {
            prefixLen -= 1
        }
        return prefixLen
    }

    // MARK: - Generation

    /// Generates predictive continuation for the given prompt context.
    public func generateContinuation(
        prompt: String,
        maxTokens: Int = 16,
        temperature: Float = 0.2,
        stopSequences: [String] = ["<|im_end|>", "<|endoftext|>", "<|im_start|>", "<eos>", "\n"],
        onToken: (@Sendable (String) -> Void)? = nil
    ) throws -> String {
        guard isLoaded, let ctx = context, let v = vocab, var b = batch else {
            throw AILocalEngineError.notLoaded
        }
        defer { self.batch = b }

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

        var prefixLen = Self.commonPrefixLength(cached: cachedPromptTokens, current: promptTokens)

        if prefixLen > 0 {
            let removed = llama_memory_seq_rm(memory, 0, llama_pos(prefixLen), -1)
            if removed {
                prefixCacheHitCount += 1
            } else {
                prefixLen = 0
                llama_memory_clear(memory, true)
            }
        } else {
            llama_memory_clear(memory, true)
        }

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
        var recentTokens: [llama_token] = Array(promptTokens.suffix(64))

        for step in 0..<maxTokens {
            if Task.isCancelled {
                break
            }

            guard let nextTok = sampleToken(
                temperature: temperature,
                topK: 40,
                topP: 0.9,
                repeatPenalty: 1.15,
                recentTokens: recentTokens
            ) else {
                break
            }

            if llama_vocab_is_eog(v, nextTok) {
                break
            }

            let pieceBytes = tokenToBytes(token: nextTok)
            accumulatedBytes.append(contentsOf: pieceBytes)
            accumulatedText = String(decoding: accumulatedBytes, as: UTF8.self)
            generatedTokens.append(nextTok)
            recentTokens.append(nextTok)
            if recentTokens.count > 64 {
                recentTokens.removeFirst()
            }

            let validText = accumulatedText.replacingOccurrences(of: "\u{FFFD}", with: "")
            if !validText.isEmpty {
                onToken?(validText)
            }

            // Check stop sequences
            var shouldStop = false
            for stop in stopSequences {
                if stop == "\n" || stop == "\r" {
                    // Only treat newline as stop sequence after non-newline content has been generated.
                    // This prevents reasoning models from terminating immediately into empty output
                    // if they emit a leading newline after the pre-closed </think>\n block.
                    let stripped = accumulatedText.drop(while: { $0.isNewline })
                    if let range = stripped.range(of: stop) {
                        accumulatedText = String(stripped[..<range.lowerBound])
                        shouldStop = true
                        break
                    }
                } else if accumulatedText.contains(stop) {
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

        while accumulatedText.hasPrefix("\n") || accumulatedText.hasPrefix("\r") {
            accumulatedText = String(accumulatedText.dropFirst())
        }

        // Start stitch session for the generated result
        self.activeStitchSession = TokenStitchSession(prompt: prompt, fullSuggestion: accumulatedText)
        return accumulatedText
    }

    // MARK: - Token Stitching

    /// Returns whether the currently loaded model embeds a chat template in its metadata.
    public func hasChatTemplate() -> Bool {
        guard isLoaded, let m = model else { return false }
        return llama_model_chat_template(m, nil) != nil
    }

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
