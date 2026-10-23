import Foundation
import AppKit
import SwiftUI

// MARK: - Smart Replies Controller
// Manages the non-activating floating HUD for one-click smart replies.

@MainActor
final class SmartRepliesController: NSObject {
    static let shared = SmartRepliesController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private let accessibilityService: AccessibilityService

    private(set) var activeReplies: [SmartRepliesEngine.ReplyCandidate] = []
    private(set) var selectedIndex: Int = 0

    var isVisible: Bool {
        panel?.isVisible == true
    }

    init(accessibilityService: AccessibilityService = AccessibilityService()) {
        self.accessibilityService = accessibilityService
        super.init()
    }

    func show(replies: [SmartRepliesEngine.ReplyCandidate], anchor: CGRect) {
        guard !replies.isEmpty else { return }

        self.activeReplies = replies
        self.selectedIndex = 0

        updateView(anchor: anchor)
    }

    private func updateView(anchor: CGRect) {
        let hudView = SmartRepliesHUDView(
            replies: activeReplies,
            selectedIndex: selectedIndex,
            onSelect: { [weak self] chosen in
                self?.applyReply(chosen)
            },
            onDismiss: { [weak self] in
                self?.hide()
            }
        )

        let wrapped = AnyView(hudView)

        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 44),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .floating
            p.hasShadow = false
            p.ignoresMouseEvents = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.panel = p
        }

        if let existingHosting = hostingView {
            existingHosting.rootView = wrapped
        } else {
            let host = NSHostingView(rootView: wrapped)
            hostingView = host
            panel?.contentView = host
        }

        hostingView?.layoutSubtreeIfNeeded()
        let fittingSize = hostingView?.fittingSize ?? CGSize(width: 380, height: 44)

        var panelX = anchor.origin.x
        var panelY = anchor.origin.y - fittingSize.height - 6

        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main {
            if panelX + fittingSize.width > screen.visibleFrame.maxX {
                panelX = screen.visibleFrame.maxX - fittingSize.width - 8
            }
            if panelX < screen.visibleFrame.minX {
                panelX = screen.visibleFrame.minX + 8
            }
            if panelY < screen.visibleFrame.minY {
                panelY = anchor.origin.y + anchor.size.height + 6
            }
        }

        panel?.setFrame(NSRect(x: panelX, y: panelY, width: fittingSize.width, height: fittingSize.height), display: true)
        panel?.orderFrontRegardless()
    }

    func cycleNext(anchor: CGRect) {
        guard !activeReplies.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % activeReplies.count
        updateView(anchor: anchor)
    }

    func cyclePrevious(anchor: CGRect) {
        guard !activeReplies.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + activeReplies.count) % activeReplies.count
        updateView(anchor: anchor)
    }

    func handleNumericInput(_ digit: Int) -> Bool {
        guard isVisible, digit >= 1, digit <= activeReplies.count else { return false }
        let chosen = activeReplies[digit - 1].text
        applyReply(chosen)
        return true
    }

    func confirmCurrentSelection() -> Bool {
        guard isVisible, selectedIndex >= 0, selectedIndex < activeReplies.count else { return false }
        let chosen = activeReplies[selectedIndex].text
        applyReply(chosen)
        return true
    }

    func applyReply(_ text: String) {
        accessibilityService.pasteReplacingSelection(text)
        hide()
    }

    private var generationTask: Task<Void, Never>?

    func hide() {
        generationTask?.cancel()
        generationTask = nil
        panel?.orderOut(nil)
        activeReplies = []
        selectedIndex = 0
    }

    func triggerSmartReplies() {
        generationTask?.cancel()
        let caret = accessibilityService.caretScreenRect() ?? CGRect(x: 200, y: 500, width: 2, height: 16)
        generationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let screenResult = await ScreenContextService.shared.extractScreenContextAsync()
            guard !Task.isCancelled else { return }
            let promptContext = screenResult?.messages.last ?? screenResult?.formattedContext ?? ""
            let replies = SmartRepliesEngine.generateReplies(for: promptContext)
            guard !Task.isCancelled else { return }
            self.show(replies: replies, anchor: caret)
        }
    }
}
