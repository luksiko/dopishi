import XCTest
@testable import LangSwitcher

final class BrowserDomainExtractorTests: XCTestCase {

    func testIsBrowser() {
        XCTAssertTrue(BrowserDomainExtractor.isBrowser(bundleID: "com.apple.Safari"))
        XCTAssertTrue(BrowserDomainExtractor.isBrowser(bundleID: "com.google.Chrome"))
        XCTAssertTrue(BrowserDomainExtractor.isBrowser(bundleID: "company.thebrowser.Arc"))
        XCTAssertTrue(BrowserDomainExtractor.isBrowser(bundleID: "com.brave.Browser"))
        XCTAssertTrue(BrowserDomainExtractor.isBrowser(bundleID: "com.microsoft.edgemac"))
        XCTAssertFalse(BrowserDomainExtractor.isBrowser(bundleID: "com.apple.Terminal"))
        XCTAssertFalse(BrowserDomainExtractor.isBrowser(bundleID: "com.microsoft.VSCode"))
        XCTAssertFalse(BrowserDomainExtractor.isBrowser(bundleID: nil))
    }

    func testSanitizeDomainFromFullHTTPSURL() {
        let domain = BrowserDomainExtractor.sanitizeDomain(from: "https://github.com/swiftlang/swift/pull/123")
        XCTAssertEqual(domain, "github.com")
    }

    func testSanitizeDomainFromSubdomain() {
        let domain = BrowserDomainExtractor.sanitizeDomain(from: "https://docs.google.com/document/d/abc/edit")
        XCTAssertEqual(domain, "docs.google.com")
    }

    func testSanitizeDomainStripsWWW() {
        let domain = BrowserDomainExtractor.sanitizeDomain(from: "https://www.reddit.com/r/swift")
        XCTAssertEqual(domain, "reddit.com")
    }

    func testSanitizeDomainWithoutScheme() {
        let domain = BrowserDomainExtractor.sanitizeDomain(from: "jira.atlassian.net/browse/PROJ-101")
        XCTAssertEqual(domain, "jira.atlassian.net")
    }

    func testSanitizeDomainIgnoresInternalAndLocalHosts() {
        XCTAssertNil(BrowserDomainExtractor.sanitizeDomain(from: "http://localhost:3000/app"))
        XCTAssertNil(BrowserDomainExtractor.sanitizeDomain(from: "http://127.0.0.1:8080"))
        XCTAssertNil(BrowserDomainExtractor.sanitizeDomain(from: "chrome://settings"))
        XCTAssertNil(BrowserDomainExtractor.sanitizeDomain(from: "about:blank"))
        XCTAssertNil(BrowserDomainExtractor.sanitizeDomain(from: "file:///Users/test/index.html"))
        XCTAssertNil(BrowserDomainExtractor.sanitizeDomain(from: ""))
    }

    func testPromptIncorporatesDomainAndSpecializedGuidelines() {
        let messages = AIInferenceEngine.completionMessages(
            context: "fix(core): update layout",
            afterCaret: "",
            instructions: nil,
            screenContext: nil,
            hasPendingQuestion: false,
            appName: "Google Chrome",
            windowTitle: "Pull Request #42",
            webDomain: "github.com"
        )

        let systemMsg = messages.first { $0["role"] == "system" }?["content"] ?? ""
        XCTAssertTrue(systemMsg.contains("github.com"))
        XCTAssertTrue(systemMsg.contains("Git"))
    }
}
