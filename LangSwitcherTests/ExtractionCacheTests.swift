import XCTest
@testable import LangSwitcher

final class ExtractionCacheTests: XCTestCase {
    
    func testExtractionCacheRecordAdvance() {
        let initialRect = CGRect(x: 100, y: 200, width: 2, height: 16)
        let fieldRect = CGRect(x: 50, y: 150, width: 500, height: 100)
        
        var record = ExtractionCacheRecord(
            fieldIdentifier: "testField",
            bundleID: "com.example.app",
            elementHash: 12345,
            approach: .standardAX,
            textBeforeCaret: "hello",
            textAfterCaret: " world",
            selectedText: "",
            caretLocation: 5,
            fullTextLength: 11,
            caretRect: initialRect,
            fieldRect: fieldRect,
            lastUpdateTime: 100.0,
            estimatedCharWidth: 8.0
        )
        
        let ctxBefore = record.toCaretContext()
        XCTAssertEqual(ctxBefore.textBeforeCaret, "hello")
        XCTAssertEqual(ctxBefore.caretLocation, 5)
        XCTAssertEqual(ctxBefore.fullTextLength, 11)
        
        // Advance with "!"
        record.advance(with: "!", time: 100.1)
        
        XCTAssertEqual(record.textBeforeCaret, "hello!")
        XCTAssertEqual(record.caretLocation, 6)
        XCTAssertEqual(record.fullTextLength, 12)
        XCTAssertEqual(record.lastUpdateTime, 100.1)
        XCTAssertEqual(record.caretRect?.origin.x, 108.0)
        XCTAssertEqual(record.caretRect?.origin.y, 200.0)
        
        // Advance with multi-character string
        record.advance(with: " test", time: 100.2)
        XCTAssertEqual(record.textBeforeCaret, "hello! test")
        XCTAssertEqual(record.caretLocation, 11)
        XCTAssertEqual(record.fullTextLength, 17)
        XCTAssertEqual(record.caretRect?.origin.x, 108.0 + (8.0 * 5))
    }
    
    func testCaretClampingToFieldRect() {
        let fieldRect = CGRect(x: 0, y: 0, width: 200, height: 50)
        var record = ExtractionCacheRecord(
            fieldIdentifier: "testField",
            bundleID: "com.example.app",
            elementHash: 12345,
            approach: .standardAX,
            textBeforeCaret: "long text",
            textAfterCaret: "",
            selectedText: "",
            caretLocation: 9,
            fullTextLength: 9,
            caretRect: CGRect(x: 195, y: 10, width: 2, height: 16),
            fieldRect: fieldRect,
            lastUpdateTime: 10.0,
            estimatedCharWidth: 10.0
        )
        
        // Advancing past fieldRect boundary should clamp within fieldRect.maxX - 2
        record.advance(with: "more text", time: 10.1)
        XCTAssertEqual(record.caretRect?.origin.x, 198.0)
    }
    
    func testCursorRetryPlanLifecycle() {
        var plan = CursorRetryPlan()
        XCTAssertTrue(plan.isInvalidated)
        XCTAssertEqual(plan.retryCount, 0)
        
        // Successful sync
        plan.recordSuccessfulSync(at: 50.0)
        XCTAssertFalse(plan.isInvalidated)
        XCTAssertNil(plan.lastInvalidationReason)
        XCTAssertEqual(plan.lastSyncTime, 50.0)
        
        // Invalidate on navigation key
        plan.invalidate(reason: .navigationKey(keyCode: 0x33))
        XCTAssertTrue(plan.isInvalidated)
        XCTAssertEqual(plan.lastInvalidationReason, .navigationKey(keyCode: 0x33))
        
        // Retry backoffs
        XCTAssertTrue(plan.shouldRetry())
        XCTAssertEqual(plan.nextRetryDelay(), 0.05)
        
        plan.recordFailure()
        XCTAssertEqual(plan.retryCount, 1)
        XCTAssertEqual(plan.nextRetryDelay(), 0.15)
        
        plan.recordFailure()
        XCTAssertEqual(plan.retryCount, 2)
        XCTAssertEqual(plan.nextRetryDelay(), 0.30)
        
        plan.recordFailure()
        XCTAssertEqual(plan.retryCount, 3)
        XCTAssertFalse(plan.shouldRetry())
        XCTAssertNil(plan.nextRetryDelay())
    }
    
    func testCursorRetryPlanDesyncDetection() {
        XCTAssertFalse(CursorRetryPlan.detectDesync(cachedTextBefore: "hello", actualTextBefore: "hello"))
        XCTAssertFalse(CursorRetryPlan.detectDesync(cachedTextBefore: "hello world", actualTextBefore: "hello"))
        XCTAssertFalse(CursorRetryPlan.detectDesync(cachedTextBefore: "hello", actualTextBefore: "hello world"))
        XCTAssertTrue(CursorRetryPlan.detectDesync(cachedTextBefore: "hello", actualTextBefore: "goodbye"))
    }
    
    func testExtractionCacheManagerValidityAndAging() {
        let manager = ExtractionCacheManager()
        manager.maxIdleAge = 0.5
        
        let initialContext = CaretContext(
            fieldIdentifier: "field1",
            textBeforeCaret: "abc",
            textAfterCaret: "def",
            selectedText: "",
            caretLocation: 3,
            fullTextLength: 6
        )
        
        manager.update(
            context: initialContext,
            bundleID: "com.test.app",
            elementHash: 999,
            approach: .standardAX,
            caretRect: CGRect(x: 10, y: 20, width: 2, height: 16),
            fieldRect: CGRect(x: 0, y: 0, width: 200, height: 100),
            estimatedCharWidth: 8.0,
            time: 100.0
        )
        
        // Cache is valid immediately
        XCTAssertTrue(manager.isCacheValid(for: "field1", currentTime: 100.1))
        XCTAssertEqual(manager.getCachedContext(currentTime: 100.1)?.textBeforeCaret, "abc")
        XCTAssertEqual(manager.getCachedCaretBounds(currentTime: 100.1)?.caret.origin.x, 10.0)
        
        // Cache for different field returns false
        XCTAssertFalse(manager.isCacheValid(for: "otherField", currentTime: 100.1))
        
        // Advance prediction
        manager.advance(characters: "d", time: 100.2)
        XCTAssertEqual(manager.getCachedContext(currentTime: 100.2)?.textBeforeCaret, "abcd")
        XCTAssertEqual(manager.getCachedContext(currentTime: 100.2)?.caretLocation, 4)
        XCTAssertEqual(manager.getCachedCaretBounds(currentTime: 100.2)?.caret.origin.x, 18.0)
        
        // Cache expires after maxIdleAge
        XCTAssertFalse(manager.isCacheValid(for: "field1", currentTime: 100.8))
        XCTAssertNil(manager.getCachedContext(currentTime: 100.8))
        
        // Invalidation explicitly invalidates
        manager.invalidate(reason: .focusChanged)
        XCTAssertFalse(manager.isCacheValid(for: "field1", currentTime: 100.2))
        XCTAssertNil(manager.getCachedContext(currentTime: 100.2))
    }
    
    func testRecordFailureAndRetryPlan() {
        let manager = ExtractionCacheManager()
        XCTAssertEqual(manager.retryPlan.retryCount, 0)
        XCTAssertEqual(manager.retryPlan.nextRetryDelay(), 0.05)
        
        manager.recordFailure()
        XCTAssertEqual(manager.retryPlan.retryCount, 1)
        XCTAssertEqual(manager.retryPlan.nextRetryDelay(), 0.15)
        
        manager.recordFailure()
        XCTAssertEqual(manager.retryPlan.retryCount, 2)
        XCTAssertEqual(manager.retryPlan.nextRetryDelay(), 0.30)
        
        manager.recordFailure()
        XCTAssertEqual(manager.retryPlan.retryCount, 3)
        XCTAssertFalse(manager.retryPlan.shouldRetry())
    }
    
    func testUpdatePreservesCaretBounds() {
        let manager = ExtractionCacheManager()
        let ctx = CaretContext(
            fieldIdentifier: "fieldX",
            textBeforeCaret: "foo",
            textAfterCaret: "",
            selectedText: "",
            caretLocation: 3,
            fullTextLength: 3
        )
        
        // Initial update with bounds
        manager.update(
            context: ctx,
            bundleID: "com.test.app",
            elementHash: 111,
            approach: .standardAX,
            caretRect: CGRect(x: 50, y: 100, width: 2, height: 16),
            fieldRect: CGRect(x: 0, y: 0, width: 400, height: 200),
            time: 10.0
        )
        XCTAssertEqual(manager.currentRecord?.caretRect?.origin.x, 50.0)
        
        // Subsequent update without bounds (passing nil) should preserve previous bounds
        let updatedCtx = CaretContext(
            fieldIdentifier: "fieldX",
            textBeforeCaret: "foob",
            textAfterCaret: "",
            selectedText: "",
            caretLocation: 4,
            fullTextLength: 4
        )
        manager.update(
            context: updatedCtx,
            bundleID: "com.test.app",
            elementHash: 111,
            approach: .standardAX,
            caretRect: nil,
            fieldRect: nil,
            time: 10.1
        )
        XCTAssertEqual(manager.currentRecord?.caretRect?.origin.x, 50.0)
        XCTAssertEqual(manager.currentRecord?.fieldRect?.width, 400.0)
    }
    
    func testUpdateDetectsDesync() {
        let manager = ExtractionCacheManager()
        let ctx1 = CaretContext(
            fieldIdentifier: "fieldSync",
            textBeforeCaret: "hello",
            textAfterCaret: "",
            selectedText: "",
            caretLocation: 5,
            fullTextLength: 5
        )
        manager.update(
            context: ctx1,
            bundleID: "com.test.app",
            elementHash: 222,
            approach: .standardAX,
            caretRect: nil,
            fieldRect: nil,
            time: 10.0
        )
        XCTAssertFalse(manager.retryPlan.isInvalidated)
        
        // Subsequent update with completely different text triggers desync detection
        let ctxDiverged = CaretContext(
            fieldIdentifier: "fieldSync",
            textBeforeCaret: "completely different",
            textAfterCaret: "",
            selectedText: "",
            caretLocation: 20,
            fullTextLength: 20
        )
        manager.update(
            context: ctxDiverged,
            bundleID: "com.test.app",
            elementHash: 222,
            approach: .standardAX,
            caretRect: nil,
            fieldRect: nil,
            time: 10.1
        )
        XCTAssertTrue(manager.retryPlan.isInvalidated)
        XCTAssertEqual(
            manager.retryPlan.lastInvalidationReason,
            .desyncDetected(reason: "Context text diverged from predicted buffer")
        )
    }
}
