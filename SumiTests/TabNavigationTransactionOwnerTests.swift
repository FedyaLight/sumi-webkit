import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabNavigationTransactionOwnerTests: XCTestCase {
    func testPreparedNavigationRunsOnlyAfterPreparation() async {
        let owner = TabNavigationTransactionOwner()
        let webView = WKWebView(frame: .zero)
        var preparation: CheckedContinuation<Void, Never>?
        var loadedWebViews: [WKWebView] = []

        owner.performAfterPreparation(
            on: webView,
            prepare: {
                await withCheckedContinuation { continuation in
                    preparation = continuation
                }
            },
            performLoad: { loadedWebViews.append($0) }
        )

        await waitUntil { preparation != nil }
        XCTAssertTrue(loadedWebViews.isEmpty)

        preparation?.resume()
        await drainMainActorTasks()

        XCTAssertEqual(loadedWebViews.count, 1)
        XCTAssertIdentical(loadedWebViews.first, webView)
    }

    func testCancelSuppressesPreparedNavigationLoad() async {
        let owner = TabNavigationTransactionOwner()
        let webView = WKWebView(frame: .zero)
        var preparation: CheckedContinuation<Void, Never>?
        var didLoad = false

        owner.performAfterPreparation(
            on: webView,
            prepare: {
                await withCheckedContinuation { continuation in
                    preparation = continuation
                }
            },
            performLoad: { _ in didLoad = true }
        )

        await waitUntil { preparation != nil }
        owner.cancelPendingMainFrameNavigation()
        preparation?.resume()
        await drainMainActorTasks()

        XCTAssertFalse(didLoad)
    }

    func testImmediateNavigationSupersedesPreparedNavigation() async {
        let owner = TabNavigationTransactionOwner()
        let webView = WKWebView(frame: .zero)
        var preparation: CheckedContinuation<Void, Never>?
        var loadEvents: [String] = []

        owner.performAfterPreparation(
            on: webView,
            prepare: {
                await withCheckedContinuation { continuation in
                    preparation = continuation
                }
            },
            performLoad: { _ in loadEvents.append("prepared") }
        )
        await waitUntil { preparation != nil }

        owner.perform(
            on: webView,
            performLoad: { _ in
                loadEvents.append("immediate")
                return true
            }
        )
        preparation?.resume()
        await drainMainActorTasks()

        XCTAssertEqual(loadEvents, ["immediate"])
    }

    func testCancellationCallbackCanScheduleReplacementWithoutBeingErased() async {
        let owner = TabNavigationTransactionOwner()
        let webView = WKWebView(frame: .zero)
        var oldPreparation: CheckedContinuation<Void, Never>?
        var replacementDidLoad = false

        owner.performAfterPreparation(
            on: webView,
            prepare: {
                await withCheckedContinuation { continuation in
                    oldPreparation = continuation
                }
            },
            didCancel: {
                owner.performAfterPreparation(
                    on: webView,
                    prepare: {},
                    performLoad: { _ in replacementDidLoad = true }
                )
            },
            performLoad: { _ in
                XCTFail("Cancelled preparation must not load")
            }
        )
        await waitUntil { oldPreparation != nil }

        owner.cancelPendingMainFrameNavigation()
        oldPreparation?.resume()
        await drainMainActorTasks()

        XCTAssertTrue(replacementDidLoad)
    }

    func testCancellationCallbackRemainsExactlyOnceAfterOwnerDeallocation() async {
        var owner: TabNavigationTransactionOwner? = TabNavigationTransactionOwner()
        let webView = WKWebView(frame: .zero)
        var preparation: CheckedContinuation<Void, Never>?
        var cancellationCount = 0

        owner?.performAfterPreparation(
            on: webView,
            prepare: {
                await withCheckedContinuation { continuation in
                    preparation = continuation
                }
            },
            didCancel: {
                cancellationCount += 1
            },
            performLoad: { _ in
                XCTFail("Cancelled preparation must not load")
            }
        )
        await waitUntil { preparation != nil }

        owner?.cancelPendingMainFrameNavigation()
        owner = nil
        preparation?.resume()
        await drainMainActorTasks()

        XCTAssertEqual(cancellationCount, 1)
    }

    func testSynchronousLoadCanSchedulePreparedReplacementWithoutBeingErased() async {
        let owner = TabNavigationTransactionOwner()
        let webView = WKWebView(frame: .zero)
        var replacementDidLoad = false

        XCTAssertTrue(owner.perform(on: webView) { _ in
            owner.performAfterPreparation(
                on: webView,
                prepare: {},
                performLoad: { _ in replacementDidLoad = true }
            )
            return true
        })
        await drainMainActorTasks()

        XCTAssertTrue(replacementDidLoad)
    }

    func testBackForwardNavigationSupersedesPreparedNavigation() async {
        let owner = TabNavigationTransactionOwner()
        let webView = WKWebView(frame: .zero)
        var preparation: CheckedContinuation<Void, Never>?
        var didLoad = false

        owner.performAfterPreparation(
            on: webView,
            prepare: {
                await withCheckedContinuation { continuation in
                    preparation = continuation
                }
            },
            performLoad: { _ in didLoad = true }
        )
        await waitUntil { preparation != nil }

        owner.beginBackForwardNavigationTracking(
            on: webView,
            environment: makeHistorySwipeEnvironment(currentWebView: { webView })
        )
        preparation?.resume()
        await drainMainActorTasks()

        XCTAssertFalse(didLoad)
        XCTAssertEqual(owner.pendingMainFrameNavigationKind, .backForward)
        XCTAssertTrue(owner.isFreezingNavDuringBackForwardGesture)
    }

    func testBackForwardTrackingSetsAndClearsTransactionState() {
        let owner = TabNavigationTransactionOwner()
        let webView = WKWebView(frame: .zero)
        var beganProtection = false
        var finishedProtection = false
        var updatedNavigationState = false

        owner.beginBackForwardNavigationTracking(
            on: webView,
            environment: makeHistorySwipeEnvironment(
                currentWebView: { webView },
                beginHistorySwipeProtection: { _, _, _, _ in
                    beganProtection = true
                },
                finishHistorySwipeProtection: { _, _, _, _ in
                    finishedProtection = true
                    return false
                },
                updateNavStateIfCurrentWebViewExists: {
                    updatedNavigationState = true
                }
            )
        )

        XCTAssertTrue(beganProtection)
        XCTAssertEqual(owner.pendingMainFrameNavigationKind, .backForward)
        XCTAssertTrue(owner.isFreezingNavDuringBackForwardGesture)

        owner.finishBackForwardNavigationTracking(
            using: webView,
            environment: makeHistorySwipeEnvironment(
                currentWebView: { webView },
                finishHistorySwipeProtection: { _, _, _, _ in
                    finishedProtection = true
                    return false
                },
                updateNavStateIfCurrentWebViewExists: {
                    updatedNavigationState = true
                }
            )
        )

        XCTAssertTrue(finishedProtection)
        XCTAssertNil(owner.pendingMainFrameNavigationKind)
        XCTAssertFalse(owner.isFreezingNavDuringBackForwardGesture)
        XCTAssertTrue(updatedNavigationState)
    }

    func testRegularNavigationFinishesActiveHistorySwipeBeforeMarkingLoad() {
        let owner = TabNavigationTransactionOwner()
        let webView = WKWebView(frame: .zero)
        let windowId = UUID()
        var events: [String] = []

        owner.beginBackForwardNavigationTracking(
            on: webView,
            environment: makeHistorySwipeEnvironment(currentWebView: { webView })
        )
        owner.markRegularMainFrameNavigation(
            on: webView,
            environment: makeHistorySwipeEnvironment(
                currentWebView: { webView },
                windowIDContaining: { _ in windowId },
                finishHistorySwipeProtection: { _, _, _, _ in
                    events.append("finish-protection")
                    return false
                },
                flushWindowMutationsAfterHistorySwipe: { id in
                    events.append("flush-\(id)")
                },
                updateNavStateIfCurrentWebViewExists: {
                    events.append("update-navigation")
                }
            )
        )

        XCTAssertEqual(owner.pendingMainFrameNavigationKind, .load)
        XCTAssertFalse(owner.isFreezingNavDuringBackForwardGesture)
        XCTAssertEqual(events, [
            "finish-protection",
            "flush-\(windowId)",
            "update-navigation",
        ])
    }

    func testSubmissionDoesNotEraseHistorySwipeBeforeLifecycleSettlesIt() {
        let owner = TabNavigationTransactionOwner()
        let webView = WKWebView(frame: .zero)
        var finishCount = 0

        owner.beginBackForwardNavigationTracking(
            on: webView,
            environment: makeHistorySwipeEnvironment(currentWebView: { webView })
        )
        XCTAssertTrue(owner.perform(on: webView) { _ in true })
        XCTAssertTrue(owner.isFreezingNavDuringBackForwardGesture)

        owner.markRegularMainFrameNavigation(
            on: webView,
            environment: makeHistorySwipeEnvironment(
                currentWebView: { webView },
                finishHistorySwipeProtection: { _, _, _, _ in
                    finishCount += 1
                    return false
                }
            )
        )

        XCTAssertEqual(finishCount, 1)
        XCTAssertFalse(owner.isFreezingNavDuringBackForwardGesture)
        XCTAssertEqual(owner.pendingMainFrameNavigationKind, .load)
    }

    func testCancellationSettlesExactSwipeSourceAfterCurrentWebViewChanges() {
        let owner = TabNavigationTransactionOwner()
        let protectedWebView = WKWebView(frame: .zero)
        let newCurrentWebView = WKWebView(frame: .zero)
        let protectedWindowID = UUID()
        let newCurrentWindowID = UUID()
        var finishedWebViews: [WKWebView] = []
        var flushedWindowIDs: [UUID] = []
        let environment = makeHistorySwipeEnvironment(
            currentWebView: { newCurrentWebView },
            windowIDContaining: { candidate in
                candidate === protectedWebView
                    ? protectedWindowID
                    : newCurrentWindowID
            },
            finishHistorySwipeProtection: { _, webView, _, _ in
                if let webView { finishedWebViews.append(webView) }
                return false
            },
            flushWindowMutationsAfterHistorySwipe: {
                flushedWindowIDs.append($0)
            }
        )

        owner.beginBackForwardNavigationTracking(
            on: protectedWebView,
            environment: environment
        )
        owner.cancelPendingMainFrameNavigation(environment: environment)

        XCTAssertEqual(finishedWebViews.count, 1)
        XCTAssertIdentical(finishedWebViews.first, protectedWebView)
        XCTAssertEqual(flushedWindowIDs, [protectedWindowID])
        XCTAssertFalse(owner.isFreezingNavDuringBackForwardGesture)
    }

    func testOverlappingSwipeFinishesFirstExactSourceBeforeProtectingSecond() {
        let owner = TabNavigationTransactionOwner()
        let firstWebView = WKWebView(frame: .zero)
        let secondWebView = WKWebView(frame: .zero)
        var beganWebViews: [WKWebView] = []
        var finishedWebViews: [WKWebView] = []
        let environment = makeHistorySwipeEnvironment(
            currentWebView: { secondWebView },
            beginHistorySwipeProtection: { _, webView, _, _ in
                beganWebViews.append(webView)
            },
            finishHistorySwipeProtection: { _, webView, _, _ in
                if let webView { finishedWebViews.append(webView) }
                return false
            }
        )

        owner.beginBackForwardNavigationTracking(
            on: firstWebView,
            environment: environment
        )
        owner.beginBackForwardNavigationTracking(
            on: secondWebView,
            environment: environment
        )

        XCTAssertEqual(beganWebViews.count, 2)
        XCTAssertIdentical(beganWebViews[0], firstWebView)
        XCTAssertIdentical(beganWebViews[1], secondWebView)
        XCTAssertEqual(finishedWebViews.count, 1)
        XCTAssertIdentical(finishedWebViews[0], firstWebView)
        XCTAssertTrue(owner.isFreezingNavDuringBackForwardGesture)

        owner.finishBackForwardNavigationTracking(
            using: secondWebView,
            environment: environment
        )
        XCTAssertEqual(finishedWebViews.count, 2)
        XCTAssertIdentical(finishedWebViews[1], secondWebView)
    }

    func testFinishCancelledHistorySwipeCancelsDeferredWindowMutations() {
        let owner = TabNavigationTransactionOwner()
        let webView = WKWebView(frame: .zero)
        let windowId = UUID()
        var events: [String] = []

        owner.beginBackForwardNavigationTracking(
            on: webView,
            environment: makeHistorySwipeEnvironment(currentWebView: { webView })
        )
        owner.finishBackForwardNavigationTracking(
            using: webView,
            environment: makeHistorySwipeEnvironment(
                currentWebView: { webView },
                windowIDContaining: { _ in windowId },
                finishHistorySwipeProtection: { _, _, _, _ in
                    events.append("finish-protection")
                    return true
                },
                cancelWindowMutationsAfterHistorySwipe: { id in
                    events.append("cancel-\(id)")
                },
                flushWindowMutationsAfterHistorySwipe: { _ in
                    XCTFail("Cancelled swipes must not flush deferred window mutations")
                }
            )
        )

        XCTAssertNil(owner.pendingMainFrameNavigationKind)
        XCTAssertFalse(owner.isFreezingNavDuringBackForwardGesture)
        XCTAssertEqual(events, [
            "finish-protection",
            "cancel-\(windowId)",
        ])
    }

    func testSameDocumentSettleAppliesDeferredActionsAfterSuccessfulMove() async {
        let owner = TabNavigationTransactionOwner()
        let webView = WKWebView(frame: .zero)
        let originURL = URL(string: "https://example.com/watch?v=1")!
        let targetURL = URL(string: "https://example.com/watch?v=2")!
        var events: [String] = []
        let didSettle = expectation(
            description: "same-document move settled"
        )

        owner.beginBackForwardNavigationTracking(
            on: webView,
            environment: makeHistorySwipeEnvironment(currentURL: { originURL })
        )
        await loadHTML("<!doctype html><html><body>target</body></html>", baseURL: targetURL, into: webView)

        owner.scheduleBackForwardSameDocumentSettle(
            using: webView,
            environment: makeHistorySwipeEnvironment(
                currentWebView: { webView },
                finishHistorySwipeProtection: { _, _, _, _ in
                    events.append("finish-protection")
                    return false
                },
                scheduleRuntimeStatePersistence: {
                    events.append("persist")
                },
                syncAcrossWindows: { _ in
                    events.append("sync")
                    didSettle.fulfill()
                }
            )
        )

        await fulfillment(of: [didSettle], timeout: 5)

        XCTAssertNil(owner.pendingMainFrameNavigationKind)
        XCTAssertFalse(owner.isFreezingNavDuringBackForwardGesture)
        XCTAssertEqual(events, [
            "finish-protection",
            "persist",
            "sync",
        ])
    }

    func testSameDocumentSettleSkipsDeferredActionsWhenHistoryDidNotMove() async {
        let owner = TabNavigationTransactionOwner()
        let webView = WKWebView(frame: .zero)
        let originURL = URL(string: "https://example.com/watch?v=1")!
        var events: [String] = []
        let didSettle = expectation(
            description: "unchanged same-document navigation settled"
        )

        await loadHTML("<!doctype html><html><body>origin</body></html>", baseURL: originURL, into: webView)
        owner.beginBackForwardNavigationTracking(
            on: webView,
            environment: makeHistorySwipeEnvironment()
        )
        owner.scheduleBackForwardSameDocumentSettle(
            using: webView,
            environment: makeHistorySwipeEnvironment(
                currentWebView: { webView },
                finishHistorySwipeProtection: { _, _, _, _ in
                    events.append("finish-protection")
                    didSettle.fulfill()
                    return false
                },
                scheduleRuntimeStatePersistence: {
                    XCTFail("Cancelled same-document settle must not persist runtime state")
                },
                syncAcrossWindows: { _ in
                    XCTFail("Cancelled same-document settle must not sync across windows")
                }
            )
        )

        await fulfillment(of: [didSettle], timeout: 5)

        XCTAssertNil(owner.pendingMainFrameNavigationKind)
        XCTAssertFalse(owner.isFreezingNavDuringBackForwardGesture)
        XCTAssertEqual(events, ["finish-protection"])
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<20 {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for condition", file: file, line: line)
    }

    private func drainMainActorTasks() async {
        for _ in 0..<3 {
            await Task.yield()
        }
    }

    private func loadHTML(
        _ html: String,
        baseURL: URL,
        into webView: WKWebView
    ) async {
        let didFinish = expectation(description: "transaction test page loaded")
        let delegate = NavigationDelegateBox {
            didFinish.fulfill()
        }

        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: baseURL)
        await fulfillment(of: [didFinish], timeout: 5.0)
        webView.navigationDelegate = nil
    }

    private func makeHistorySwipeEnvironment(
        tabId: UUID = UUID(),
        currentWebView: @escaping @MainActor () -> WKWebView? = { nil },
        currentURL: @escaping @MainActor () -> URL? = { nil },
        windowIDContaining: @escaping @MainActor (WKWebView) -> UUID? = { _ in nil },
        beginHistorySwipeProtection: @escaping @MainActor (
            UUID,
            WKWebView,
            URL?,
            WKBackForwardListItem?
        ) -> Void = { _, _, _, _ in /* No-op. */ },
        finishHistorySwipeProtection: @escaping @MainActor (
            UUID,
            WKWebView?,
            URL?,
            WKBackForwardListItem?
        ) -> Bool = { _, _, _, _ in false },
        cancelWindowMutationsAfterHistorySwipe: @escaping @MainActor (UUID) -> Void = { _ in /* No-op. */ },
        flushWindowMutationsAfterHistorySwipe: @escaping @MainActor (UUID) -> Void = { _ in /* No-op. */ },
        updateNavStateIfCurrentWebViewExists: @escaping @MainActor () -> Void = { /* No-op. */ },
        scheduleRuntimeStatePersistence: @escaping @MainActor () -> Void = { /* No-op. */ },
        syncAcrossWindows: @escaping @MainActor (WKWebView) -> Void = { _ in /* No-op. */ }
    ) -> TabNavigationTransactionOwner.HistorySwipeEnvironment {
        TabNavigationTransactionOwner.HistorySwipeEnvironment(
            tabId: tabId,
            currentWebView: currentWebView,
            currentURL: currentURL,
            windowIDContaining: windowIDContaining,
            beginHistorySwipeProtection: beginHistorySwipeProtection,
            finishHistorySwipeProtection: finishHistorySwipeProtection,
            cancelWindowMutationsAfterHistorySwipe: cancelWindowMutationsAfterHistorySwipe,
            flushWindowMutationsAfterHistorySwipe: flushWindowMutationsAfterHistorySwipe,
            updateNavStateIfCurrentWebViewExists: updateNavStateIfCurrentWebViewExists,
            scheduleRuntimeStatePersistence: scheduleRuntimeStatePersistence,
            syncAcrossWindows: syncAcrossWindows
        )
    }
}

private final class NavigationDelegateBox: NSObject, WKNavigationDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func webView(
        _: WKWebView,
        didFinish _: WKNavigation?
    ) {
        onFinish()
    }
}
