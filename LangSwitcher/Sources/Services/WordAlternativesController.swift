import Foundation
import AppKit
import SwiftUI

// MARK: - Word Alternatives Controller
// Manages the non-activating floating carousel panel for alternative completions.

@MainActor
final class WordAlternativesController: NSObject {
    static let shared = WordAlternativesController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var onSelectCallback: ((String) -> Void)?

    private(set) var alternatives: [WordAlternativesEngine.Alternative] = []
    private(set) var selectedIndex: Int = 0

    var isVisible: Bool {
        panel?.isVisible == true
    }

    override init() {
        super.init()
    }

    func show(
        alternatives: [WordAlternativesEngine.Alternative],
        anchor: CGRect,
        onSelect: @escaping (String) -> Void
    ) {
        guard !alternatives.isEmpty else { return }

        self.alternatives = alternatives
        self.selectedIndex = 0
        self.onSelectCallback = onSelect

        updateView(anchor: anchor)
    }

    private func updateView(anchor: CGRect) {
        let hudView = WordAlternativesHUDView(
            alternatives: alternatives,
            selectedIndex: selectedIndex,
            onSelect: { [weak self] chosen in
                self?.select(chosen)
            },
            onDismiss: { [weak self] in
                self?.hide()
            }
        )

        let wrapped = AnyView(hudView)

        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 44),
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
        let fittingSize = hostingView?.fittingSize ?? CGSize(width: 320, height: 44)

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
        panel?.orderFront(nil)
    }

    func cycleNext(anchor: CGRect) {
        guard !alternatives.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % alternatives.count
        updateView(anchor: anchor)
    }

    func cyclePrevious(anchor: CGRect) {
        guard !alternatives.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + alternatives.count) % alternatives.count
        updateView(anchor: anchor)
    }

    func handleNumericInput(_ digit: Int) -> Bool {
        guard isVisible, digit >= 1, digit <= alternatives.count else { return false }
        let chosen = alternatives[digit - 1].text
        select(chosen)
        return true
    }

    func confirmCurrentSelection() -> Bool {
        guard isVisible, selectedIndex >= 0, selectedIndex < alternatives.count else { return false }
        let chosen = alternatives[selectedIndex].text
        select(chosen)
        return true
    }

    func select(_ candidate: String) {
        let callback = onSelectCallback
        hide()
        callback?(candidate)
    }

    func hide() {
        panel?.orderOut(nil)
        alternatives = []
        selectedIndex = 0
        onSelectCallback = nil
    }
}
