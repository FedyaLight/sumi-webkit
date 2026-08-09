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
            policy: .standard,
            fallback: .safeOrdinaryNavigation
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
            policy: .fromOrigin,
            fallback: .safeOrdinaryNavigation
        )

        XCTAssertEqual(webView.standardReloadCount, 0)
        XCTAssertEqual(webView.fromOriginReloadCount, 1)
        XCTAssertEqual(webView.requests.map(\.url), [targetURL])
        XCTAssertEqual(
            webView.requests.map(\.cachePolicy),
            [.reloadIgnoringLocalAndRemoteCacheData]
        )
    }

    func testNilNativeReloadDoesNotConstructOrdinaryNavigationWithoutAdmission() throws {
        let webView = MainFrameLoaderRecordingWebView()
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/post-result"))

        let result = WebRuntimeMainFrameReloader.reloadOrLoad(
            targetURL,
            on: webView,
            policy: .standard,
            fallback: .disallowed
        )

        guard case .failed = result else {
            return XCTFail("Nil native reload must remain a typed failure")
        }
        XCTAssertEqual(webView.standardReloadCount, 1)
        XCTAssertTrue(webView.requests.isEmpty)
    }

    func testConcreteNativeReloadMatrixNeverConstructsURLFallback() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/current-item"))
        for policy in [
            WebRuntimeMainFrameReloadPolicy.standard,
            .fromOrigin,
        ] {
            let webView = MainFrameLoaderRecordingWebView(
                returnsConcreteReload: true
            )
            let result = WebRuntimeMainFrameReloader.reloadOrLoad(
                targetURL,
                on: webView,
                policy: policy,
                fallback: .safeOrdinaryNavigation
            )

            guard case .reloaded = result else {
                XCTFail("Expected a concrete native reload for \(policy)")
                continue
            }
            XCTAssertTrue(webView.requests.isEmpty)
            XCTAssertEqual(
                webView.standardReloadCount,
                policy == .standard ? 1 : 0
            )
            XCTAssertEqual(
                webView.fromOriginReloadCount,
                policy == .fromOrigin ? 1 : 0
            )
        }
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
    private let returnsConcreteReload: Bool

    init(returnsConcreteReload: Bool = false) {
        self.returnsConcreteReload = returnsConcreteReload
        super.init(frame: .zero, configuration: WKWebViewConfiguration())
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func reload() -> WKNavigation? {
        standardReloadCount += 1
        return returnsConcreteReload
            ? super.loadHTMLString("", baseURL: nil)
            : nil
    }

    override func reloadFromOrigin() -> WKNavigation? {
        fromOriginReloadCount += 1
        return returnsConcreteReload
            ? super.loadHTMLString("", baseURL: nil)
            : nil
    }

    override func load(_ request: URLRequest) -> WKNavigation? {
        requests.append(request)
        return super.loadHTMLString("", baseURL: request.url)
    }

    override func loadFileURL(
        _ fileURL: URL,
        allowingReadAccessTo readAccessURL: URL
    ) -> WKNavigation? {
        fileURLs.append((fileURL, readAccessURL))
        return nil
    }
}
