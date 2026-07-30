import SumiDomain
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabWebViewProcessPrewarmingServiceTests: XCTestCase {
    func testExactHTTPWebViewStartsProcessAndBecomesReady() {
        let tab = makeTab(url: URL(string: "https://example.com")!)
        let webView = normalTabWebView()
        var launchedWebView: WKWebView?
        var completion: (@MainActor (Error?) -> Void)?
        let service = TabWebViewProcessPrewarmingService(
            candidate: { candidateTab in
                XCTAssertIdentical(candidateTab, tab)
                return webView
            },
            launchProcess: { candidate, processCompletion in
                launchedWebView = candidate
                completion = processCompletion
            }
        )

        service.prepare(tab)

        XCTAssertIdentical(launchedWebView, webView)
        XCTAssertEqual(
            TabWebViewProcessPrewarmingService.stateForTesting(webView),
            "inFlight"
        )

        completion?(nil)

        XCTAssertEqual(
            TabWebViewProcessPrewarmingService.stateForTesting(webView),
            "ready"
        )
    }

    func testNativeSurfaceDoesNotCreateCandidate() {
        let tab = makeTab(url: SumiSurface.emptyTabURL)
        var candidateCount = 0
        let service = TabWebViewProcessPrewarmingService(
            candidate: { _ in
                candidateCount += 1
                return WKWebView()
            },
            launchProcess: { _, _ in
                XCTFail("Native surface must not launch WebContent")
            }
        )

        service.prepare(tab)

        XCTAssertEqual(candidateCount, 0)
    }

    func testCheckoutClearsCandidateState() {
        let tab = makeTab(url: URL(string: "https://example.com")!)
        let webView = normalTabWebView()
        let service = TabWebViewProcessPrewarmingService(
            candidate: { _ in webView },
            launchProcess: { _, _ in }
        )
        service.prepare(tab)

        TabWebViewProcessPrewarmingService.checkOut(webView)

        XCTAssertNil(
            TabWebViewProcessPrewarmingService.stateForTesting(webView)
        )
    }

    func testUnclaimedCandidateExpiresAndIsReleased() async {
        let tab = makeTab(url: URL(string: "https://example.com")!)
        let webView = normalTabWebView()
        let released = expectation(description: "candidate released")
        let service = TabWebViewProcessPrewarmingService(
            candidate: { candidateTab in
                candidateTab.webViewSession.replaceUntracked(with: webView)
                return webView
            },
            launchProcess: { _, _ in },
            releaseCandidate: { releasedTab, releasedWebView in
                XCTAssertIdentical(releasedTab, tab)
                XCTAssertIdentical(releasedWebView, webView)
                released.fulfill()
            },
            expirationNanoseconds: 1
        )
        service.prepare(tab)

        await fulfillment(of: [released], timeout: 1)

        XCTAssertNil(
            TabWebViewProcessPrewarmingService.stateForTesting(webView)
        )
    }

    private func makeTab(url: URL) -> Tab {
        Tab(
            url: url,
            webViewSessions: WebViewSessionRepository()
        )
    }

    private func normalTabWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.sumiIsNormalTabWebViewConfiguration = true
        return WKWebView(frame: .zero, configuration: configuration)
    }
}
