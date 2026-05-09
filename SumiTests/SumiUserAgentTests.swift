import WebKit
import XCTest
@testable import Sumi

@MainActor
final class SumiUserAgentTests: XCTestCase {
    func testSharedBrowserConfigurationUsesSafariCompatibleApplicationNameForUserAgent() {
        XCTAssertEqual(
            BrowserConfiguration.shared.webViewConfiguration.applicationNameForUserAgent,
            "Version/26.0 Safari/605.1.15"
        )
    }

    func testSharedBrowserConfigurationDoesNotSetCustomUserAgentOverride() {
        let webView = WKWebView(
            frame: .zero,
            configuration: BrowserConfiguration.shared.webViewConfiguration
        )

        XCTAssertTrue(webView.customUserAgent?.isEmpty ?? true)
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
