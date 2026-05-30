import WebKit
import XCTest
@testable import Sumi

@MainActor
final class SumiUserAgentTests: XCTestCase {
    func testSharedBrowserConfigurationUsesSafariCompatibleApplicationNameForUserAgent() {
        let appName = BrowserConfiguration.shared.webViewConfiguration.applicationNameForUserAgent
        XCTAssertNotNil(appName)
        XCTAssertTrue(appName?.hasPrefix("Version/") ?? false)
        XCTAssertTrue(appName?.contains(" Safari/") ?? false)
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
