import WebKit
import XCTest

@testable import Sumi

@MainActor
final class WindowWebContentHostRegistryTests: XCTestCase {
    func testParkedHostIsResolvedByExactTabAndWebViewIdentity() {
        let registry = WindowWebContentHostRegistry()
        let tabID = UUID()
        let webView = WKWebView()
        let host = SumiWebViewContainerView(tabID: tabID, webView: webView)

        registry.parkHost(host)

        XCTAssertTrue(registry.parkedHost(for: tabID, webView: webView) === host)
        XCTAssertNil(registry.parkedHost(for: UUID(), webView: webView))
    }

    func testDisplayingParkedHostRemovesItsParkedResidence() {
        let registry = WindowWebContentHostRegistry()
        let tabID = UUID()
        let webView = WKWebView()
        let host = SumiWebViewContainerView(tabID: tabID, webView: webView)

        registry.parkHost(host)
        registry.setHost(host, for: .single)

        XCTAssertTrue(registry.host(for: .single) === host)
        XCTAssertNil(registry.parkedHost(for: tabID, webView: webView))
    }

    func testRuntimeEvictionClearsDisplayedAndParkedResidences() {
        let registry = WindowWebContentHostRegistry()
        let displayedWebView = WKWebView()
        let displayedHost = SumiWebViewContainerView(
            tabID: UUID(),
            webView: displayedWebView
        )
        let parkedWebView = WKWebView()
        let parkedTabID = UUID()
        let parkedHost = SumiWebViewContainerView(
            tabID: parkedTabID,
            webView: parkedWebView
        )

        registry.setHost(displayedHost, for: .single)
        registry.parkHost(parkedHost)
        displayedHost.evictFromRuntime()
        parkedHost.evictFromRuntime()

        XCTAssertNil(registry.host(for: .single))
        XCTAssertNil(
            registry.parkedHost(
                for: parkedTabID,
                webView: parkedWebView
            )
        )
    }
}
