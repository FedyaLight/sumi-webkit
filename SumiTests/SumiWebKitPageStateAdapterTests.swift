import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiWebKitPageStateAdapterTests: XCTestCase {
    func testWebViewWithoutCommittedHistoryCannotProduceRestoreNavigation() throws {
        let data = try XCTUnwrap(
            SumiWebKitPageStateAdapter.sessionStateData(from: WKWebView())
        )
        XCTAssertNil(
            SumiWebKitPageStateAdapter.restoreSessionState(
                data,
                to: WKWebView()
            )
        )
    }

    func testNativeSessionStateProducesConcreteRestoreNavigation() async throws {
        let server = try await AutofillPagesHTTPServer.start(preferredPort: 0)
        defer { server.stop() }
        let source = WKWebView()
        let finished = expectation(description: "source document committed")
        let delegate = SessionStateNavigationDelegate {
            finished.fulfill()
        }
        source.navigationDelegate = delegate
        source.load(URLRequest(url: server.loginBasicURL))
        await fulfillment(of: [finished], timeout: 10)

        let data = try XCTUnwrap(
            SumiWebKitPageStateAdapter.sessionStateData(from: source)
        )
        XCTAssertFalse(data.isEmpty)

        let restored = WKWebView()
        let navigation = SumiWebKitPageStateAdapter.restoreSessionState(
            data,
            to: restored
        )

        XCTAssertNotNil(navigation)
        withExtendedLifetime(delegate) {}
    }

    func testInvalidNativeSessionStateReturnsNoNavigation() {
        XCTAssertNil(SumiWebKitPageStateAdapter.restoreSessionState(
            Data([0x00, 0x01, 0x02]),
            to: WKWebView()
        ))
    }
}

@MainActor
private final class SessionStateNavigationDelegate: NSObject, WKNavigationDelegate {
    private let didFinish: () -> Void

    init(didFinish: @escaping () -> Void) {
        self.didFinish = didFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinish()
    }
}
