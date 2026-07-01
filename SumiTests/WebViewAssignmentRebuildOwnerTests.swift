import WebKit
import XCTest

@testable import Sumi

@MainActor
final class WebViewAssignmentRebuildOwnerTests: XCTestCase {
    func testRefreshPrimaryTrackedWebViewUsesInjectedCandidate() {
        let owner = WebViewAssignmentRebuildOwner()
        let tab = makeTab()
        let windowId = UUID()
        let webView = WKWebView(frame: .zero)
        var requestedTabIds: [UUID] = []

        owner.refreshPrimaryTrackedWebView(
            for: tab,
            runtime: makeRuntime(
                primaryCandidate: { tabId in
                    requestedTabIds.append(tabId)
                    return (
                        TrackedWebViewOwner(tabID: tab.id, windowID: windowId),
                        webView
                    )
                }
            )
        )

        XCTAssertEqual(requestedTabIds, [tab.id])
        XCTAssertIdentical(tab.assignedWebView, webView)
        XCTAssertEqual(tab.primaryWindowId, windowId)
    }

    func testRefreshPrimaryTrackedWebViewClearsOwnershipWhenCandidateIsMissing() {
        let owner = WebViewAssignmentRebuildOwner()
        let tab = makeTab()
        let originalWindowId = UUID()
        tab.assignWebViewToWindow(WKWebView(frame: .zero), windowId: originalWindowId)

        owner.refreshPrimaryTrackedWebView(
            for: tab,
            runtime: makeRuntime(primaryCandidate: { _ in nil })
        )

        XCTAssertNil(tab.assignedWebView)
        XCTAssertNil(tab.primaryWindowId)
    }

    func testRebuildLiveWebViewsDoesNotUseStalePrimaryMirrorAsTargetWindow() {
        let owner = WebViewAssignmentRebuildOwner()
        let tab = makeTab()
        let staleWindowId = UUID()
        tab.assignWebViewToWindow(WKWebView(frame: .zero), windowId: staleWindowId)

        let rebuilt = owner.rebuildLiveWebViews(
            for: tab,
            runtime: makeRuntime()
        )

        XCTAssertFalse(rebuilt)
        XCTAssertEqual(tab.primaryWindowId, staleWindowId)
    }

    private func makeTab() -> Tab {
        Tab(
            url: URL(string: "https://example.com")!,
            loadsCachedFaviconOnInit: false
        )
    }

    private func makeRuntime(
        webViewRegistry: WindowWebViewRegistry = WindowWebViewRegistry(),
        primaryCandidate: @escaping WebViewAssignmentRebuildOwner.PrimaryCandidateResolver = { _ in nil }
    ) -> WebViewAssignmentRebuildOwner.Runtime {
        WebViewAssignmentRebuildOwner.Runtime(
            webViewRegistry: webViewRegistry,
            initialDocumentWarmupRuntime: nil,
            registerTrackedWebView: { _, _, _ in /* No-op. */ },
            unregisterTrackedWebViewSlot: { _, _ in nil },
            removeFromContainers: { _ in /* No-op. */ },
            isWebViewProtectedFromCompositorMutation: { _ in false },
            deferProtectedRebuild: { _, _, _ in /* No-op. */ },
            primaryCandidate: primaryCandidate,
            liveWindowSelection: { .allTrackedWindows },
            refreshCompositor: { _ in /* No-op. */ },
            notifyTabActivatedIfCurrent: { _, _ in /* No-op. */ }
        )
    }
}
