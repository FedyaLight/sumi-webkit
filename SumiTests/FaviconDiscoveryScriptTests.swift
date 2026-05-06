import AppKit
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class FaviconDiscoveryScriptTests: XCTestCase {
    func testDDGUserContentControllerReportsInitialPayloadThroughFaviconUserScript() async throws {
        let controller = SumiNormalTabUserContentControllerFactory.makeController()
        let scriptsProvider = try XCTUnwrap(controller.sumiNormalTabUserScriptsProvider).faviconScripts
        let recorder = FaviconUserScriptRecorder()
        scriptsProvider.faviconScript.delegate = recorder
        await controller.awaitContentBlockingAssetsInstalled()

        let webView = makeWebView(userContentController: controller)
        let payloadReceived = expectation(description: "initial DDG favicon payload delivered")
        recorder.onLinks = { links, documentURL, messageWebView in
            guard documentURL.absoluteString == "https://example.com/article" else { return }
            guard messageWebView === webView else { return }
            guard links.contains(where: {
                $0.href.absoluteString == "https://example.com/favicon.ico"
                    && $0.rel == "icon"
                    && $0.type == "image/x-icon"
            }) else { return }
            payloadReceived.fulfill()
        }

        try await loadHTML(
            """
            <!doctype html>
            <html>
              <head>
                <link rel="icon" href="/favicon.ico" type="image/x-icon">
              </head>
              <body>ok</body>
            </html>
            """,
            baseURL: URL(string: "https://example.com/article")!,
            into: webView
        )

        await fulfillment(of: [payloadReceived], timeout: 5.0)
    }

    func testDDGUserContentControllerReportsSVGFaviconPayloadThroughFaviconUserScript() async throws {
        let controller = SumiNormalTabUserContentControllerFactory.makeController()
        let scriptsProvider = try XCTUnwrap(controller.sumiNormalTabUserScriptsProvider).faviconScripts
        let recorder = FaviconUserScriptRecorder()
        scriptsProvider.faviconScript.delegate = recorder
        await controller.awaitContentBlockingAssetsInstalled()

        let webView = makeWebView(userContentController: controller)
        let payloadReceived = expectation(description: "SVG favicon payload delivered")
        recorder.onLinks = { links, documentURL, messageWebView in
            guard documentURL.absoluteString == "https://example.com/article" else { return }
            guard messageWebView === webView else { return }
            guard links.contains(where: {
                $0.href.absoluteString == "https://example.com/favicon.svg"
                    && $0.rel == "icon"
                    && $0.type == "image/svg+xml"
            }) else { return }
            payloadReceived.fulfill()
        }

        try await loadHTML(
            """
            <!doctype html>
            <html>
              <head>
                <link rel="icon" href="/favicon.svg" type="image/svg+xml">
              </head>
              <body>ok</body>
            </html>
            """,
            baseURL: URL(string: "https://example.com/article")!,
            into: webView
        )

        await fulfillment(of: [payloadReceived], timeout: 5.0)
    }

    func testDDGUserContentControllerReportsDynamicHeadChanges() async throws {
        let controller = SumiNormalTabUserContentControllerFactory.makeController()
        let scriptsProvider = try XCTUnwrap(controller.sumiNormalTabUserScriptsProvider).faviconScripts
        let recorder = FaviconUserScriptRecorder()
        scriptsProvider.faviconScript.delegate = recorder
        await controller.awaitContentBlockingAssetsInstalled()

        let webView = makeWebView(userContentController: controller)
        let initialPayload = expectation(description: "initial payload delivered")
        recorder.onLinks = { links, _, _ in
            if links.contains(where: { $0.href.absoluteString == "https://example.com/one.ico" }) {
                initialPayload.fulfill()
            }
        }

        try await loadHTML(
            """
            <!doctype html>
            <html>
              <head>
                <link id="fav" rel="icon" href="/one.ico" type="image/x-icon">
              </head>
              <body>ok</body>
            </html>
            """,
            baseURL: URL(string: "https://example.com/article")!,
            into: webView
        )

        await fulfillment(of: [initialPayload], timeout: 5.0)

        let updatedPayload = expectation(description: "updated payload delivered")
        recorder.onLinks = { links, _, _ in
            guard links.contains(where: {
                $0.href.absoluteString == "https://example.com/two.png"
                    && $0.rel == "icon"
                    && $0.type == "image/png"
            }) else { return }
            updatedPayload.fulfill()
        }

        try await evaluate(
            """
            const favicon = document.getElementById('fav');
            favicon.setAttribute('href', '/two.png');
            favicon.setAttribute('type', 'image/png');
            """,
            in: webView
        )

        await fulfillment(of: [updatedPayload], timeout: 5.0)
    }

    func testDDGUserContentControllerSuppressesNoiseWhenHeadChangesWithoutFaviconChange() async throws {
        let controller = SumiNormalTabUserContentControllerFactory.makeController()
        let scriptsProvider = try XCTUnwrap(controller.sumiNormalTabUserScriptsProvider).faviconScripts
        let recorder = FaviconUserScriptRecorder()
        scriptsProvider.faviconScript.delegate = recorder
        await controller.awaitContentBlockingAssetsInstalled()

        let webView = makeWebView(userContentController: controller)
        let initialPayload = expectation(description: "initial payload delivered")
        recorder.onLinks = { links, _, _ in
            if links.contains(where: { $0.href.absoluteString == "https://example.com/one.ico" }) {
                initialPayload.fulfill()
            }
        }

        try await loadHTML(
            """
            <!doctype html>
            <html>
              <head>
                <link id="fav" rel="icon" href="/one.ico" type="image/x-icon">
              </head>
              <body>ok</body>
            </html>
            """,
            baseURL: URL(string: "https://example.com/article")!,
            into: webView
        )

        await fulfillment(of: [initialPayload], timeout: 5.0)

        let duplicatePayload = expectation(description: "no payload for non-favicon head noise")
        duplicatePayload.isInverted = true
        recorder.onLinks = { _, _, _ in
            duplicatePayload.fulfill()
        }

        try await evaluate(
            """
            const stylesheet = document.createElement('link');
            stylesheet.setAttribute('rel', 'stylesheet');
            stylesheet.setAttribute('href', '/styles.css');
            document.head.appendChild(stylesheet);
            """,
            in: webView
        )

        await fulfillment(of: [duplicatePayload], timeout: 0.5)
    }

    func testSeparateDDGControllersKeepFaviconDeliveryIsolated() async throws {
        let firstController = SumiNormalTabUserContentControllerFactory.makeController()
        let secondController = SumiNormalTabUserContentControllerFactory.makeController()
        let firstProvider = try XCTUnwrap(firstController.sumiNormalTabUserScriptsProvider).faviconScripts
        let secondProvider = try XCTUnwrap(secondController.sumiNormalTabUserScriptsProvider).faviconScripts
        let firstRecorder = FaviconUserScriptRecorder()
        let secondRecorder = FaviconUserScriptRecorder()
        firstProvider.faviconScript.delegate = firstRecorder
        secondProvider.faviconScript.delegate = secondRecorder
        await firstController.awaitContentBlockingAssetsInstalled()
        await secondController.awaitContentBlockingAssetsInstalled()

        let firstWebView = makeWebView(userContentController: firstController)
        let secondWebView = makeWebView(userContentController: secondController)
        let firstDelivered = expectation(description: "first controller delivered")
        let secondDelivered = expectation(description: "second controller delivered")

        firstRecorder.onLinks = { links, _, messageWebView in
            guard messageWebView === firstWebView else { return }
            if links.contains(where: { $0.href.absoluteString == "https://first.example/favicon.ico" }) {
                firstDelivered.fulfill()
            }
        }
        secondRecorder.onLinks = { links, _, messageWebView in
            guard messageWebView === secondWebView else { return }
            if links.contains(where: { $0.href.absoluteString == "https://second.example/favicon.ico" }) {
                secondDelivered.fulfill()
            }
        }

        try await loadHTML(
            """
            <!doctype html>
            <html><head><link rel="icon" href="/favicon.ico"></head><body>first</body></html>
            """,
            baseURL: URL(string: "https://first.example/page")!,
            into: firstWebView
        )
        try await loadHTML(
            """
            <!doctype html>
            <html><head><link rel="icon" href="/favicon.ico"></head><body>second</body></html>
            """,
            baseURL: URL(string: "https://second.example/page")!,
            into: secondWebView
        )

        await fulfillment(of: [firstDelivered, secondDelivered], timeout: 5.0)
    }

    private func makeWebView(userContentController: WKUserContentController) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        return WKWebView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
    }

    private func loadHTML(
        _ html: String,
        baseURL: URL,
        into webView: WKWebView
    ) async throws {
        let didFinish = expectation(description: "html loaded")
        let delegate = NavigationDelegateBox {
            didFinish.fulfill()
        }

        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: baseURL)
        await fulfillment(of: [didFinish], timeout: 5.0)
        webView.navigationDelegate = nil
    }

    private func evaluate(
        _ script: String,
        in webView: WKWebView
    ) async throws {
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

@MainActor
private final class FaviconUserScriptRecorder: NSObject, SumiDDGFaviconUserScriptDelegate {
    var onLinks: (([SumiDDGFaviconUserScript.FaviconLink], URL, WKWebView?) -> Void)?

    func faviconUserScript(
        _ faviconUserScript: SumiDDGFaviconUserScript,
        didFindFaviconLinks faviconLinks: [SumiDDGFaviconUserScript.FaviconLink],
        for documentUrl: URL,
        in webView: WKWebView?
    ) {
        _ = faviconUserScript
        onLinks?(faviconLinks, documentUrl, webView)
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
