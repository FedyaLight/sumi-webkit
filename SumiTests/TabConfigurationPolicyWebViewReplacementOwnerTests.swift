@testable import Sumi
import WebKit
import XCTest

@MainActor
final class TabWebViewReplacementOwnerTests: XCTestCase {
    func testTrackedReplacementSetsAssignsAndRefreshesInOrder() {
        let owner = TabWebViewReplacementOwner()
        let tabId = UUID()
        let windowId = UUID()
        let previousWebView = WKWebView()
        let replacementWebView = WKWebView()
        var events: [String] = []

        XCTAssertTrue(
            owner.replaceNormalWebView(
                reason: "tracked-success",
                context: makeContext(
                    ReplacementContextFixture(
                        tabId: tabId,
                        previousWebView: previousWebView,
                        replacementWebView: replacementWebView,
                        trackedWindowId: windowId,
                        hasTrackedWebViews: true,
                        removeTrackedWebViews: {
                            events.append("remove")
                            return true
                        },
                        record: { event in
                            events.append(event)
                        }
                    )
                )
            )
        )

        XCTAssertEqual(
            events,
            [
                "make:tracked-success",
                "invalidate:tracked-success",
                "remove",
                "setTracked",
                "assign",
                "refresh",
            ]
        )
    }

    func testTrackedRemovalFailureCallsFailureCallbackAndSkipsAssignment() {
        let owner = TabWebViewReplacementOwner()
        let tabId = UUID()
        let windowId = UUID()
        let previousWebView = WKWebView()
        let replacementWebView = WKWebView()
        var events: [String] = []

        XCTAssertFalse(
            owner.replaceNormalWebView(
                reason: "tracked-failure",
                context: makeContext(
                    ReplacementContextFixture(
                        tabId: tabId,
                        previousWebView: previousWebView,
                        replacementWebView: replacementWebView,
                        trackedWindowId: windowId,
                        hasTrackedWebViews: true,
                        removeTrackedWebViews: {
                            events.append("remove")
                            return false
                        },
                        record: { event in
                            events.append(event)
                        }
                    )
                ),
                onTrackedWebViewRemovalFailure: {
                    events.append("failure")
                }
            )
        )

        XCTAssertEqual(
            events,
            [
                "make:tracked-failure",
                "invalidate:tracked-failure",
                "remove",
                "failure",
            ]
        )
    }

    func testUntrackedReplacementCleansPreviousWebViewAndReplacesUntracked() {
        let owner = TabWebViewReplacementOwner()
        let tabId = UUID()
        let previousWebView = WKWebView()
        let replacementWebView = WKWebView()
        var events: [String] = []

        XCTAssertTrue(
            owner.replaceNormalWebView(
                reason: "untracked",
                context: makeContext(
                    ReplacementContextFixture(
                        tabId: tabId,
                        previousWebView: previousWebView,
                        replacementWebView: replacementWebView,
                        trackedWindowId: nil,
                        hasTrackedWebViews: false,
                        removeTrackedWebViews: {
                            events.append("remove")
                            return false
                        },
                        record: { event in
                            events.append(event)
                        }
                    )
                )
            )
        )

        XCTAssertEqual(
            events,
            [
                "make:untracked",
                "invalidate:untracked",
                "remove",
                "cleanup",
                "clearCurrent",
                "replaceUntracked",
            ]
        )
    }

    private struct ReplacementContextFixture {
        let tabId: UUID
        let previousWebView: WKWebView
        let replacementWebView: WKWebView
        let trackedWindowId: UUID?
        let hasTrackedWebViews: Bool
        let removeTrackedWebViews: () -> Bool
        let record: (String) -> Void
    }

    private func makeContext(_ fixture: ReplacementContextFixture) -> TabWebViewReplacementContext {
        TabWebViewReplacementContext(
            tabId: fixture.tabId,
            existingWebView: { fixture.previousWebView },
            primaryWindowId: nil,
            trackedWindowIdContainingWebView: { webView in
                XCTAssertIdentical(webView, fixture.previousWebView)
                return fixture.trackedWindowId
            },
            hasTrackedWebViews: { requestedTabId in
                XCTAssertEqual(requestedTabId, fixture.tabId)
                return fixture.hasTrackedWebViews
            },
            setTrackedWebView: { webView, requestedTabId, requestedWindowId in
                XCTAssertIdentical(webView, fixture.replacementWebView)
                XCTAssertEqual(requestedTabId, fixture.tabId)
                XCTAssertEqual(Optional(requestedWindowId), fixture.trackedWindowId)
                fixture.record("setTracked")
            },
            makeNormalTabWebView: { reason in
                fixture.record("make:\(reason)")
                return fixture.replacementWebView
            },
            invalidatePermissionPageForReplacement: { reason in
                fixture.record("invalidate:\(reason)")
            },
            removeTrackedWebViews: fixture.removeTrackedWebViews,
            cleanupCloneWebView: { webView in
                XCTAssertIdentical(webView, fixture.previousWebView)
                fixture.record("cleanup")
            },
            clearCurrentWebViewOwnership: {
                fixture.record("clearCurrent")
            },
            replaceUntrackedWebView: { webView in
                XCTAssertIdentical(webView, fixture.replacementWebView)
                fixture.record("replaceUntracked")
            },
            assignWebViewToWindow: { webView, requestedWindowId in
                XCTAssertIdentical(webView, fixture.replacementWebView)
                XCTAssertEqual(Optional(requestedWindowId), fixture.trackedWindowId)
                fixture.record("assign")
            },
            refreshWindowAfterWebViewReplacement: { requestedWindowId in
                XCTAssertEqual(Optional(requestedWindowId), fixture.trackedWindowId)
                fixture.record("refresh")
            }
        )
    }
}
