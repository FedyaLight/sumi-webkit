import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabWebViewReplacementContextOwnerTests: XCTestCase {
    func testMakeContextReflectsUntrackedOwnership() {
        let owner = TabWebViewReplacementContextOwner()
        let tab = Tab(url: URL(string: "https://example.com/replacement-context")!)
        let existingWebView = WKWebView()
        let replacementWebView = WKWebView()
        tab.replaceUntrackedWebView(existingWebView)
        tab.navigationRuntime.webViewReplacementRuntime = TabWebViewReplacementRuntime(
            rebuildTrackedWebViews: { _, _, _, _, _ in .failed },
            commitUntrackedReplacement: { runtimeTab, previous, replacement, _ in
                XCTAssertIdentical(runtimeTab, tab)
                XCTAssertIdentical(previous, existingWebView)
                runtimeTab.replaceUntrackedWebView(replacement)
                return .committed
            }
        )

        let context = owner.makeContext(for: tab)

        XCTAssertIdentical(context.existingWebView(), existingWebView)
        XCTAssertFalse(context.hasTrackedWebViews())

        XCTAssertEqual(
            context.commitUntrackedReplacement(
                existingWebView,
                replacementWebView,
                "context-test"
            ),
            .committed
        )

        XCTAssertIdentical(tab.resolvedCurrentWebView(), replacementWebView)
    }

    func testMakeContextRoutesTrackedTransactionThroughInjectedRuntime() {
        let owner = TabWebViewReplacementContextOwner()
        let tab = Tab(url: URL(string: "https://example.com/replacement-runtime")!)
        let targetURL = URL(string: "https://example.com/target")!
        var calls: [TrackedRebuildCall] = []

        tab.navigationRuntime.webViewReplacementRuntime = TabWebViewReplacementRuntime(
            rebuildTrackedWebViews: { runtimeTab, windowID, url, reason, configuration in
                calls.append(TrackedRebuildCall(
                    tabID: runtimeTab.id,
                    windowID: windowID,
                    url: url,
                    reason: reason,
                    configuration: configuration
                ))
                return .committed
            },
            commitUntrackedReplacement: { _, _, _, _ in .rejected }
        )

        let context = owner.makeContext(for: tab)

        XCTAssertFalse(tab.hasBrowserRuntime)
        XCTAssertFalse(context.hasTrackedWebViews())
        XCTAssertEqual(
            context.rebuildTrackedWebViews(
                targetURL,
                "context-test",
                .currentExtensionPage
            ),
            .committed
        )
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].tabID, tab.id)
        XCTAssertNil(calls[0].windowID)
        XCTAssertEqual(calls[0].url, targetURL)
        XCTAssertEqual(calls[0].reason, "context-test")
        XCTAssertEqual(calls[0].configuration, .currentExtensionPage)
    }
}

private struct TrackedRebuildCall {
    let tabID: UUID
    let windowID: UUID?
    let url: URL
    let reason: String
    let configuration: DeferredWebViewRebuildConfiguration
}
