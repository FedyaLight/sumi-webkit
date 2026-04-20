import WebKit
import XCTest
@testable import Sumi

@MainActor
final class SumiUserAgentTests: XCTestCase {
    func testSharedBrowserConfigurationUsesDuckDuckGoApplicationNameToken() {
        XCTAssertEqual(
            BrowserConfiguration.shared.webViewConfiguration.applicationNameForUserAgent,
            SumiUserAgent.duckDuckGoApplicationNameForUserAgent
        )
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
