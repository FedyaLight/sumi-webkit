import WebKit
import XCTest

@testable import Sumi

@MainActor
final class WindowWebContentHostRegistryTests: XCTestCase {
    func testParkedHostIsResolvedByExactTabAndWebViewIdentity() {
        let registry = WindowWebContentHostRegistry()
        let tabID = UUID()
        let webView = WKWebView()
        let host = SumiWebViewContainerView(tabID: tabID, webView: webView)

        registry.parkHost(host)

        XCTAssertTrue(registry.parkedHost(for: tabID, webView: webView) === host)
        XCTAssertNil(registry.parkedHost(for: UUID(), webView: webView))
    }

    func testDisplayingParkedHostRemovesItsParkedResidence() {
        let registry = WindowWebContentHostRegistry()
        let tabID = UUID()
        let webView = WKWebView()
        let host = SumiWebViewContainerView(tabID: tabID, webView: webView)

        registry.parkHost(host)
        registry.setHost(host, for: .single)

        XCTAssertTrue(registry.host(for: .single) === host)
        XCTAssertNil(registry.parkedHost(for: tabID, webView: webView))
    }

    func testRuntimeEvictionClearsDisplayedAndParkedResidences() {
        let registry = WindowWebContentHostRegistry()
        let displayedWebView = WKWebView()
        let displayedHost = SumiWebViewContainerView(
            tabID: UUID(),
            webView: displayedWebView
        )
        let parkedWebView = WKWebView()
        let parkedTabID = UUID()
        let parkedHost = SumiWebViewContainerView(
            tabID: parkedTabID,
            webView: parkedWebView
        )

        registry.setHost(displayedHost, for: .single)
        registry.parkHost(parkedHost)
        displayedHost.evictFromRuntime()
        parkedHost.evictFromRuntime()

        XCTAssertNil(registry.host(for: .single))
        XCTAssertNil(
            registry.parkedHost(
                for: parkedTabID,
                webView: parkedWebView
            )
        )
    }

    func testRuntimeEvictionDoesNotExtendWebViewLifetime() {
        var retainedHost: SumiWebViewContainerView?
        weak var releasedWebView: WKWebView?

        autoreleasepool {
            let webView = WKWebView()
            let host = SumiWebViewContainerView(
                tabID: UUID(),
                webView: webView
            )
            retainedHost = host
            releasedWebView = webView

            host.evictFromRuntime()
        }

        XCTAssertNotNil(retainedHost)
        XCTAssertNil(
            releasedWebView,
            "A SwiftUI-cached presentation host must not own a retired WKWebView"
        )
    }

    func testPhysicalCleanupEvictsParkedHostOutsideCompositorTree() {
        let graph = makeTestWebViewRuntimeGraph()
        let windowID = UUID()
        let registration = graph.compositorRuntime.registerContainer(
            NSView(),
            for: windowID
        )
        defer {
            _ = graph.compositorRuntime.tearDownContainer(registration) {}
        }
        var retainedHost: SumiWebViewContainerView?
        weak var releasedWebView: WKWebView?

        autoreleasepool {
            let registry = WindowWebContentHostRegistry()
            let webView = WKWebView()
            let tabID = UUID()
            let host = SumiWebViewContainerView(
                tabID: tabID,
                webView: webView
            )
            retainedHost = host
            releasedWebView = webView
            registry.parkHost(host)

            graph.compositorRuntime.removeWebViewFromContainers(webView)

            XCTAssertNil(registry.parkedHost(for: tabID, webView: webView))
        }

        XCTAssertNotNil(retainedHost)
        XCTAssertNil(
            releasedWebView,
            "Physical cleanup must evict a host parked outside the AppKit tree"
        )
    }
}
