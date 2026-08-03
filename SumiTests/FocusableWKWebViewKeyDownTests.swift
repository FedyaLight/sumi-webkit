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

        let shortcutManager = try makeShortcutManager()
        let eventMonitor = try XCTUnwrap(
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                shortcutManager.routeLocalKeyDown(event, keyWindow: window)
            }
        )
        defer { NSEvent.removeMonitor(eventMonitor) }

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
                if (event.key === 'j') window.handledKeyCount += 1;
              });
            </script>
            """,
            baseURL: nil
        )
        await fulfillment(of: [navigationFinished], timeout: 2)

        let event = try Self.keyDownEvent(window: window, key: "j", keyCode: 38)
        XCTAssertIdentical(
            shortcutManager.routeLocalKeyDown(event, keyWindow: window),
            event
        )
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

    func testDistinctEquivalentKeyEventsAreNotTreatedAsWebKitRedispatch() throws {
        let shortcutManager = try makeShortcutManager()
        let webView = FocusableWKWebView()
        let window = NSWindow(contentViewController: NSViewController())
        window.contentView = webView
        XCTAssertTrue(window.makeFirstResponder(webView))
        let firstEvent = try Self.keyDownEvent(window: window, key: "j", keyCode: 38)
        let secondEvent = try Self.keyDownEvent(window: window, key: "j", keyCode: 38)

        XCTAssertIdentical(
            shortcutManager.routeLocalKeyDown(firstEvent, keyWindow: window),
            firstEvent
        )
        XCTAssertIdentical(
            shortcutManager.routeLocalKeyDown(secondEvent, keyWindow: window),
            secondEvent
        )
        XCTAssertNil(shortcutManager.routeLocalKeyDown(firstEvent, keyWindow: window))
    }

    private func makeShortcutManager() throws -> KeyboardShortcutManager {
        let suiteName = "FocusableWKWebViewKeyDownTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return KeyboardShortcutManager(
            userDefaults: defaults,
            installEventMonitor: false
        )
    }

    private static func keyDownEvent(
        window: NSWindow,
        key: String,
        keyCode: UInt16
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish()
    }
}
