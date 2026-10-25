import Foundation
import AppKit
import ApplicationServices
import Vision

// MARK: - Screen Context Result
// Extracted visible dialogue and context from the frontmost window.

struct ScreenContextResult: Equatable {
    let appBundleID: String
    let appName: String
    let windowTitle: String?
    let webDomain: String?
    let messages: [String]
    let formattedContext: String
    let hasPendingQuestion: Bool

    init(
        appBundleID: String,
        appName: String,
        windowTitle: String?,
        webDomain: String? = nil,
        messages: [String],
        formattedContext: String,
        hasPendingQuestion: Bool = false
    ) {
        self.appBundleID = appBundleID
        self.appName = appName
        self.windowTitle = windowTitle
        self.webDomain = webDomain
        self.messages = messages
        self.formattedContext = formattedContext
        self.hasPendingQuestion = hasPendingQuestion
    }
}

// MARK: - Screen Context Service
// Reads recent messages and dialogue context from active chat windows or documents
// using macOS Accessibility APIs (AXUIElement), safely bounding time and traversal depth.

@MainActor
final class ScreenContextService: ObservableObject {

    static let shared = ScreenContextService()

    // Bounds and limits
    nonisolated static let maxDepth = 20
    nonisolated static let maxVisitedElements = 250
    nonisolated static let maxTimeBudgetSeconds = 0.150 // 150 ms background budget
    nonisolated static let defaultMaxMessages = 8
    nonisolated static let defaultMaxCharacters = 1000

    // TTL Cache
    nonisolated static let cacheTTL: TimeInterval = 1.8 // 1.8 seconds

    private struct CacheEntry {
        let key: String
        let result: ScreenContextResult?
        let timestamp: Date
    }

    private var cache: CacheEntry?

    // Speaker attribution
    enum Speaker: String, Equatable {
        case incoming = "Partner"
        case outgoing = "You"
        case neutral = ""
    }

    // Roles to completely skip during traversal
    nonisolated static let ignoredRoles: Set<String> = [
        "AXButton",
        "AXPopUpButton",
        "AXMenuButton",
        "AXScrollBar",
        "AXSlider",
        "AXSplitter",
        "AXToolbar",
        "AXTabGroup",
        "AXMenuBar",
        "AXMenu",
        "AXMenuItem",
        "AXProgressIndicator",
        "AXColorWell",
        "AXImage",
        "AXRuler",
        "AXDisclosureTriangle",
        "AXGrowArea",
        "AXDrawer",
        "AXSheet"
    ]

    // Roles holding readable text
    nonisolated static let textRoles: Set<String> = [
        "AXStaticText",
        "AXTextArea",
        "AXTextField",
        "AXHeading",
        "AXParagraph"
    ]

    // Common UI noise labels in chat applications
    nonisolated static let noiseLabels: Set<String> = [
        "send", "attach", "search", "close", "minimize", "zoom", "emoji", "stickers",
        "mute", "reply", "forward", "edit", "delete", "copy", "save", "ok", "cancel",
        "pinned message", "members", "read", "delivered", "typing", "online",
        "copy message", "copy response", "read aloud", "good response", "bad response",
        "more actions", "thought for", "sources", "context7",
        "отправить", "прикрепить", "поиск", "закрыть", "свернуть", "отмена", "удалить",
        "копировать", "ответить", "переслать", "изменено", "прочитано", "доставлено",
        "в сети", "был(а) в сети", "печатает", "перейти к контенту", "сообщение",
        "скопировать", "скопировать сообщение", "скопировать ответ", "копировать ответ",
        "прочитать вслух", "оценить ответ", "другие действия", "последний ответ",
        "источники", "новая вкладка"
    ]

    // Web browser bundle identifiers for AXWebArea fast-path
    nonisolated static let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "company.thebrowser.Browser", // Arc
        "com.operasoftware.Opera",
        "com.operasoftware.OperaNext",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "ru.yandex.desktop.yandex-browser",
        "ru.yandex.desktop.browser",
        "ru.yandex.browser"
    ]

    nonisolated static func isBrowserApp(bundleID: String) -> Bool {
        browserBundleIDs.contains(bundleID)
    }

    // Chat application bundle identifiers
    nonisolated static let chatBundleIDs: Set<String> = [
        "ru.keepcoder.Telegram",
        "org.telegram.desktop",
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "net.whatsapp.WhatsApp",
        "com.apple.MobileSMS",
        "org.whispersystems.signal-desktop",
        "com.skype.skype",
        "com.viber.osx",
        "com.openai.codex",
        "com.openai.chat",
        "com.anthropic.claudedesktop",
        "com.microsoft.teams",
        "com.microsoft.teams2"
    ]

    nonisolated static func isChatApp(bundleID: String) -> Bool {
        chatBundleIDs.contains(bundleID)
    }

    // Terminal application bundle identifiers
    nonisolated static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Main",
        "dev.warp.Warp-Stable",
        "io.alacritty",
        "net.kovidgoyal.kitty",
        "co.zeit.hyper",
        "com.github.wez.wezterm"
    ]

    nonisolated static func isTerminalApp(bundleID: String) -> Bool {
        terminalBundleIDs.contains(bundleID)
    }

    // Code editor bundle identifiers (VS Code, Cursor, Zed, JetBrains, Xcode)
    nonisolated static let codeEditorBundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.visualstudio.code.oss",
        "com.vscodium",
        "com.cursor.Cursor",
        "com.exafunction.windsurf",
        "dev.zed.Zed",
        "com.sublimetext.4",
        "com.sublimetext.3",
        "com.jetbrains.intellij",
        "com.jetbrains.intellij.ce",
        "com.jetbrains.pycharm",
        "com.jetbrains.pycharm.ce",
        "com.jetbrains.webstorm",
        "com.jetbrains.CLion",
        "com.jetbrains.rider",
        "com.jetbrains.goland",
        "com.jetbrains.AppCode",
        "com.jetbrains.datagrip",
        "com.jetbrains.rubymine",
        "com.apple.dt.Xcode"
    ]

    nonisolated static func isCodeEditorApp(bundleID: String) -> Bool {
        codeEditorBundleIDs.contains(bundleID)
    }

    /// Bottom-Up Strategy:
    /// Walks UP from the focused element (active text field / caret) to locate
    /// the conversation message container directly adjacent to or enclosing the input field.
    /// This bypasses traversing down through the window or WebArea hierarchy entirely.
    nonisolated static func findBottomUpMessageContainer(from element: AXUIElement, focusedRect: CGRect?) -> AXUIElement? {
        var current: AXUIElement = element
        let elemFrame = focusedRect ?? elementFrame(element)

        for _ in 0..<18 {
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef) == .success,
                  let parent = parentRef, CFGetTypeID(parent) == AXUIElementGetTypeID() else {
                break
            }
            let parentEl = parent as! AXUIElement
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(parentEl, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String ?? ""
            if role == "AXWindow" { break }

            // Check children of this ancestor for a sibling message container
            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(parentEl, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let children = childrenRef as? [AXUIElement], children.count > 1 {
                for sibling in children {
                    if !CFEqual(sibling, current) {
                        var sRoleRef: CFTypeRef?
                        var sDescRef: CFTypeRef?
                        var sIdRef: CFTypeRef?
                        AXUIElementCopyAttributeValue(sibling, kAXRoleAttribute as CFString, &sRoleRef)
                        AXUIElementCopyAttributeValue(sibling, kAXRoleDescriptionAttribute as CFString, &sDescRef)
                        AXUIElementCopyAttributeValue(sibling, "AXDOMIdentifier" as CFString, &sIdRef)
                        let sRole = sRoleRef as? String ?? ""
                        let sDesc = (sDescRef as? String ?? "").lowercased()
                        let sId = (sIdRef as? String ?? "").lowercased()

                        // Check explicit roles or DOM IDs
                        if sRole == "AXScrollArea" || sDesc.contains("message") || sId.contains("messages") ||
                           sId.contains("conversation") || sId.contains("chat") {
                            return sibling
                        }

                        // Check spatial alignment: if positioned above the input field and shares column width
                        if let eFrame = elemFrame, let sFrame = elementFrame(sibling) {
                            if sFrame.origin.y < eFrame.origin.y && sFrame.height >= 80 {
                                let xOverlap = (sFrame.origin.x <= eFrame.origin.x + 80) &&
                                               ((sFrame.origin.x + sFrame.width) >= (eFrame.origin.x + eFrame.width - 80))
                                if xOverlap {
                                    return sibling
                                }
                            }
                        }
                    }
                }
            }

            // If parent itself is identified as the conversation pane (e.g. main or chat panel)
            var pDescRef: CFTypeRef?
            var pIdRef: CFTypeRef?
            AXUIElementCopyAttributeValue(parentEl, kAXRoleDescriptionAttribute as CFString, &pDescRef)
            AXUIElementCopyAttributeValue(parentEl, "AXDOMIdentifier" as CFString, &pIdRef)
            let pDesc = (pDescRef as? String ?? "").lowercased()
            let pId = (pIdRef as? String ?? "").lowercased()
            if pDesc == "main" || role == "AXLandmarkMain" || pId.contains("chat-panel") {
                return parentEl
            }

            current = parentEl
        }
        return nil
    }

    /// Walk up the parent hierarchy from the focused input field in chat apps
    /// to locate the active conversation column container, completely bypassing the left sidebar.
    nonisolated static func findChatColumnAncestor(of element: AXUIElement, focusedRect: CGRect) -> AXUIElement? {
        var current: AXUIElement = element
        var bestAncestor: AXUIElement?
        for _ in 0..<8 {
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef) == .success,
                  let parent = parentRef, CFGetTypeID(parent) == AXUIElementGetTypeID() else {
                break
            }
            let parentEl = parent as! AXUIElement
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(parentEl, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String ?? ""
            if role == "AXWindow" { break }

            var posRef: CFTypeRef?
            var sizeRef: CFTypeRef?
            AXUIElementCopyAttributeValue(parentEl, kAXPositionAttribute as CFString, &posRef)
            AXUIElementCopyAttributeValue(parentEl, kAXSizeAttribute as CFString, &sizeRef)
            var pos = CGPoint.zero
            var size = CGSize.zero
            if let p = posRef, CFGetTypeID(p) == AXValueGetTypeID(), AXValueGetValue(p as! AXValue, .cgPoint, &pos),
               let s = sizeRef, CFGetTypeID(s) == AXValueGetTypeID(), AXValueGetValue(s as! AXValue, .cgSize, &size) {
                // Enclosing conversation pane that contains the input column but excludes the left sidebar
                if pos.x >= focusedRect.origin.x - 30 && size.width <= focusedRect.width + 140 && size.height > focusedRect.height * 1.5 {
                    bestAncestor = parentEl
                }
            }
            current = parentEl
        }
        return bestAncestor
    }

    nonisolated static func findWebAreaAncestor(of element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement = element
        for _ in 0..<12 {
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef) == .success,
                  let parent = parentRef, CFGetTypeID(parent) == AXUIElementGetTypeID() else {
                return nil
            }
            let parentEl = parent as! AXUIElement
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(parentEl, kAXRoleAttribute as CFString, &roleRef)
            if (roleRef as? String) == "AXWebArea" {
                return parentEl
            }
            current = parentEl
        }
        return nil
    }

    nonisolated static func findWebAreaInWindow(_ window: AXUIElement) -> AXUIElement? {
        var queue: [(element: AXUIElement, depth: Int)] = [(window, 0)]
        var head = 0
        while head < queue.count && head < 80 {
            let (el, depth) = queue[head]
            head += 1
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String ?? ""
            if role == "AXWebArea" {
                return el
            }
            if ["AXToolbar", "AXTabGroup", "AXMenuBar", "AXButton", "AXSplitter"].contains(role) {
                continue
            }
            if depth < 12 {
                var childrenRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                   let children = childrenRef as? [AXUIElement] {
                    for c in children {
                        queue.append((c, depth + 1))
                    }
                }
            }
        }
        return nil
    }

    /// Locate primary conversation pane or article body inside a web area,
    /// bypassing navigation sidebars, channels, and toolbars.
    nonisolated static func findMainConversationContainer(in root: AXUIElement) -> AXUIElement? {
        var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        var head = 0
        while head < queue.count && head < 60 {
            let (el, depth) = queue[head]
            head += 1
            var r: CFTypeRef?
            var d: CFTypeRef?
            var idRef: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &r)
            AXUIElementCopyAttributeValue(el, kAXRoleDescriptionAttribute as CFString, &d)
            AXUIElementCopyAttributeValue(el, "AXDOMIdentifier" as CFString, &idRef)
            let role = r as? String ?? ""
            let desc = (d as? String ?? "").lowercased()
            let domId = (idRef as? String ?? "").lowercased()
            if desc == "main" || role == "AXLandmarkMain" || domId.contains("chat-panel") ||
               domId == "conversation" || domId.contains("messages-container") {
                return el
            }
            if ["AXToolbar", "AXTabGroup", "AXMenuBar", "AXButton", "AXSplitter"].contains(role) {
                continue
            }
            if depth < 10 {
                var childrenRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                   let children = childrenRef as? [AXUIElement] {
                    for c in children {
                        queue.append((c, depth + 1))
                    }
                }
            }
        }
        return nil
    }

    // Privacy regexes
    nonisolated private static let creditCardRegex = try? NSRegularExpression(pattern: #"\b(?:\d[ -]*?){13,16}\b"#)
    nonisolated private static let emailRegex = try? NSRegularExpression(pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#)
    nonisolated private static let phoneRegex = try? NSRegularExpression(pattern: #"\b(?:\+?\d{1,3}[-.\s]?)?\(?\d{2,4}\)?[-.\s]?\d{3}[-.\s]?\d{2,4}\b"#)
    nonisolated private static let secretTokenRegex = try? NSRegularExpression(pattern: #"(?:ey[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+|ghp_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,})"#)
    nonisolated private static let timestampRegex = try? NSRegularExpression(
        pattern: #"^\[?\(?\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AP]M)?\]?\)?(?:\s*[,.]?\s*(?:[✓✔\u2713\u2714]+|[\[\(]?(?:изм\.?|ред\.?|edited|изменено)[\]\)]?))*$"#,
        options: .caseInsensitive
    )
    nonisolated private static let dateLabelRegex = try? NSRegularExpression(
        pattern: #"^(?:today|yesterday|сегодня|вчера|just now|только что)(?:\s*(?:at|в|,)\s*\[?\(?\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AP]M)?\]?\)?)?$"#,
        options: .caseInsensitive
    )
    nonisolated private static let dayOfWeekRegex = try? NSRegularExpression(
        pattern: #"^(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|wed|thu|fri|sat|sun|понедельник|вторник|среда|четверг|пятница|суббота|воскресенье|пн|вт|ср|чт|пт|сб|вс)$"#,
        options: .caseInsensitive
    )
    nonisolated private static let dateNumericOrMonthRegex = try? NSRegularExpression(
        pattern: #"^(?:(?:\d{1,2}\.\d{1,2}\.\d{2,4}|\d{1,2}[/-]\d{1,2}[/-]\d{4}|\d{4}[-/]\d{1,2}[-/]\d{1,2})(?:\s*г\.?)?|\d{1,2}\s+(?:янв(?:аря)?|фев(?:раля)?|мар(?:та)?|апр(?:еля)?|ма[яй]|июн(?:я)?|июл(?:я)?|авг(?:уста)?|сен(?:тября)?|окт(?:ября)?|ноя(?:бря)?|дек(?:абря)?|jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun[e]?|jul[y]?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)(?:\s+\d{2,4})?(?:\s*г\.?)?)$"#,
        options: .caseInsensitive
    )
    nonisolated private static let trailingMessengerTimeWithStatusRegex = try? NSRegularExpression(
        pattern: #"\s+\[?\(?\b\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AP]M)?\]?\)?(?:\s*[,.]?\s*(?:[✓✔\u2713\u2714]+|[\[\(]?(?:изм\.?|ред\.?|edited|изменено)[\]\)]?))+\s*$"#,
        options: .caseInsensitive
    )
    nonisolated private static let trailingPrepositionWithTimeRegex = try? NSRegularExpression(
        pattern: #"\b(?:в|во|к|ко|до|после|около|с|со|на|at|by|around|about|before|after|from|till|until)\s+\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AP]M)?(?:\s*[,.]?\s*(?:[✓✔\u2713\u2714]+|[\[\(]?(?:изм\.?|ред\.?|edited|изменено)[\]\)]?))+\s*$"#,
        options: .caseInsensitive
    )
    nonisolated private static let trailingStatusOnlyRegex = try? NSRegularExpression(
        pattern: #"\s*[,.]?\s*(?:[✓✔\u2713\u2714]+|[\[\(]?(?:изм\.?|ред\.?|edited|изменено)[\]\)]?)+\s*$"#,
        options: .caseInsensitive
    )
    nonisolated private static let trailingBracketedTimestampRegex = try? NSRegularExpression(
        pattern: #"\s*(?:\[\s*\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AP]M)?\s*\]|\(\s*\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AP]M)?\s*\))\s*$"#,
        options: .caseInsensitive
    )
    nonisolated private static let trailingPunctuationSeparatedTimestampRegex = try? NSRegularExpression(
        pattern: #"(?<=[.!?…\n\r|•·]|\s{2})\s*\b\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AP]M)?\s*$"#,
        options: .caseInsensitive
    )
    nonisolated private static let roleRegex = try? NSRegularExpression(
        pattern: #"^\[?\b(user|assistant|human|system|model)\s*(\[?\d+\]?|:)|\[\s*\d{2,}\s*\]"#,
        options: .caseInsensitive
    )
    nonisolated private static let pendingQuestionRegex = try? NSRegularExpression(
        pattern: #"[?？][^\p{L}\p{N}]*$"#
    )

    private var consecutiveFailures = 0
    private var circuitBreakerUntil: Date?

    init() {}

    func invalidateCache() {
        cache = nil
    }

    // MARK: - Speaker Attribution Helper

    nonisolated static func detectSpeaker(elementFrame: CGRect?, columnMinX: CGFloat, columnMaxX: CGFloat) -> Speaker {
        guard let frame = elementFrame else { return .neutral }
        let columnWidth = columnMaxX - columnMinX
        guard columnWidth > 150 else { return .neutral }

        let midX = (columnMinX + columnMaxX) / 2.0
        let elementMidX = frame.origin.x + (frame.width / 2.0)

        // Full-width elements are document text or system notices
        if frame.width > columnWidth * 0.80 {
            return .neutral
        }

        // Chat bubble horizontal alignment
        if elementMidX < midX - (columnWidth * 0.05) || frame.origin.x < columnMinX + (columnWidth * 0.25) {
            return .incoming
        } else if elementMidX > midX + (columnWidth * 0.05) || (frame.origin.x + frame.width) > columnMaxX - (columnWidth * 0.25) {
            return .outgoing
        }

        return .neutral
    }

    // MARK: - Filter & Sanitization Helpers

    nonisolated static func isIgnoredRole(_ role: String) -> Bool {
        ignoredRoles.contains(role)
    }

    nonisolated static func isTimestampOrDate(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        if let timestampRegex, timestampRegex.firstMatch(in: trimmed, range: range) != nil {
            return true
        }
        if let dateLabelRegex, dateLabelRegex.firstMatch(in: trimmed, range: range) != nil {
            return true
        }
        if let dayOfWeekRegex, dayOfWeekRegex.firstMatch(in: trimmed, range: range) != nil {
            return true
        }
        if let dateNumericOrMonthRegex, dateNumericOrMonthRegex.firstMatch(in: trimmed, range: range) != nil {
            return true
        }
        return false
    }

    nonisolated static func isUINoiseText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return true }
        if noiseLabels.contains(trimmed) { return true }
        if TerminalPromptExtractor.isDividerLine(trimmed) {
            return true
        }

        // Single characters, symbols, or pure digits
        if trimmed.count == 1 { return true }
        if trimmed.allSatisfy(\.isNumber) { return true }
        if trimmed.allSatisfy({ $0.isPunctuation || $0.isSymbol }) { return true }

        // Dynamic thinking / action labels in chat UIs
        if trimmed.hasPrefix("работал на протяжении") || trimmed.hasPrefix("работает уже") ||
           trimmed.hasPrefix("thought for") || trimmed.hasPrefix("thinking for") ||
           trimmed.hasPrefix("скопировать сообщение") || trimmed.hasPrefix("копировать ответ") ||
           trimmed.hasPrefix("прочитано ") || trimmed.hasPrefix("доставлено ") {
            return true
        }

        // Dialogue turn and role markers like "[User 001]", "User [002]", "[001]", "User:", "Model:"
        if let roleRegex {
            let range = NSRange(location: 0, length: trimmed.utf16.count)
            if roleRegex.firstMatch(in: trimmed, range: range) != nil {
                return true
            }
        }
        return false
    }

    nonisolated static func sanitizeMessage(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }

        let range = NSRange(location: 0, length: trimmed.utf16.count)

        // Drop secret tokens / API keys / Bearer JWTs
        if let secretTokenRegex, secretTokenRegex.firstMatch(in: trimmed, range: range) != nil {
            return nil
        }

        // Drop credit cards
        if let creditCardRegex, creditCardRegex.firstMatch(in: trimmed, range: range) != nil {
            return nil
        }

        // Check for password / secret / credential prefixes
        let lower = trimmed.lowercased()
        if lower.hasPrefix("password:") || lower.hasPrefix("пароль:") ||
           lower.hasPrefix("token:") || lower.hasPrefix("pin:") ||
           lower.hasPrefix("cvv:") || lower.hasPrefix("secret:") {
            return nil
        }

        var sanitized = trimmed
        // Redact emails
        if let emailRegex {
            sanitized = emailRegex.stringByReplacingMatches(in: sanitized, range: range, withTemplate: "[email]")
        }
        // Redact phone numbers
        let updatedRange = NSRange(location: 0, length: sanitized.utf16.count)
        if let phoneRegex {
            sanitized = phoneRegex.stringByReplacingMatches(in: sanitized, range: updatedRange, withTemplate: "[phone]")
        }
        // Strip trailing messenger timestamps without stripping normal speech times (e.g. "Встретимся в 14:00")
        let finalRange = NSRange(location: 0, length: sanitized.utf16.count)
        if let prepRegex = trailingPrepositionWithTimeRegex,
           prepRegex.firstMatch(in: sanitized, range: finalRange) != nil {
            if let statusRegex = trailingStatusOnlyRegex {
                sanitized = statusRegex.stringByReplacingMatches(in: sanitized, range: finalRange, withTemplate: "")
            }
        } else if let timeWithStatusRegex = trailingMessengerTimeWithStatusRegex {
            sanitized = timeWithStatusRegex.stringByReplacingMatches(in: sanitized, range: finalRange, withTemplate: "")
        } else if let statusRegex = trailingStatusOnlyRegex {
            sanitized = statusRegex.stringByReplacingMatches(in: sanitized, range: finalRange, withTemplate: "")
        }

        let bracketRange = NSRange(location: 0, length: sanitized.utf16.count)
        if let bracketedRegex = trailingBracketedTimestampRegex {
            sanitized = bracketedRegex.stringByReplacingMatches(in: sanitized, range: bracketRange, withTemplate: "")
        }

        let punctRange = NSRange(location: 0, length: sanitized.utf16.count)
        if let afterPunctRegex = trailingPunctuationSeparatedTimestampRegex {
            sanitized = afterPunctRegex.stringByReplacingMatches(in: sanitized, range: punctRange, withTemplate: "")
        }

        // Clean any remaining trailing status after bracketed or punctuation timestamps
        let trailingRange = NSRange(location: 0, length: sanitized.utf16.count)
        if let statusRegex = trailingStatusOnlyRegex {
            sanitized = statusRegex.stringByReplacingMatches(in: sanitized, range: trailingRange, withTemplate: "")
        }
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sanitized.count >= 2 else { return nil }

        return sanitized
    }

    nonisolated static func detectPendingQuestion(messages: [(text: String, speaker: Speaker)]) -> Bool {
        guard let last = messages.last else { return false }
        // If the user already answered last (You: ...), there is no pending question
        guard last.speaker == .incoming || last.speaker == .neutral else { return false }
        let trimmed = last.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Matches questions ending in ? optionally followed by smileys, emoji, quotes, brackets or whitespace
        if let pendingQuestionRegex {
            let range = NSRange(location: 0, length: trimmed.utf16.count)
            return pendingQuestionRegex.firstMatch(in: trimmed, range: range) != nil
        }
        return trimmed.hasSuffix("?") || trimmed.hasSuffix("?!") || trimmed.hasSuffix("?..")
    }

    // Backward-compatible overload for 3-tuple (text, y, x)
    nonisolated static func filterAndFormat(
        items: [(text: String, y: CGFloat, x: CGFloat)],
        windowTitle: String?,
        appBundleID: String,
        appName: String,
        webDomain: String? = nil,
        maxCharacters: Int = defaultMaxCharacters,
        maxMessages: Int = defaultMaxMessages
    ) -> ScreenContextResult? {
        let attributed = items.map { (text: $0.text, y: $0.y, x: $0.x, speaker: Speaker.neutral) }
        return filterAndFormat(
            attributedItems: attributed,
            windowTitle: windowTitle,
            appBundleID: appBundleID,
            appName: appName,
            webDomain: webDomain,
            maxCharacters: maxCharacters,
            maxMessages: maxMessages
        )
    }

    nonisolated static func filterAndFormat(
        attributedItems: [(text: String, y: CGFloat, x: CGFloat, speaker: Speaker)],
        windowTitle: String?,
        appBundleID: String,
        appName: String,
        webDomain: String? = nil,
        maxCharacters: Int = defaultMaxCharacters,
        maxMessages: Int = defaultMaxMessages
    ) -> ScreenContextResult? {
        guard !attributedItems.isEmpty else { return nil }

        // Sort by vertical position: top to bottom (earlier messages first)
        let sorted = attributedItems.sorted { $0.y < $1.y }

        // Deduplicate consecutive identical messages
        var uniqueMessages: [(text: String, speaker: Speaker)] = []
        for item in sorted {
            if uniqueMessages.last?.text != item.text {
                uniqueMessages.append((text: item.text, speaker: item.speaker))
            }
        }

        guard !uniqueMessages.isEmpty else { return nil }

        // Keep the most recent messages (up to maxMessages)
        var recent = Array(uniqueMessages.suffix(maxMessages))

        let header: String
        let contextType = chatBundleIDs.contains(appBundleID) ? "dialogue" : (webDomain != nil ? "web page" : "window")
        if let domain = webDomain, !domain.isEmpty {
            if let title = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                header = "[Context from active \(contextType) (\(domain) - \(title))]:"
            } else {
                header = "[Context from active \(contextType) (\(domain))]:"
            }
        } else if let title = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            header = "[Context from active \(contextType) (\(title))]:"
        } else {
            header = "[Context from active \(contextType)]:"
        }

        // Drop oldest messages until whole context fits into maxCharacters without truncating strings
        while !recent.isEmpty {
            let candidateLines = [header] + recent.map { item -> String in
                let clean = item.text.replacingOccurrences(of: "\n", with: " ")
                switch item.speaker {
                case .incoming:
                    return "Partner: " + clean
                case .outgoing:
                    return "You: " + clean
                case .neutral:
                    return "- " + clean
                }
            }
            let formatted = candidateLines.joined(separator: "\n")
            if formatted.count <= maxCharacters {
                let hasQuestion = detectPendingQuestion(messages: recent)
                return ScreenContextResult(
                    appBundleID: appBundleID,
                    appName: appName,
                    windowTitle: windowTitle,
                    webDomain: webDomain,
                    messages: recent.map(\.text),
                    formattedContext: formatted,
                    hasPendingQuestion: hasQuestion
                )
            }
            recent.removeFirst()
        }

        return nil
    }

    // MARK: - Extraction Pipeline

    /// Synchronous extraction method with caching.
    func extractScreenContext(
        frontmostApp: NSRunningApplication? = nil,
        focusedElement: AXUIElement? = nil,
        excludedBundleIDs: Set<String> = AutoCorrectionGate.defaultExcludedBundleIDs,
        maxCharacters: Int = defaultMaxCharacters,
        maxMessages: Int = defaultMaxMessages
    ) -> ScreenContextResult? {
        guard AXIsProcessTrusted() else { return nil }

        guard let app = frontmostApp ?? NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else { return nil }

        // Check security exclusions
        if excludedBundleIDs.contains(bundleID) {
            return nil
        }

        // Fast-fail if focused element is a password/secure field
        if let focused = focusedElement {
            var roleRef: CFTypeRef?
            var subroleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &roleRef)
            AXUIElementCopyAttributeValue(focused, kAXSubroleAttribute as CFString, &subroleRef)
            let role = roleRef as? String
            let subrole = subroleRef as? String
            if AutoCorrectionGate.isSecureField(role: role, subrole: subrole) {
                return nil
            }
        }

        let appName = app.localizedName ?? bundleID
        let cacheKey = "\(app.processIdentifier):\(focusedElement.map { CFHash($0) } ?? 0)"
        if let entry = cache, entry.key == cacheKey, Date().timeIntervalSince(entry.timestamp) < Self.cacheTTL {
            return entry.result
        }

        let result = Self.performExtraction(
            pid: app.processIdentifier,
            bundleID: bundleID,
            appName: appName,
            focusedElement: focusedElement,
            maxCharacters: maxCharacters,
            maxMessages: maxMessages,
            allowVisionOCR: !Thread.isMainThread
        )
        self.cache = CacheEntry(key: cacheKey, result: result, timestamp: Date())
        return result
    }

    /// Asynchronous extraction running off the main thread with an explicit timeout.
    /// Never blocks the main RunLoop or CGEventTap.
    func extractScreenContextAsync(
        frontmostApp: NSRunningApplication? = nil,
        focusedElement: AXUIElement? = nil,
        excludedBundleIDs: Set<String> = AutoCorrectionGate.defaultExcludedBundleIDs,
        maxCharacters: Int = defaultMaxCharacters,
        maxMessages: Int = defaultMaxMessages
    ) async -> ScreenContextResult? {
        guard AXIsProcessTrusted() else { return nil }
        if let until = circuitBreakerUntil, Date() < until {
            return nil
        }
        guard let app = frontmostApp ?? NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else { return nil }
        if excludedBundleIDs.contains(bundleID) { return nil }

        if let focused = focusedElement {
            var roleRef: CFTypeRef?
            var subroleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &roleRef)
            AXUIElementCopyAttributeValue(focused, kAXSubroleAttribute as CFString, &subroleRef)
            if AutoCorrectionGate.isSecureField(role: roleRef as? String, subrole: subroleRef as? String) {
                return nil
            }
        }

        let pid = app.processIdentifier
        let appName = app.localizedName ?? bundleID
        let cacheKey = "\(pid):\(focusedElement.map { CFHash($0) } ?? 0)"
        if let entry = cache, entry.key == cacheKey, Date().timeIntervalSince(entry.timestamp) < Self.cacheTTL {
            return entry.result
        }

        let timeoutNanos = UInt64((Self.maxTimeBudgetSeconds + 0.03) * 1_000_000_000)
        let outcome = await withTaskGroup(of: ExtractionTaskOutcome.self) { group -> ExtractionTaskOutcome in
            group.addTask(priority: .utility) {
                let res = Self.performExtraction(
                    pid: pid,
                    bundleID: bundleID,
                    appName: appName,
                    focusedElement: focusedElement,
                    maxCharacters: maxCharacters,
                    maxMessages: maxMessages,
                    allowVisionOCR: false
                )
                return .completed(res)
            }
            group.addTask(priority: .utility) {
                try? await Task.sleep(nanoseconds: timeoutNanos)
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }

        switch outcome {
        case .completed(let axResult):
            consecutiveFailures = 0
            circuitBreakerUntil = nil
            if let res = axResult, !res.messages.isEmpty {
                self.cache = CacheEntry(key: cacheKey, result: res, timestamp: Date())
                return res
            }
            // Fallback to Apple Vision OCR off the main thread without tripping the AX circuit breaker
            let ocrResult = await Task.detached(priority: .utility) {
                Self.performVisionFallbackForApp(
                    pid: pid,
                    bundleID: bundleID,
                    appName: appName,
                    focusedElement: focusedElement,
                    fallbackWindowTitle: axResult?.windowTitle,
                    fallbackWebDomain: axResult?.webDomain,
                    maxMessages: maxMessages
                )
            }.value ?? axResult
            self.cache = CacheEntry(key: cacheKey, result: ocrResult, timestamp: Date())
            return ocrResult
        case .timedOut:
            consecutiveFailures += 1
            if consecutiveFailures >= 3 {
                circuitBreakerUntil = Date().addingTimeInterval(15)
            }
            self.cache = CacheEntry(key: cacheKey, result: nil, timestamp: Date())
            return nil
        }
    }

    private enum ExtractionTaskOutcome {
        case completed(ScreenContextResult?)
        case timedOut
    }

    // MARK: - Background Traversal Engine

    nonisolated static func performExtraction(
        pid: pid_t,
        bundleID: String,
        appName: String,
        focusedElement: AXUIElement?,
        maxCharacters: Int = defaultMaxCharacters,
        maxMessages: Int = defaultMaxMessages,
        allowVisionOCR: Bool = true
    ) -> ScreenContextResult? {
        let appElement = AXUIElementCreateApplication(pid)
        // Bound individual IPC messages to 50ms so an unresponsive app never hangs LangSwitcher
        AXUIElementSetMessagingTimeout(appElement, 0.05)

        // Locate focused or main window
        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) != .success {
            if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &windowRef) != .success {
                var windowsRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                   let wins = windowsRef as? [AXUIElement], let first = wins.first {
                    windowRef = first
                }
            }
        }

        guard let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() else { return nil }
        let window = windowRef as! AXUIElement
        AXUIElementSetMessagingTimeout(window, 0.05)

        // Extract window title
        var titleRef: CFTypeRef?
        var windowTitle: String?
        if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
           let title = titleRef as? String {
            windowTitle = title
        }

        // Extract web domain if app is a browser
        var webDomain: String?
        if BrowserDomainExtractor.isBrowser(bundleID: bundleID) {
            webDomain = BrowserDomainExtractor.shared.extractDomain(
                pid: pid,
                bundleID: bundleID,
                focusedElement: focusedElement,
                window: window
            )
        }

        // Determine focused element rect if available
        var focusedRect: CGRect?
        if let focused = focusedElement {
            focusedRect = elementFrame(focused)
        }

        let isChat = isChatApp(bundleID: bundleID)

        // Locate root content node:
        // Priority 1: Bottom-up from focused input element (fastest: locates adjacent message list in 2-4ms)
        // Priority 2: WebArea ancestor of focused element -> <main> conversation container
        // Priority 3: WebArea in window -> <main> conversation container
        // Priority 4: Chat column ancestor of focused element
        // Priority 5: Fallback to full window
        var traversalRoot: AXUIElement = window
        var isInsideConversationPane = false

        if let focused = focusedElement, let bottomUp = findBottomUpMessageContainer(from: focused, focusedRect: focusedRect) {
            traversalRoot = bottomUp
            isInsideConversationPane = true
        } else if let focused = focusedElement, let webArea = findWebAreaAncestor(of: focused) {
            if let main = findMainConversationContainer(in: webArea) {
                traversalRoot = main
                isInsideConversationPane = true
            } else {
                traversalRoot = webArea
            }
        } else if let webArea = findWebAreaInWindow(window) {
            if let main = findMainConversationContainer(in: webArea) {
                traversalRoot = main
                isInsideConversationPane = true
            } else {
                traversalRoot = webArea
            }
        } else if let focused = focusedElement, let f = focusedRect, isChat,
                  let chatAncestor = findChatColumnAncestor(of: focused, focusedRect: f) {
            traversalRoot = chatAncestor
            isInsideConversationPane = true
        }

        if isChat && focusedRect == nil && !isInsideConversationPane {
            return nil
        }

        // Fast path for terminal emulators: extract visible screen text and clean TUI/borders
        if isTerminalApp(bundleID: bundleID) {
            if let terminalText = extractElementText(traversalRoot) ?? extractElementText(window) {
                let parsed = TerminalPromptExtractor.parseTerminalBuffer(terminalText)
                if !parsed.cleanedLines.isEmpty {
                    var items: [(text: String, y: CGFloat, x: CGFloat, speaker: Speaker)] = []
                    for (index, line) in parsed.cleanedLines.suffix(maxMessages).enumerated() {
                        let isCurrent = (line == parsed.currentCommand)
                        let speaker: Speaker = isCurrent ? .outgoing : .incoming
                        items.append((text: line, y: CGFloat(index * 20), x: 0, speaker: speaker))
                    }
                    if let result = filterAndFormat(
                        attributedItems: items,
                        windowTitle: windowTitle,
                        appBundleID: bundleID,
                        appName: appName,
                        maxCharacters: maxCharacters,
                        maxMessages: maxMessages
                    ) {
                        return result
                    }
                }
            }
        }

        let deadline = ProcessInfo.processInfo.systemUptime + maxTimeBudgetSeconds
        var visitedCount = 0
        var collectedItems: [(text: String, y: CGFloat, x: CGFloat, speaker: Speaker)] = []
        var activeSpeaker: Speaker = .neutral

        // Compute column bounds for conversation text
        var columnMinX: CGFloat = 0
        var columnMaxX: CGFloat = 800
        if isInsideConversationPane, let containerFrame = elementFrame(traversalRoot) {
            columnMinX = containerFrame.origin.x
            columnMaxX = containerFrame.origin.x + containerFrame.width
        } else if let f = focusedRect, f.width > 20 {
            if isChat {
                columnMinX = f.origin.x - 10
                columnMaxX = f.origin.x + f.width + 10
            } else {
                columnMinX = f.origin.x - 30
                columnMaxX = f.origin.x + f.width + 30
            }
        } else if let winFrame = elementFrame(window) {
            columnMinX = winFrame.origin.x
            columnMaxX = winFrame.origin.x + winFrame.width
        }

        // If content root has a specific title and window title is missing or generic, refine it
        if !CFEqual(traversalRoot, window) {
            var webTitleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(traversalRoot, kAXTitleAttribute as CFString, &webTitleRef) == .success,
               let webTitle = webTitleRef as? String, !webTitle.isEmpty {
                windowTitle = webTitle
            }
        }

        // Breadth-First traversal of content elements using index cursor
        var queue: [(element: AXUIElement, depth: Int)] = [(traversalRoot, 0)]
        var head = 0

        while head < queue.count && visitedCount < maxVisitedElements {
            if ProcessInfo.processInfo.systemUptime >= deadline {
                break
            }

            let (element, depth) = queue[head]
            head += 1
            visitedCount += 1

            // Skip the active text field itself so we do not duplicate caret context
            if let focused = focusedElement, CFEqual(element, focused) {
                continue
            }

            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String ?? ""

            if isIgnoredRole(role) {
                continue
            }

            if isChat, let f = focusedRect, let elemFrame = elementFrame(element) {
                if elemFrame.origin.x + elemFrame.width < f.origin.x - 10 {
                    continue
                }
            }

            // Track explicit speaker headings (ChatGPT, Claude, web chats, forum quotes)
            var valHRef: CFTypeRef?
            var descHRef: CFTypeRef?
            var titleHRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valHRef)
            AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descHRef)
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleHRef)
            let headerText = [valHRef as? String, descHRef as? String, titleHRef as? String]
                .compactMap { $0 }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            if headerText.contains("вы сказали") || headerText.contains("you said") || headerText.hasPrefix("вы:") || headerText.hasPrefix("you:") {
                activeSpeaker = .outgoing
            } else if headerText.contains("сказал:") || headerText.contains("said:") ||
                      headerText.contains("chatgpt") || headerText.contains("claude") ||
                      headerText.contains("assistant") || headerText.hasPrefix("цитата:") ||
                      headerText.hasPrefix("quote:") {
                activeSpeaker = .incoming
            }

            if textRoles.contains(role) {
                let rawText = Self.extractElementText(element)

                if let text = rawText,
                   !isTimestampOrDate(text),
                   !isUINoiseText(text),
                   let sanitized = sanitizeMessage(text) {

                    let frame = elementFrame(element)
                    var acceptSpatial = true

                    if let f = focusedRect, f.width > 20, let elemFrame = frame {
                        if f.insetBy(dx: -2, dy: -2).intersects(elemFrame) {
                            acceptSpatial = false
                        } else if !isInsideConversationPane {
                            let elementMidX = elemFrame.origin.x + (elemFrame.width / 2.0)
                            let overlapsColumn = (elementMidX >= columnMinX) &&
                                                 (elementMidX <= columnMaxX) &&
                                                 (elemFrame.origin.x >= columnMinX - 15)
                            let isAbove = elemFrame.origin.y < f.origin.y + 4
                            acceptSpatial = overlapsColumn && isAbove
                        } else {
                            acceptSpatial = elemFrame.origin.y < f.origin.y + 4
                        }
                    }

                    if acceptSpatial {
                        let yPos = frame?.origin.y ?? CGFloat(visitedCount)
                        let xPos = frame?.origin.x ?? 0
                        var speaker = activeSpeaker
                        if speaker == .neutral {
                            speaker = detectSpeaker(elementFrame: frame, columnMinX: columnMinX, columnMaxX: columnMaxX)
                        }
                        if speaker == .neutral && (sanitized.hasPrefix("Цитата:") || sanitized.hasPrefix("Quote:")) {
                            speaker = .incoming
                        }
                        collectedItems.append((text: sanitized, y: yPos, x: xPos, speaker: speaker))
                    }
                }
            }

            if depth < maxDepth {
                var childrenRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                   let children = childrenRef as? [AXUIElement] {
                    // For conversation containers, reverse top-level children so newest messages (at bottom) are visited first
                    let orderedChildren = (isInsideConversationPane && depth <= 2) ? Array(children.reversed()) : children
                    for child in orderedChildren {
                        queue.append((child, depth + 1))
                    }
                }
            }
        }

        let axResult = filterAndFormat(
            attributedItems: collectedItems,
            windowTitle: windowTitle,
            appBundleID: bundleID,
            appName: appName,
            webDomain: webDomain,
            maxCharacters: maxCharacters,
            maxMessages: maxMessages
        )

        if let res = axResult, !res.messages.isEmpty {
            return res
        }

        guard allowVisionOCR else {
            return axResult
        }

        // Fallback to high-speed Apple Vision OCR on window screenshot when AX tree has no text
        // (common in Electron/Qt apps like Telegram, Slack, VSCode, Chrome canvas)
        let winFrame = elementFrame(window)
        return performVisionOCR(
            windowFrame: winFrame,
            focusedRect: focusedRect,
            bundleID: bundleID,
            appName: appName,
            windowTitle: windowTitle,
            webDomain: webDomain,
            maxMessages: maxMessages
        ) ?? axResult
    }

    nonisolated private static func performVisionFallbackForApp(
        pid: pid_t,
        bundleID: String,
        appName: String,
        focusedElement: AXUIElement?,
        fallbackWindowTitle: String?,
        fallbackWebDomain: String?,
        maxMessages: Int
    ) -> ScreenContextResult? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.05)

        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) != .success {
            _ = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &windowRef)
        }
        var winFrame: CGRect?
        var windowTitle = fallbackWindowTitle
        if let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() {
            let win = windowRef as! AXUIElement
            AXUIElementSetMessagingTimeout(win, 0.05)
            winFrame = elementFrame(win)
            if windowTitle == nil {
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef) == .success {
                    windowTitle = titleRef as? String
                }
            }
        }
        let focusedRect = focusedElement.flatMap { elementFrame($0) }
        return performVisionOCR(
            windowFrame: winFrame,
            focusedRect: focusedRect,
            bundleID: bundleID,
            appName: appName,
            windowTitle: windowTitle,
            webDomain: fallbackWebDomain,
            maxMessages: maxMessages
        )
    }

    // MARK: - Apple Vision OCR Engine

    nonisolated static func performVisionOCR(
        windowFrame: CGRect?,
        focusedRect: CGRect?,
        bundleID: String,
        appName: String,
        windowTitle: String?,
        webDomain: String?,
        maxMessages: Int = defaultMaxMessages
    ) -> ScreenContextResult? {
        guard CGPreflightScreenCaptureAccess() else { return nil }

        // Determine screenshot region
        let targetRect: CGRect
        if let f = focusedRect, f.origin.y > 60 {
            // Region above the typing field where chat messages reside
            let topY = max(0, f.origin.y - 450)
            let height = f.origin.y - topY
            let width = max(500.0, f.width + 120.0)
            let originX = max(0, f.origin.x - 40.0)
            targetRect = CGRect(x: originX, y: topY, width: width, height: height)
        } else if let w = windowFrame, w.width > 100, w.height > 100 {
            targetRect = w
        } else {
            return nil
        }

        guard let image = CGWindowListCreateImage(
            targetRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .nominalResolution]
        ) else {
            return nil
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.recognitionLanguages = ["ru-RU", "en-US", "uk-UA"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observations = request.results, !observations.isEmpty else { return nil }

        // Sort observations top-to-bottom
        let sorted = observations.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
        var recognizedLines: [String] = []

        for obs in sorted {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.count >= 2 else { continue }
            if isTimestampOrDate(text) || isUINoiseText(text) { continue }
            if let sanitized = sanitizeMessage(text) {
                recognizedLines.append(sanitized)
            }
        }

        guard !recognizedLines.isEmpty else { return nil }

        let tailLines = Array(recognizedLines.suffix(maxMessages))
        let joined = tailLines.joined(separator: "\n")
        let hasQuestion = joined.contains("?")

        var formatted = (appName.isEmpty ? "" : "[\(appName)]\n")
        formatted += joined

        return ScreenContextResult(
            appBundleID: bundleID,
            appName: appName,
            windowTitle: windowTitle,
            webDomain: webDomain,
            messages: tailLines,
            formattedContext: formatted,
            hasPendingQuestion: hasQuestion
        )
    }

    // MARK: - AX Helpers

    /// Safely extracts text from an accessibility element using:
    /// 1. Parameterized visible character range (kAXVisibleCharacterRangeAttribute + kAXStringForRangeParameterizedAttribute),
    ///    which is optimal for native AppKit NSTextView (TextEdit, Notes, Mail, Pages, Xcode).
    /// 2. Direct kAXValueAttribute (plain text fields, static texts, web text nodes).
    /// 3. kAXDescriptionAttribute (accessible labels, icons with descriptions).
    /// 4. kAXTitleAttribute (window / element titles).
    nonisolated static func extractElementText(_ element: AXUIElement) -> String? {
        // 1. Try visible character range with parameterized string lookup (ideal for NSTextView / large documents)
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXVisibleCharacterRangeAttribute as CFString, &rangeRef) == .success,
           let rangeValue = rangeRef, CFGetTypeID(rangeValue) == AXValueGetTypeID() {
            var cfRange = CFRange(location: 0, length: 0)
            if AXValueGetValue(rangeValue as! AXValue, .cfRange, &cfRange), cfRange.length > 0 {
                // Bound the range to avoid huge IPC allocations
                let boundedLength = min(cfRange.length, 2500)
                var queryRange = CFRange(location: cfRange.location, length: boundedLength)
                if let boundedValue = AXValueCreate(.cfRange, &queryRange) {
                    var strRef: CFTypeRef?
                    if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, boundedValue, &strRef) == .success {
                        if let s = strRef as? String, !s.isEmpty {
                            return s
                        } else if let attrStr = strRef as? NSAttributedString, !attrStr.string.isEmpty {
                            return attrStr.string
                        }
                    }
                }
            }
        }

        // 2. Direct value attribute (strings, text fields, static texts)
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success {
            if let str = valueRef as? String, !str.isEmpty {
                return str
            } else if let attrStr = valueRef as? NSAttributedString, !attrStr.string.isEmpty {
                return attrStr.string
            }
        }

        // 3. Accessibility Description attribute
        var descRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef) == .success,
           let desc = descRef as? String, !desc.isEmpty {
            return desc
        }

        // 4. Accessibility Title attribute
        var titleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
           let title = titleRef as? String, !title.isEmpty {
            return title
        }

        return nil
    }

    nonisolated static func elementFrame(_ element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)

        var pos = CGPoint.zero
        var size = CGSize.zero
        var gotPos = false
        var gotSize = false

        if let p = posRef, CFGetTypeID(p) == AXValueGetTypeID() {
            gotPos = AXValueGetValue(p as! AXValue, .cgPoint, &pos)
        }
        if let s = sizeRef, CFGetTypeID(s) == AXValueGetTypeID() {
            gotSize = AXValueGetValue(s as! AXValue, .cgSize, &size)
        }

        guard gotPos && gotSize else { return nil }
        return CGRect(origin: pos, size: size)
    }
}
