import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabWebViewReplacementOwnerTests: XCTestCase {
    func testTrackedReplacementDelegatesWholeSetTransactionAndDoesNotCreateLocally() {
        let owner = TabWebViewReplacementOwner()
        let previousWebView = WKWebView()
        let targetURL = URL(string: "https://example.com/tracked")!
        var events: [String] = []

        let outcome = owner.replaceNormalWebView(
            targetURL: targetURL,
            reason: "tracked-success",
            context: makeContext(
                previousWebView: previousWebView,
                hasTrackedWebViews: true,
                rebuildTrackedWebViews: { url, reason, configuration in
                    XCTAssertEqual(url, targetURL)
                    XCTAssertEqual(reason, "tracked-success")
                    XCTAssertEqual(configuration, .normal)
                    events.append("cas")
                    return .committed
                },
                makeNormalTabWebView: { _ in
                    XCTFail("Tracked replacement creation belongs to the assignment transaction")
                    return nil
                },
                record: { events.append($0) }
            )
        )

        XCTAssertEqual(outcome, .replacedAndScheduledNavigation)
        XCTAssertEqual(events, ["cas"])
    }

    func testTrackedCommitFailurePreservesPermissionAndReportsFailure() {
        let owner = TabWebViewReplacementOwner()
        let previousWebView = WKWebView()
        var events: [String] = []

        let outcome = owner.replaceNormalWebView(
            targetURL: URL(string: "https://example.com/failure")!,
            reason: "tracked-failure",
            context: makeContext(
                previousWebView: previousWebView,
                hasTrackedWebViews: true,
                rebuildTrackedWebViews: { _, _, _ in
                    events.append("cas-failed")
                    return .failed
                },
                makeNormalTabWebView: { _ in
                    XCTFail("Tracked replacement creation belongs to the assignment transaction")
                    return nil
                },
                record: { events.append($0) }
            ),
            onReplacementFailure: {
                events.append("failure")
            }
        )

        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(events, ["cas-failed", "failure"])
    }

    func testProtectedTrackedReplacementDefersWithoutInvalidationOrFailureCallback() {
        let owner = TabWebViewReplacementOwner()
        let previousWebView = WKWebView()
        var events: [String] = []

        let outcome = owner.replaceCurrentWebView(
            targetURL: URL(string: "safari-web-extension://extension/page.html")!,
            reason: "protected-extension",
            configuration: .currentExtensionPage,
            context: makeContext(
                previousWebView: previousWebView,
                hasTrackedWebViews: true,
                rebuildTrackedWebViews: { _, _, configuration in
                    XCTAssertEqual(configuration, .currentExtensionPage)
                    events.append("defer")
                    return .deferred
                },
                makeNormalTabWebView: { _ in nil },
                record: { events.append($0) }
            ),
            makeReplacementWebView: { _ in
                XCTFail("Protected tracked replacement must not create a local provisional WebView")
                return nil
            },
            onReplacementFailure: {
                events.append("failure")
            }
        )

        XCTAssertEqual(outcome, .deferred)
        XCTAssertEqual(events, ["defer"])
    }

    func testUntrackedReplacementCommitsResidenceBeforeCleaningDisplacedWebView() {
        let owner = TabWebViewReplacementOwner()
        let previousWebView = WKWebView()
        let replacementWebView = WKWebView()
        var events: [String] = []

        let outcome = owner.replaceNormalWebView(
            targetURL: URL(string: "https://example.com/untracked")!,
            reason: "untracked",
            context: makeContext(
                previousWebView: previousWebView,
                hasTrackedWebViews: false,
                rebuildTrackedWebViews: { _, _, _ in
                    XCTFail("Detached replacement must not enter the tracked transaction")
                    return .failed
                },
                makeNormalTabWebView: { reason in
                    XCTAssertEqual(reason, "untracked")
                    events.append("make")
                    return replacementWebView
                },
                record: { events.append($0) }
            )
        )

        XCTAssertEqual(outcome, .replacedNavigationPending)
        XCTAssertEqual(events, ["make", "commitUntracked", "invalidate:untracked"])
    }

    func testProtectedUntrackedReplacementKeepsDisplacedWebViewLeasedUntilRelease() async throws {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let coordinator = WebViewCoordinator(webViewSessions: browserManager.webViewSessions)
        browserManager.windowRegistry = windowRegistry
        browserManager.bindTestWebViewCoordinator(coordinator)
        let tab = browserManager.tabManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/original")!,
            loadsCachedFaviconOnInit: false
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        let displaced = WKWebView()
        let replacement = WKWebView()
        let container = NSView()
        let registration = coordinator.compositorRuntime.registerContainer(
            container,
            for: UUID()
        )
        tab.replaceUntrackedWebView(displaced)
        let protectionLease = try XCTUnwrap(coordinator.protectionRuntime.beginVisualHandoff(
            for: displaced,
            containerRegistration: registration
        ))

        XCTAssertEqual(coordinator.ownershipService.replaceDetached(
            displaced,
            with: replacement,
            for: tab,
            reason: "test.protected-replacement"
        ), .committed)

        XCTAssertIdentical(tab.resolvedCurrentWebView(), replacement)
        guard case .pendingCleanup(let lease) = browserManager.webViewSessions.residence(of: displaced) else {
            return XCTFail("Displaced WebView must remain lease-owned")
        }
        XCTAssertEqual(lease.tabID, tab.id)

        coordinator.protectionRuntime.finishVisualHandoff(protectionLease)
        await drainMainQueue()

        XCTAssertNil(browserManager.webViewSessions.residence(of: displaced))
        XCTAssertIdentical(tab.resolvedCurrentWebView(), replacement)
        withExtendedLifetime((windowRegistry, container)) { /* keep weak bindings alive */ }
    }

    func testProtectedUntrackedReleaseKeepsWebViewLeasedUntilProtectionEnds() async throws {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let coordinator = WebViewCoordinator(webViewSessions: browserManager.webViewSessions)
        browserManager.windowRegistry = windowRegistry
        browserManager.bindTestWebViewCoordinator(coordinator)
        let tab = browserManager.tabManager.tabFactory.makeTab(loadsCachedFaviconOnInit: false)
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        let webView = WKWebView()
        let container = NSView()
        let registration = coordinator.compositorRuntime.registerContainer(
            container,
            for: UUID()
        )
        tab.replaceUntrackedWebView(webView)
        let protectionLease = try XCTUnwrap(coordinator.protectionRuntime.beginVisualHandoff(
            for: webView,
            containerRegistration: registration
        ))

        coordinator.ownershipService.releaseUntracked(for: tab)

        XCTAssertNil(tab.resolvedCurrentWebView())
        guard case .pendingCleanup(let lease) = browserManager.webViewSessions.residence(of: webView) else {
            return XCTFail("Released WebView must remain lease-owned")
        }
        XCTAssertEqual(lease.tabID, tab.id)

        coordinator.protectionRuntime.finishVisualHandoff(protectionLease)
        await drainMainQueue()

        XCTAssertNil(browserManager.webViewSessions.residence(of: webView))
        withExtendedLifetime((windowRegistry, container)) { /* keep weak bindings alive */ }
    }

    private func drainMainQueue() async {
        for _ in 0..<4 {
            await Task.yield()
        }
    }

    private func makeContext(
        previousWebView: WKWebView,
        hasTrackedWebViews: Bool,
        rebuildTrackedWebViews: @escaping (
            URL,
            String,
            DeferredWebViewRebuildConfiguration
        ) -> TabWebViewRebuildResult,
        makeNormalTabWebView: @escaping (String) -> WKWebView?,
        record: @escaping (String) -> Void
    ) -> TabWebViewReplacementContext {
        TabWebViewReplacementContext(
            existingWebView: { previousWebView },
            hasTrackedWebViews: { hasTrackedWebViews },
            rebuildTrackedWebViews: rebuildTrackedWebViews,
            makeNormalTabWebView: makeNormalTabWebView,
            invalidatePermissionPageForReplacement: { reason in
                record("invalidate:\(reason)")
            },
            cleanupCloneWebView: { webView in
                record("cleanup:\(ObjectIdentifier(webView))")
            },
            commitUntrackedReplacement: { previous, replacement, reason in
                XCTAssertIdentical(previous, previousWebView)
                XCTAssertNotIdentical(replacement, previousWebView)
                XCTAssertFalse(reason.isEmpty)
                record("commitUntracked")
                return .committed
            }
        )
    }
}
