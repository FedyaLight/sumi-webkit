import WebKit
import XCTest

@testable import SumiWebRuntime

@MainActor
final class WebViewTabTeardownOwnerTests: XCTestCase {
    func testParkedOnlyTeardownRunsLifecycleAndClearsResidence() {
        let repository = WebViewSessionRepository()
        let tab = TeardownTab(repository: repository)
        let parkedWebView = WKWebView()
        tab.webViewSession.park(parkedWebView)
        var cleanedDetached: [ObjectIdentifier] = []
        let owner = makeOwner(
            repository: repository,
            cleanupDetached: { webView, _, _ in
                cleanedDetached.append(ObjectIdentifier(webView))
                tab.cleanupCloneWebView(webView)
            }
        )

        let result = owner.removeAllWebViews(for: tab)

        XCTAssertEqual(result, .init(
            discoveredWebViewCount: 1,
            cleanedWebViewCount: 1,
            deferredWebViewCount: 0,
            unscheduledProtectedWebViewCount: 0
        ))
        XCTAssertEqual(cleanedDetached, [ObjectIdentifier(parkedWebView)])
        XCTAssertEqual(tab.cleanedWebViewIDs, [ObjectIdentifier(parkedWebView)])
        XCTAssertTrue(tab.cancelledNavigation)
        XCTAssertTrue(repository.queries.allKnownWebViews(for: tab.id).isEmpty)
        XCTAssertNil(repository.residence(of: parkedWebView))
    }

    func testMixedProtectedAndUnprotectedTrackedTeardownCleansAvailableSlotImmediately() {
        let repository = WebViewSessionRepository()
        let tab = TeardownTab(repository: repository)
        let protectedWindowID = UUID()
        let unprotectedWindowID = UUID()
        let protectedWebView = WKWebView()
        let unprotectedWebView = WKWebView()
        register(protectedWebView, tabID: tab.id, windowID: protectedWindowID, in: repository)
        register(unprotectedWebView, tabID: tab.id, windowID: unprotectedWindowID, in: repository)
        var deferredCommands: [DeferredWebViewCommand] = []
        let tracking = WebViewTrackingLifecycleOwner()
        let owner = makeOwner(
            repository: repository,
            isProtected: { $0 === protectedWebView },
            enqueue: { command, _, _ in
                deferredCommands.append(command)
                return true
            },
            cleanupTracked: { webView, trackedOwner, _ in
                guard tracking.unregisterTrackedWebViewSlot(
                    owner: trackedOwner,
                    expectedWebView: webView,
                    in: repository,
                    removeFromContainers: { _ in },
                    uninstallRuntimeObservationsIfUntracked: { _ in },
                    pruneInvalidDeferredCommands: { _ in },
                    forgetRecentVisibility: { _ in }
                ) != nil else { return false }
                tab.cleanupCloneWebView(webView)
                return true
            }
        )

        let result = owner.removeAllWebViews(for: tab)

        XCTAssertEqual(result, .init(
            discoveredWebViewCount: 2,
            cleanedWebViewCount: 1,
            deferredWebViewCount: 1,
            unscheduledProtectedWebViewCount: 0
        ))
        XCTAssertEqual(tab.cleanedWebViewIDs, [ObjectIdentifier(unprotectedWebView)])
        XCTAssertNil(repository.residence(of: unprotectedWebView))
        XCTAssertEqual(
            repository.residence(of: protectedWebView),
            .window(.init(tabID: tab.id, windowID: protectedWindowID))
        )
        XCTAssertEqual(deferredCommands.count, 1)
        guard case .removeTrackedWebView(let webViewID, let tabID, let windowID) = deferredCommands[0] else {
            return XCTFail("Expected protected tracked cleanup command")
        }
        XCTAssertEqual(webViewID, ObjectIdentifier(protectedWebView))
        XCTAssertEqual(tabID, tab.id)
        XCTAssertEqual(windowID, protectedWindowID)
    }

    func testBlockedTrackedCleanupIsReportedAndResidenceStaysCanonical() {
        let repository = WebViewSessionRepository()
        let tab = TeardownTab(repository: repository)
        let windowID = UUID()
        let webView = WKWebView()
        register(webView, tabID: tab.id, windowID: windowID, in: repository)
        let owner = makeOwner(
            repository: repository,
            cleanupTracked: { _, _, _ in false }
        )

        let result = owner.removeAllWebViews(for: tab)

        XCTAssertEqual(result, .init(
            discoveredWebViewCount: 1,
            cleanedWebViewCount: 0,
            deferredWebViewCount: 0,
            unscheduledProtectedWebViewCount: 0,
            blockedWebViewCount: 1
        ))
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(
            repository.residence(of: webView),
            .window(.init(tabID: tab.id, windowID: windowID))
        )
        XCTAssertTrue(tab.cleanedWebViewIDs.isEmpty)
    }

    private func makeOwner(
        repository: WebViewSessionRepository,
        isProtected: @escaping (WKWebView) -> Bool = { _ in false },
        enqueue: @escaping (DeferredWebViewCommand, WKWebView, String) -> Bool = { _, _, _ in false },
        cleanupTracked: @escaping (
            WKWebView,
            TrackedWebViewOwner,
            (any WebRuntimeTabHandle)?
        ) -> Bool = { _, _, _ in true },
        cleanupDetached: @escaping (
            WKWebView,
            UUID,
            (any WebRuntimeTabHandle)?
        ) -> Void = { _, _, _ in }
    ) -> WebViewTabTeardownOwner {
        WebViewTabTeardownOwner(
            webViewSessions: repository,
            isWebViewProtectedFromCompositorMutation: isProtected,
            enqueueDeferredProtectedCommand: enqueue,
            cleanupUnprotectedTrackedWebView: cleanupTracked,
            cleanupUnprotectedDetachedWebView: cleanupDetached,
            refreshPrimaryTrackedWebView: { _ in },
            removeWebViewFromContainers: { _ in },
            unregisterTrackedWebViewSlot: { _, _ in nil }
        )
    }

    private func register(
        _ webView: WKWebView,
        tabID: UUID,
        windowID: UUID,
        in repository: WebViewSessionRepository
    ) {
        WebViewTrackingLifecycleOwner().registerTrackedWebView(
            webView,
            for: .init(tabID: tabID, windowID: windowID),
            in: repository,
            removeFromContainers: { _ in },
            installRuntimeObservations: { _ in },
            uninstallRuntimeObservationsIfUntracked: { _ in },
            pruneInvalidDeferredCommands: { _ in },
            canDisplaceWebView: { _ in true },
            removeRecentVisibility: { _ in },
            cleanupDisplacedWebView: { _, _ in }
        )
    }
}

@MainActor
private final class TeardownTab: WebRuntimeTabHandle, WebRuntimeTabTeardownLifecycle {
    let id = UUID()
    let webViewSession: WebViewSessionHandle
    let requiresPrimaryWebView = true
    var url = URL(string: "https://example.com")!
    let isEphemeral = false
    let resolvedProfileId: UUID? = nil
    private(set) var cleanedWebViewIDs: [ObjectIdentifier] = []
    private(set) var cancelledNavigation = false

    init(repository: WebViewSessionRepository) {
        webViewSession = WebViewSessionHandle(tabID: id, repository: repository)
    }

    func cleanupCloneWebView(_ webView: WKWebView) {
        cleanedWebViewIDs.append(ObjectIdentifier(webView))
    }

    func cancelPendingMainFrameNavigation() {
        cancelledNavigation = true
    }
}
