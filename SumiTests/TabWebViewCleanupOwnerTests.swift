import WebKit
import XCTest

@testable import Sumi
import SumiDomain
import SumiWebRuntime

@MainActor
final class TabWebViewCleanupOwnerTests: XCTestCase {
    func testCleanupDoesNotStartReplacementNavigation() {
        let webView = LoadRecordingWKWebView()
        let context = makeContext(tabId: UUID())

        TabWebViewCleanupOwner.cleanupWebView(webView, context: context)

        XCTAssertTrue(
            webView.loadedRequests.isEmpty,
            "Terminal WebView cleanup must destroy the current page instead of loading a replacement document"
        )
    }

    func testCleanupWebViewUsesScopedRuntimeInOrder() {
        let tabId = UUID()
        let webView = WKWebView(frame: .zero)
        var events: [Event] = []
        var handledEvent: SumiPermissionLifecycleEvent?
        var deferredWebView: WKWebView?
        var deferredTabId: UUID?
        var deferredReason: String?

        let context = makeContext(
            tabId: tabId,
            handlePermissionLifecycleEvent: { event in
                handledEvent = event
                events.append(.permissionEvent)
            },
            deferProtectedWebViewCleanup: { candidateWebView, candidateTabId, reason in
                deferredWebView = candidateWebView
                deferredTabId = candidateTabId
                deferredReason = reason
                events.append(.protectedCleanupCheck)
                return false
            },
            shutdownRuntime: SumiWebViewShutdown.NormalTabRuntime(
                removeWebViewFromContainers: { candidateWebView in
                    XCTAssertIdentical(candidateWebView, webView)
                    events.append(.removeFromContainers)
                }
            ),
            currentPermissionPageId: { "page-1" },
            profilePartitionId: { "profile-1" },
            webViewDidLeaveRuntime: { candidateWebView in
                XCTAssertIdentical(candidateWebView, webView)
                events.append(.leaveNavigationRuntime)
            }
        )

        TabWebViewCleanupOwner.cleanupWebView(webView, context: context)

        XCTAssertEqual(
            handledEvent,
            .webViewDeallocated(
                pageId: "page-1",
                tabId: tabId.uuidString.lowercased(),
                profilePartitionId: "profile-1",
                reason: "normal-tab-last-webview-cleanup"
            )
        )
        XCTAssertIdentical(deferredWebView, webView)
        XCTAssertEqual(deferredTabId, tabId)
        XCTAssertEqual(deferredReason, "Tab.cleanupCloneWebView")
        XCTAssertEqual(
            events,
            [
                .protectedCleanupCheck,
                .permissionEvent,
                .leaveNavigationRuntime,
                .removeFromContainers,
            ]
        )
    }

    func testCleanupWebViewDeferralSkipsShutdownAndTabLocalCleanup() {
        let tabId = UUID()
        let webView = WKWebView(frame: .zero)
        var events: [Event] = []

        let context = makeContext(
            tabId: tabId,
            handlePermissionLifecycleEvent: { _ in
                events.append(.permissionEvent)
            },
            deferProtectedWebViewCleanup: { _, _, _ in
                events.append(.protectedCleanupCheck)
                return true
            },
            shutdownRuntime: SumiWebViewShutdown.NormalTabRuntime(
                removeWebViewFromContainers: { _ in
                    XCTFail("Deferred cleanup must not remove containers")
                }
            ),
            webViewDidLeaveRuntime: { _ in
                XCTFail("Deferred cleanup must not leave navigation runtime")
            }
        )

        TabWebViewCleanupOwner.cleanupWebView(webView, context: context)

        XCTAssertEqual(events, [.protectedCleanupCheck])
    }

    func testComprehensiveCleanupMarksTeardownAsRetirement() {
        var receivedIntent: TabWebViewTeardownIntent?
        let context = makeContext(
            tabId: UUID(),
            removeAllWebViews: { intent in
                receivedIntent = intent
                return .none
            }
        )

        TabWebViewCleanupOwner.performComprehensiveCleanup(context: context)

        XCTAssertEqual(receivedIntent, .retirement)
    }

    func testComprehensiveCleanupReportsProtectedDetachedWebViewAsIncomplete() {
        let webView = WKWebView(frame: .zero)
        var didClearOwnership = false
        let context = makeContext(
            tabId: UUID(),
            deferProtectedWebViewCleanup: { candidate, _, _ in
                candidate === webView
            },
            remainingOwnedWebViews: { [webView] },
            clearDetachedWebViews: { didClearOwnership = true }
        )

        let completed = TabWebViewCleanupOwner.performComprehensiveCleanup(
            context: context
        )

        XCTAssertFalse(completed)
        XCTAssertFalse(didClearOwnership)
    }

    func testUnloadMarksTeardownAsSuspension() {
        var receivedIntent: TabWebViewTeardownIntent?
        let context = makeContext(
            tabId: UUID(),
            removeAllWebViews: { intent in
                receivedIntent = intent
                return .none
            }
        )

        TabWebViewCleanupOwner.unloadWebView(context: context)

        XCTAssertEqual(receivedIntent, .suspension)
    }

    func testTrackedCleanupSettlesLogicalOwnersBeforeResidenceRelease() {
        let repository = WebViewSessionRepository()
        let owner = TrackedWebViewOwner(tabID: UUID(), windowID: UUID())
        let webView = WKWebView()
        let tracking = WebViewTrackingLifecycleOwner()
        XCTAssertEqual(
            tracking.registerTrackedWebView(
                webView,
                for: owner,
                in: repository,
                removeFromContainers: { _ in },
                installRuntimeObservations: { _ in },
                uninstallRuntimeObservationsIfUntracked: { _ in },
                pruneInvalidDeferredCommands: { _ in },
                canDisplaceWebView: { _ in true },
                removeRecentVisibility: { _ in },
                cleanupDisplacedWebView: { _, _ in }
            ),
            .committed
        )
        var events: [String] = []
        let lifecycle = RetirementLifecycleSpy(
            onWillLeave: { departing in
                XCTAssertEqual(departing.count, 1)
                XCTAssertIdentical(departing.first, webView)
                XCTAssertEqual(repository.residence(of: webView), .window(owner))
                events.append("logical-departure")
            },
            onDestroy: { retired in
                XCTAssertIdentical(retired, webView)
                XCTAssertNil(repository.residence(of: webView))
                events.append("physical-destruction")
            }
        )

        XCTAssertTrue(WebViewTrackedCleanupExecutionOwner()
            .cleanupUnprotectedTrackedWebView(
                webView,
                owner: owner,
                tab: lifecycle,
                webViewSessions: repository,
                trackingLifecycleOwner: tracking,
                runtime: .init(
                    cancelProcessRecovery: { _ in
                        events.append("cancel-recovery")
                    },
                    finishDestructiveCleanupSuppression: { _ in
                        events.append("finish-cleanup-owner")
                    },
                    uninstallRuntimeObservationsIfUntracked: { _ in
                        events.append("detach-observations")
                    },
                    pruneInvalidDeferredCommands: { _ in },
                    fallbackCleanup: { _, _ in
                        XCTFail("Exact lifecycle must own destruction")
                    },
                    forgetRecentVisibility: { _ in }
                )
            ))

        XCTAssertEqual(
            events,
            [
                "cancel-recovery",
                "finish-cleanup-owner",
                "logical-departure",
                "detach-observations",
                "physical-destruction",
            ]
        )
    }

    func testRetirementLedgerIsIdempotentAndWeaklyOwned() {
        let ledger = TabWebViewRetirementLedger()
        weak var releasedWebView: WKWebView?
        autoreleasepool {
            let webView = WKWebView()
            releasedWebView = webView

            XCTAssertEqual(ledger.claimLogicalDeparture([webView]).count, 1)
            XCTAssertTrue(ledger.claimLogicalDeparture([webView]).isEmpty)
            XCTAssertTrue(ledger.claimPhysicalDestruction(webView))
            XCTAssertFalse(ledger.claimPhysicalDestruction(webView))
        }
        XCTAssertNil(releasedWebView)
    }

    private func makeContext(
        tabId: UUID,
        handlePermissionLifecycleEvent: @escaping TabWebViewCleanupOwner.PermissionLifecycleEventHandler = { _ in /* No-op. */ },
        deferProtectedWebViewCleanup: @escaping TabWebViewCleanupOwner.ProtectedWebViewCleanupDeferrer = { _, _, _ in false },
        shutdownRuntime: SumiWebViewShutdown.NormalTabRuntime = SumiWebViewShutdown.NormalTabRuntime(
            removeWebViewFromContainers: { _ in /* No-op. */ }
        ),
        currentPermissionPageId: @escaping () -> String = { "page" },
        profilePartitionId: @escaping () -> String? = { nil },
        webViewDidLeaveRuntime: @escaping (WKWebView) -> Void = { _ in /* No-op. */ },
        remainingOwnedWebViews: @escaping () -> [WKWebView] = { [] },
        clearDetachedWebViews: @escaping () -> Void = { /* No-op. */ },
        removeAllWebViews: @escaping (
            TabWebViewTeardownIntent
        ) -> WebViewTabTeardownResult = { _ in .none }
    ) -> TabWebViewCleanupOwner.Context {
        TabWebViewCleanupOwner.Context(
            tabId: tabId,
            tabName: { "Example" },
            handlePermissionLifecycleEvent: handlePermissionLifecycleEvent,
            deferProtectedWebViewCleanup: deferProtectedWebViewCleanup,
            shutdownRuntime: shutdownRuntime,
            notifyNowPlayingTabUnloaded: { _ in /* No-op. */ },
            remainingOwnedWebViews: remainingOwnedWebViews,
            clearDetachedWebViews: clearDetachedWebViews,
            removeAllWebViews: removeAllWebViews,
            currentPermissionPageId: currentPermissionPageId,
            profilePartitionId: profilePartitionId,
            invalidatePermissionPageForReplacement: { _ in /* No-op. */ },
            claimLogicalDeparture: { $0 },
            claimPhysicalDestruction: { _ in true },
            webViewDidLeaveRuntime: webViewDidLeaveRuntime,
            resetPlaybackActivity: { /* No-op. */ },
            setLoadingIdle: { /* No-op. */ }
        )
    }
}

@MainActor
private final class RetirementLifecycleSpy: WebRuntimeTabTeardownLifecycle {
    private let onWillLeave: ([WKWebView]) -> Void
    private let onDestroy: (WKWebView) -> Void

    init(
        onWillLeave: @escaping ([WKWebView]) -> Void,
        onDestroy: @escaping (WKWebView) -> Void
    ) {
        self.onWillLeave = onWillLeave
        self.onDestroy = onDestroy
    }

    func webViewsWillLeaveRuntime(_ webViews: [WKWebView]) {
        onWillLeave(webViews)
    }

    func destroyRetiredWebView(_ webView: WKWebView) {
        onDestroy(webView)
    }

    func cleanupCloneWebView(_ webView: WKWebView) {
        XCTFail("Sealed retirement must not use ambiguous cleanup")
    }

    func cancelPendingMainFrameNavigation() {}
}

private enum Event: Equatable {
    case permissionEvent
    case protectedCleanupCheck
    case leaveNavigationRuntime
    case removeFromContainers
}

private final class LoadRecordingWKWebView: WKWebView {
    private(set) var loadedRequests: [URLRequest] = []

    override func load(_ request: URLRequest) -> WKNavigation? {
        loadedRequests.append(request)
        return nil
    }
}
