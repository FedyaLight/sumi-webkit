import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabWebViewSessionStoreTests: XCTestCase {
    func testAllKnownWebViewsUsesSessionAndRegistry() {
        let registry = WindowWebViewRegistry()
        let store = TabWebViewSessionStore(webViewRegistry: registry)
        let tab = Tab(
            url: URL(string: "https://example.com/session")!,
            loadsCachedFaviconOnInit: false
        )
        let parked = WKWebView(frame: .zero)
        let untracked = WKWebView(frame: .zero)
        let windowed = WKWebView(frame: .zero)
        let windowId = UUID()

        // Session-first notes (authoritative); Tab mirror optional for compat.
        store.noteParkedWebView(parked, for: tab.id)
        store.noteUntrackedWebView(untracked, for: tab.id)
        registry.setWebView(
            windowed,
            for: TrackedWebViewOwner(tabID: tab.id, windowID: windowId)
        )

        let known = store.allKnownWebViews(for: tab)
        XCTAssertTrue(known.contains { $0 === windowed })
        XCTAssertTrue(known.contains { $0 === untracked })
        XCTAssertTrue(known.contains { $0 === parked })
    }

    func testSyncFromTabImportsOnlyWhenSessionEmpty() {
        let registry = WindowWebViewRegistry()
        let store = TabWebViewSessionStore(webViewRegistry: registry)
        let tab = Tab(
            url: URL(string: "https://example.com/import")!,
            loadsCachedFaviconOnInit: false
        )
        let tabParked = WKWebView(frame: .zero)
        let sessionParked = WKWebView(frame: .zero)
        tab.parkExistingWebView(tabParked)

        store.noteParkedWebView(sessionParked, for: tab.id)
        store.syncFromTabIfNeeded(tab)

        XCTAssertIdentical(store.parkedWebView(for: tab.id), sessionParked)
    }

    func testClearAllRemovesSessionMaterial() {
        let registry = WindowWebViewRegistry()
        let store = TabWebViewSessionStore(webViewRegistry: registry)
        let tabId = UUID()
        store.noteUntrackedWebView(WKWebView(frame: .zero), for: tabId)
        store.noteParkedWebView(WKWebView(frame: .zero), for: tabId)

        store.clearAll(for: tabId)

        XCTAssertNil(store.untrackedWebView(for: tabId))
        XCTAssertNil(store.parkedWebView(for: tabId))
    }
}
