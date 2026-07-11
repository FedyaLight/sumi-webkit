import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiTabLifecycleReentrancyTests: XCTestCase {
    func testCommitStopsWhenLocalPreparationStartsSuccessorIntent() {
        let fixture = makeFixture()
        let successorURL = URL(string: "https://successor.example/local")!
        fixture.runtime.prepareExtensionWebViewHook = { [weak tab = fixture.tab] _, _ in
            _ = tab?.beginMainFrameNavigationIntent(to: successorURL)
        }

        fixture.responder.navigationDidCommit(fixture.context)

        XCTAssertEqual(fixture.tab.mainFrameLoads.currentIntent.targetURL, successorURL)
        XCTAssertNil(
            fixture.tab.committedDocumentRuntime.lease(for: fixture.webView)
        )
        XCTAssertTrue(fixture.runtime.markedEligibleTabIds.isEmpty)
    }

    func testCommitStopsWhenAuthorityPreparationStartsSuccessorIntent() {
        let fixture = makeFixture()
        let successorURL = URL(string: "https://successor.example/authority")!
        fixture.runtime.prepareExtensionRuntimeBeforeCommitHook = {
            tab,
            _ in
            _ = tab.beginMainFrameNavigationIntent(to: successorURL)
        }

        fixture.responder.navigationDidCommit(fixture.context)

        XCTAssertEqual(fixture.tab.mainFrameLoads.currentIntent.targetURL, successorURL)
        XCTAssertNil(
            fixture.tab.committedDocumentRuntime.lease(for: fixture.webView)
        )
        XCTAssertTrue(fixture.runtime.markedEligibleTabIds.isEmpty)
    }

    func testFinishStopsWhenPreflightStartsSuccessorIntent() {
        let fixture = makeFixture()
        let successorURL = URL(string: "https://successor.example/preflight")!
        fixture.runtime.loadZoomHook = { [weak tab = fixture.tab] _, _ in
            _ = tab?.beginMainFrameNavigationIntent(to: successorURL)
        }

        fixture.responder.navigationDidFinish(fixture.context)

        XCTAssertEqual(fixture.tab.mainFrameLoads.currentIntent.targetURL, successorURL)
        XCTAssertNil(
            fixture.tab.committedDocumentRuntime.lease(for: fixture.webView)
        )
        XCTAssertNotEqual(fixture.tab.loadingState, .didFinish)
        XCTAssertTrue(fixture.runtime.siteDataPolicyTabIds.isEmpty)
        XCTAssertTrue(fixture.runtime.documentSuspensionReconcileTabIds.isEmpty)
    }

    func testFinishCannotPublishAfterCommitEffectStartsSuccessorIntent() {
        let fixture = makeFixture()
        let successorURL = URL(string: "https://successor.example/commit-effect")!
        fixture.runtime.markExtensionEligibleAfterCommitHook = {
            tab in
            _ = tab.beginMainFrameNavigationIntent(to: successorURL)
        }

        fixture.responder.navigationDidFinish(fixture.context)

        XCTAssertEqual(fixture.tab.mainFrameLoads.currentIntent.targetURL, successorURL)
        XCTAssertNotEqual(fixture.tab.loadingState, .didFinish)
        XCTAssertTrue(fixture.runtime.siteDataPolicyTabIds.isEmpty)
        XCTAssertTrue(fixture.runtime.documentSuspensionReconcileTabIds.isEmpty)
    }

    func testDuplicateCommitPublishesSharedEffectsOnce() {
        let fixture = makeFixture()

        fixture.responder.navigationDidCommit(fixture.context)
        fixture.responder.navigationDidCommit(fixture.context)

        XCTAssertNotNil(
            fixture.tab.committedDocumentRuntime.lease(for: fixture.webView)
        )
        XCTAssertEqual(fixture.runtime.markedEligibleTabIds, [fixture.tab.id])
    }

    func testDuplicateFinishPublishesSharedEffectsOnce() {
        let fixture = makeFixture()

        fixture.responder.navigationDidFinish(fixture.context)
        fixture.responder.navigationDidFinish(fixture.context)

        XCTAssertEqual(fixture.tab.loadingState, .didFinish)
        XCTAssertEqual(fixture.runtime.siteDataPolicyTabIds, [fixture.tab.id])
        XCTAssertEqual(
            fixture.runtime.documentSuspensionReconcileTabIds,
            [fixture.tab.id]
        )
    }

    private func makeFixture() -> Fixture {
        let initialURL = URL(string: "https://initial.example/page")!
        let targetURL = URL(string: "https://target.example/page")!
        let tab = Tab(url: initialURL, loadsCachedFaviconOnInit: false)
        let runtime = RecordingTabLifecycleNavigationRuntime()
        tab.navigationRuntime.lifecycleNavigationRuntime = runtime.runtime
        let webView = SumiNavigationURLReportingWebView(frame: .zero)
        webView.reportedURL = targetURL
        let navigation = NSObject()
        let context = SumiNavigationContext(
            navigationID: ObjectIdentifier(navigation),
            navigationLifetime: navigation,
            action: nil,
            url: targetURL,
            isCurrent: true,
            isCommitted: false,
            isMainFrame: true,
            webView: webView
        )
        XCTAssertEqual(
            tab.beginMainFrameLifecycle(
                from: webView,
                navigationID: context.navigationID,
                navigationLifetime: navigation,
                targetURL: targetURL,
                allowsUserInitiatedSupersession: false,
                continuationKind: nil
            ),
            .authority
        )
        return Fixture(
            tab: tab,
            runtime: runtime,
            responder: tab.makeMainFrameLifecycleResponder(),
            webView: webView,
            context: context
        )
    }

    private struct Fixture {
        let tab: Tab
        let runtime: RecordingTabLifecycleNavigationRuntime
        let responder: SumiTabLifecycleNavigationResponder
        let webView: WKWebView
        let context: SumiNavigationContext
    }
}
