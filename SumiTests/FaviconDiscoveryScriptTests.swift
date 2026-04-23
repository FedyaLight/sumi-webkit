import AppKit
import Foundation
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class FaviconDiscoveryScriptTests: XCTestCase {
    func testParseDiscoveredFaviconPayloadAcceptsDDGShape() throws {
        let body: [String: Any] = [
            "documentUrl": "https://example.com/article",
            "favicons": [
                [
                    "href": "https://example.com/favicon.ico",
                    "rel": "icon",
                    "type": "image/x-icon",
                ],
            ],
        ]

        let parsed = try XCTUnwrap(Tab.parseDiscoveredFaviconPayload(body))
        XCTAssertEqual(parsed.documentURL.absoluteString, "https://example.com/article")
        XCTAssertEqual(parsed.fullLinks?.count, 1)
        XCTAssertEqual(parsed.fullLinks?.first?.url.absoluteString, "https://example.com/favicon.ico")
        XCTAssertEqual(parsed.fullLinks?.first?.relation, "icon")
        XCTAssertEqual(parsed.fullLinks?.first?.type, "image/x-icon")
        XCTAssertTrue(parsed.upsertedLinks.isEmpty)
        XCTAssertTrue(parsed.removedLinks.isEmpty)
    }

    func testParseDiscoveredFaviconPayloadAcceptsDeltaShape() throws {
        let body: [String: Any] = [
            "documentUrl": "https://example.com/article",
            "faviconDelta": [
                "upserted": [
                    [
                        "href": "https://example.com/updated.png",
                        "rel": "icon",
                        "type": "image/png",
                    ],
                ],
                "removed": [
                    [
                        "href": "https://example.com/old.ico",
                        "rel": "icon",
                        "type": "image/x-icon",
                    ],
                ],
            ],
        ]

        let parsed = try XCTUnwrap(Tab.parseDiscoveredFaviconPayload(body))
        XCTAssertEqual(parsed.documentURL.absoluteString, "https://example.com/article")
        XCTAssertNil(parsed.fullLinks)
        XCTAssertEqual(parsed.upsertedLinks.count, 1)
        XCTAssertEqual(parsed.upsertedLinks[0].url.absoluteString, "https://example.com/updated.png")
        XCTAssertEqual(parsed.removedLinks.count, 1)
        XCTAssertEqual(parsed.removedLinks[0].url.absoluteString, "https://example.com/old.ico")
    }

    func testMergeDiscoveredFaviconPayloadReconstructsCurrentSetFromDelta() throws {
        let existingLinks = [
            SumiDiscoveredFaviconLink(
                url: URL(string: "https://example.com/old.ico")!,
                relation: "icon",
                type: "image/x-icon"
            ),
            SumiDiscoveredFaviconLink(
                url: URL(string: "https://example.com/touch.png")!,
                relation: "apple-touch-icon",
                type: "image/png"
            ),
        ]
        let parsed = try XCTUnwrap(
            Tab.parseDiscoveredFaviconPayload(
                [
                    "documentUrl": "https://example.com/article",
                    "faviconDelta": [
                        "upserted": [
                            [
                                "href": "https://example.com/updated.png",
                                "rel": "icon",
                                "type": "image/png",
                            ],
                        ],
                        "removed": [
                            [
                                "href": "https://example.com/old.ico",
                                "rel": "icon",
                                "type": "image/x-icon",
                            ],
                        ],
                    ],
                ]
            )
        )

        let merged = Tab.mergeDiscoveredFaviconPayload(existingLinks: existingLinks, parsed: parsed)
        XCTAssertEqual(
            merged,
            [
                SumiDiscoveredFaviconLink(
                    url: URL(string: "https://example.com/touch.png")!,
                    relation: "apple-touch-icon",
                    type: "image/png"
                ),
                SumiDiscoveredFaviconLink(
                    url: URL(string: "https://example.com/updated.png")!,
                    relation: "icon",
                    type: "image/png"
                ),
            ]
        )
    }

    func testDiscoveryScriptReportsInitialPayloadAfterPageLoad() async throws {
        let handlerName = "faviconLinks_initial"
        let recorder = FaviconMessageRecorder()
        let webView = makeWebView(
            handlers: [
                (handlerName, Tab.faviconDiscoveryScriptSource(
                    handlerName: handlerName,
                    marker: "__sumiFaviconReporter_initial"
                ), recorder),
            ]
        )

        let payloadReceived = expectation(description: "initial favicon payload delivered")
        recorder.onMessage = { body in
            guard let parsed = Tab.parseDiscoveredFaviconPayload(body) else { return }
            guard parsed.documentURL.absoluteString == "https://example.com/article" else { return }
            guard let links = parsed.fullLinks else { return }
            guard links.contains(where: {
                $0.url.absoluteString == "https://example.com/favicon.ico"
                    && $0.relation == "icon"
                    && $0.type == "image/x-icon"
            }) else {
                return
            }
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

    func testDiscoveryScriptReportsDynamicHeadChanges() async throws {
        let handlerName = "faviconLinks_dynamic"
        let recorder = FaviconMessageRecorder()
        let webView = makeWebView(
            handlers: [
                (handlerName, Tab.faviconDiscoveryScriptSource(
                    handlerName: handlerName,
                    marker: "__sumiFaviconReporter_dynamic"
                ), recorder),
            ]
        )

        let initialPayload = expectation(description: "initial payload delivered")
        recorder.onMessage = { body in
            guard let parsed = Tab.parseDiscoveredFaviconPayload(body) else { return }
            if parsed.fullLinks?.contains(where: { $0.url.absoluteString == "https://example.com/one.ico" }) == true {
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
        recorder.onMessage = { body in
            guard let parsed = Tab.parseDiscoveredFaviconPayload(body) else { return }
            guard parsed.fullLinks == nil else { return }
            guard parsed.upsertedLinks.contains(where: {
                $0.url.absoluteString == "https://example.com/two.png"
                    && $0.type == "image/png"
            }) else { return }
            guard parsed.removedLinks.contains(where: {
                $0.url.absoluteString == "https://example.com/one.ico"
                    && $0.type == "image/x-icon"
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

    func testDiscoveryScriptSuppressesNoiseWhenHeadChangesWithoutFaviconDelta() async throws {
        let handlerName = "faviconLinks_noise"
        let recorder = FaviconMessageRecorder()
        let webView = makeWebView(
            handlers: [
                (handlerName, Tab.faviconDiscoveryScriptSource(
                    handlerName: handlerName,
                    marker: "__sumiFaviconReporter_noise"
                ), recorder),
            ]
        )

        let initialPayload = expectation(description: "initial payload delivered")
        recorder.onMessage = { body in
            guard let parsed = Tab.parseDiscoveredFaviconPayload(body) else { return }
            if parsed.fullLinks?.contains(where: { $0.url.absoluteString == "https://example.com/one.ico" }) == true {
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

        let duplicatePayload = expectation(description: "no duplicate payload for non-favicon head noise")
        duplicatePayload.isInverted = true
        recorder.onMessage = { _ in
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

    func testTabScopedFaviconHandlersRemainIsolatedOnSharedUserContentController() async throws {
        let firstTabId = UUID()
        let secondTabId = UUID()
        let firstHandlerName = Tab.coreScriptMessageHandlerName("faviconLinks", for: firstTabId)
        let secondHandlerName = Tab.coreScriptMessageHandlerName("faviconLinks", for: secondTabId)

        let firstRecorder = FaviconMessageRecorder()
        let secondRecorder = FaviconMessageRecorder()
        let webView = makeWebView(
            handlers: [
                (
                    firstHandlerName,
                    Tab.faviconDiscoveryScriptSource(
                        handlerName: firstHandlerName,
                        marker: Tab.faviconDiscoveryMarker(for: firstTabId)
                    ),
                    firstRecorder
                ),
                (
                    secondHandlerName,
                    Tab.faviconDiscoveryScriptSource(
                        handlerName: secondHandlerName,
                        marker: Tab.faviconDiscoveryMarker(for: secondTabId)
                    ),
                    secondRecorder
                ),
            ]
        )

        let firstDelivered = expectation(description: "first handler delivered")
        let secondDelivered = expectation(description: "second handler delivered")
        firstRecorder.onMessage = { body in
            guard let parsed = Tab.parseDiscoveredFaviconPayload(body) else { return }
            if parsed.fullLinks?.contains(where: { $0.url.absoluteString == "https://example.com/first.ico" }) == true {
                firstDelivered.fulfill()
            }
        }
        secondRecorder.onMessage = { body in
            guard let parsed = Tab.parseDiscoveredFaviconPayload(body) else { return }
            if parsed.fullLinks?.contains(where: { $0.url.absoluteString == "https://example.com/first.ico" }) == true {
                secondDelivered.fulfill()
            }
        }

        try await loadHTML(
            """
            <!doctype html>
            <html>
              <head>
                <link rel="icon" href="/first.ico" type="image/x-icon">
              </head>
              <body>ok</body>
            </html>
            """,
            baseURL: URL(string: "https://example.com/first")!,
            into: webView
        )

        await fulfillment(of: [firstDelivered, secondDelivered], timeout: 5.0)

        webView.configuration.userContentController.removeScriptMessageHandler(forName: firstHandlerName)

        let removedHandlerStaysDetached = expectation(description: "removed handler stays detached")
        removedHandlerStaysDetached.isInverted = true
        let survivingHandlerStillDelivers = expectation(description: "surviving handler still delivers")
        firstRecorder.onMessage = { body in
            guard let parsed = Tab.parseDiscoveredFaviconPayload(body) else { return }
            if parsed.fullLinks?.contains(where: { $0.url.absoluteString == "https://example.com/second.ico" }) == true {
                removedHandlerStaysDetached.fulfill()
            }
        }
        secondRecorder.onMessage = { body in
            guard let parsed = Tab.parseDiscoveredFaviconPayload(body) else { return }
            if parsed.fullLinks?.contains(where: { $0.url.absoluteString == "https://example.com/second.ico" }) == true {
                survivingHandlerStillDelivers.fulfill()
            }
        }

        try await loadHTML(
            """
            <!doctype html>
            <html>
              <head>
                <link rel="icon" href="/second.ico" type="image/x-icon">
              </head>
              <body>ok</body>
            </html>
            """,
            baseURL: URL(string: "https://example.com/second")!,
            into: webView
        )

        await fulfillment(
            of: [survivingHandlerStillDelivers, removedHandlerStaysDetached],
            timeout: 5.0
        )
    }

    func testDidFinishDoesNotReplaceJSDiscoveredFavicon() async throws {
        SumiFaviconSystem.shared.manager.clearAll()
        defer { SumiFaviconSystem.shared.manager.clearAll() }

        let pageURL = URL(string: "https://example.com/article")!
        let faviconURL = try XCTUnwrap(
            Self.makeDataURL(color: .systemBlue, size: 180)
        )
        let webView = makeWebView(handlers: [])
        let tab = Tab(url: pageURL, existingWebView: webView)
        tab._webView = webView

        try await loadHTML(
            """
            <!doctype html>
            <html>
              <head></head>
              <body>ok</body>
            </html>
            """,
            baseURL: pageURL,
            into: webView
        )

        await tab.applyDiscoveredFaviconLinks(
            [
                SumiDiscoveredFaviconLink(
                    url: faviconURL,
                    relation: "apple-touch-icon",
                    type: "image/png"
                ),
            ],
            documentURL: pageURL
        )

        XCTAssertFalse(tab.faviconIsTemplateGlobePlaceholder)
        let resolvedCacheKey = try XCTUnwrap(tab.resolvedFaviconCacheKey)
        XCTAssertNotNil(Tab.getCachedFavicon(for: resolvedCacheKey))

        tab.webView(webView, didFinish: nil)

        XCTAssertFalse(tab.faviconIsTemplateGlobePlaceholder)
        XCTAssertEqual(tab.resolvedFaviconCacheKey, resolvedCacheKey)
        XCTAssertNotNil(Tab.getCachedFavicon(for: resolvedCacheKey))
    }

    private func makeWebView(
        handlers: [(name: String, script: String, recorder: FaviconMessageRecorder)]
    ) -> WKWebView {
        let userContentController = WKUserContentController()
        for handler in handlers {
            userContentController.add(handler.recorder, name: handler.name)
            userContentController.addUserScript(
                WKUserScript(
                    source: handler.script,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true
                )
            )
        }

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

    private static func makeDataURL(color: NSColor, size: CGFloat) -> URL? {
        guard let data = makeImageData(color: color, size: size) else { return nil }
        return URL(string: "data:image/png;base64,\(data.base64EncodedString())")
    }

    private static func makeImageData(color: NSColor, size: CGFloat) -> Data? {
        let pixelSize = max(1, Int(size.rounded()))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        color.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)).fill()
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .png, properties: [:])
    }
}

@MainActor
private final class FaviconMessageRecorder: NSObject, WKScriptMessageHandler {
    var onMessage: (([String: Any]) -> Void)?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any] else { return }
        onMessage?(body)
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
