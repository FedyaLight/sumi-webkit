import XCTest
import WebKit
import SumiWebRuntime

final class WebViewCrossWindowNavigationTests: XCTestCase {
    @MainActor
    func testCrossWindowSyncDoesNotLoadWebViewWithPendingTarget() {
        let owner = WebViewCrossWindowSyncOwner()
        let webView = WKWebView()
        let targetURL = URL(string: "https://pending.example")!
        var pendingChecks = 0
        var deferredTargets = 0
        var loads = 0

        owner.syncTab(
            UUID(),
            to: targetURL,
            webViews: [webView],
            originatingWebView: nil,
            hasPendingTarget: { candidate, candidateURL in
                XCTAssertIdentical(candidate, webView)
                XCTAssertEqual(candidateURL, targetURL)
                pendingChecks += 1
                return true
            },
            isProtected: { _ in false },
            deferProtectedTarget: { _ in
                deferredTargets += 1
                return .deferred
            },
            load: { _ in loads += 1 }
        )

        XCTAssertEqual(pendingChecks, 1)
        XCTAssertEqual(deferredTargets, 0)
        XCTAssertEqual(loads, 0)
    }

    @MainActor
    func testCrossWindowSyncDefersProtectedTargetExactlyOnceWithoutLoading() {
        let owner = WebViewCrossWindowSyncOwner()
        let webView = WKWebView()
        let targetURL = URL(string: "https://protected.example")!
        var deferredTargets = 0
        var loads = 0

        owner.syncTab(
            UUID(),
            to: targetURL,
            webViews: [webView],
            originatingWebView: nil,
            hasPendingTarget: { _, _ in false },
            isProtected: { candidate in candidate === webView },
            deferProtectedTarget: { candidate in
                XCTAssertIdentical(candidate, webView)
                deferredTargets += 1
                return .deferred
            },
            load: { _ in loads += 1 }
        )

        XCTAssertEqual(deferredTargets, 1)
        XCTAssertEqual(loads, 0)
    }

    @MainActor
    func testCrossWindowReloadDefersProtectedCloneWithoutLosingTheEffect() {
        let owner = WebViewCrossWindowSyncOwner()
        let protectedWebView = WKWebView()
        let unprotectedWebView = WKWebView()
        var deferredWebViews: [ObjectIdentifier] = []
        var reloadedWebViews: [ObjectIdentifier] = []

        owner.reloadTab(
            UUID(),
            webViews: [protectedWebView, unprotectedWebView],
            isProtected: { $0 === protectedWebView },
            deferProtectedReload: {
                deferredWebViews.append(ObjectIdentifier($0))
                return .deferred
            },
            reload: {
                reloadedWebViews.append(ObjectIdentifier($0))
            }
        )

        XCTAssertEqual(deferredWebViews, [ObjectIdentifier(protectedWebView)])
        XCTAssertEqual(reloadedWebViews, [ObjectIdentifier(unprotectedWebView)])
    }

    @MainActor
    func testReloadExecutesWhenProtectionEndsDuringDeferralHandoff() {
        let owner = WebViewCrossWindowSyncOwner()
        let webView = WKWebView()
        var reloadCount = 0

        owner.reloadTab(
            UUID(),
            webViews: [webView],
            isProtected: { _ in true },
            deferProtectedReload: { _ in .executeNow },
            reload: { _ in reloadCount += 1 }
        )

        XCTAssertEqual(reloadCount, 1)
    }

    func testDeferredNavigationCoalescesLatestIntentByWebViewIdentity() {
        let webView = NSObject()
        let webViewID = ObjectIdentifier(webView)
        let firstTargetURL = URL(string: "https://first.example")!
        let latestTargetURL = URL(string: "https://latest.example")!
        var buffer = DeferredProtectedCommandBuffer()

        let firstOutcome = buffer.enqueue(.synchronizeTrackedNavigation(
            webViewID: webViewID,
            tabID: UUID(),
            windowID: UUID(),
            intent: DeferredWebViewNavigationIntent(
                revision: 1,
                targetURL: firstTargetURL
            )
        ))
        guard case .enqueued = firstOutcome else {
            return XCTFail("Expected the first navigation command to be enqueued")
        }

        let latestTabID = UUID()
        let latestWindowID = UUID()
        let latestOutcome = buffer.enqueue(.synchronizeTrackedNavigation(
            webViewID: webViewID,
            tabID: latestTabID,
            windowID: latestWindowID,
            intent: DeferredWebViewNavigationIntent(
                revision: 2,
                targetURL: latestTargetURL
            )
        ))
        guard case .collapsed = latestOutcome else {
            return XCTFail("Expected the newer navigation command to replace the same identity")
        }

        XCTAssertEqual(buffer.count, 1)
        guard case .synchronizeTrackedNavigation(
            let retainedWebViewID,
            let retainedTabID,
            let retainedWindowID,
            let retainedIntent
        ) = buffer.drain().first else {
            return XCTFail("Expected one retained cross-window navigation command")
        }
        XCTAssertEqual(retainedWebViewID, webViewID)
        XCTAssertEqual(retainedTabID, latestTabID)
        XCTAssertEqual(retainedWindowID, latestWindowID)
        XCTAssertEqual(retainedIntent.revision, 2)
        XCTAssertEqual(retainedIntent.targetURL, latestTargetURL)
    }

    func testDeferredNavigationHasGuaranteedDeliveryAtSoftCapacity() {
        let webView = NSObject()
        let webViewID = ObjectIdentifier(webView)
        var buffer = DeferredProtectedCommandBuffer()

        for _ in 0..<DeferredProtectedCommandBuffer.softCapacity {
            let outcome = buffer.enqueue(.cleanupWindow(windowID: UUID()))
            guard case .enqueued = outcome else {
                return XCTFail("Expected guaranteed setup command to be enqueued")
            }
        }

        let navigationOutcome = buffer.enqueue(.synchronizeTrackedNavigation(
            webViewID: webViewID,
            tabID: UUID(),
            windowID: UUID(),
            intent: DeferredWebViewNavigationIntent(
                revision: 1,
                targetURL: URL(string: "https://guaranteed.example")!
            )
        ))

        guard case .enqueued = navigationOutcome else {
            return XCTFail("Expected navigation to survive a full guaranteed-delivery buffer")
        }
        XCTAssertEqual(buffer.count, DeferredProtectedCommandBuffer.softCapacity + 1)
        XCTAssertTrue(buffer.drain().contains { command in
            guard case .synchronizeTrackedNavigation(let retainedID, _, _, _) = command else {
                return false
            }
            return retainedID == webViewID
        })
    }

    func testDeferredReloadOutranksURLSyncForTheSameSemanticRevision() {
        let webView = NSObject()
        let webViewID = ObjectIdentifier(webView)
        let tabID = UUID()
        let windowID = UUID()
        let targetURL = URL(string: "https://refresh.example")!
        var buffer = DeferredProtectedCommandBuffer()

        XCTAssertEqual(buffer.enqueue(.synchronizeTrackedNavigation(
            webViewID: webViewID,
            tabID: tabID,
            windowID: windowID,
            intent: .init(revision: 7, targetURL: targetURL)
        )), .enqueued)
        XCTAssertEqual(buffer.enqueue(.reloadTrackedNavigation(
            webViewID: webViewID,
            tabID: tabID,
            windowID: windowID,
            intent: .init(
                revision: 7,
                targetURL: targetURL,
                policy: .standard
            )
        )), .collapsed)
        XCTAssertEqual(buffer.enqueue(.synchronizeTrackedNavigation(
            webViewID: webViewID,
            tabID: tabID,
            windowID: windowID,
            intent: .init(revision: 7, targetURL: targetURL)
        )), .collapsed)

        guard case .reloadTrackedNavigation(_, _, _, let retainedIntent) = buffer.drain().first else {
            return XCTFail("The semantic refresh must survive a same-revision URL sync")
        }
        XCTAssertEqual(retainedIntent.revision, 7)
        XCTAssertEqual(retainedIntent.policy, .standard)
    }

    func testDeferredTrackedNavigationUsesRevisionBeforeOperationStrength() {
        let webView = NSObject()
        let webViewID = ObjectIdentifier(webView)
        let tabID = UUID()
        let windowID = UUID()
        let refreshedURL = URL(string: "https://refresh.example")!
        let newerURL = URL(string: "https://newer.example")!
        var buffer = DeferredProtectedCommandBuffer()

        _ = buffer.enqueue(.reloadTrackedNavigation(
            webViewID: webViewID,
            tabID: tabID,
            windowID: windowID,
            intent: .init(
                revision: 7,
                targetURL: refreshedURL,
                policy: .fromOrigin
            )
        ))
        XCTAssertEqual(buffer.enqueue(.synchronizeTrackedNavigation(
            webViewID: webViewID,
            tabID: tabID,
            windowID: windowID,
            intent: .init(revision: 8, targetURL: newerURL)
        )), .collapsed)
        XCTAssertEqual(buffer.enqueue(.reloadTrackedNavigation(
            webViewID: webViewID,
            tabID: tabID,
            windowID: windowID,
            intent: .init(
                revision: 7,
                targetURL: refreshedURL,
                policy: .fromOrigin
            )
        )), .collapsed)

        guard case .synchronizeTrackedNavigation(_, _, _, let retainedIntent) = buffer.drain().first else {
            return XCTFail("A newer semantic navigation must supersede an older hard reload")
        }
        XCTAssertEqual(retainedIntent.revision, 8)
        XCTAssertEqual(retainedIntent.targetURL, newerURL)
    }

    func testDeferredHardReloadOutranksStandardReloadAtEqualRevision() {
        let webView = NSObject()
        let webViewID = ObjectIdentifier(webView)
        let tabID = UUID()
        let windowID = UUID()
        let targetURL = URL(string: "https://refresh.example")!
        var buffer = DeferredProtectedCommandBuffer()

        _ = buffer.enqueue(.reloadTrackedNavigation(
            webViewID: webViewID,
            tabID: tabID,
            windowID: windowID,
            intent: .init(
                revision: 9,
                targetURL: targetURL,
                policy: .standard
            )
        ))
        _ = buffer.enqueue(.reloadTrackedNavigation(
            webViewID: webViewID,
            tabID: tabID,
            windowID: windowID,
            intent: .init(
                revision: 9,
                targetURL: targetURL,
                policy: .fromOrigin
            )
        ))
        _ = buffer.enqueue(.reloadTrackedNavigation(
            webViewID: webViewID,
            tabID: tabID,
            windowID: windowID,
            intent: .init(
                revision: 9,
                targetURL: targetURL,
                policy: .standard
            )
        ))

        guard case .reloadTrackedNavigation(_, _, _, let retainedIntent) = buffer.drain().first else {
            return XCTFail("Expected one retained reload")
        }
        XCTAssertEqual(retainedIntent.policy, .fromOrigin)
    }

    func testDeferredReloadHasGuaranteedDeliveryAtSoftCapacity() {
        let webView = NSObject()
        let webViewID = ObjectIdentifier(webView)
        var buffer = DeferredProtectedCommandBuffer()

        for _ in 0..<DeferredProtectedCommandBuffer.softCapacity {
            XCTAssertEqual(
                buffer.enqueue(.cleanupWindow(windowID: UUID())),
                .enqueued
            )
        }

        XCTAssertEqual(buffer.enqueue(.reloadTrackedNavigation(
            webViewID: webViewID,
            tabID: UUID(),
            windowID: UUID(),
            intent: .init(
                revision: 1,
                targetURL: URL(string: "https://guaranteed-reload.example")!,
                policy: .standard
            )
        )), .enqueued)
        XCTAssertEqual(
            buffer.count,
            DeferredProtectedCommandBuffer.softCapacity + 1
        )
        XCTAssertTrue(buffer.drain().contains {
            guard case .reloadTrackedNavigation(let retainedID, _, _, _) = $0 else {
                return false
            }
            return retainedID == webViewID
        })
    }
}
