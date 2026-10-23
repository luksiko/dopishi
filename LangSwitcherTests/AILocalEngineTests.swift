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
}
