import Foundation
import AppKit

// MARK: - Text Extraction Approach
/// Strategy used to extract text and cursor position from different application categories.
enum TextExtractionApproach: String, Equatable, CaseIterable {
    /// Standard AppKit / Cocoa UI controls (NSTextField, NSTextView with kAXSelectedTextRangeAttribute).
    case standardAX
    /// WebKit / Safari / Mail / Google Docs marker range attributes.
    case webKitMarker
    /// macOS Apple Terminal (`com.apple.Terminal`) scroll area / text view inspection.
    case terminalLastPage
    /// GPU and xterm terminal emulators (iTerm2, Ghostty, Alacritty, Warp) screen buffer inspection.
    case xtermScreen
}

// MARK: - Cursor Retry Plan
/// Manages retry strategy and invalidation tracking when synchronization between local typing
/// prediction and actual AX accessibility state diverges or requires verification.
struct CursorRetryPlan: Equatable {
    
    enum InvalidationReason: Equatable {
        case focusChanged
        case navigationKey(keyCode: UInt16)
        case mouseClick
        case typingPaused
        case desyncDetected(reason: String)
        case replacementApplied
        case explicitReset
    }
    
    private(set) var retryCount: Int = 0
    let maxRetries: Int = 3
    let retryBackoffs: [TimeInterval] = [0.05, 0.15, 0.30]
    private(set) var isInvalidated: Bool = true
    private(set) var lastInvalidationReason: InvalidationReason?
    private(set) var lastSyncTime: TimeInterval = 0
    
    init() {}
    
    mutating func invalidate(reason: InvalidationReason) {
        isInvalidated = true
        lastInvalidationReason = reason
        retryCount = 0
    }
    
    mutating func recordSuccessfulSync(at time: TimeInterval) {
        isInvalidated = false
        lastInvalidationReason = nil
        retryCount = 0
        lastSyncTime = time
    }
    
    mutating func recordFailure() {
        retryCount += 1
    }
    
    func shouldRetry() -> Bool {
        retryCount < maxRetries
    }
    
    func nextRetryDelay() -> TimeInterval? {
        guard shouldRetry() else { return nil }
        let idx = min(retryCount, retryBackoffs.count - 1)
        return retryBackoffs[idx]
    }
    
    /// Detects whether actual AX text diverges from locally cached and advanced text.
    static func detectDesync(cachedTextBefore: String, actualTextBefore: String) -> Bool {
        if cachedTextBefore == actualTextBefore { return false }
        // If actual has diverged in prefix or length, signal desync
        if actualTextBefore.count < cachedTextBefore.count {
            return !cachedTextBefore.hasPrefix(actualTextBefore)
        } else {
            return !actualTextBefore.hasPrefix(cachedTextBefore)
        }
    }
}

// MARK: - Extraction Cache Record
/// Locally cached snapshot of active element text and caret coordinates.
struct ExtractionCacheRecord: Equatable {
    let fieldIdentifier: String
    let bundleID: String
    let elementHash: CFHashCode
    var approach: TextExtractionApproach
    var textBeforeCaret: String
    var textAfterCaret: String
    var selectedText: String
    var caretLocation: Int
    var fullTextLength: Int
    var caretRect: CGRect?
    var fieldRect: CGRect?
    var lastUpdateTime: TimeInterval
    var estimatedCharWidth: CGFloat
    
    init(
        fieldIdentifier: String,
        bundleID: String,
        elementHash: CFHashCode,
        approach: TextExtractionApproach,
        textBeforeCaret: String,
        textAfterCaret: String,
        selectedText: String,
        caretLocation: Int,
        fullTextLength: Int,
        caretRect: CGRect?,
        fieldRect: CGRect?,
        lastUpdateTime: TimeInterval,
        estimatedCharWidth: CGFloat = 8.5
    ) {
        self.fieldIdentifier = fieldIdentifier
        self.bundleID = bundleID
        self.elementHash = elementHash
        self.approach = approach
        self.textBeforeCaret = textBeforeCaret
        self.textAfterCaret = textAfterCaret
        self.selectedText = selectedText
        self.caretLocation = caretLocation
        self.fullTextLength = fullTextLength
        self.caretRect = caretRect
        self.fieldRect = fieldRect
        self.lastUpdateTime = lastUpdateTime
        self.estimatedCharWidth = estimatedCharWidth
    }
    
    func toCaretContext() -> CaretContext {
        CaretContext(
            fieldIdentifier: fieldIdentifier,
            textBeforeCaret: textBeforeCaret,
            textAfterCaret: textAfterCaret,
            selectedText: selectedText,
            caretLocation: caretLocation,
            fullTextLength: fullTextLength
        )
    }
    
    /// Incrementally advances the cached text buffer and predicts new caret coordinates
    /// without incurring synchronous AX cross-process IPC lag.
    mutating func advance(with characters: String, time: TimeInterval) {
        textBeforeCaret.append(characters)
        let charCount = characters.utf16.count
        caretLocation += charCount
        fullTextLength += charCount
        selectedText = ""
        lastUpdateTime = time
        
        if var rect = caretRect {
            let advanceWidth = estimatedCharWidth * CGFloat(characters.count)
            rect.origin.x += advanceWidth
            if let f = fieldRect, rect.origin.x > f.maxX - 2 {
                rect.origin.x = f.maxX - 2
            }
            caretRect = rect
        }
    }
}

// MARK: - Extraction Cache Manager
/// Coordinates caching, predicted typing advances, and synchronized full AX re-extractions.
final class ExtractionCacheManager {
    var currentRecord: ExtractionCacheRecord?
    private(set) var retryPlan = CursorRetryPlan()
    var maxIdleAge: TimeInterval = 0.6 // 600ms idle threshold
    
    init() {}
    
    func isCacheValid(for fieldID: String?, currentTime: TimeInterval) -> Bool {
        guard !retryPlan.isInvalidated,
              let record = currentRecord else { return false }
        if let fid = fieldID, !fid.isEmpty, record.fieldIdentifier != fid {
            return false
        }
        if currentTime - record.lastUpdateTime > maxIdleAge {
            return false
        }
        return true
    }
    
    func getCachedContext(fieldID: String? = nil, currentTime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> CaretContext? {
        guard isCacheValid(for: fieldID, currentTime: currentTime),
              let record = currentRecord else { return nil }
        return record.toCaretContext()
    }
    
    func getCachedCaretBounds(fieldID: String? = nil, currentTime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> (caret: CGRect, fieldRect: CGRect?)? {
        guard isCacheValid(for: fieldID, currentTime: currentTime),
              let record = currentRecord,
              let caret = record.caretRect else { return nil }
        return (caret: caret, fieldRect: record.fieldRect)
    }
    
    func advance(characters: String, time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard !retryPlan.isInvalidated else { return }
        currentRecord?.advance(with: characters, time: time)
    }
    
    func invalidate(reason: CursorRetryPlan.InvalidationReason) {
        retryPlan.invalidate(reason: reason)
    }
    
    func recordFailure() {
        retryPlan.recordFailure()
    }

    func update(
        context: CaretContext,
        bundleID: String,
        elementHash: CFHashCode,
        approach: TextExtractionApproach,
        caretRect: CGRect?,
        fieldRect: CGRect?,
        estimatedCharWidth: CGFloat = 8.5,
        time: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        var desyncReason: String?
        if let existing = currentRecord, existing.fieldIdentifier == context.fieldIdentifier {
            if CursorRetryPlan.detectDesync(cachedTextBefore: existing.textBeforeCaret, actualTextBefore: context.textBeforeCaret) {
                desyncReason = "Context text diverged from predicted buffer"
            }
        }

        let preservedCaretRect = caretRect ?? (currentRecord?.fieldIdentifier == context.fieldIdentifier ? currentRecord?.caretRect : nil)
        let preservedFieldRect = fieldRect ?? (currentRecord?.fieldIdentifier == context.fieldIdentifier ? currentRecord?.fieldRect : nil)

        let record = ExtractionCacheRecord(
            fieldIdentifier: context.fieldIdentifier,
            bundleID: bundleID,
            elementHash: elementHash,
            approach: approach,
            textBeforeCaret: context.textBeforeCaret,
            textAfterCaret: context.textAfterCaret,
            selectedText: context.selectedText,
            caretLocation: context.caretLocation,
            fullTextLength: context.fullTextLength,
            caretRect: preservedCaretRect,
            fieldRect: preservedFieldRect,
            lastUpdateTime: time,
            estimatedCharWidth: estimatedCharWidth
        )
        self.currentRecord = record
        if let desyncReason {
            self.retryPlan.invalidate(reason: .desyncDetected(reason: desyncReason))
        } else {
            self.retryPlan.recordSuccessfulSync(at: time)
        }
    }
    
    func clear() {
        currentRecord = nil
        retryPlan.invalidate(reason: .explicitReset)
    }
}
