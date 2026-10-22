import XCTest
@testable import LangSwitcher

@MainActor
final class AIModelProfilerTests: XCTestCase {
    
    func testStandardTestCasesContainRussianAndEnglish() {
        let cases = AIModelProfiler.standardTestCases
        XCTAssertGreaterThanOrEqual(cases.count, 4)
        
        let russianCases = cases.filter { $0.expectedScript == "ru" }
        let englishCases = cases.filter { $0.expectedScript == "en" }
        
        XCTAssertFalse(russianCases.isEmpty)
        XCTAssertFalse(englishCases.isEmpty)
        XCTAssertTrue(russianCases.contains(where: { $0.prompt.contains("Tab") }))
    }
    
    func testBenchmarkReportAggregation() {
        let sample1 = BenchmarkSample(
            prompt: "Prompt 1",
            continuation: "Continuation 1",
            ttftMs: 150.0,
            totalDurationMs: 400.0,
            tokensCount: 8,
            tokensPerSecond: 20.0,
            isAppropriate: true
        )
        
        let sample2 = BenchmarkSample(
            prompt: "Prompt 2",
            continuation: "Continuation 2",
            ttftMs: 250.0,
            totalDurationMs: 600.0,
            tokensCount: 12,
            tokensPerSecond: 20.0,
            isAppropriate: false
        )
        
        let report = BenchmarkReport(
            modelName: "TestModel",
            date: Date(),
            averageTTFTMs: 200.0,
            averageLatencyMs: 500.0,
            averageTokensPerSecond: 20.0,
            successRate: 0.5,
            samples: [sample1, sample2]
        )
        
        XCTAssertEqual(report.averageTTFTMs, 200.0)
        XCTAssertEqual(report.averageLatencyMs, 500.0)
        XCTAssertEqual(report.averageTokensPerSecond, 20.0)
        XCTAssertEqual(report.successRate, 0.5)
        XCTAssertEqual(report.samples.count, 2)
    }

    func testBenchmarkSampleAppropriatenessForEmptyContinuation() {
        let sample = BenchmarkSample(
            prompt: "Test prompt",
            continuation: "",
            ttftMs: 25.0,
            totalDurationMs: 25.0,
            tokensCount: 0,
            tokensPerSecond: 0.0,
            isAppropriate: false
        )
        XCTAssertFalse(sample.isAppropriate)
        XCTAssertEqual(sample.tokensCount, 0)
        XCTAssertEqual(sample.tokensPerSecond, 0.0)
    }
}
