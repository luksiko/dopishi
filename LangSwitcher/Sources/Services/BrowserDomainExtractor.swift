import Foundation
import ApplicationServices

// MARK: - Browser Domain Extractor
// Extracts the active website domain (e.g. github.com, docs.google.com, jira.atlassian.net)
// from macOS web browsers (Safari, Chrome, Arc, Brave, Edge, Opera, Firefox) via Accessibility APIs.

final class BrowserDomainExtractor: @unchecked Sendable {
    
    static let shared = BrowserDomainExtractor()
    
    private let lock = NSLock()
    
    // MARK: - Known Browser Bundle Identifiers
    
    static let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "company.thebrowser.Arc",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
        "org.mozilla.firefox",
        "org.mozilla.nightly"
    ]
    
    public static func isBrowser(bundleID: String?) -> Bool {
        guard let bundleID = bundleID else { return false }
        return browserBundleIDs.contains(bundleID)
    }
    
    // MARK: - Cache
    
    private struct CacheEntry {
        let domain: String?
        let timestamp: Date
    }
    
    private var cache: [String: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 1.5 // 1.5 seconds TTL
    
    // MARK: - Public Extraction
    
    /// Extracts domain from current frontmost browser or given AX elements.
    func extractDomain(
        pid: pid_t,
        bundleID: String,
        focusedElement: AXUIElement? = nil,
        window: AXUIElement? = nil
    ) -> String? {
        guard Self.isBrowser(bundleID: bundleID) else { return nil }
        
        let cacheKey = "\(pid):\(bundleID)"
        let now = Date()
        
        lock.lock()
        if let cached = cache[cacheKey], now.timeIntervalSince(cached.timestamp) < cacheTTL {
            let res = cached.domain
            lock.unlock()
            return res
        }
        lock.unlock()
        
        let domain = performExtraction(pid: pid, bundleID: bundleID, focusedElement: focusedElement, window: window)
        
        lock.lock()
        cache[cacheKey] = CacheEntry(domain: domain, timestamp: now)
        lock.unlock()
        return domain
    }
    
    // MARK: - Internal Extraction
    
    private func performExtraction(
        pid: pid_t,
        bundleID: String,
        focusedElement: AXUIElement?,
        window: AXUIElement?
    ) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.05)
        
        // Strategy 1: Window Document URL (Standard Safari & WebKit)
        if let win = window ?? copyFocusedWindow(app: appElement) {
            if let docURL = copyStringAttribute(element: win, attribute: kAXDocumentAttribute as CFString) {
                if let domain = Self.sanitizeDomain(from: docURL) {
                    return domain
                }
            }
            if let axURL = copyStringAttribute(element: win, attribute: "AXURL" as CFString) {
                if let domain = Self.sanitizeDomain(from: axURL) {
                    return domain
                }
            }
        }
        
        // Strategy 2: Upward traversal from focused element to AXWebArea (Chromium & WebKit)
        if let focused = focusedElement {
            var current: AXUIElement? = focused
            var depth = 0
            while let el = current, depth < 8 {
                if let axURL = copyStringAttribute(element: el, attribute: "AXURL" as CFString) {
                    if let domain = Self.sanitizeDomain(from: axURL) {
                        return domain
                    }
                }
                
                var parentVal: CFTypeRef?
                if AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &parentVal) == .success,
                   let parent = parentVal, CFGetTypeID(parent) == AXUIElementGetTypeID() {
                    current = (parent as! AXUIElement)
                } else {
                    current = nil
                }
                depth += 1
            }
        }
        
        // Strategy 3: Window children scan for Address bar or WebArea
        if let win = window ?? copyFocusedWindow(app: appElement) {
            if let domain = searchChildrenForURL(element: win, maxDepth: 4) {
                return domain
            }
        }
        
        return nil
    }
    
    private func searchChildrenForURL(element: AXUIElement, maxDepth: Int) -> String? {
        guard maxDepth > 0 else { return nil }
        
        var childrenVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenVal) == .success,
              let children = childrenVal as? [AXUIElement] else {
            return nil
        }
        
        for child in children.prefix(20) {
            // Check direct URL attribute
            if let axURL = copyStringAttribute(element: child, attribute: "AXURL" as CFString),
               let domain = Self.sanitizeDomain(from: axURL) {
                return domain
            }
            
            // Check address bar value
            if let role = copyStringAttribute(element: child, attribute: kAXRoleAttribute as CFString),
               role == (kAXTextFieldRole as String) {
                if let val = copyStringAttribute(element: child, attribute: kAXValueAttribute as CFString),
                   let domain = Self.sanitizeDomain(from: val) {
                    return domain
                }
            }
            
            if let deeper = searchChildrenForURL(element: child, maxDepth: maxDepth - 1) {
                return deeper
            }
        }
        return nil
    }
    
    private func copyFocusedWindow(app: AXUIElement) -> AXUIElement? {
        var winVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &winVal) == .success,
           let win = winVal, CFGetTypeID(win) == AXUIElementGetTypeID() {
            return (win as! AXUIElement)
        }
        if AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &winVal) == .success,
           let win = winVal, CFGetTypeID(win) == AXUIElementGetTypeID() {
            return (win as! AXUIElement)
        }
        return nil
    }
    
    private func copyStringAttribute(element: AXUIElement, attribute: CFString) -> String? {
        var val: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &val) == .success,
              let strVal = val as? String else {
            return nil
        }
        return strVal
    }
    
    // MARK: - Domain Normalization & Sanitization
    
    /// Normalizes raw URLs or address bar inputs into clean domain hosts (e.g. "github.com", "docs.google.com").
    static func sanitizeDomain(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // Ignore file / chrome internal URLs
        if trimmed.hasPrefix("file://") || trimmed.hasPrefix("chrome://") ||
           trimmed.hasPrefix("about:") || trimmed.hasPrefix("safari-") {
            return nil
        }
        
        var urlCandidate = trimmed
        if !urlCandidate.contains("://") {
            urlCandidate = "https://" + urlCandidate
        }
        
        guard let url = URL(string: urlCandidate), let host = url.host?.lowercased() else {
            return nil
        }
        
        // Filter out IPs, localhost, or non-domain tokens
        if host == "localhost" || host == "127.0.0.1" || host == "::1" || !host.contains(".") {
            return nil
        }
        
        // Strip www. prefix
        var cleanHost = host
        if cleanHost.hasPrefix("www.") {
            cleanHost = String(cleanHost.dropFirst(4))
        }
        
        guard cleanHost.count >= 4 && cleanHost.contains(".") else { return nil }
        return cleanHost
    }
}
