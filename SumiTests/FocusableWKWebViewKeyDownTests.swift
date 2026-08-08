import AppKit
import ObjectiveC.runtime
@testable import Sumi
import WebKit
import XCTest

@MainActor
final class FocusableWKWebViewKeyDownTests: XCTestCase {
    func testPageHandledPlainKeyDoesNotFallThroughResponderChain() async throws {
        let noResponderProbe = try NoResponderProbe.install()
        defer { noResponderProbe.uninstall() }

        let webView = FocusableWKWebView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 240),
            configuration: WKWebViewConfiguration()
        )
        let window = NSWindow(
            contentRect: webView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        XCTAssertTrue(window.makeFirstResponder(webView))

        let navigationFinished = expectation(description: "HTML loaded")
        let navigationDelegate = NavigationFinishedDelegate {
            navigationFinished.fulfill()
        }
        webView.navigationDelegate = navigationDelegate
        webView.loadHTMLString(
            """
            <script>
              window.handledKeyCount = 0;
              addEventListener('keydown', event => {
                if (event.key === 'j') {
                  event.preventDefault();
                  window.handledKeyCount += 1;
                }
              });
            </script>
            """,
            baseURL: nil
        )
        await fulfillment(of: [navigationFinished], timeout: 2)

        let event = try Self.keyDownEvent(window: window, key: "j", keyCode: 38)
        window.sendEvent(event)

        try await Task.sleep(for: .milliseconds(100))
        let handledKeyCount = try await webView.evaluateJavaScript("window.handledKeyCount") as? Int
        XCTAssertEqual(handledKeyCount, 1, "The page command must still execute")
        XCTAssertEqual(
            noResponderProbe.keyDownCount,
            0,
            "A plain key delivered to web content must not fall off the responder chain and beep"
        )
    }

    func testUnhandledPlainKeyTerminatesAtWebHostWithoutSystemBeep() async throws {
        let noResponderProbe = try NoResponderProbe.install()
        defer { noResponderProbe.uninstall() }

        let webView = FocusableWKWebView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 240),
            configuration: WKWebViewConfiguration()
        )
        let container = SumiWebViewContainerView(
            tabID: UUID(),
            webView: webView
        )
        container.frame = webView.frame
        let window = NSWindow(
            contentRect: webView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        XCTAssertTrue(window.makeFirstResponder(webView))

        let navigationFinished = expectation(description: "HTML loaded")
        let navigationDelegate = NavigationFinishedDelegate {
            navigationFinished.fulfill()
        }
        webView.navigationDelegate = navigationDelegate
        webView.loadHTMLString("<p>Passive page</p>", baseURL: nil)
        await fulfillment(of: [navigationFinished], timeout: 2)

        window.sendEvent(try Self.keyDownEvent(
            window: window,
            key: "j",
            keyCode: 38
        ))
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(noResponderProbe.keyDownCount, 0)
    }

    func testNativeCopyAndPasteKeyEquivalentsRemainWebKitOwned() async throws {
        let webView = FocusableWKWebView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 240),
            configuration: WKWebViewConfiguration()
        )
        let window = NSWindow(contentViewController: NSViewController())
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        XCTAssertTrue(window.makeFirstResponder(webView))
        let navigationFinished = expectation(description: "HTML loaded")
        let navigationDelegate = NavigationFinishedDelegate {
            navigationFinished.fulfill()
        }
        webView.navigationDelegate = navigationDelegate
        webView.loadHTMLString(
            "<input id='editor' value='copy me' autofocus>",
            baseURL: nil
        )
        await fulfillment(of: [navigationFinished], timeout: 2)
        _ = try await webView.evaluateJavaScript(
            "editor.focus(); editor.select();"
        )
        XCTAssertTrue(window.makeFirstResponder(webView))
        let copyEvent = try Self.keyDownEvent(
            window: window,
            key: "c",
            keyCode: 8,
            modifierFlags: .command
        )
        XCTAssertTrue(webView.performKeyEquivalent(with: copyEvent))
        let pasteEvent = try Self.keyDownEvent(
            window: window,
            key: "v",
            keyCode: 9,
            modifierFlags: .command
        )
        XCTAssertTrue(webView.performKeyEquivalent(with: pasteEvent))
    }

    private static func keyDownEvent(
        window: NSWindow,
        key: String,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifierFlags,
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: key,
                charactersIgnoringModifiers: key,
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }
}

private final class NoResponderProbe {
    private let method: Method
    private let originalImplementation: IMP
    private(set) var keyDownCount = 0

    private init(method: Method, originalImplementation: IMP) {
        self.method = method
        self.originalImplementation = originalImplementation
    }

    @MainActor
    static func install() throws -> NoResponderProbe {
        let selector = #selector(NSResponder.noResponder(for:))
        let method = try XCTUnwrap(class_getInstanceMethod(NSApplication.self, selector))
        let originalImplementation = method_getImplementation(method)
        let probe = NoResponderProbe(
            method: method,
            originalImplementation: originalImplementation
        )
        let replacement: @convention(block) (AnyObject, Selector) -> Void = { _, eventSelector in
            if eventSelector == #selector(NSResponder.keyDown(with:)) {
                probe.keyDownCount += 1
            }
        }
        method_setImplementation(method, imp_implementationWithBlock(replacement))
        return probe
    }

    func uninstall() {
        method_setImplementation(method, originalImplementation)
    }
}

@MainActor
private final class NavigationFinishedDelegate: NSObject, WKNavigationDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func webView(_: WKWebView, didFinish _: WKNavigation?) {
        onFinish()
    }
}
