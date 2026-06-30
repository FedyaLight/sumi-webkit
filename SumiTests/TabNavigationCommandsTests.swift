import Combine
import Foundation
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabNavigationCommandsTests: XCTestCase {
    func testResolverBasedLoadURLRecordsTargetWhenWebViewIsDeferred() throws {
        let originalURL = try XCTUnwrap(URL(string: "https://example.com/start"))
        let targetURL = try XCTUnwrap(URL(string: "https://target.example/path"))
        let tab = Tab(url: originalURL, loadsCachedFaviconOnInit: false)
        var resolverCallCount = 0

        tab.navigationCommandOwner.loadURL(
            targetURL,
            for: tab,
            resolvedWebView: {
                resolverCallCount += 1
                return nil
            },
            reason: "TabNavigationCommandsTests.deferredResolver"
        )

        XCTAssertEqual(resolverCallCount, 1)
        XCTAssertEqual(tab.url, targetURL)
        XCTAssertNil(tab.existingWebView)
    }

    func testNavigationCommandURLRequestUsesReturnCacheDataElseLoadForRegularURL() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/path"))

        let request = Tab.navigationCommandURLRequest(for: url)

        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.cachePolicy, .returnCacheDataElseLoad)
        XCTAssertEqual(request.timeoutInterval, 30.0)
    }

    func testNavigationCommandURLRequestBypassesLocalCacheForExtensionSchemes() throws {
        let urls = [
            try XCTUnwrap(URL(string: "webkit-extension://extension-id/options.html")),
            try XCTUnwrap(URL(string: "safari-web-extension://extension-id/options.html")),
            try XCTUnwrap(URL(string: "WebKit-Extension://extension-id/options.html")),
        ]

        for url in urls {
            let request = Tab.navigationCommandURLRequest(for: url)

            XCTAssertEqual(request.url, url)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(request.timeoutInterval, 30.0)
        }
    }

    func testContentBlockingAssetWaitDelaysMainFrameLoad() async throws {
        let controller = DelayedNavigationUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/start")),
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tab._webView = webView
        var didLoad = false

        tab.performMainFrameNavigationAfterContentBlockingAssetsIfNeeded(
            on: webView,
            waitForContentBlockingAssets: true
        ) { resolvedWebView in
            XCTAssertIdentical(resolvedWebView, webView)
            didLoad = true
        }

        for _ in 0..<20 where controller.waitCallCount == 0 {
            await Task.yield()
        }

        XCTAssertEqual(controller.waitCallCount, 1)
        XCTAssertFalse(didLoad)

        controller.finishInitialUserContentInstallation()

        for _ in 0..<20 where !didLoad {
            await Task.yield()
        }

        XCTAssertTrue(didLoad)
    }

    func testContentBlockingAssetWaitBypassesPreparationWhenNotRequested() throws {
        let controller = DelayedNavigationUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/start")),
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tab._webView = webView
        var didLoad = false

        tab.performMainFrameNavigationAfterContentBlockingAssetsIfNeeded(
            on: webView,
            waitForContentBlockingAssets: false
        ) { resolvedWebView in
            XCTAssertIdentical(resolvedWebView, webView)
            didLoad = true
        }

        XCTAssertEqual(controller.waitCallCount, 0)
        XCTAssertTrue(didLoad)
    }
}

@MainActor
private final class DelayedNavigationUserContentController:
    WKUserContentController,
    SumiNormalTabUserContentControlling {
    var normalTabUserScriptsProvider: SumiNormalTabUserScripts?
    var contentBlockingAssetSummary = SumiNormalTabContentBlockingAssetSummary(
        isInstalled: false,
        globalRuleListCount: 0,
        updateRuleCount: 0,
        isContentBlockingFeatureEnabled: false
    )
    var hasInstalledInitialUserContent = false
    private(set) var waitCallCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    var wkUserContentController: WKUserContentController {
        self
    }

    #if DEBUG
        var contentBlockingAssetSummaryPublisher: AnyPublisher<SumiNormalTabContentBlockingAssetSummary, Never> {
            Just(contentBlockingAssetSummary).eraseToAnyPublisher()
        }
    #endif

    func replaceNormalTabUserScripts(with provider: SumiNormalTabUserScripts) async {
        normalTabUserScriptsProvider = provider
    }

    func waitForContentBlockingAssetsInstalled() async {
        waitCallCount += 1
        guard hasInstalledInitialUserContent == false else { return }

        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finishInitialUserContentInstallation() {
        hasInstalledInitialUserContent = true
        continuation?.resume()
        continuation = nil
    }

    func cleanUpBeforeClosing() {}
}
