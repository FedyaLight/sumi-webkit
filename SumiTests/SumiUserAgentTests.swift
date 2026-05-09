import WebKit
import XCTest
@testable import Sumi

@MainActor
final class SumiUserAgentTests: XCTestCase {
    func testSharedBrowserConfigurationLeavesApplicationNameForUserAgentNil() {
        XCTAssertNil(BrowserConfiguration.shared.webViewConfiguration.applicationNameForUserAgent)
    }

    func testApplyResetsCustomUserAgentOverride() {
        let webView = WKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        webView.customUserAgent = "SumiCustomUserAgent/1.0"

        SumiUserAgent.apply(to: webView)

        XCTAssertEqual(webView.customUserAgent, "")
    }
}
