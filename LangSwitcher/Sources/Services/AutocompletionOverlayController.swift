import Foundation
import AppKit
import SwiftUI

// MARK: - Autocompletion Overlay Controller
// Manages the non-activating floating NSPanel displaying AutocompletionPopupView.
// Features Cotypist-inspired asynchronous caret stabilization to eliminate lag
// in Electron apps (VSCode, Slack, Discord) and webviews.

@MainActor
final class AutocompletionOverlayController: NSObject {
    
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    
    private(set) var candidates: [AutocompletionCandidate] = []
    private(set) var selectedIndex: Int = 0
    private var onSelectCallback: ((AutocompletionCandidate) -> Void)?
    private var currentAcceptKeyHint: String = "⇥"
    
    // MARK: - Caret Stabilization (Cotypist Algorithm)
    /// The expected text anchor position.
    private(set) var pendingCaretAnchor: CGRect?
    /// High-frequency polling task tracking AX caret updates.
    private(set) var pendingCaretPollTask: Task<Void, Never>?
    /// Hard deadline timeout for the caret poll task (typically 120ms).
    private(set) var pendingCaretPollDeadline: Date?
    
    var isVisible: Bool {
        panel?.isVisible == true
    }
    
    var panelFrame: NSRect? {
        panel?.frame
    }
    
    func containsPoint(_ point: NSPoint) -> Bool {
        guard let p = panel, p.isVisible else { return false }
        return p.frame.contains(point)
    }
    
    var selectedCandidate: AutocompletionCandidate? {
        guard !candidates.isEmpty, selectedIndex >= 0, selectedIndex < candidates.count else {
            return nil
        }
        return candidates[selectedIndex]
    }
    
    override init() {
        super.init()
    }
    
    func show(
        candidates: [AutocompletionCandidate],
        caretRect: CGRect?,
        acceptKeyHint: String,
        caretProvider: (() -> CGRect?)? = nil,
        onSelect: @escaping (AutocompletionCandidate) -> Void
    ) {
        let hasValidInitialCaret = Self.isValidCaretRect(caretRect)
        guard !candidates.isEmpty, (hasValidInitialCaret || caretProvider != nil) else {
            hide()
            return
        }
        
        self.candidates = candidates
        self.selectedIndex = 0
        self.currentAcceptKeyHint = acceptKeyHint
        self.onSelectCallback = onSelect
        
        let p = getOrCreatePanel()
        updateContent()
        
        let initialCaret = hasValidInitialCaret ? caretRect : nil
        let previousAnchor = pendingCaretAnchor
        
        if let initialCaret = initialCaret {
            pendingCaretAnchor = initialCaret
            positionPanel(caretRect: initialCaret)
            p.orderFrontRegardless()
            
            let isStaleAnchor = previousAnchor != nil && Self.isCaretEqual(initialCaret, previousAnchor)
            let isFieldFallback = Self.isFieldRect(initialCaret)
            
            if (isStaleAnchor || isFieldFallback), let provider = caretProvider {
                // The caret bounds haven't moved yet after keystroke (typical in Electron apps)
                // or we only have coarse field bounds. Poll until updated caret arrives.
                startPendingCaretPoll(anchor: initialCaret, provider: provider)
            } else {
                cancelPendingCaretPoll()
            }
        } else if let provider = caretProvider {
            // Initial caret rect was not immediately available. Start polling immediately.
            startPendingCaretPoll(anchor: nil, provider: provider)
        }
    }
    
    func hide() {
        cancelPendingCaretPoll()
        panel?.orderOut(nil)
        candidates.removeAll()
        selectedIndex = 0
        onSelectCallback = nil
        pendingCaretAnchor = nil
    }
    
    func selectNext() {
        guard !candidates.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % candidates.count
        updateContent()
    }
    
    func selectPrevious() {
        guard !candidates.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + candidates.count) % candidates.count
        updateContent()
    }
    
    func selectIndex(_ index: Int) {
        guard index >= 0 && index < candidates.count else { return }
        selectedIndex = index
        acceptCurrent()
    }
    
    func acceptCurrent() {
        guard let candidate = selectedCandidate else { return }
        let callback = onSelectCallback
        hide()
        callback?(candidate)
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
                try? await Task.sleep(nanoseconds: 15_000_000) // 15ms poll interval
                guard !Task.isCancelled, let self = self else { return }
                
                if let currentDeadline = self.pendingCaretPollDeadline, Date() >= currentDeadline {
                    if self.panel?.isVisible != true {
                        self.hide()
                    } else {
                        self.cancelPendingCaretPoll()
                    }
                    return
                }
                
                if let newRect = provider(), Self.isValidCaretRect(newRect), !Self.isFieldRect(newRect) {
                    let hasResolved: Bool
                    if let anchor = anchor {
                        if Self.isFieldRect(anchor) {
                            hasResolved = true
                        } else {
                            hasResolved = !Self.isCaretEqual(newRect, anchor)
                        }
                    } else {
                        hasResolved = true
                    }
                    
                    if hasResolved {
                        self.pendingCaretAnchor = newRect
                        self.positionPanel(caretRect: newRect)
                        if let p = self.panel, !p.isVisible {
                            p.orderFrontRegardless()
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
        return true
    }
    
    // MARK: - Caret vs Field Boundary Thresholds
    /// Maximum dimensions for an insertion point caret. Any rect exceeding these
    /// dimensions is treated as a coarse field/container bounding box fallback.
    static let maxCaretWidth: CGFloat = 40
    static let maxCaretHeight: CGFloat = 60
    
    static func isFieldRect(_ rect: CGRect) -> Bool {
        return rect.width > maxCaretWidth || rect.height > maxCaretHeight
    }
    
    static func isCaretEqual(_ a: CGRect?, _ b: CGRect?) -> Bool {
        guard let a = a, let b = b else { return a == nil && b == nil }
        return abs(a.origin.x - b.origin.x) < 0.5 &&
               abs(a.origin.y - b.origin.y) < 0.5 &&
               abs(a.size.width - b.size.width) < 0.5 &&
               abs(a.size.height - b.size.height) < 0.5
    }
    
    private func updateContent() {
        let view = AutocompletionPopupView(
            candidates: candidates,
            selectedIndex: selectedIndex,
            acceptKeyHint: currentAcceptKeyHint,
            onSelect: { [weak self] candidate in
                self?.hide()
                self?.onSelectCallback?(candidate)
            }
        )
        
        if let hosting = hostingView {
            hosting.rootView = AnyView(view)
        } else {
            let hosting = NSHostingView(rootView: AnyView(view))
            // Preserve fittingSize measurement without automatic min/max window
            // constraints, which otherwise feed back into manual panel resizing.
            hosting.sizingOptions = [.intrinsicContentSize]
            panel?.contentView = hosting
            hostingView = hosting
        }
        
        // Resize panel to fit content
        if let p = panel, let hosting = hostingView {
            let fittingSize = hosting.fittingSize
            if p.frame.size != fittingSize {
                var frame = p.frame
                frame.size = fittingSize
                p.setFrame(frame, display: true)
                if let anchor = pendingCaretAnchor {
                    positionPanel(caretRect: anchor)
                }
            }
        }
    }
    
    private func getOrCreatePanel() -> NSPanel {
        if let existing = panel { return existing }
        
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.ignoresMouseEvents = false
        
        self.panel = p
        return p
    }
    
    private func positionPanel(caretRect: CGRect?) {
        guard let p = panel else { return }
        let size = p.frame.size
        
        // Choose screen containing caret or mouse
        let screen = NSScreen.screens.first { s in
            if let c = caretRect {
                return s.frame.intersects(c)
            }
            return false
        } ?? NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        
        let visibleFrame = screen.visibleFrame
        var origin = CGPoint.zero
        
        if let caret = caretRect {
            origin.x = caret.origin.x
            // Default: position below caret
            origin.y = caret.origin.y - size.height - 4
            // If going below screen, position above caret
            if origin.y < visibleFrame.minY {
                origin.y = caret.origin.y + caret.height + 4
            }
        } else {
            let mouse = NSEvent.mouseLocation
            origin.x = mouse.x + 10
            origin.y = mouse.y - size.height - 10
        }
        
        // Constrain within visible frame
        if origin.x + size.width > visibleFrame.maxX {
            origin.x = visibleFrame.maxX - size.width - 4
        }
        if origin.x < visibleFrame.minX {
            origin.x = visibleFrame.minX + 4
        }
        if origin.y < visibleFrame.minY {
            origin.y = visibleFrame.minY + 4
        }
        if origin.y + size.height > visibleFrame.maxY {
            origin.y = visibleFrame.maxY - size.height - 4
        }
        
        p.setFrameOrigin(origin)
    }
}
