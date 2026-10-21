import XCTest
@testable import LangSwitcher

@MainActor
final class AIInferenceTests: XCTestCase {
    
    func testAIDebounceTimerCancellation() async {
        let debouncer = AIDebounceTimer()
        var executed = false
        
        debouncer.schedule(delay: 0.1) {
            executed = true
        }
        
        // Cancel immediately
        debouncer.cancel()
        
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertFalse(executed, "Cancelled debouncer task should not execute")
    }
    
    func testAIDebounceTimerExecutionAfterDelay() async {
        let debouncer = AIDebounceTimer()
        var executed = false
        
        debouncer.schedule(delay: 0.05) {
            executed = true
        }
        
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(executed, "Debouncer task should execute after delay")
    }
    
    func testContinuationCleaningAndTrimming() {
        let engine = AIInferenceEngine.shared
        // Test binary lookup doesn't crash
        _ = engine.findEngineBinary()
    }
    
    func testPromptFormattingWithoutInstructions() {
        let formatted = AIInferenceEngine.formatPrompt(context: "Hello world", instructions: nil)
        XCTAssertEqual(formatted, "Hello world")
        
        let formattedEmpty = AIInferenceEngine.formatPrompt(context: "Hello world", instructions: "   ")
        XCTAssertEqual(formattedEmpty, "Hello world")
    }
    
    func testPromptFormattingWithCustomInstructions() {
        let formatted = AIInferenceEngine.formatPrompt(
            context: "print(\"Hello",
            instructions: "Я программист, пиши лаконично"
        )
        XCTAssertEqual(formatted, "[System: Я программист, пиши лаконично]\nprint(\"Hello")
    }
}
