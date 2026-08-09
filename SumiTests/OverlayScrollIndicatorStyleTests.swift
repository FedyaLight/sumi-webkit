import AppKit
import WebKit
import XCTest
@testable import Sumi

final class OverlayScrollIndicatorStyleTests: XCTestCase {
    func testSharedStyleUsesMidGrayThumbColor() {
        let color = OverlayScrollIndicatorStyle.thumbColor.usingColorSpace(.sRGB)
        XCTAssertNotNil(color)

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        XCTAssertEqual(red, 0.50, accuracy: 0.001)
        XCTAssertEqual(green, 0.50, accuracy: 0.001)
        XCTAssertEqual(blue, 0.50, accuracy: 0.001)
        XCTAssertEqual(alpha, 1.0, accuracy: 0.001)
        XCTAssertEqual(OverlayScrollIndicatorStyle.thumbOpacity, 0.40, accuracy: 0.001)
    }

    func testSidebarLayoutAliasesSharedStyleMetrics() {
        XCTAssertEqual(
            SidebarPassiveScrollIndicatorLayout.thumbWidth,
            OverlayScrollIndicatorStyle.thumbWidth,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SidebarPassiveScrollIndicatorLayout.expandedThumbWidth,
            OverlayScrollIndicatorStyle.expandedThumbWidth,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SidebarPassiveScrollIndicatorLayout.thumbOpacity,
            OverlayScrollIndicatorStyle.thumbOpacity,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SidebarPassiveScrollIndicatorLayout.visibleDuration,
            OverlayScrollIndicatorStyle.visibleDuration,
            accuracy: 0.001
        )
    }

    @MainActor
    func testPageScrollbarUsesEventDrivenAppKitOverlay() {
        let source = SumiPageScrollbarOverlayUserScript.makeSource()
        XCTAssertTrue(source.contains("::-webkit-scrollbar"))
        XCTAssertTrue(source.contains("html::-webkit-scrollbar"))
        XCTAssertTrue(source.contains("body::-webkit-scrollbar"))
        XCTAssertTrue(source.contains("scrollbar-width: none"))
        XCTAssertTrue(source.contains("display: none"))
        XCTAssertTrue(source.contains("requestAnimationFrame"))
        XCTAssertTrue(source.contains("ResizeObserver"))
        XCTAssertTrue(source.contains("messageHandlers"))
        XCTAssertTrue(source.contains("passive: true"))
        XCTAssertFalse(source.contains("window.scrollTo"))
        XCTAssertFalse(source.contains("createElement('div')"))
    }

    @MainActor
    func testPageScrollbarOverlayIsHostedAboveWebKitContent() throws {
        let webView = FocusableWKWebView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 240),
            configuration: WKWebViewConfiguration()
        )
        let host = SumiWebViewContainerView(tabID: UUID(), webView: webView)
        host.frame = webView.frame
        host.layoutSubtreeIfNeeded()

        let overlay = try XCTUnwrap(
            host.subviews.first {
                $0.identifier?.rawValue == "SumiPageScrollbarOverlay"
            }
        )
        XCTAssertTrue(overlay.superview === host)
        XCTAssertTrue(overlay !== webView)
        XCTAssertEqual(overlay.frame.maxX, host.bounds.maxX - 3, accuracy: 0.001)
        XCTAssertEqual(overlay.frame.height, host.bounds.height, accuracy: 0.001)
    }

    @MainActor
    func testLivePageMetricsRevealAppKitOverlay() async throws {
        let pageScript = SumiPageScrollbarOverlayUserScript()
        let userContentController = WKUserContentController()
        for messageName in pageScript.messageNames {
            userContentController.add(
                pageScript,
                contentWorld: pageScript.getContentWorld(),
                name: messageName
            )
        }
        userContentController.addUserScript(
            SumiPageScriptBuilder.makeWKUserScript(from: pageScript)
        )

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        let webView = FocusableWKWebView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 240),
            configuration: configuration
        )
        let host = SumiWebViewContainerView(tabID: UUID(), webView: webView)
        host.frame = webView.frame
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(NSSize(width: 320, height: 240))
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        webView.frame = host.bounds
        window.displayIfNeeded()
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
            for messageName in pageScript.messageNames {
                userContentController.removeScriptMessageHandler(
                    forName: messageName,
                    contentWorld: pageScript.getContentWorld()
                )
            }
        }

        let navigationFinished = expectation(description: "page navigation finished")
        let navigationDelegate = PageScrollbarNavigationDelegate(navigationFinished)
        webView.navigationDelegate = navigationDelegate
        webView.loadHTMLString(
            "<!doctype html><html><body style='margin:0;height:4000px'></body></html>",
            baseURL: nil
        )
        await fulfillment(of: [navigationFinished], timeout: 3)

        let overlay = try XCTUnwrap(
            host.subviews.first {
                $0.identifier?.rawValue == "SumiPageScrollbarOverlay"
            }
        )
        let isolatedState = try await webView.callAsyncJavaScript(
            """
            const handler = window.webkit?.messageHandlers?.sumiPageScrollbarOverlay;
            const viewportHeight = window.visualViewport?.height
                || window.innerHeight
                || document.documentElement.clientHeight;
            const contentHeight = document.documentElement.scrollHeight;
            handler?.postMessage({
                context: "sumiPageScrollbarOverlay",
                viewportHeight,
                contentHeight,
                contentOffset: 800,
                reveal: true
            });
            return {
                installed: window.__sumiPageScrollbarOverlayInstalled === true,
                handler: !!handler,
                viewportHeight,
                contentHeight
            };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .defaultClient
        )
        let state = try XCTUnwrap(isolatedState as? [String: Any])
        XCTAssertEqual(state["installed"] as? Bool, true, "\(state)")
        XCTAssertEqual(state["handler"] as? Bool, true, "\(state)")
        XCTAssertLessThan(
            (state["viewportHeight"] as? NSNumber)?.doubleValue ?? .infinity,
            1000,
            "\(state)"
        )
        XCTAssertGreaterThan((state["contentHeight"] as? NSNumber)?.doubleValue ?? 0, 3000, "\(state)")
        let deadline = Date(timeIntervalSinceNow: 1)
        while overlay.isHidden && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertFalse(overlay.isHidden)
        XCTAssertTrue(overlay.superview === host)
        XCTAssertTrue(webView.superview === host)
    }
}

@MainActor
private final class PageScrollbarNavigationDelegate: NSObject, WKNavigationDelegate {
    private let didFinish: XCTestExpectation

    init(_ didFinish: XCTestExpectation) {
        self.didFinish = didFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        _ = webView
        _ = navigation
        didFinish.fulfill()
    }
}
