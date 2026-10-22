import Foundation

// MARK: - Benchmark Sample & Report Models

struct BenchmarkSample: Identifiable, Equatable {
    var id = UUID()
    let prompt: String
    let continuation: String
    let ttftMs: Double
    let totalDurationMs: Double
    let tokensCount: Int
    let tokensPerSecond: Double
    let isAppropriate: Bool
}

struct BenchmarkReport: Equatable {
    let modelName: String
    let date: Date
    let averageTTFTMs: Double
    let averageLatencyMs: Double
    let averageTokensPerSecond: Double
    let successRate: Double
    let samples: [BenchmarkSample]
}

// MARK: - AI Model Profiler
// Measures real-time latency, TTFT, token speed, and continuation quality on standardized prompts.

@MainActor
final class AIModelProfiler: ObservableObject {
    
    static let shared = AIModelProfiler()
    
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var currentProgress: Double = 0.0
    @Published private(set) var lastReport: BenchmarkReport?
    
    struct TestCase: Sendable {
        let prompt: String
        let expectedScript: String // "ru" or "en"
    }
    
    nonisolated static let standardTestCases: [TestCase] = [
        TestCase(prompt: "Теперь при нажатии Tab следующее ", expectedScript: "ru"),
        TestCase(prompt: "Функция возвращает массив из ", expectedScript: "ru"),
        TestCase(prompt: "Please let me know if you have any ", expectedScript: "en"),
        TestCase(prompt: "The application failed to compile because of ", expectedScript: "en"),
        TestCase(prompt: "Сегодня на встрече мы обсудили ", expectedScript: "ru")
    ]
    
    /// Run benchmark on the currently active model
    @discardableResult
    func runBenchmark(testCases: [TestCase] = standardTestCases) async -> BenchmarkReport? {
        guard !isRunning else { return lastReport }
        
        let engine = AIInferenceEngine.shared
        guard await engine.ensureRunning() else {
            return nil
        }
        
        isRunning = true
        currentProgress = 0.0
        defer {
            isRunning = false
            currentProgress = 1.0
        }
        
        let modelName = (engine.currentLoadedModelPath as NSString?)?.lastPathComponent ?? "Unknown Model"
        var samples: [BenchmarkSample] = []
        
        for (index, test) in testCases.enumerated() {
            let start = DispatchTime.now()
            var firstTokenTime: DispatchTime?
            var accumulatedText = ""
            var tokenCount = 0
            
            let result = await engine.predictContinuationStream(
                context: test.prompt,
                afterCaret: "",
                wordBuffer: "",
                maxWords: 4,
                customInstructions: nil
            ) { partial in
                if firstTokenTime == nil {
                    firstTokenTime = DispatchTime.now()
                }
                tokenCount += 1
                accumulatedText = partial
            }
            
            let end = DispatchTime.now()
            let totalMs = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
            let ttftMs: Double
            if let ft = firstTokenTime {
                ttftMs = Double(ft.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
            } else {
                ttftMs = totalMs
            }
            
            let finalOutput = result ?? accumulatedText
            let trimmed = finalOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasOutput = !trimmed.isEmpty
            let wordCount = hasOutput ? trimmed.split(separator: " ").count : 0
            let tokenMultiplier = (test.expectedScript == "ru") ? 3 : 2
            let effectiveTokens = hasOutput ? max(tokenCount, max(1, wordCount * tokenMultiplier)) : 0
            let generationDurationMs = max(1.0, totalMs - (firstTokenTime != nil ? ttftMs : 0.0))
            let tps = (effectiveTokens > 0) ? (Double(effectiveTokens) / (generationDurationMs / 1000.0)) : 0.0
            
            // Check appropriateness: non-empty, matching script, no leftover tags
            let isCyrillic = AIInferenceEngine.containsCyrillic(finalOutput)
            let matchesScript = (test.expectedScript == "ru") ? isCyrillic : !isCyrillic
            let hasMarkup = finalOutput.contains("<") || finalOutput.contains(">")
            let isAppropriate = hasOutput
                && matchesScript
                && !hasMarkup
            
            let sample = BenchmarkSample(
                prompt: test.prompt,
                continuation: finalOutput,
                ttftMs: ttftMs,
                totalDurationMs: totalMs,
                tokensCount: effectiveTokens,
                tokensPerSecond: tps,
                isAppropriate: isAppropriate
            )
            samples.append(sample)
            currentProgress = Double(index + 1) / Double(testCases.count)
        }
        
        guard !samples.isEmpty else { return nil }
        
        let validSamples = samples.filter { !$0.continuation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let avgTTFT = validSamples.isEmpty ? 0.0 : (validSamples.map(\.ttftMs).reduce(0, +) / Double(validSamples.count))
        let avgLatency = samples.map(\.totalDurationMs).reduce(0, +) / Double(samples.count)
        let avgTPS = validSamples.isEmpty ? 0.0 : (validSamples.map(\.tokensPerSecond).reduce(0, +) / Double(validSamples.count))
        let successCount = samples.filter(\.isAppropriate).count
        let successRate = Double(successCount) / Double(samples.count)
        
        let report = BenchmarkReport(
            modelName: modelName,
            date: Date(),
            averageTTFTMs: avgTTFT,
            averageLatencyMs: avgLatency,
            averageTokensPerSecond: avgTPS,
            successRate: successRate,
            samples: samples
        )
        self.lastReport = report
        return report
    }
}
