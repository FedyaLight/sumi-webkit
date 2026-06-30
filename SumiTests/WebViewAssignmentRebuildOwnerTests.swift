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
        XCTAssertTrue(tab.assignedWebView === webView)
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

    private func makeTab() -> Tab {
        Tab(
            url: URL(string: "https://example.com")!,
            loadsCachedFaviconOnInit: false
        )
    }

    private func makeRuntime(
        primaryCandidate: @escaping WebViewAssignmentRebuildOwner.PrimaryCandidateResolver = { _ in nil }
    ) -> WebViewAssignmentRebuildOwner.Runtime {
        WebViewAssignmentRebuildOwner.Runtime(
            webViewRegistry: WindowWebViewRegistry(),
            initialDocumentWarmupRuntime: nil,
            registerTrackedWebView: { _, _, _ in },
            unregisterTrackedWebViewSlot: { _, _ in nil },
            removeFromContainers: { _ in },
            isWebViewProtectedFromCompositorMutation: { _ in false },
            deferProtectedRebuild: { _, _, _ in },
            primaryCandidate: primaryCandidate,
            liveWindowIDs: { nil },
            refreshCompositor: { _ in },
            notifyTabActivatedIfCurrent: { _, _ in }
        )
    }
}
