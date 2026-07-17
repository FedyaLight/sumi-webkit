import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabWebViewReplacementServiceTests: XCTestCase {
    func testTrackedReplacementDelegatesWholeGenerationTransaction() {
        let fixture = makeTrackedFixture()
        let targetURL = URL(string: "https://example.com/tracked")!
        var calls: [TrackedCall] = []
        fixture.tab.navigationRuntime.webViewReplacementRuntime =
            TabWebViewReplacementRuntime(
                rebuildTrackedWebViews: {
                    tab, windowID, url, reason, configuration in
                    calls.append(
                        TrackedCall(
                            tabID: tab.id,
                            windowID: windowID,
                            url: url,
                            reason: reason,
                            configuration: configuration
                        )
                    )
                    return .committed
                },
                commitUntrackedReplacement: { _, _, _ in
                    XCTFail("Tracked replacement cannot use detached commit")
                    return .rejected
                }
            )

        let outcome = TabWebViewReplacementService()
            .replaceCurrentWebView(
                in: fixture.tab,
                targetURL: targetURL,
                reason: "tracked-success",
                configuration: .normal,
                makeReplacementWebView: { _ in
                    XCTFail("Tracked replacement creation belongs to the generation transaction")
                    return nil
                }
            )

        XCTAssertEqual(outcome, .replacedAndScheduledNavigation)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].tabID, fixture.tab.id)
        XCTAssertEqual(calls[0].windowID, fixture.windowID)
        XCTAssertEqual(calls[0].url, targetURL)
        XCTAssertEqual(calls[0].reason, "tracked-success")
        XCTAssertEqual(calls[0].configuration, .normal)
    }

    func testTrackedFailureDoesNotCreateDetachedCandidate() {
        let fixture = makeTrackedFixture()
        fixture.tab.navigationRuntime.webViewReplacementRuntime =
            TabWebViewReplacementRuntime(
                rebuildTrackedWebViews: { _, _, _, _, _ in .failed },
                commitUntrackedReplacement: { _, _, _ in .rejected }
            )

        let outcome = TabWebViewReplacementService()
            .replaceCurrentWebView(
                in: fixture.tab,
                targetURL: URL(string: "https://example.com/failure")!,
                reason: "tracked-failure",
                configuration: .normal,
                makeReplacementWebView: { _ in
                    XCTFail("Failed tracked transaction cannot fall back to detached replacement")
                    return nil
                }
            )

        XCTAssertEqual(outcome, .failed)
        XCTAssertIdentical(
            fixture.tab.resolvedCurrentWebView(),
            fixture.webView
        )
    }

    func testProtectedTrackedReplacementReportsDeferral() {
        let fixture = makeTrackedFixture()
        fixture.tab.navigationRuntime.webViewReplacementRuntime =
            TabWebViewReplacementRuntime(
                rebuildTrackedWebViews: {
                    _, _, _, _, configuration in
                    XCTAssertEqual(configuration, .currentExtensionPage)
                    return .deferred
                },
                commitUntrackedReplacement: { _, _, _ in .rejected }
            )

        let outcome = TabWebViewReplacementService()
            .replaceCurrentWebView(
                in: fixture.tab,
                targetURL: URL(
                    string: "safari-web-extension://extension/page.html"
                )!,
                reason: "protected-extension",
                configuration: .currentExtensionPage,
                makeReplacementWebView: { _ in
                    XCTFail("Deferred transaction cannot create a local candidate")
                    return nil
                }
            )

        XCTAssertEqual(outcome, .deferred)
    }

    func testDetachedReplacementCommitsExactCandidate() {
        let tab = Tab(url: URL(string: "https://example.com/original")!)
        let previous = WKWebView()
        let replacement = WKWebView()
        tab.replaceUntrackedWebView(previous)
        tab.navigationRuntime.webViewReplacementRuntime =
            TabWebViewReplacementRuntime(
                rebuildTrackedWebViews: { _, _, _, _, _ in .failed },
                commitUntrackedReplacement: {
                    runtimeTab, displaced, candidate in
                    XCTAssertIdentical(runtimeTab, tab)
                    XCTAssertIdentical(displaced, previous)
                    XCTAssertIdentical(candidate, replacement)
                    runtimeTab.replaceUntrackedWebView(candidate)
                    return .committed
                }
            )

        let outcome = TabWebViewReplacementService()
            .replaceCurrentWebView(
                in: tab,
                targetURL: URL(string: "https://example.com/replacement")!,
                reason: "detached",
                configuration: .normal,
                makeReplacementWebView: { _ in replacement }
            )

        XCTAssertEqual(outcome, .replacedNavigationPending)
        XCTAssertIdentical(tab.resolvedCurrentWebView(), replacement)
    }

    func testProtectedUntrackedReplacementKeepsDisplacedWebViewLeasedUntilRelease() async throws {
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(windowRegistry: windowRegistry)
        let webViewRuntime = browserManager.testWebViewRuntime()
        let tab = browserManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/original")!,
            loadsCachedFaviconOnInit: false
        )
        tab.attachBrowserRuntime(
            TabBrowserRuntimeFactory.make(for: browserManager)
        )
        let displaced = WKWebView()
        let replacement = WKWebView()
        let container = NSView()
        let registration = webViewRuntime.compositorRuntime
            .registerContainer(container, for: UUID())
        tab.replaceUntrackedWebView(displaced)
        let protectionLease = try XCTUnwrap(
            webViewRuntime.protectionRuntime.beginVisualHandoff(
                for: displaced,
                containerRegistration: registration
            )
        )

        XCTAssertEqual(
            webViewRuntime.detachedWebViewReplacement.replace(
                displaced,
                with: replacement,
                for: tab
            ),
            .committed
        )

        XCTAssertIdentical(tab.resolvedCurrentWebView(), replacement)
        guard case .pendingCleanup(let lease) =
            browserManager.webViewSessions.residence(of: displaced) else {
            return XCTFail("Displaced WebView must remain lease-owned")
        }
        XCTAssertEqual(lease.tabID, tab.id)

        webViewRuntime.protectionRuntime.finishVisualHandoff(
            protectionLease
        )
        await drainMainQueue()

        XCTAssertNil(
            browserManager.webViewSessions.residence(of: displaced)
        )
        XCTAssertIdentical(tab.resolvedCurrentWebView(), replacement)
        withExtendedLifetime((windowRegistry, container)) {}
    }

    func testProtectedUntrackedReleaseKeepsWebViewLeasedUntilProtectionEnds() async throws {
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(windowRegistry: windowRegistry)
        let webViewRuntime = browserManager.testWebViewRuntime()
        let tab = browserManager.tabFactory.makeTab(
            loadsCachedFaviconOnInit: false
        )
        tab.attachBrowserRuntime(
            TabBrowserRuntimeFactory.make(for: browserManager)
        )
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        let container = NSView()
        let registration = webViewRuntime.compositorRuntime
            .registerContainer(container, for: UUID())
        tab.replaceUntrackedWebView(webView)
        let protectionLease = try XCTUnwrap(
            webViewRuntime.protectionRuntime.beginVisualHandoff(
                for: webView,
                containerRegistration: registration
            )
        )

        webViewRuntime.detachedWebViewCleanup.releaseUntracked(for: tab)

        XCTAssertNil(tab.resolvedCurrentWebView())
        guard case .pendingCleanup(let lease) =
            browserManager.webViewSessions.residence(of: webView) else {
            return XCTFail("Released WebView must remain lease-owned")
        }
        XCTAssertEqual(lease.tabID, tab.id)

        webViewRuntime.protectionRuntime.finishVisualHandoff(
            protectionLease
        )
        await drainMainQueue()

        XCTAssertNil(browserManager.webViewSessions.residence(of: webView))
        withExtendedLifetime((windowRegistry, container)) {}
    }

    private func makeTrackedFixture() -> (
        browserManager: BrowserManager,
        tab: Tab,
        webView: WKWebView,
        windowID: UUID
    ) {
        let browserManager = BrowserManager()
        let tab = browserManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/original")!,
            loadsCachedFaviconOnInit: false
        )
        tab.attachBrowserRuntime(
            TabBrowserRuntimeFactory.make(for: browserManager)
        )
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        let windowID = UUID()
        let webViewRuntime = browserManager.testWebViewRuntime()
        let trackedAdmission = webViewRuntime.trackedWebViewAdmission
        XCTAssertEqual(
            webViewRuntime.untrackedWebViewInstallationService.installUntracked(
                webView,
                for: tab
            ),
            .committed
        )
        trackedAdmission.attemptAssignment(
            webView,
            to: tab,
            in: windowID,
            replaySemanticOperation: { XCTFail("Unexpected WebView deferral") }
        )
        XCTAssertEqual(tab.resolvedPrimaryWindowId(), windowID)
        return (browserManager, tab, webView, windowID)
    }

    private func drainMainQueue() async {
        for _ in 0..<4 { await Task.yield() }
    }
}

private struct TrackedCall {
    let tabID: UUID
    let windowID: UUID?
    let url: URL
    let reason: String
    let configuration: DeferredWebViewRebuildConfiguration
}
