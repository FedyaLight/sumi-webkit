import WebKit
import XCTest

@testable import Sumi

@MainActor
final class WindowWebViewRegistryTests: XCTestCase {
    func testTrackedOwnerWithIdentifierReturnsCurrentOwner() {
        let registry = WindowWebViewRegistry()
        let owner = TrackedWebViewOwner(tabID: UUID(), windowID: UUID())
        let webView = WKWebView()

        registry.setWebView(webView, for: owner)

        XCTAssertEqual(registry.trackedOwner(with: ObjectIdentifier(webView)), owner)
    }

    func testTrackedOwnerWithIdentifierDropsStaleReverseIndex() {
        let registry = WindowWebViewRegistry()
        let owner = TrackedWebViewOwner(tabID: UUID(), windowID: UUID())
        let staleWebView = WKWebView()
        let currentWebView = WKWebView()

        registry.setWebView(staleWebView, for: owner)
        registry.setWebView(currentWebView, for: owner)

        XCTAssertNil(registry.trackedOwner(with: ObjectIdentifier(staleWebView)))
        XCTAssertFalse(registry.isIndexed(staleWebView))
        XCTAssertEqual(registry.trackedOwner(with: ObjectIdentifier(currentWebView)), owner)
    }
}
