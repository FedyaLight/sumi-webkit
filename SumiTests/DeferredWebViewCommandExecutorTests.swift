import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class DeferredWebViewCommandExecutorTests: XCTestCase {
    func testMaintenanceFailureIsRetryableAndSuccessIsExecuted() {
        let effects = ExecutorEffects()
        let executor = makeExecutor(effects: effects)
        let webView = WKWebView()
        let command = DeferredWebViewCommandAuthority.PreparedCommand
            .removeWebViewFromContainers(webView: webView)

        effects.maintenanceSucceeds = false
        XCTAssertEqual(executor.execute(command), .retry)
        effects.maintenanceSucceeds = true
        XCTAssertEqual(executor.execute(command), .executed)
        XCTAssertEqual(effects.removedWebViews.count, 2)
        XCTAssertTrue(effects.removedWebViews.allSatisfy { $0 === webView })
    }

    func testConfigurationRoutePreservesPreparedTabWindowAndIntent() {
        let effects = ExecutorEffects()
        let executor = makeExecutor(effects: effects)
        let tab = Tab(url: URL(string: "about:blank")!)
        let windowID = UUID()
        let intent = DeferredWebViewRebuildIntent(
            revision: 7,
            targetURL: URL(string: "https://example.com/rebuild")!,
            configuration: .normal,
            kind: .semanticNavigation
        )

        XCTAssertEqual(executor.execute(.rebuildLiveWebViews(
            tab: tab,
            preferredPrimaryWindowID: windowID,
            intent: intent
        )), .executed)

        XCTAssertIdentical(effects.rebuiltTab, tab)
        XCTAssertEqual(effects.rebuildWindowID, windowID)
        XCTAssertEqual(effects.rebuildIntent, intent)
    }

    func testStalePreparedNavigationIsRejectedBeforeWebKitSubmission() {
        let effects = ExecutorEffects()
        let executor = makeExecutor(effects: effects)
        let initialURL = URL(string: "https://example.com/initial")!
        let targetURL = URL(string: "https://example.com/target")!
        let tab = Tab(url: initialURL)
        let webView = WKWebView()
        let intent = tab.beginMainFrameNavigationIntent(to: targetURL)
        _ = tab.beginMainFrameNavigationIntent(
            to: URL(string: "https://example.com/newer")!
        )

        XCTAssertEqual(executor.execute(.synchronizeTrackedNavigation(
            webView: webView,
            tab: tab,
            owner: TrackedWebViewOwner(tabID: tab.id, windowID: UUID()),
            intent: DeferredWebViewNavigationIntent(
                revision: intent.revision,
                targetURL: targetURL
            )
        )), .invalidTarget)
        XCTAssertTrue(effects.removedWebViews.isEmpty)
    }

    func testFallbackCleanupConsumesExactLeaseBeforeOwnerlessShutdown() throws {
        let sessions = WebViewSessionRepository()
        let effects = ExecutorEffects()
        let webView = WKWebView()
        let tabID = UUID()
        let lease = try XCTUnwrap(sessions.beginPendingCleanup(
            of: webView,
            for: tabID
        ))
        var shutdownWebView: WKWebView?
        var shutdownTabID: UUID?
        let executor = makeExecutor(
            effects: effects,
            sessions: sessions,
            shutdownOwnerlessWebView: { webView, tabID in
                shutdownWebView = webView
                shutdownTabID = tabID
            }
        )

        XCTAssertEqual(executor.execute(.performFallbackWebViewCleanup(
            webView: webView,
            lease: lease,
            tab: nil
        )), .executed)
        XCTAssertNil(sessions.residence(of: webView))
        XCTAssertIdentical(shutdownWebView, webView)
        XCTAssertEqual(shutdownTabID, tabID)
    }

    private func makeExecutor(
        effects: ExecutorEffects,
        sessions: WebViewSessionRepository = WebViewSessionRepository(),
        shutdownOwnerlessWebView: @escaping @MainActor (WKWebView, UUID) -> Void = {
            _, _ in
        }
    ) -> DeferredWebViewCommandExecutor {
        return DeferredWebViewCommandExecutor(
            cleanup: DeferredWebViewCleanupExecutor(
                sessions: sessions,
                closeWebView: { _ in false },
                removeFromContainers: { [effects] webView in
                    effects.removedWebViews.append(webView)
                    return effects.maintenanceSucceeds
                },
                cleanupTrackedWebView: { _, _ in false },
                shutdownOwnerlessWebView: shutdownOwnerlessWebView
            ),
            windowMaintenance: DeferredWebViewWindowMaintenanceExecutor(
                cleanupWindow: { _ in false },
                cleanupAllWebViews: { false },
                evictHiddenWebViews: { _, _ in false },
                visibleTabIDs: { _ in [] }
            ),
            configuration: DeferredWebViewConfigurationExecutor(
                rebuild: { [effects] tab, windowID, intent in
                    effects.rebuiltTab = tab
                    effects.rebuildWindowID = windowID
                    effects.rebuildIntent = intent
                    return .committed
                },
                assignProfile: { _, _, _ in false },
                assignSpaceProfile: { _ in false }
            )
        )
    }
}

@MainActor
private final class ExecutorEffects {
    var maintenanceSucceeds = false
    var removedWebViews: [WKWebView] = []
    var rebuiltTab: Tab?
    var rebuildWindowID: UUID?
    var rebuildIntent: DeferredWebViewRebuildIntent?
}
