import XCTest
@testable import LangSwitcher

final class AILocalEngineTests: XCTestCase {

    func testTokenStitchSessionBasicAdvance() {
        var session = TokenStitchSession(prompt: "Hello", fullSuggestion: " world, how are you?")
        XCTAssertEqual(session.remainingSuggestion, " world, how are you?")
        XCTAssertEqual(session.typedChars, "")

        let afterSpace = session.advance(with: " ")
        XCTAssertEqual(afterSpace, "world, how are you?")
        XCTAssertEqual(session.typedChars, " ")

        let afterW = session.advance(with: "w")
        XCTAssertEqual(afterW, "orld, how are you?")
        XCTAssertEqual(session.typedChars, " w")
    }

    func testTokenStitchSessionCaseInsensitive() {
        var session = TokenStitchSession(prompt: "при", fullSuggestion: "вет друг")
        
        // Capital 'В' should match lowercase 'в'
        let afterV = session.advance(with: "В")
        XCTAssertEqual(afterV, "ет друг")
        XCTAssertEqual(session.typedChars, "В")

        let afterE = session.advance(with: "е")
        XCTAssertEqual(afterE, "т друг")
    }

    func testTokenStitchSessionMismatchReturnsNil() {
        var session = TokenStitchSession(prompt: "test", fullSuggestion: " continuation")
        let mismatch = session.advance(with: "x")
        XCTAssertNil(mismatch)
        XCTAssertEqual(session.remainingSuggestion, " continuation")
    }

    func testTokenStitchSessionStringAdvance() {
        var session = TokenStitchSession(prompt: "abc", fullSuggestion: "defgh")
        let result = session.advance(with: "def")
        XCTAssertEqual(result, "gh")
        XCTAssertEqual(session.typedChars, "def")

        // Partial mismatch should be transactional: nothing modified
        var session2 = TokenStitchSession(prompt: "abc", fullSuggestion: "defgh")
        let mismatch = session2.advance(with: "dez")
        XCTAssertNil(mismatch)
        XCTAssertEqual(session2.remainingSuggestion, "defgh")
        XCTAssertEqual(session2.typedChars, "")
    }

    func testAILocalEngineErrorDescriptions() {
        let err1 = AILocalEngineError.modelNotFound("/path/to/missing.gguf")
        XCTAssertTrue(err1.errorDescription?.contains("missing.gguf") == true)

        let err2 = AILocalEngineError.notLoaded
        XCTAssertEqual(err2.errorDescription, "Local AI model is not loaded")

        let err3 = AILocalEngineError.decodeFailed(1)
        XCTAssertTrue(err3.errorDescription?.contains("1") == true)
    }

    func testAILocalEngineUnloadedState() async {
        let engine = AILocalEngine()
        let isLoaded = await engine.isLoaded
        XCTAssertFalse(isLoaded)

        let path = await engine.currentModelPath
        XCTAssertNil(path)

        // Attempting to generate without loaded model should throw .notLoaded
        do {
            _ = try await engine.generateContinuation(prompt: "test")
            XCTFail("Should have thrown .notLoaded")
        } catch let error as AILocalEngineError {
            XCTAssertEqual(error, .notLoaded)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // Attempting to load non-existent file should throw .modelNotFound
        do {
            try await engine.loadModel(path: "/non/existent/model.gguf")
            XCTFail("Should have thrown .modelNotFound")
        } catch let error as AILocalEngineError {
            if case .modelNotFound(let p) = error {
                XCTAssertEqual(p, "/non/existent/model.gguf")
            } else {
                XCTFail("Expected .modelNotFound, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAILocalEngineStitchLifecycle() async {
        let engine = AILocalEngine()
        
        let initialStitch = await engine.attemptStitch(typedText: "a")
        XCTAssertNil(initialStitch)

        await engine.resetStitch()
        let session = await engine.activeStitchSession
        XCTAssertNil(session)
    }

    func testPrefixCacheClearAndState() async {
        let engine = AILocalEngine()
        let initialHits = await engine.prefixCacheHitCount
        XCTAssertEqual(initialHits, 0)

        // Clear cache should be safe even when unloaded
        await engine.clearPrefixCache()
        let hitsAfterClear = await engine.prefixCacheHitCount
        XCTAssertEqual(hitsAfterClear, 0)

        await engine.unload()
        let hitsAfterUnload = await engine.prefixCacheHitCount
        XCTAssertEqual(hitsAfterUnload, 0)
    }

    func testHasChatTemplateWhenUnloaded() async {
        let engine = AILocalEngine()
        let hasTemplate = await engine.hasChatTemplate()
        XCTAssertFalse(hasTemplate)
    }

    func testPerformWarmupWhenUnloadedIsSafe() async {
        let engine = AILocalEngine()
        await engine.performWarmup()
        let isLoaded = await engine.isLoaded
        XCTAssertFalse(isLoaded)
    }

    func testClearPrefixCacheResetsActiveStitchSession() async {
        let engine = AILocalEngine()
        await engine.clearPrefixCache()
        let session = await engine.activeStitchSession
        XCTAssertNil(session)
    }

    func testStrippingGeneratedMarkupRemovesStandaloneVoidAndFormTags() {
        let raw = "<code><input></code> будет выбран."
        let stripped = AIInferenceEngine.strippingGeneratedMarkup(raw)
        XCTAssertEqual(stripped, " будет выбран.")
    }

    func testResolveFocusedTextNodeTraversesInsideUnconfirmedWebArea() {
        // Root (AXGroup, confirmed) -> child AXWebArea (unconfirmed) -> grandchild AXTextArea (focused)
        let nodes: [Int: (role: String?, subrole: String?, focused: Bool, focusedChild: Int?, children: [Int])] = [
            1: ("AXGroup", "AXLandmarkRegion", false, nil, [2]),
            2: ("AXWebArea", nil, false, 3, [3]),
            3: ("AXTextArea", nil, true, nil, [])
        ]
        let resolved = AccessibilityService.resolveFocusedTextNode(
            root: 1,
            attributes: { id in
                let n = nodes[id]!
                return (n.role, n.subrole, n.focused)
            },
            focusedChild: { id in nodes[id]?.focusedChild },
            children: { id in nodes[id]?.children ?? [] }
        )
        XCTAssertEqual(resolved, 3)
    }

    func testCommonPrefixLengthMatching() {
        // Disjoint tokens -> prefixLen = 0
        XCTAssertEqual(AILocalEngine.commonPrefixLength(cached: [1, 2, 3], current: [4, 5, 6]), 0)

        // Empty cached -> prefixLen = 0
        XCTAssertEqual(AILocalEngine.commonPrefixLength(cached: [], current: [1, 2, 3]), 0)

        // Empty current -> prefixLen = 0
        XCTAssertEqual(AILocalEngine.commonPrefixLength(cached: [1, 2], current: []), 0)

        // Partial match
        XCTAssertEqual(AILocalEngine.commonPrefixLength(cached: [1, 2, 3, 4], current: [1, 2, 5]), 2)

        // Identical tokens leaves 1 token for sampling logits
        XCTAssertEqual(AILocalEngine.commonPrefixLength(cached: [1, 2, 3], current: [1, 2, 3]), 2)

        // Current longer than cached
        XCTAssertEqual(AILocalEngine.commonPrefixLength(cached: [1, 2, 3], current: [1, 2, 3, 4, 5]), 3)
    }

    // MARK: - Vectorized Sampler (Accelerate vDSP) Tests

    func testVectorizedSamplerGreedyPicksMaximumLogit() {
        let logits: [Float] = [1.2, 5.8, -3.1, 12.4, 9.0, 0.5]
        let token = VectorizedSampler.sampleGreedy(logits: logits)
        XCTAssertEqual(token, 3, "Index 3 has the highest logit (12.4)")
    }

    func testVectorizedSamplerGreedyEdgeCases() {
        // Empty array returns 0
        XCTAssertEqual(VectorizedSampler.sampleGreedy(logits: []), 0)

        // Single element returns 0
        XCTAssertEqual(VectorizedSampler.sampleGreedy(logits: [42.0]), 0)

        // All negative values
        let negativeLogits: [Float] = [-100.0, -25.5, -5.2, -80.0]
        XCTAssertEqual(VectorizedSampler.sampleGreedy(logits: negativeLogits), 2, "Least negative is -5.2 at index 2")

        // Large 256K vocabulary (e.g. Gemma 2B)
        var vocab256K = [Float](repeating: -10.0, count: 256_000)
        vocab256K[185_432] = 99.5
        let sampled = VectorizedSampler.sampleGreedy(logits: vocab256K)
        XCTAssertEqual(sampled, 185_432, "Must accurately find max across 256,000 tokens")
    }

    func testVectorizedSamplerTopKCandidates() {
        let logits: [Float] = [10.0, 50.0, 20.0, 40.0, 30.0]
        logits.withUnsafeBufferPointer { buf in
            let candidates = VectorizedSampler.topKCandidates(logits: buf.baseAddress!, count: buf.count, k: 3)
            XCTAssertEqual(candidates.count, 3)
            XCTAssertEqual(candidates[0].token, 1) // logit 50.0
            XCTAssertEqual(candidates[0].logit, 50.0)
            XCTAssertEqual(candidates[1].token, 3) // logit 40.0
            XCTAssertEqual(candidates[1].logit, 40.0)
            XCTAssertEqual(candidates[2].token, 4) // logit 30.0
            XCTAssertEqual(candidates[2].logit, 30.0)
        }
    }

    func testVectorizedSamplerTopKWhenKExceedsCount() {
        let logits: [Float] = [5.0, 15.0]
        logits.withUnsafeBufferPointer { buf in
            let candidates = VectorizedSampler.topKCandidates(logits: buf.baseAddress!, count: buf.count, k: 10)
            XCTAssertEqual(candidates.count, 2)
            XCTAssertEqual(candidates[0].token, 1)
            XCTAssertEqual(candidates[1].token, 0)
        }
    }

    func testVectorizedSamplerSoftmaxSumAndOverflowProtection() {
        let candidates = [
            VectorizedSampler.Candidate(token: 0, logit: 1000.0),
            VectorizedSampler.Candidate(token: 1, logit: 999.0),
            VectorizedSampler.Candidate(token: 2, logit: 998.0)
        ]

        let probs = VectorizedSampler.computeSoftmax(candidates: candidates, temperature: 1.0)
        XCTAssertEqual(probs.count, 3)

        // Softmax sum should equal ~1.0
        let sum = probs.reduce(0, +)
        XCTAssertEqual(sum, 1.0, accuracy: 0.001)

        // Token 0 should have the largest probability
        XCTAssertGreaterThan(probs[0], probs[1])
        XCTAssertGreaterThan(probs[1], probs[2])

        // Verify no NaN or Inf despite huge 1000.0 logits due to vDSP -maxVal shift
        XCTAssertFalse(probs[0].isNaN)
        XCTAssertFalse(probs[0].isInfinite)
    }

    func testVectorizedSamplerTemperatureSharpeningAndFlattening() {
        let candidates = [
            VectorizedSampler.Candidate(token: 0, logit: 2.0),
            VectorizedSampler.Candidate(token: 1, logit: 1.0)
        ]

        let sharpProbs = VectorizedSampler.computeSoftmax(candidates: candidates, temperature: 0.1)
        let flatProbs = VectorizedSampler.computeSoftmax(candidates: candidates, temperature: 2.0)

        // Lower temperature should make top token much more probable
        XCTAssertGreaterThan(sharpProbs[0], 0.99)
        // Higher temperature should make probabilities closer to uniform
        XCTAssertLessThan(flatProbs[0], 0.7)
        XCTAssertGreaterThan(flatProbs[1], 0.3)
    }

    func testVectorizedSamplerGreedyFastPathOnLowTemperature() {
        // Temperature <= 0.05 must take greedy path directly
        let logits: [Float] = [1.0, 10.0, 3.0]
        let sampled = VectorizedSampler.sample(logits: logits, temperature: 0.02, topK: 40)
        XCTAssertEqual(sampled, 1)
    }

    func testVectorizedSamplerDeterministicSamplingWithRandomValue() {
        // Candidate 0 has ~52.5% prob, Candidate 1 has ~47.5% prob
        let logits: [Float] = [10.0, 9.9]

        // r = 0.1 should pick candidate 0
        let pick0 = VectorizedSampler.sample(
            logits: logits,
            temperature: 1.0,
            topK: 2,
            topP: 1.0,
            randomValue: 0.1
        )
        XCTAssertEqual(pick0, 0)

        // r = 0.9 should pick candidate 1
        let pick1 = VectorizedSampler.sample(
            logits: logits,
            temperature: 1.0,
            topK: 2,
            topP: 1.0,
            randomValue: 0.9
        )
        XCTAssertEqual(pick1, 1)
    }

    func testVectorizedSamplerTopPNucleusCutoff() {
        // Logits: token 0 dominates
        let logits: [Float] = [20.0, 5.0, 2.0]

        // With topP = 0.8, only token 0 enters the nucleus since its softmax prob is > 0.99
        let picked = VectorizedSampler.sample(
            logits: logits,
            temperature: 1.0,
            topK: 3,
            topP: 0.8,
            randomValue: 0.99 // Even with high r, cannot pick excluded tokens
        )
        XCTAssertEqual(picked, 0)
    }

    func testVectorizedSamplerTopKHandlesNaNsInInitialWindow() {
        // Token 0 has NaN logit, but tokens 3 and 4 have highest valid logits
        let logits: [Float] = [Float.nan, 10.0, 20.0, 500.0, 1000.0]
        logits.withUnsafeBufferPointer { buf in
            let candidates = VectorizedSampler.topKCandidates(logits: buf.baseAddress!, count: buf.count, k: 3)
            XCTAssertEqual(candidates.count, 3)
            // NaN must not block the heap or be selected as top token
            XCTAssertEqual(candidates[0].token, 4) // 1000.0
            XCTAssertEqual(candidates[0].logit, 1000.0)
            XCTAssertEqual(candidates[1].token, 3) // 500.0
            XCTAssertEqual(candidates[1].logit, 500.0)
            XCTAssertEqual(candidates[2].token, 2) // 20.0
            XCTAssertEqual(candidates[2].logit, 20.0)
        }
    }

    func testVectorizedSamplerTopKHandlesNaNsInSubsequentWindow() {
        let logits: [Float] = [10.0, 50.0, 20.0, Float.nan, 80.0, Float.nan]
        logits.withUnsafeBufferPointer { buf in
            let candidates = VectorizedSampler.topKCandidates(logits: buf.baseAddress!, count: buf.count, k: 3)
            XCTAssertEqual(candidates.count, 3)
            XCTAssertEqual(candidates[0].token, 4) // 80.0
            XCTAssertEqual(candidates[1].token, 1) // 50.0
            XCTAssertEqual(candidates[2].token, 2) // 20.0
        }
    }

    func testVectorizedSamplerSoftmaxDegenerateAndInfiniteFallback() {
        // All candidates have -infinity or NaN
        let candidates = [
            VectorizedSampler.Candidate(token: 0, logit: -Float.infinity),
            VectorizedSampler.Candidate(token: 1, logit: -Float.infinity)
        ]
        let probs = VectorizedSampler.computeSoftmax(candidates: candidates, temperature: 1.0)
        XCTAssertEqual(probs.count, 2)
        XCTAssertEqual(probs[0], 1.0)
        XCTAssertEqual(probs[1], 0.0)
    }

    func testVectorizedSamplerResilienceToNaNHyperparameters() {
        let logits: [Float] = [10.0, 50.0, 20.0]

        // NaN temperature should fall back cleanly to greedy sampling (token 1 = 50.0)
        let sampledWithNanTemp = VectorizedSampler.sample(
            logits: logits,
            temperature: Float.nan,
            topK: 3
        )
        XCTAssertEqual(sampledWithNanTemp, 1)

        // NaN randomValue should fall back cleanly without selecting excluded or crashing
        let sampledWithNanRandom = VectorizedSampler.sample(
            logits: logits,
            temperature: 1.0,
            topK: 3,
            topP: Float.nan,
            randomValue: Float.nan
        )
        XCTAssertTrue([0, 1, 2].contains(sampledWithNanRandom))
    }
}

