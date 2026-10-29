import Foundation
import AppKit

// MARK: - Ghost Text Overlay Controller
// Manages the floating transparent panel that renders inline ghost text at the caret.

@MainActor
final class GhostTextOverlayController: NSObject {

    private var presentationRevision = 0
    private var panel: NSPanel?
    private var textView: GhostTextView?
    private(set) var currentSuffix: String = ""
    private(set) var currentCandidate: AutocompletionCandidate?
    private(set) var lastCaretRect: CGRect?
    private(set) var lastFieldRect: CGRect?
    private(set) var pendingCaretAnchor: CGRect?
    private var pendingCaretPollTask: Task<Void, Never>?
    private var pendingCaretPollDeadline: Date?

    var isVisible: Bool {
        panel?.isVisible == true
    }

    var panelFrame: NSRect? {
        panel?.frame
    }

    override init() {
        super.init()
    }

    func show(
        candidate: AutocompletionCandidate,
        suffix: String,
        caretRect: CGRect?,
        fieldRect: CGRect? = nil,
        caretProvider: (() -> CGRect?)? = nil,
        bundleID: String? = nil
    ) {
        guard !suffix.isEmpty else {
            hide()
            return
        }

        if let fieldRect = fieldRect {
            lastFieldRect = fieldRect
        }

        self.currentCandidate = candidate
        self.currentSuffix = suffix

        let previousAnchor = pendingCaretAnchor
        let initialCaret = Self.isValidCaretRect(caretRect) ? caretRect : (Self.isValidCaretRect(lastCaretRect) ? lastCaretRect : nil)

        if let initialCaret = initialCaret {
            let isStaleAnchor = previousAnchor != nil && Self.isCaretEqual(initialCaret, previousAnchor)

            if isStaleAnchor, let provider = caretProvider {
                // The caret bounds haven't moved yet after keystroke (typical in Electron apps like VS Code, Slack).
                // If the panel is already visible, update the text view content immediately so the newly typed char
                // disappears from the ghost text, but hold panel position until the updated caret arrives from AX.
                if panel?.isVisible == true, let tv = textView {
                    tv.text = suffix
                }
                startPendingCaretPoll(anchor: initialCaret, provider: provider)
            } else {
                cancelPendingCaretPoll()
                pendingCaretAnchor = initialCaret
                lastCaretRect = initialCaret
                positionAndDisplay(caret: initialCaret, suffix: suffix, fieldRect: fieldRect, bundleID: bundleID)
            }
        } else if let provider = caretProvider {
            // Initial caret rect not available yet (e.g. during fast typing in webviews).
            startPendingCaretPoll(anchor: nil, provider: provider)
        } else {
            hide()
        }
    }

    func positionAndDisplay(caret: CGRect, suffix: String, fieldRect: CGRect? = nil, bundleID: String? = nil) {
        if let fieldRect = fieldRect {
            lastFieldRect = fieldRect
        }
        let effectiveField = fieldRect ?? lastFieldRect

        let p = getOrCreatePanel()

        if textView == nil {
            let v = GhostTextView()
            p.contentView = v
            textView = v
        }

        guard let tv = textView else { return }

        let targetBundleID = bundleID ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let customFont = EditorFontCustomizer.shared.font(for: targetBundleID, caretHeight: caret.height)
        tv.customFont = customFont

        if let font = customFont {
            tv.fontSize = font.pointSize
        } else if caret.height > 8, caret.height < 120 {
            // Proportional font line-height scaling: font point size is typically ~76% of line height
            tv.fontSize = max(11.0, min(64.0, round(caret.height * 0.76)))
        } else {
            tv.fontSize = 13.5
        }
        tv.text = suffix
        let fittingSize = tv.idealSize()

        // Position directly at the right edge of caret with zero margin
        // Typographic baseline alignment:
        // In Cocoa screen coordinates (origin at bottom-left, y increasing upwards),
        // the caret spans the line height. With symmetric leading, the caret baseline is:
        // caretBaseline = caret.midY - (tv.activeFont.ascender + tv.activeFont.descender) / 2
        // Inside the flipped ghost text view, the glyph baseline is at tv.baselineOffsetFromTop from top.
        // Therefore, for the ghost text baseline to match caretBaseline:
        // origin.y + fittingSize.height - tv.baselineOffsetFromTop = caretBaseline
        let fontCenter = (tv.activeFont.ascender + tv.activeFont.descender) / 2
        let caretBaseline = caret.midY - fontCenter
        var origin = CGPoint(
            x: caret.maxX,
            y: round(caretBaseline - (fittingSize.height - tv.baselineOffsetFromTop))
        )

        // Ensure within screen visible frame
        let screen = NSScreen.screens.first { s in
            s.frame.intersects(caret)
        } ?? NSScreen.main ?? NSScreen.screens.first ?? NSScreen()

        let vf = screen.visibleFrame
        var maxAllowedX = vf.maxX - 2
        if let effectiveField = effectiveField {
            maxAllowedX = min(maxAllowedX, effectiveField.maxX - 4)
        }
        let availableWidth = maxAllowedX - origin.x
        if availableWidth < 16 {
            hide()
            return
        }

        // Anchor origin.x strictly to caret.maxX. Never shift leftwards over typed text.
        var panelSize = fittingSize
        panelSize.width = min(fittingSize.width, availableWidth)

        if origin.y < vf.minY {
            origin.y = vf.minY + 2
        }
        if origin.y + panelSize.height > vf.maxY {
            origin.y = vf.maxY - panelSize.height - 2
        }

        let newFrame = NSRect(origin: origin, size: panelSize)
        if p.frame != newFrame {
            p.setFrame(newFrame, display: true)
        }
        if !p.isVisible {
            p.orderFrontRegardless()
        }
    }

    func hide() {
        cancelPendingCaretPoll()
        presentationRevision &+= 1
        panel?.orderOut(nil)
        currentSuffix = ""
        currentCandidate = nil
        lastCaretRect = nil
        lastFieldRect = nil
        pendingCaretAnchor = nil
    }

    // MARK: - Caret Stabilization Polling Implementation

    func cancelPendingCaretPoll() {
        pendingCaretPollTask?.cancel()
        pendingCaretPollTask = nil
        pendingCaretPollDeadline = nil
    }

    func startPendingCaretPoll(anchor: CGRect?, provider: @escaping () -> CGRect?) {
        cancelPendingCaretPoll()

        let deadline = Date().addingTimeInterval(0.12) // 120ms hard timeout
        self.pendingCaretPollDeadline = deadline

        pendingCaretPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000) // 12ms poll interval
                guard !Task.isCancelled, let self = self else { return }

                if let currentDeadline = self.pendingCaretPollDeadline, Date() >= currentDeadline {
                    if self.panel?.isVisible != true {
                        self.hide()
                    } else {
                        self.cancelPendingCaretPoll()
                    }
                    return
                }

                if let newRect = provider(), Self.isValidCaretRect(newRect) {
                    let hasResolved: Bool
                    if let anchor = anchor {
                        hasResolved = !Self.isCaretEqual(newRect, anchor)
                    } else {
                        hasResolved = true
                    }

                    if hasResolved {
                        self.pendingCaretAnchor = newRect
                        self.lastCaretRect = newRect
                        if !self.currentSuffix.isEmpty {
                            self.positionAndDisplay(caret: newRect, suffix: self.currentSuffix)
                        }
                        self.cancelPendingCaretPoll()
                        return
                    }
                }
            }
        }
    }

    static func isValidCaretRect(_ rect: CGRect?) -> Bool {
        guard let rect = rect, !rect.isEmpty, !rect.isNull else { return false }
        guard rect.width > 0 && rect.height > 0 else { return false }
        guard rect.origin.x.isFinite && rect.origin.y.isFinite else { return false }
        if rect.origin == .zero && rect.size.width <= 1.0 && rect.size.height <= 1.0 {
            return false
        }
        if rect.width > 40 || rect.height > 60 {
            return false
        }
        return true
    }

    static func isCaretEqual(_ a: CGRect?, _ b: CGRect?) -> Bool {
        guard let a = a, let b = b else { return a == nil && b == nil }
        return abs(a.origin.x - b.origin.x) < 0.5 &&
               abs(a.origin.y - b.origin.y) < 0.5 &&
               abs(a.size.width - b.size.width) < 0.5 &&
               abs(a.size.height - b.size.height) < 0.5
    }

    static func hasCaretAdvanced(from stale: CGRect?, to current: CGRect?) -> Bool {
        guard let current = current, isValidCaretRect(current) else { return false }
        guard let stale = stale, isValidCaretRect(stale) else { return true }
        if isCaretEqual(stale, current) { return false }
        if abs(current.origin.y - stale.origin.y) >= 4.0 { return true }
        return current.origin.x > stale.origin.x + 1.0
    }

    /// Retain a known continuation while AX catches up with the insertion.
    /// Keep the panel hidden until real caret coordinates have advanced past the insertion point.
    func showContinuation(
        candidate: AutocompletionCandidate,
        suffix: String,
        staleAnchor: CGRect? = nil,
        estimatedCaret: CGRect? = nil,
        bundleID: String? = nil,
        caretProvider: @escaping () -> CGRect?,
        isCurrent: @escaping () -> Bool
    ) {
        cancelPendingCaretPoll()
        guard !suffix.isEmpty else {
            hide()
            return
        }

        presentationRevision &+= 1
        panel?.orderOut(nil)
        currentCandidate = candidate
        currentSuffix = suffix

        // Probe caretProvider synchronously once
        if let currentCaret = caretProvider(), Self.isValidCaretRect(currentCaret) {
            if Self.hasCaretAdvanced(from: staleAnchor, to: currentCaret) {
                self.pendingCaretAnchor = currentCaret
                self.lastCaretRect = currentCaret
                self.positionAndDisplay(caret: currentCaret, suffix: suffix, bundleID: bundleID)
                return
            }
        }

        let revision = presentationRevision
        let deadline = Date().addingTimeInterval(0.35)

        pendingCaretPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000)
                guard !Task.isCancelled, let self = self else { return }
                guard self.presentationRevision == revision, isCurrent() else {
                    self.hide()
                    return
                }

                if let currentCaret = caretProvider(), Self.isValidCaretRect(currentCaret) {
                    if Self.hasCaretAdvanced(from: staleAnchor, to: currentCaret) {
                        self.cancelPendingCaretPoll()
                        self.pendingCaretAnchor = currentCaret
                        self.lastCaretRect = currentCaret
                        self.positionAndDisplay(caret: currentCaret, suffix: suffix, bundleID: bundleID)
                        return
                    }
                }

                if Date() >= deadline {
                    if let estimated = estimatedCaret, Self.isValidCaretRect(estimated) {
                        self.cancelPendingCaretPoll()
                        self.pendingCaretAnchor = estimated
                        self.lastCaretRect = estimated
                        self.positionAndDisplay(caret: estimated, suffix: suffix, bundleID: bundleID)
                    } else {
                        self.hide()
                    }
                    return
                }
            }
        }
    }

    private func getOrCreatePanel() -> NSPanel {
        if let existing = panel { return existing }

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 24),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.isReleasedWhenClosed = false
        p.ignoresMouseEvents = true // Allow clicks to pass straight into the text editor

        self.panel = p
        return p
    }
}

// MARK: - Rounded Background Layout Manager
// Dedicated layout manager matching Cotypist's architecture for single completion overlays.
// Handles line fragment padding, exact baseline alignment, and background/glyph rendering.
final class RoundedBackgroundLayoutManager: NSLayoutManager {
    override func fillBackgroundRectArray(
        _ rectArray: UnsafePointer<NSRect>,
        count rectCount: Int,
        forCharacterRange charRange: NSRange,
        color: NSColor
    ) {
        guard rectCount > 0 else { return }
        color.setFill()
        for i in 0..<rectCount {
            let rect = rectArray[i]
            let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            path.fill()
        }
    }
}

// MARK: - Native AppKit Ghost Text View
// Ultra-lightweight native view: 0 SwiftUI constraints, 0 recursion, zero overhead.
// Uses NSTextContainer + NSLayoutManager (RoundedBackgroundLayoutManager) for exact typography,
// baseline alignment, line fragment padding suppression, and clean boundary clipping.
final class GhostTextView: NSView {
    override var isFlipped: Bool { true }

    private let textStorage = NSTextStorage()
    private let layoutManager = RoundedBackgroundLayoutManager()
    private let textContainer = NSTextContainer()

    var text: String = "" {
        didSet {
            updateTextStorage()
        }
    }

    var customFont: NSFont? {
        didSet {
            updateTextStorage()
        }
    }

    var fontSize: CGFloat = 13.5 {
        didSet {
            font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
            updateTextStorage()
        }
    }

    private var font = NSFont.systemFont(ofSize: 13.5, weight: .regular)
    var activeFont: NSFont {
        customFont ?? font
    }

    var baselineOffsetFromTop: CGFloat {
        activeFont.ascender
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTextSystem()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTextSystem()
    }

    private func setupTextSystem() {
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byClipping
        textContainer.maximumNumberOfLines = 1
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false

        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
    }

    func textAttributes() -> [NSAttributedString.Key: Any] {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.shadowBlurRadius = 1.0

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping

        return [
            .font: activeFont,
            .foregroundColor: NSColor(white: 0.48, alpha: 0.88),
            .shadow: shadow,
            .paragraphStyle: paragraphStyle
        ]
    }

    private func updateTextStorage() {
        if text.isEmpty {
            textStorage.setAttributedString(NSAttributedString())
        } else {
            let attrString = NSAttributedString(string: text, attributes: textAttributes())
            textStorage.setAttributedString(attrString)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !text.isEmpty, bounds.width > 0, bounds.height > 0 else { return }

        textContainer.size = bounds.size
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        guard glyphRange.length > 0 else { return }

        layoutManager.drawBackground(forGlyphRange: glyphRange, at: .zero)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)
    }

    func idealSize() -> CGSize {
        guard !text.isEmpty else { return .zero }
        textContainer.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        _ = layoutManager.glyphRange(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return CGSize(width: ceil(usedRect.width) + 4, height: max(16, ceil(usedRect.height)))
    }
}

