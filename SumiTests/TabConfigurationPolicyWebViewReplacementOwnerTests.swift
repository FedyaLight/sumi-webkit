import WebKit
import XCTest
@testable import Sumi

@MainActor
final class TabConfigurationPolicyWebViewReplacementOwnerTests: XCTestCase {
    func testTrackedReplacementSetsAssignsAndRefreshesInOrder() {
        let owner = TabConfigurationPolicyWebViewReplacementOwner()
        let tabId = UUID()
        let windowId = UUID()
        let previousWebView = WKWebView()
        let replacementWebView = WKWebView()
        var events: [String] = []

        XCTAssertTrue(
            owner.replaceNormalWebView(
                reason: "tracked-success",
                context: makeContext(
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
        let owner = TabConfigurationPolicyWebViewReplacementOwner()
        let tabId = UUID()
        let windowId = UUID()
        let previousWebView = WKWebView()
        let replacementWebView = WKWebView()
        var events: [String] = []

        XCTAssertFalse(
            owner.replaceNormalWebView(
                reason: "tracked-failure",
                context: makeContext(
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
        let owner = TabConfigurationPolicyWebViewReplacementOwner()
        let tabId = UUID()
        let previousWebView = WKWebView()
        let replacementWebView = WKWebView()
        var events: [String] = []

        XCTAssertTrue(
            owner.replaceNormalWebView(
                reason: "untracked",
                context: makeContext(
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

    private func makeContext(
        tabId: UUID,
        previousWebView: WKWebView,
        replacementWebView: WKWebView,
        trackedWindowId: UUID?,
        hasTrackedWebViews: Bool,
        removeTrackedWebViews: @escaping () -> Bool,
        record: @escaping (String) -> Void
    ) -> TabConfigurationPolicyWebViewReplacementContext {
        TabConfigurationPolicyWebViewReplacementContext(
            tabId: tabId,
            existingWebView: { previousWebView },
            primaryWindowId: nil,
            trackedWindowIdContainingWebView: { webView in
                XCTAssertIdentical(webView, previousWebView)
                return trackedWindowId
            },
            hasTrackedWebViews: { requestedTabId in
                XCTAssertEqual(requestedTabId, tabId)
                return hasTrackedWebViews
            },
            setTrackedWebView: { webView, requestedTabId, requestedWindowId in
                XCTAssertIdentical(webView, replacementWebView)
                XCTAssertEqual(requestedTabId, tabId)
                XCTAssertEqual(Optional(requestedWindowId), trackedWindowId)
                record("setTracked")
            },
            makeNormalTabWebView: { reason in
                record("make:\(reason)")
                return replacementWebView
            },
            invalidateCurrentPermissionPageForWebViewReplacement: { reason in
                record("invalidate:\(reason)")
            },
            removeTrackedWebViews: removeTrackedWebViews,
            cleanupCloneWebView: { webView in
                XCTAssertIdentical(webView, previousWebView)
                record("cleanup")
            },
            clearCurrentWebViewOwnership: {
                record("clearCurrent")
            },
            replaceUntrackedWebView: { webView in
                XCTAssertIdentical(webView, replacementWebView)
                record("replaceUntracked")
            },
            assignWebViewToWindow: { webView, requestedWindowId in
                XCTAssertIdentical(webView, replacementWebView)
                XCTAssertEqual(Optional(requestedWindowId), trackedWindowId)
                record("assign")
            },
            refreshWindowAfterWebViewReplacement: { requestedWindowId in
                XCTAssertEqual(Optional(requestedWindowId), trackedWindowId)
                record("refresh")
            }
        )
    }
}
