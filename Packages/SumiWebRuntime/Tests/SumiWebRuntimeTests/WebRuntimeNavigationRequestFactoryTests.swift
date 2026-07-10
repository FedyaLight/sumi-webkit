import Foundation
import WebKit
import XCTest
@testable import SumiWebRuntime

@MainActor
final class WebRuntimeNavigationRequestFactoryTests: XCTestCase {
    func testMainFrameLoaderUsesScopedFileLoading() {
        let webView = MainFrameLoaderRecordingWebView()
        let url = URL(fileURLWithPath: "/tmp/sumi-loader/index.html")

        WebRuntimeMainFrameLoader.load(url, on: webView)

        XCTAssertTrue(webView.requests.isEmpty)
        XCTAssertEqual(webView.fileURLs.map(\.url), [url])
        XCTAssertEqual(
            webView.fileURLs.map(\.readAccessURL),
            [url.deletingLastPathComponent()]
        )
    }

    func testMainFrameLoaderUsesCanonicalRequestPolicyForWebURL() throws {
        let webView = MainFrameLoaderRecordingWebView()
        let url = try XCTUnwrap(URL(string: "https://example.com/article"))

        WebRuntimeMainFrameLoader.load(url, on: webView)

        XCTAssertTrue(webView.fileURLs.isEmpty)
        XCTAssertEqual(webView.requests.map(\.url), [url])
        XCTAssertEqual(webView.requests.map(\.cachePolicy), [.useProtocolCachePolicy])
        XCTAssertEqual(
            webView.requests.map(\.timeoutInterval),
            [URLRequest(url: url).timeoutInterval]
        )
    }

    func testStandardReloadMaterializesExactTargetWhenWebKitHasNoDocument() throws {
        let webView = MainFrameLoaderRecordingWebView()
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/empty-clone"))

        WebRuntimeMainFrameReloader.reloadOrLoad(
            targetURL,
            on: webView,
            policy: .standard
        )

        XCTAssertEqual(webView.standardReloadCount, 1)
        XCTAssertEqual(webView.fromOriginReloadCount, 0)
        XCTAssertEqual(webView.requests.map(\.url), [targetURL])
        XCTAssertEqual(
            webView.requests.map(\.cachePolicy),
            [.useProtocolCachePolicy]
        )
    }

    func testFromOriginReloadMaterializesExactTargetWithBypassPolicyWhenEmpty() throws {
        let webView = MainFrameLoaderRecordingWebView()
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/empty-clone"))

        WebRuntimeMainFrameReloader.reloadOrLoad(
            targetURL,
            on: webView,
            policy: .fromOrigin
        )

        XCTAssertEqual(webView.standardReloadCount, 0)
        XCTAssertEqual(webView.fromOriginReloadCount, 1)
        XCTAssertEqual(webView.requests.map(\.url), [targetURL])
        XCTAssertEqual(
            webView.requests.map(\.cachePolicy),
            [.reloadIgnoringLocalAndRemoteCacheData]
        )
    }

    func testHTTPNavigationPreservesStandardURLLoadingPolicy() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/article"))

        let request = WebRuntimeNavigationRequestFactory.navigationRequest(for: url)
        let standardRequest = URLRequest(url: url)

        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.cachePolicy, standardRequest.cachePolicy)
        XCTAssertEqual(request.timeoutInterval, standardRequest.timeoutInterval)
    }

    func testWebKitExtensionNavigationBypassesCachedPage() throws {
        let url = try XCTUnwrap(URL(string: "webkit-extension://example/page.html"))

        let request = WebRuntimeNavigationRequestFactory.navigationRequest(for: url)

        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testSafariExtensionNavigationBypassesCachedPageCaseInsensitively() throws {
        let url = try XCTUnwrap(URL(string: "SAFARI-WEB-EXTENSION://example/page.html"))

        let request = WebRuntimeNavigationRequestFactory.navigationRequest(for: url)

        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testNavigationIdentityNormalizesHTTPSpellingWithoutMergingDifferentResources() throws {
        let bareHost = try XCTUnwrap(URL(string: "https://EXAMPLE.com"))
        let explicitRoot = try XCTUnwrap(URL(string: "https://example.com:443/"))
        let escapedUnreserved = try XCTUnwrap(URL(string: "https://example.com/%7euser"))
        let literalUnreserved = try XCTUnwrap(URL(string: "https://example.com/~user"))
        let differentQuery = try XCTUnwrap(URL(string: "https://example.com/?page=2"))

        XCTAssertTrue(WebRuntimeNavigationIdentity.matches(bareHost, explicitRoot))
        XCTAssertTrue(WebRuntimeNavigationIdentity.matches(escapedUnreserved, literalUnreserved))
        XCTAssertFalse(WebRuntimeNavigationIdentity.matches(explicitRoot, differentQuery))
    }
}

@MainActor
private final class MainFrameLoaderRecordingWebView: WKWebView {
    private(set) var requests: [URLRequest] = []
    private(set) var fileURLs: [(url: URL, readAccessURL: URL)] = []
    private(set) var standardReloadCount = 0
    private(set) var fromOriginReloadCount = 0

    override func reload() -> WKNavigation? {
        standardReloadCount += 1
        return nil
    }

    override func reloadFromOrigin() -> WKNavigation? {
        fromOriginReloadCount += 1
        return nil
    }

    override func load(_ request: URLRequest) -> WKNavigation? {
        requests.append(request)
        return nil
    }

    override func loadFileURL(
        _ fileURL: URL,
        allowingReadAccessTo readAccessURL: URL
    ) -> WKNavigation? {
        fileURLs.append((fileURL, readAccessURL))
        return nil
    }
}
