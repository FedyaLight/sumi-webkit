import AppKit
@testable import Sumi
import WebKit
import XCTest

@MainActor
final class WebKitTransientChromeInteractionShieldOwnerTests: XCTestCase {
    func testExpandingActiveShieldOverPointerDispatchesPageHoverExit() async throws {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let navigation = NavigationWaiter()
        webView.navigationDelegate = navigation
        webView.loadHTMLString(
            """
            <!doctype html>
            <style>html, body, #target { margin: 0; width: 100%; height: 100%; }</style>
            <div id="target"></div>
            <script>
                window.hoverExitCount = 0;
                document.getElementById("target").addEventListener("mouseout", function() {
                    window.hoverExitCount += 1;
                });
            </script>
            """,
            baseURL: nil
        )
        await fulfillment(of: [navigation.finished], timeout: 3)

        _ = try await webView.evaluateJavaScript(
            SumiTransientChromeInteractionShieldUserScript.makeSetActiveSource(
                true,
                clientPoint: CGPoint(x: 10, y: 10),
                rects: [
                    SumiTransientChromeInteractionShieldRect(
                        x: 150,
                        y: 0,
                        width: 40,
                        height: 40
                    ),
                ]
            )
        )
        _ = try await webView.evaluateJavaScript(
            SumiTransientChromeInteractionShieldUserScript.makeSetActiveSource(
                true,
                clientPoint: CGPoint(x: 10, y: 10),
                rects: [
                    SumiTransientChromeInteractionShieldRect(
                        x: 0,
                        y: 0,
                        width: 100,
                        height: 100
                    ),
                ]
            )
        )

        let hoverExitValue = try await webView.evaluateJavaScript("window.hoverExitCount")
        let hoverExitCount = try XCTUnwrap(hoverExitValue as? Int)
        XCTAssertEqual(hoverExitCount, 1)
    }

    func testSuppressingAppliesScriptRefreshesTrackingAndClearsHoveredLink() {
        var scripts: [String] = []
        var refreshCount = 0
        var clearHoveredLinkCount = 0
        let owner = makeOwner(
            currentClientPoint: { CGPoint(x: 12, y: 34) },
            evaluateJavaScript: { scripts.append($0) },
            refreshPointerPresentation: { refreshCount += 1 },
            clearHoveredLink: { clearHoveredLinkCount += 1 }
        )

        owner.setMouseTrackingSuppressed(true, shieldRects: [
            SumiTransientChromeInteractionShieldRect(x: 1, y: 2, width: 3, height: 4),
        ])

        XCTAssertTrue(owner.isMouseTrackingSuppressed)
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(clearHoveredLinkCount, 1)
        XCTAssertEqual(scripts.count, 1)
        XCTAssertTrue(scripts[0].contains("shield.setActive(true"))
        XCTAssertTrue(scripts[0].contains("clientX: 12.0"))
    }

    func testSuppressionExemptionKeepsShieldInactive() {
        var scripts: [String] = []
        var refreshCount = 0
        var clearHoveredLinkCount = 0
        let owner = makeOwner(
            isSuppressionExempt: { true },
            evaluateJavaScript: { scripts.append($0) },
            refreshPointerPresentation: { refreshCount += 1 },
            clearHoveredLink: { clearHoveredLinkCount += 1 }
        )

        owner.setMouseTrackingSuppressed(true, shieldRects: [
            SumiTransientChromeInteractionShieldRect(x: 1, y: 2, width: 3, height: 4),
        ])

        XCTAssertFalse(owner.isMouseTrackingSuppressed)
        XCTAssertTrue(scripts.isEmpty)
        XCTAssertEqual(refreshCount, 0)
        XCTAssertEqual(clearHoveredLinkCount, 0)
    }

    func testRectChangeReappliesScriptWithoutRefreshingMouseTrackingState() {
        var scripts: [String] = []
        var refreshCount = 0
        var clearHoveredLinkCount = 0
        let owner = makeOwner(
            evaluateJavaScript: { scripts.append($0) },
            refreshPointerPresentation: { refreshCount += 1 },
            clearHoveredLink: { clearHoveredLinkCount += 1 }
        )

        owner.setMouseTrackingSuppressed(true, shieldRects: [
            SumiTransientChromeInteractionShieldRect(x: 1, y: 2, width: 3, height: 4),
        ])
        owner.setMouseTrackingSuppressed(true, shieldRects: [
            SumiTransientChromeInteractionShieldRect(x: 5, y: 6, width: 7, height: 8),
        ])

        XCTAssertTrue(owner.isMouseTrackingSuppressed)
        XCTAssertEqual(scripts.count, 2)
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(clearHoveredLinkCount, 1)
        XCTAssertTrue(scripts[1].contains("left: 5.0"))
    }

    private func makeOwner(
        isSuppressionExempt: @escaping @MainActor () -> Bool = { false },
        currentClientPoint: @escaping @MainActor () -> CGPoint? = { nil },
        evaluateJavaScript: @escaping @MainActor (String) -> Void = { _ in },
        refreshPointerPresentation: @escaping @MainActor () -> Void = {},
        clearHoveredLink: @escaping @MainActor () -> Void = {}
    ) -> WebKitTransientChromeInteractionShieldOwner {
        WebKitTransientChromeInteractionShieldOwner(
            isSuppressionExempt: isSuppressionExempt,
            currentClientPoint: currentClientPoint,
            evaluateJavaScript: evaluateJavaScript,
            refreshPointerPresentation: refreshPointerPresentation,
            clearHoveredLink: clearHoveredLink
        )
    }
}

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    let finished = XCTestExpectation(description: "Web content loaded")

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished.fulfill()
    }
}
