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
        let tab = Tab(
            url: URL(string: "https://files.example/page")!,
            loadsCachedFaviconOnInit: false
        )
        tab.attachBrowserRuntime(browserManager.makeTabBrowserRuntime())
        let webView = WKWebView()

        let context = try XCTUnwrap(tab.filePickerPermissionTabContext(for: webView))

        XCTAssertEqual(context.tabId, tab.id.uuidString.lowercased())
        XCTAssertEqual(context.pageId, tab.currentPermissionPageId())
        XCTAssertEqual(context.profilePartitionId, browserManager.currentProfile?.id.uuidString.lowercased())
        XCTAssertEqual(context.visibleURL, tab.url)
        XCTAssertEqual(context.mainFrameURL, tab.url)
    }
}
