import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabWebKitPermissionUIDelegateOwnerTests: XCTestCase {
    func testLegacyMediaUIDelegateFailsClosedWithoutBrowserManager() {
        let tab = Tab(
            url: URL(string: "https://top.example/page")!,
            loadsCachedFaviconOnInit: false
        )
        let webView = WKWebView()
        var decisions: [Bool] = []

        tab.webKitUIDelegateOwner.webView(
            webView,
            requestUserMediaAuthorizationForDevices: SumiWebKitLegacyCaptureDevices.camera.rawValue,
            url: URL(string: "https://camera.example/request")!,
            mainFrameURL: URL(string: "https://top.example/page")!
        ) { decision in
            decisions.append(decision)
        }

        XCTAssertEqual(decisions, [false])
    }

    func testFilePickerPermissionContextFacadeRemainsAvailableForAuxiliaryDelegatePath() throws {
        let browserManager = BrowserManager()
        let tab = browserManager.tabManager.tabFactory.makeTab(
            url: URL(string: "https://files.example/page")!,
            loadsCachedFaviconOnInit: false
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        let webView = PermissionCommittedURLWebView()
        let navigation = bindCommittedDocument(on: webView, tab: tab)

        let context = try XCTUnwrap(tab.filePickerPermissionTabContext(for: webView))

        XCTAssertEqual(context.tabId, tab.id.uuidString.lowercased())
        XCTAssertEqual(context.pageId, tab.currentPermissionPageId())
        XCTAssertEqual(context.profilePartitionId, browserManager.currentProfile?.id.uuidString.lowercased())
        XCTAssertEqual(context.visibleURL, tab.url)
        XCTAssertEqual(context.mainFrameURL, tab.url)
        XCTAssertTrue(context.isCurrentPage())
        withExtendedLifetime(navigation) { /* Keep navigation identity alive. */ }
    }

    func testLegacyMediaUIDelegateRejectsCallbackWebViewWithoutExactDocumentLease() {
        let browserManager = BrowserManager()
        let tab = browserManager.tabManager.tabFactory.makeTab(
            url: URL(string: "https://top.example/page")!,
            loadsCachedFaviconOnInit: false
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        let authorityWebView = PermissionCommittedURLWebView()
        let navigation = bindCommittedDocument(on: authorityWebView, tab: tab)
        let unrelatedCallbackWebView = PermissionCommittedURLWebView()
        unrelatedCallbackWebView.reportedCommittedURL = tab.url
        var decisions: [Bool] = []

        tab.webKitUIDelegateOwner.webView(
            unrelatedCallbackWebView,
            requestUserMediaAuthorizationForDevices: SumiWebKitLegacyCaptureDevices.camera.rawValue,
            url: URL(string: "https://top.example/page")!,
            mainFrameURL: URL(string: "https://top.example/page")!
        ) { decision in
            decisions.append(decision)
        }

        XCTAssertEqual(decisions, [false])
        withExtendedLifetime(navigation) { /* Keep navigation identity alive. */ }
    }

    @discardableResult
    private func bindCommittedDocument(
        on webView: PermissionCommittedURLWebView,
        tab: Tab
    ) -> NSObject {
        let intent = tab.beginMainFrameNavigationIntent(to: tab.url)
        webView.reportedCommittedURL = tab.url
        XCTAssertTrue(tab.markDeferredMainFrameLoad(on: webView, intent: intent))
        XCTAssertEqual(
            tab.claimDeferredMainFrameLoad(
                on: webView,
                revision: intent.revision,
                targetURL: intent.targetURL
            ),
            .claimed
        )
        let navigation = NSObject()
        XCTAssertTrue(tab.bindSubmittedMainFrameLoad(
            on: webView,
            navigationID: ObjectIdentifier(navigation),
            navigationLifetime: navigation
        ))
        XCTAssertNotEqual(
            tab.recordMainFrameCommitSnapshot(
                from: webView,
                navigationID: ObjectIdentifier(navigation),
                committedURL: tab.url,
                isPDF: false
            ).role,
            .stale
        )
        return navigation
    }
}
