import Foundation
import AppKit
import ApplicationServices

// MARK: - Screen Context Result
// Extracted visible dialogue and context from the frontmost window.

struct ScreenContextResult: Equatable {
    let appBundleID: String
    let appName: String
    let windowTitle: String?
    let messages: [String]
    let formattedContext: String
    let hasPendingQuestion: Bool
    
    init(
        appBundleID: String,
        appName: String,
        windowTitle: String?,
        messages: [String],
        formattedContext: String,
        hasPendingQuestion: Bool = false
    ) {
        self.appBundleID = appBundleID
        self.appName = appName
        self.windowTitle = windowTitle
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
    nonisolated static let maxDepth = 12
    nonisolated static let maxVisitedElements = 120
    nonisolated static let maxTimeBudgetSeconds = 0.035 // 35 ms
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
        "отправить", "прикрепить", "поиск", "закрыть", "свернуть", "отмена", "удалить",
        "копировать", "ответить", "переслать", "изменено", "прочитано", "доставлено",
        "в сети", "был(а) в сети", "печатает", "перейти к контенту", "сообщение"
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
        "org.mozilla.firefox"
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
        "com.viber.osx"
    ]

    nonisolated static func isChatApp(bundleID: String) -> Bool {
        chatBundleIDs.contains(bundleID)
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
        while head < queue.count && head < 60 {
            let (el, depth) = queue[head]
            head += 1
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String ?? ""
            if role == "AXWebArea" {
                return el
            }
            if ["AXToolbar", "AXTabGroup", "AXMenuBar", "AXButton"].contains(role) {
                continue
            }
            if depth < 8 {
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
    private static let creditCardRegex = try? NSRegularExpression(pattern: #"\b(?:\d[ -]*?){13,16}\b"#)
    private static let emailRegex = try? NSRegularExpression(pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#)
    private static let phoneRegex = try? NSRegularExpression(pattern: #"\b(?:\+?\d{1,3}[-.\s]?)?\(?\d{2,4}\)?[-.\s]?\d{3}[-.\s]?\d{2,4}\b"#)
    private static let secretTokenRegex = try? NSRegularExpression(pattern: #"(?:ey[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+|ghp_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,})"#)
    private static let timestampRegex = try? NSRegularExpression(pattern: #"^\d{1,2}:\d{2}(?::\d{2})?(?:\s*[AP]M)?$"#, options: .caseInsensitive)
    private static let dateLabelRegex = try? NSRegularExpression(pattern: #"^(today|yesterday|сегодня|вчера|just now|только что)$"#, options: .caseInsensitive)
    
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
        return false
    }
    
    nonisolated static func isUINoiseText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return true }
        if noiseLabels.contains(trimmed) { return true }
        
        // Single characters, symbols, or pure digits
        if trimmed.count == 1 { return true }
        if trimmed.allSatisfy(\.isNumber) { return true }
        if trimmed.allSatisfy({ $0.isPunctuation || $0.isSymbol }) { return true }
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
        
        return sanitized
    }
    
    nonisolated static func detectPendingQuestion(messages: [(text: String, speaker: Speaker)]) -> Bool {
        guard let last = messages.last else { return false }
        // If the user already answered last (You: ...), there is no pending question
        guard last.speaker == .incoming || last.speaker == .neutral else { return false }
        let trimmed = last.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Matches questions ending in ? optionally followed by smileys, emoji, quotes, brackets or whitespace
        let pattern = #"[?？][^\p{L}\p{N}]*$"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(location: 0, length: trimmed.utf16.count)
            return regex.firstMatch(in: trimmed, range: range) != nil
        }
        return trimmed.hasSuffix("?") || trimmed.hasSuffix("?!") || trimmed.hasSuffix("?..")
    }
    
    // Backward-compatible overload for 3-tuple (text, y, x)
    nonisolated static func filterAndFormat(
        items: [(text: String, y: CGFloat, x: CGFloat)],
        windowTitle: String?,
        appBundleID: String,
        appName: String,
        maxCharacters: Int = defaultMaxCharacters,
        maxMessages: Int = defaultMaxMessages
    ) -> ScreenContextResult? {
        let attributed = items.map { (text: $0.text, y: $0.y, x: $0.x, speaker: Speaker.neutral) }
        return filterAndFormat(
            attributedItems: attributed,
            windowTitle: windowTitle,
            appBundleID: appBundleID,
            appName: appName,
            maxCharacters: maxCharacters,
            maxMessages: maxMessages
        )
    }
    
    nonisolated static func filterAndFormat(
        attributedItems: [(text: String, y: CGFloat, x: CGFloat, speaker: Speaker)],
        windowTitle: String?,
        appBundleID: String,
        appName: String,
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
        let contextType = chatBundleIDs.contains(appBundleID) ? "dialogue" : "window"
        if let title = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
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
            maxMessages: maxMessages
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
        let result = await withTaskGroup(of: ScreenContextResult?.self) { group -> ScreenContextResult? in
            group.addTask(priority: .utility) {
                Self.performExtraction(
                    pid: pid,
                    bundleID: bundleID,
                    appName: appName,
                    focusedElement: focusedElement,
                    maxCharacters: maxCharacters,
                    maxMessages: maxMessages
                )
            }
            group.addTask(priority: .utility) {
                try? await Task.sleep(nanoseconds: timeoutNanos)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        
        self.cache = CacheEntry(key: cacheKey, result: result, timestamp: Date())
        if result == nil {
            consecutiveFailures += 1
            if consecutiveFailures >= 3 {
                circuitBreakerUntil = Date().addingTimeInterval(15)
            }
        } else {
            consecutiveFailures = 0
            circuitBreakerUntil = nil
        }
        return result
    }
    
    // MARK: - Background Traversal Engine
    
    nonisolated static func performExtraction(
        pid: pid_t,
        bundleID: String,
        appName: String,
        focusedElement: AXUIElement?,
        maxCharacters: Int = defaultMaxCharacters,
        maxMessages: Int = defaultMaxMessages
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
        
        // Determine focused element rect if available
        var focusedRect: CGRect?
        if let focused = focusedElement {
            focusedRect = elementFrame(focused)
        }
        
        let isChat = isChatApp(bundleID: bundleID)
        if isChat && focusedRect == nil {
            return nil
        }
        
        let deadline = ProcessInfo.processInfo.systemUptime + maxTimeBudgetSeconds
        var visitedCount = 0
        var collectedItems: [(text: String, y: CGFloat, x: CGFloat, speaker: Speaker)] = []
        
        // Compute column bounds for conversation text
        var columnMinX: CGFloat = 0
        var columnMaxX: CGFloat = 800
        if let f = focusedRect, f.width > 20 {
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
        
        // Locate root content node: if web app, prioritize AXWebArea; if chat app, prioritize chat column container
        var traversalRoot: AXUIElement = window
        if let focused = focusedElement, let webArea = findWebAreaAncestor(of: focused) {
            traversalRoot = webArea
        } else if isBrowserApp(bundleID: bundleID), let webArea = findWebAreaInWindow(window) {
            traversalRoot = webArea
        } else if let focused = focusedElement, let f = focusedRect, isChat,
                  let chatAncestor = findChatColumnAncestor(of: focused, focusedRect: f) {
            traversalRoot = chatAncestor
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
            
            if textRoles.contains(role) {
                var valueRef: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
                var rawText = (valueRef as? String) ?? (valueRef as? NSAttributedString)?.string
                
                if rawText == nil || rawText?.isEmpty == true {
                    var descRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)
                    rawText = descRef as? String
                }
                
                if rawText == nil || rawText?.isEmpty == true {
                    var titleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
                    rawText = titleRef as? String
                }
                
                if let text = rawText,
                   !isTimestampOrDate(text),
                   !isUINoiseText(text),
                   let sanitized = sanitizeMessage(text) {
                    
                    let frame = elementFrame(element)
                    var acceptSpatial = true
                    
                    if let f = focusedRect, f.width > 20, let elemFrame = frame {
                        if f.insetBy(dx: -2, dy: -2).intersects(elemFrame) {
                            acceptSpatial = false
                        } else {
                            let elementMidX = elemFrame.origin.x + (elemFrame.width / 2.0)
                            let overlapsColumn = (elementMidX >= columnMinX) &&
                                                 (elementMidX <= columnMaxX) &&
                                                 (elemFrame.origin.x >= columnMinX - 15)
                            let isAbove = elemFrame.origin.y < f.origin.y + 4
                            acceptSpatial = overlapsColumn && isAbove
                        }
                    }
                    
                    if acceptSpatial {
                        let yPos = frame?.origin.y ?? CGFloat(visitedCount)
                        let xPos = frame?.origin.x ?? 0
                        let speaker = detectSpeaker(elementFrame: frame, columnMinX: columnMinX, columnMaxX: columnMaxX)
                        collectedItems.append((text: sanitized, y: yPos, x: xPos, speaker: speaker))
                    }
                }
            }
            
            if depth < maxDepth {
                var childrenRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                   let children = childrenRef as? [AXUIElement] {
                    for child in children {
                        queue.append((child, depth + 1))
                    }
                }
            }
        }
        
        return filterAndFormat(
            attributedItems: collectedItems,
            windowTitle: windowTitle,
            appBundleID: bundleID,
            appName: appName,
            maxCharacters: maxCharacters,
            maxMessages: maxMessages
        )
    }
    
    // MARK: - AX Helpers
    
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
