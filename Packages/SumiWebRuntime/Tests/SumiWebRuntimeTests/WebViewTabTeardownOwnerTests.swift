import WebKit
import XCTest

@testable import SumiWebRuntime

@MainActor
final class WebViewTabTeardownOwnerTests: XCTestCase {
    func testSuspensionVetoesWholeGenerationBeforeMutatingAnyResidence() {
        let repository = WebViewSessionRepository()
        let tab = TeardownTab(repository: repository)
        let firstWebView = WKWebView()
        let protectedWebView = WKWebView()
        tab.webViewSession.replaceUntracked(with: firstWebView)
        tab.webViewSession.park(protectedWebView)
        var removedContainerIDs: [ObjectIdentifier] = []
        let owner = WebViewTabTeardownOwner(
            webViewSessions: repository,
            isWebViewProtectedFromCompositorMutation: {
                $0 === protectedWebView
            },
            enqueueDeferredProtectedCommand: { _, _, _ in false },
            cleanupUnprotectedTrackedWebView: { _, _, _ in
                XCTFail("Suspension veto must precede tracked cleanup")
                return false
            },
            cleanupUnprotectedDetachedWebView: { _, _, _ in
                XCTFail("Suspension veto must precede detached cleanup")
            },
            refreshPrimaryTrackedWebView: { _ in },
            removeWebViewFromContainers: {
                removedContainerIDs.append(ObjectIdentifier($0))
            },
            unregisterTrackedWebViewSlot: { _, _ in
                XCTFail("Suspension veto must precede slot removal")
                return nil
            }
        )

        XCTAssertFalse(owner.suspendWebViews(for: tab, reason: "test-veto"))
        XCTAssertTrue(removedContainerIDs.isEmpty)
        XCTAssertTrue(tab.cleanedWebViewIDs.isEmpty)
        XCTAssertEqual(
            Set(repository.queries.allKnownWebViews(for: tab.id).map(ObjectIdentifier.init)),
            Set([ObjectIdentifier(firstWebView), ObjectIdentifier(protectedWebView)])
        )
        XCTAssertEqual(
            repository.residence(of: firstWebView),
            .untracked(tabID: tab.id)
        )
        XCTAssertEqual(repository.residence(of: protectedWebView), .parked(tabID: tab.id))
    }

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

    func testLogicalGenerationDeparturePrecedesEveryResidenceMutation() {
        let repository = WebViewSessionRepository()
        let tab = TeardownTab(repository: repository)
        let windowID = UUID()
        let trackedWebView = WKWebView()
        let detachedWebView = WKWebView()
        register(
            trackedWebView,
            tabID: tab.id,
            windowID: windowID,
            in: repository
        )
        tab.webViewSession.park(detachedWebView)
        var events: [String] = []
        tab.onWillLeave = { webViews in
            XCTAssertEqual(
                Set(webViews.map(ObjectIdentifier.init)),
                Set([
                    ObjectIdentifier(trackedWebView),
                    ObjectIdentifier(detachedWebView),
                ])
            )
            XCTAssertNotNil(repository.residence(of: trackedWebView))
            XCTAssertNotNil(repository.residence(of: detachedWebView))
            events.append("logical-departure")
        }
        let tracking = WebViewTrackingLifecycleOwner()
        let owner = makeOwner(
            repository: repository,
            cleanupTracked: { webView, trackedOwner, lifecycle in
                events.append("tracked-mutation")
                _ = tracking.unregisterTrackedWebViewSlot(
                    owner: trackedOwner,
                    expectedWebView: webView,
                    in: repository,
                    removeFromContainers: { _ in },
                    uninstallRuntimeObservationsIfUntracked: { _ in },
                    pruneInvalidDeferredCommands: { _ in },
                    forgetRecentVisibility: { _ in }
                )
                (lifecycle as? any WebRuntimeTabTeardownLifecycle)?
                    .destroyRetiredWebView(webView)
                return true
            },
            cleanupDetached: { webView, _, lifecycle in
                events.append("detached-mutation")
                (lifecycle as? any WebRuntimeTabTeardownLifecycle)?
                    .destroyRetiredWebView(webView)
            }
        )

        _ = owner.removeAllWebViews(for: tab)

        XCTAssertEqual(
            events,
            ["logical-departure", "tracked-mutation", "detached-mutation"]
        )
        XCTAssertEqual(
            tab.destroyedWebViewIDs,
            [ObjectIdentifier(trackedWebView), ObjectIdentifier(detachedWebView)]
        )
    }

    func testMixedProtectedAndUnprotectedTrackedTeardownDefersWholeGeneration() {
        let repository = WebViewSessionRepository()
        let tab = TeardownTab(repository: repository)
        let protectedWindowID = UUID()
        let unprotectedWindowID = UUID()
        let protectedWebView = WKWebView()
        let unprotectedWebView = WKWebView()
        register(protectedWebView, tabID: tab.id, windowID: protectedWindowID, in: repository)
        register(unprotectedWebView, tabID: tab.id, windowID: unprotectedWindowID, in: repository)
        var deferredCommands: [DeferredWebViewCommand] = []
        let owner = makeOwner(
            repository: repository,
            isProtected: { $0 === protectedWebView },
            enqueue: { command, _, _ in
                deferredCommands.append(command)
                return true
            },
            cleanupTracked: { webView, trackedOwner, _ in
                XCTFail(
                    "Protected generation must remain physically intact: \(webView) \(trackedOwner)"
                )
                return false
            }
        )

        let result = owner.removeAllWebViews(for: tab)

        XCTAssertEqual(result, .init(
            discoveredWebViewCount: 2,
            cleanedWebViewCount: 0,
            deferredWebViewCount: 2,
            unscheduledProtectedWebViewCount: 0
        ))
        XCTAssertTrue(tab.cleanedWebViewIDs.isEmpty)
        XCTAssertEqual(
            repository.residence(of: unprotectedWebView),
            .window(.init(tabID: tab.id, windowID: unprotectedWindowID))
        )
        XCTAssertEqual(
            repository.residence(of: protectedWebView),
            .window(.init(tabID: tab.id, windowID: protectedWindowID))
        )
        XCTAssertEqual(deferredCommands.count, 1)
        guard case .retireTabWebViewGeneration(
            let tabID,
            let expectedGeneration
        ) = deferredCommands[0] else {
            return XCTFail("Expected whole-generation retirement command")
        }
        XCTAssertEqual(tabID, tab.id)
        XCTAssertEqual(
            expectedGeneration,
            repository.queries.generation(for: tab.id)
        )
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
    private(set) var destroyedWebViewIDs: [ObjectIdentifier] = []
    private(set) var cancelledNavigation = false
    var onWillLeave: (([WKWebView]) -> Void)?

    init(repository: WebViewSessionRepository) {
        webViewSession = WebViewSessionHandle(tabID: id, repository: repository)
    }

    func cleanupCloneWebView(_ webView: WKWebView) {
        cleanedWebViewIDs.append(ObjectIdentifier(webView))
    }

    func webViewsWillLeaveRuntime(_ webViews: [WKWebView]) {
        onWillLeave?(webViews)
    }

    func destroyRetiredWebView(_ webView: WKWebView) {
        destroyedWebViewIDs.append(ObjectIdentifier(webView))
    }

    func cancelPendingMainFrameNavigation() {
        cancelledNavigation = true
    }
}
