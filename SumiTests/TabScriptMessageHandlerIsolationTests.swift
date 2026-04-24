import BrowserServicesKit
import WebKit
import XCTest
@testable import Sumi

@MainActor
final class TabScriptMessageHandlerIsolationTests: XCTestCase {
    func testBrokeredTabMessagesRemainScopedByContext() async throws {
        let firstTab = Tab(name: "First")
        let secondTab = Tab(name: "Second")
        let scriptsProvider = SumiNormalTabUserScripts(
            managedUserScripts: firstTab.normalTabCoreUserScripts() + secondTab.normalTabCoreUserScripts()
        )
        let controller = SumiNormalTabUserContentControllerFactory.makeController(
            scriptsProvider: scriptsProvider
        )
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )

        await controller.awaitContentBlockingAssetsInstalled()
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

        try await postLinkHover(
            "https://first.example/",
            context: linkContext(for: firstTab),
            in: webView
        )
        try await postLinkHover(
            "https://second.example/",
            context: linkContext(for: secondTab),
            in: webView
        )

        await fulfillment(of: [firstDelivered, secondDelivered], timeout: 5.0)
    }

    func testControllerCleanupRemovesBrokerHandlers() async throws {
        let tab = Tab(name: "Cleanup")
        let scriptsProvider = SumiNormalTabUserScripts(
            managedUserScripts: tab.normalTabCoreUserScripts()
        )
        let controller = SumiNormalTabUserContentControllerFactory.makeController(
            scriptsProvider: scriptsProvider
        )
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )

        await controller.awaitContentBlockingAssetsInstalled()
        try await loadBlankDocument(into: webView)

        controller.cleanUpBeforeClosing()

        let removedHandlerDidNotFire = expectation(description: "removed handler stays detached")
        removedHandlerDidNotFire.isInverted = true
        tab.onLinkHover = { _ in
            removedHandlerDidNotFire.fulfill()
        }

        try await postLinkHover(
            "https://removed.example/",
            context: linkContext(for: tab),
            in: webView
        )

        await fulfillment(of: [removedHandlerDidNotFire], timeout: 0.5)
    }

    func testMalformedBrokerPayloadFailsLocally() async throws {
        let tab = Tab(name: "Malformed")
        let webView = try await makeWebView(with: tab)
        let malformedDidNotFire = expectation(description: "malformed payload has no side effects")
        malformedDidNotFire.isInverted = true
        tab.onLinkHover = { _ in
            malformedDidNotFire.fulfill()
        }

        try await evaluate(
            """
            const handler = window.webkit?.messageHandlers?.["\(linkContext(for: tab))"];
            handler.postMessage({
                context: "\(linkContext(for: tab))",
                featureName: "linkInteraction",
                method: "linkHover",
                params: []
            });
            """,
            in: webView
        )

        await fulfillment(of: [malformedDidNotFire], timeout: 0.5)
    }

    func testUnknownBrokerMethodIsIgnoredSafely() async throws {
        let tab = Tab(name: "Unknown")
        let webView = try await makeWebView(with: tab)
        let unknownDidNotFire = expectation(description: "unknown message has no side effects")
        unknownDidNotFire.isInverted = true
        tab.onLinkHover = { _ in
            unknownDidNotFire.fulfill()
        }

        try await evaluate(
            """
            const handler = window.webkit?.messageHandlers?.["\(linkContext(for: tab))"];
            handler.postMessage({
                context: "\(linkContext(for: tab))",
                featureName: "linkInteraction",
                method: "unknownMethod",
                params: {}
            });
            """,
            in: webView
        )

        await fulfillment(of: [unknownDidNotFire], timeout: 0.5)
    }

    private func linkContext(for tab: Tab) -> String {
        "sumiLinkInteraction_\(tab.id.uuidString)"
    }

    private func makeWebView(with tab: Tab) async throws -> WKWebView {
        let scriptsProvider = SumiNormalTabUserScripts(
            managedUserScripts: tab.normalTabCoreUserScripts()
        )
        let controller = SumiNormalTabUserContentControllerFactory.makeController(
            scriptsProvider: scriptsProvider
        )
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        await controller.awaitContentBlockingAssetsInstalled()
        try await loadBlankDocument(into: webView)
        return webView
    }

    private func postLinkHover(_ href: String, context: String, in webView: WKWebView) async throws {
        try await evaluate(
            """
            const handler = window.webkit?.messageHandlers?.["\(context)"];
            if (handler) {
                handler.postMessage({
                    context: "\(context)",
                    featureName: "linkInteraction",
                    method: "linkHover",
                    params: { href: "\(href)" }
                });
            }
            """,
            in: webView
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
        _ = webView
        _ = navigation
        onFinish()
    }
}
