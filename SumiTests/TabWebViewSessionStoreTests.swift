import WebKit
import XCTest
import SumiWebRuntime

@testable import Sumi

@MainActor
final class TabWebViewSessionStoreTests: XCTestCase {
    func testAllKnownWebViewsUsesSessionAndRegistry() {
        let registry = WindowWebViewRegistry()
        let store = TabWebViewSessionStore(webViewRegistry: registry)
        let tabId = UUID()
        let localSession = TabWebViewSession(tabId: tabId)
        let parked = WKWebView(frame: .zero)
        let untracked = WKWebView(frame: .zero)
        let windowed = WKWebView(frame: .zero)
        let windowId = UUID()

        store.noteParkedWebView(parked, for: tabId)
        store.noteUntrackedWebView(untracked, for: tabId)
        registry.setWebView(
            windowed,
            for: TrackedWebViewOwner(tabID: tabId, windowID: windowId)
        )

        let known = store.allKnownWebViews(for: tabId, localSession: localSession)
        XCTAssertTrue(known.contains { $0 === windowed })
        XCTAssertTrue(known.contains { $0 === untracked })
        XCTAssertTrue(known.contains { $0 === parked })
    }

    func testAllKnownWebViewsPromotesLocalSessionNotes() {
        let registry = WindowWebViewRegistry()
        let store = TabWebViewSessionStore(webViewRegistry: registry)
        let tabId = UUID()
        let localSession = TabWebViewSession(tabId: tabId)
        let localParked = WKWebView(frame: .zero)
        let localUntracked = WKWebView(frame: .zero)
        localSession.parkedWebView = localParked
        localSession.untrackedWebView = localUntracked

        let known = store.allKnownWebViews(for: tabId, localSession: localSession)

        XCTAssertTrue(known.contains { $0 === localParked })
        XCTAssertTrue(known.contains { $0 === localUntracked })
        XCTAssertIdentical(store.parkedWebView(for: tabId), localParked)
        XCTAssertIdentical(store.untrackedWebView(for: tabId), localUntracked)
        // Promote copies without clearing the local session.
        XCTAssertIdentical(localSession.parkedWebView, localParked)
        XCTAssertIdentical(localSession.untrackedWebView, localUntracked)
    }

    func testProtectedCandidateWebViewsIncludesRegistryAndSession() {
        let registry = WindowWebViewRegistry()
        let store = TabWebViewSessionStore(webViewRegistry: registry)
        let tabId = UUID()
        let localSession = TabWebViewSession(tabId: tabId)
        let windowed = WKWebView(frame: .zero)
        let primary = WKWebView(frame: .zero)
        let parked = WKWebView(frame: .zero)
        let windowId = UUID()

        registry.setWebView(
            windowed,
            for: TrackedWebViewOwner(tabID: tabId, windowID: windowId)
        )
        store.notePrimaryAssignment(windowId: windowId, for: tabId, webView: primary)
        store.noteParkedWebView(parked, for: tabId)

        let candidates = store.protectedCandidateWebViews(
            for: tabId,
            localSession: localSession
        )

        XCTAssertTrue(candidates.contains { $0 === windowed })
        XCTAssertTrue(candidates.contains { $0 === primary })
        XCTAssertTrue(candidates.contains { $0 === parked })
        XCTAssertEqual(candidates.count, 3)
    }

    func testProtectedCandidateWebViewsPromotesLocalPrimaryHint() {
        let registry = WindowWebViewRegistry()
        let store = TabWebViewSessionStore(webViewRegistry: registry)
        let tabId = UUID()
        let localSession = TabWebViewSession(tabId: tabId)
        let localPrimary = WKWebView(frame: .zero)
        let windowId = UUID()
        localSession.primaryWindowId = windowId
        localSession.primaryWebView = localPrimary

        let candidates = store.protectedCandidateWebViews(
            for: tabId,
            localSession: localSession
        )

        XCTAssertTrue(candidates.contains { $0 === localPrimary })
        XCTAssertEqual(store.primaryWindowId(for: tabId), windowId)
        XCTAssertIdentical(store.session(for: tabId).primaryWebView, localPrimary)
        XCTAssertIdentical(localSession.primaryWebView, localPrimary)
    }

    func testPromoteLocalSessionImportsTabLocalNotesWithoutClearing() {
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
        store.promoteLocalSessionIfNeeded(
            tabId: tab.id,
            localSession: tab.webViewOwnershipOwner.localSession
        )

        // Existing session note wins; Tab-local parked remains for pre-runtime readers.
        XCTAssertIdentical(store.parkedWebView(for: tab.id), sessionParked)
        XCTAssertIdentical(tab.resolvedParkedWebView(), tabParked)
    }

    func testPromoteLocalSessionNoopsWhenLocalSessionIsEmpty() {
        let registry = WindowWebViewRegistry()
        let store = TabWebViewSessionStore(webViewRegistry: registry)
        let tabId = UUID()
        let localSession = TabWebViewSession(tabId: tabId)

        store.promoteLocalSessionIfNeeded(tabId: tabId, localSession: localSession)

        XCTAssertNil(store.parkedWebView(for: tabId))
        XCTAssertNil(store.untrackedWebView(for: tabId))
        XCTAssertNil(store.primaryWindowId(for: tabId))
        // Empty promote must not create a session entry with material.
        let session = store.session(for: tabId)
        XCTAssertNil(session.parkedWebView)
        XCTAssertNil(session.untrackedWebView)
        XCTAssertNil(session.primaryWebView)
        XCTAssertNil(session.primaryWindowId)
    }

    func testClearCurrentIfIdenticalUsesSessionCurrentWebView() {
        let tab = Tab(
            url: URL(string: "https://example.com/clear-identical")!,
            loadsCachedFaviconOnInit: false
        )
        let webView = WKWebView(frame: .zero)
        tab.replaceUntrackedWebView(webView)

        let cleared = tab.clearCurrentWebViewOwnershipIfIdentical(to: webView)

        XCTAssertTrue(cleared)
        XCTAssertNil(tab.resolvedCurrentWebView())
        XCTAssertNil(tab.resolvedPrimaryWindowId())
    }

    func testPrimaryAssignmentMutatorNotesLocalSession() {
        let tab = Tab(
            url: URL(string: "https://example.com/primary")!,
            loadsCachedFaviconOnInit: false
        )
        let webView = WKWebView(frame: .zero)
        let windowId = UUID()
        tab.assignPrimaryWebView(webView, windowId: windowId)
        XCTAssertEqual(tab.resolvedPrimaryWindowId(), windowId)
        XCTAssertIdentical(tab.resolvedAssignedWebView(), webView)

        tab.clearCurrentWebViewOwnership()
        XCTAssertNil(tab.resolvedPrimaryWindowId())
        XCTAssertNil(tab.resolvedAssignedWebView())
    }

    func testAssignedWebViewResolvesFromLocalPrimarySession() {
        let tab = Tab(
            url: URL(string: "https://example.com/assigned")!,
            loadsCachedFaviconOnInit: false
        )
        let webView = WKWebView(frame: .zero)
        let windowId = UUID()
        tab.assignPrimaryWebView(webView, windowId: windowId)

        XCTAssertIdentical(tab.resolvedAssignedWebView(), webView)
        XCTAssertIdentical(tab.resolvedCurrentWebView(), webView)
        XCTAssertEqual(tab.resolvedPrimaryWindowId(), windowId)
        XCTAssertFalse(tab.isUnloaded)
    }

    func testParkedAndUntrackedSessionNotesDriveReloadTitlePermissionReaders() {
        let tab = Tab(
            url: URL(string: "https://example.com/readers")!,
            loadsCachedFaviconOnInit: false
        )
        let untracked = WKWebView(frame: .zero)
        tab.replaceUntrackedWebView(untracked)

        // Reload / title / favicon / permission heavy readers go through resolve helpers.
        XCTAssertIdentical(tab.resolvedCurrentWebView(), untracked)
        XCTAssertNil(tab.resolvedAssignedWebView())
        XCTAssertTrue(tab.hasCurrentWebView)

        let parked = WKWebView(frame: .zero)
        tab.parkExistingWebView(parked)
        XCTAssertIdentical(tab.resolvedParkedWebView(), parked)

        tab.assignPrimaryWebView(untracked, windowId: UUID())
        XCTAssertIdentical(tab.resolvedAssignedWebView(), untracked)
        XCTAssertFalse(tab.isUnloaded)
    }

    func testAdoptLocalSessionClearsTabLocalNotes() {
        let registry = WindowWebViewRegistry()
        let store = TabWebViewSessionStore(webViewRegistry: registry)
        let tab = Tab(
            url: URL(string: "https://example.com/adopt")!,
            loadsCachedFaviconOnInit: false
        )
        let untracked = WKWebView(frame: .zero)
        tab.replaceUntrackedWebView(untracked)

        store.adoptLocalSession(tab.webViewOwnershipOwner.localSession, for: tab.id)

        XCTAssertIdentical(store.untrackedWebView(for: tab.id), untracked)
        XCTAssertNil(tab.webViewOwnershipOwner.localSession.untrackedWebView)
    }

    func testReloadPolicyRebuildContextReadsResolvedCurrentWebView() {
        let tab = Tab(
            url: URL(string: "https://example.com/reload-context")!,
            loadsCachedFaviconOnInit: false
        )
        let webView = WKWebView(frame: .zero)
        tab.replaceUntrackedWebView(webView)

        let context = TabReloadPolicyWebViewRebuildContext(
            currentURL: tab.url,
            existingWebView: { tab.resolvedCurrentWebView() },
            webViewConfigurationOverride: nil,
            isPopupHost: false,
            profile: nil,
            replacementContext: TabWebViewReplacementContextOwner().makeContext(for: tab),
            publishNavigationStateChangeIfNeeded: { _ in /* No-op. */ }
        )

        XCTAssertIdentical(context.existingWebView(), webView)
    }

    func testPermissionVisibilityUsesResolvedPrimaryAssignment() {
        let tab = Tab(
            url: URL(string: "https://example.com/permission-visible")!,
            loadsCachedFaviconOnInit: false
        )
        let webView = WKWebView(frame: .zero)
        let windowId = UUID()

        XCTAssertNil(tab.resolvedAssignedWebView())
        XCTAssertNil(tab.resolvedPrimaryWindowId())

        tab.assignPrimaryWebView(webView, windowId: windowId)

        XCTAssertIdentical(tab.resolvedAssignedWebView(), webView)
        XCTAssertEqual(tab.resolvedPrimaryWindowId(), windowId)
        XCTAssertTrue(
            TabPermissionSurfaceOwner.Context.live(tab: tab).isVisibleTab()
        )
    }

    func testNormalWebViewRuntimeContextResolvesCurrentAndParked() {
        let tab = Tab(
            url: URL(string: "https://example.com/setup-context")!,
            loadsCachedFaviconOnInit: false
        )
        let current = WKWebView(frame: .zero)
        let parked = WKWebView(frame: .zero)
        tab.replaceUntrackedWebView(current)
        tab.parkExistingWebView(parked)

        let context = tab.normalWebViewRuntimeContext()
        XCTAssertIdentical(context.currentWebView(), current)
        XCTAssertIdentical(context.parkedWebView(), parked)
        XCTAssertTrue(context.hasCurrentWebView)
        XCTAssertTrue(context.hasParkedWebView)
    }

    func testTabDualWriteMutatorsRemainThinForwards() {
        let tab = Tab(
            url: URL(string: "https://example.com/dual-write")!,
            loadsCachedFaviconOnInit: false
        )
        let parked = WKWebView(frame: .zero)
        let untracked = WKWebView(frame: .zero)
        let primary = WKWebView(frame: .zero)
        let windowId = UUID()

        tab.parkExistingWebView(parked)
        XCTAssertIdentical(tab.webViewOwnershipOwner.localSession.parkedWebView, parked)

        tab.replaceUntrackedWebView(untracked)
        XCTAssertIdentical(tab.webViewOwnershipOwner.localSession.untrackedWebView, untracked)
        XCTAssertNil(tab.webViewOwnershipOwner.localSession.primaryWindowId)

        tab.assignPrimaryWebView(primary, windowId: windowId)
        XCTAssertEqual(tab.webViewOwnershipOwner.localSession.primaryWindowId, windowId)
        XCTAssertIdentical(tab.webViewOwnershipOwner.localSession.primaryWebView, primary)
        XCTAssertNil(tab.webViewOwnershipOwner.localSession.untrackedWebView)

        tab.clearCurrentWebViewOwnership()
        XCTAssertNil(tab.webViewOwnershipOwner.localSession.primaryWebView)
        XCTAssertNil(tab.webViewOwnershipOwner.localSession.primaryWindowId)
        XCTAssertIdentical(tab.webViewOwnershipOwner.localSession.parkedWebView, parked)

        tab.clearAllWebViewOwnership()
        XCTAssertNil(tab.webViewOwnershipOwner.localSession.parkedWebView)
    }
}
