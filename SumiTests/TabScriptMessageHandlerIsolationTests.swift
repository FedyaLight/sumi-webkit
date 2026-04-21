import WebKit
import XCTest
@testable import Sumi

@MainActor
final class TabScriptMessageHandlerIsolationTests: XCTestCase {
    func testTabScopedHandlersRemainIsolatedOnSharedUserContentController() async throws {
        let userContentController = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController

        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )

        let firstTab = Tab(name: "First")
        let secondTab = Tab(name: "Second")

        firstTab.replaceCoreScriptMessageHandlers(on: userContentController)
        secondTab.replaceCoreScriptMessageHandlers(on: userContentController)

        try await loadBlankDocument(into: webView)

        let firstDelivered = expectation(description: "first tab message delivered")
        let secondDelivered = expectation(description: "second tab message delivered")
        firstTab.onLinkHover = { href in
            if href == "https://first.example/" {
                firstDelivered.fulfill()
            }
        }
        secondTab.onLinkHover = { href in
            if href == "https://second.example/" {
                secondDelivered.fulfill()
            }
        }

        try await evaluate(
            """
            const firstHandler = window.webkit?.messageHandlers?.["\(Tab.coreScriptMessageHandlerName("linkHover", for: firstTab.id))"];
            if (firstHandler) {
                firstHandler.postMessage("https://first.example/");
            }
            const secondHandler = window.webkit?.messageHandlers?.["\(Tab.coreScriptMessageHandlerName("linkHover", for: secondTab.id))"];
            if (secondHandler) {
                secondHandler.postMessage("https://second.example/");
            }
            """,
            in: webView
        )

        await fulfillment(of: [firstDelivered, secondDelivered], timeout: 5.0)

        for handlerName in Tab.coreScriptMessageHandlerNames(for: firstTab.id) {
            userContentController.removeScriptMessageHandler(forName: handlerName)
        }

        let removedHandlerDidNotFire = expectation(
            description: "removed handler stays detached"
        )
        removedHandlerDidNotFire.isInverted = true
        let survivingHandlerStillFires = expectation(
            description: "second tab handler still works"
        )

        firstTab.onLinkHover = { _ in
            removedHandlerDidNotFire.fulfill()
        }
        secondTab.onLinkHover = { href in
            if href == "https://second-after-cleanup.example/" {
                survivingHandlerStillFires.fulfill()
            }
        }

        try await evaluate(
            """
            const removedHandler = window.webkit?.messageHandlers?.["\(Tab.coreScriptMessageHandlerName("linkHover", for: firstTab.id))"];
            if (removedHandler) {
                removedHandler.postMessage("https://first-after-cleanup.example/");
            }
            const survivingHandler = window.webkit?.messageHandlers?.["\(Tab.coreScriptMessageHandlerName("linkHover", for: secondTab.id))"];
            if (survivingHandler) {
                survivingHandler.postMessage("https://second-after-cleanup.example/");
            }
            """,
            in: webView
        )

        await fulfillment(
            of: [survivingHandlerStillFires, removedHandlerDidNotFire],
            timeout: 5.0
        )
    }

    private func loadBlankDocument(into webView: WKWebView) async throws {
        let didFinish = expectation(description: "blank document loaded")
        let delegate = NavigationDelegateBox {
            didFinish.fulfill()
        }

        webView.navigationDelegate = delegate
        webView.loadHTMLString(
            "<!doctype html><html><body>ok</body></html>",
            baseURL: URL(string: "https://example.com")
        )

        await fulfillment(of: [didFinish], timeout: 5.0)
        webView.navigationDelegate = nil
    }

    private func evaluate(_ script: String, in webView: WKWebView) async throws {
        let wrappedScript = """
        (() => {
        \(script)
        return null;
        })();
        """

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            webView.evaluateJavaScript(wrappedScript) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

private final class NavigationDelegateBox: NSObject, WKNavigationDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        onFinish()
    }
}
