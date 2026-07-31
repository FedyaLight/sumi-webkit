import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiTabLifecycleReentrancyTests: XCTestCase {
    func testDidStartStopsBeforeAuthorityPreparationWhenSharedStartBecomesStale() {
        let fixture = makeFixture()
        let successorURL = URL(string: "https://successor.example/shared-start")!
        fixture.runtime.resetRevisitProtectionHook = { tab in
            _ = tab.beginMainFrameNavigationIntent(to: successorURL)
        }

        fixture.responder.navigationDidStart(fixture.context)

        XCTAssertEqual(fixture.tab.mainFrameLoads.currentIntent.targetURL, successorURL)
        XCTAssertTrue(fixture.runtime.beforeCommitURLs.isEmpty)
        XCTAssertEqual(fixture.tab.url, fixture.initialURL)
    }

    func testDidStartStopsAfterReentrantLoadingNotification() {
        let fixture = makeFixture()
        let successorURL = URL(string: "https://successor.example/loading-notification")!
        let properties = NavigationRecordingTabExtensionPropertiesRuntime()
        properties.notifyHook = { tab, _ in
            _ = tab.beginMainFrameNavigationIntent(to: successorURL)
        }
        fixture.tab.navigationRuntime.extensionPropertiesRuntime = properties.runtime

        fixture.responder.navigationDidStart(fixture.context)

        XCTAssertEqual(fixture.tab.mainFrameLoads.currentIntent.targetURL, successorURL)
        XCTAssertEqual(properties.properties.count, 1)
        XCTAssertEqual(fixture.tab.url, fixture.initialURL)
    }

    func testStartPreparationUsesCanonicalParticipantTarget() {
        let fixture = makeFixture()
        let staleCallbackURL = URL(string: "https://stale-callback.example/page")!
        let staleContext = SumiNavigationContext(
            navigationID: fixture.context.navigationID,
            navigationLifetime: fixture.context.navigationLifetime,
            action: nil,
            url: staleCallbackURL,
            isCurrent: true,
            isCommitted: false,
            isMainFrame: true,
            webView: fixture.webView
        )

        fixture.responder.navigationDidStart(staleContext)

        XCTAssertEqual(fixture.runtime.preparedExtensionURLs, [fixture.targetURL])
        XCTAssertEqual(fixture.runtime.beforeCommitURLs, [fixture.targetURL])
    }

    func testReentrantCommitInvalidatesPrecommitStartLease() {
        let fixture = makeFixture()
        let properties = NavigationRecordingTabExtensionPropertiesRuntime()
        fixture.tab.navigationRuntime.extensionPropertiesRuntime = properties.runtime
        fixture.runtime.resetRevisitProtectionHook = { [weak responder = fixture.responder] _ in
            responder?.navigationDidCommit(fixture.context)
        }

        fixture.responder.navigationDidStart(fixture.context)

        XCTAssertEqual(fixture.tab.loadingState, .didCommit)
        XCTAssertEqual(fixture.runtime.resetRevisitProtectionTabIds, [fixture.tab.id])
        XCTAssertEqual(fixture.runtime.beforeCommitURLs, [fixture.targetURL])
        XCTAssertEqual(properties.properties.count, 2)
    }

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
        let properties = NavigationRecordingTabExtensionPropertiesRuntime()
        fixture.tab.navigationRuntime.extensionPropertiesRuntime = properties.runtime
        var syncedTabIDs: [UUID] = []
        var routing = TabWebViewRoutingRuntime.inactive
        routing.syncTabAcrossWindows = { tabID, _ in
            syncedTabIDs.append(tabID)
        }
        fixture.tab.navigationRuntime.webViewRouting = routing
        fixture.runtime.markExtensionEligibleAfterCommitHook = {
            tab in
            _ = tab.beginMainFrameNavigationIntent(to: successorURL)
        }

        fixture.responder.navigationDidFinish(fixture.context)

        XCTAssertEqual(fixture.tab.mainFrameLoads.currentIntent.targetURL, successorURL)
        XCTAssertNotEqual(fixture.tab.loadingState, .didFinish)
        XCTAssertTrue(syncedTabIDs.isEmpty)
        XCTAssertEqual(properties.properties.count, 1)
        XCTAssertTrue(fixture.runtime.siteDataPolicyTabIds.isEmpty)
        XCTAssertTrue(fixture.runtime.documentSuspensionReconcileTabIds.isEmpty)
    }

    func testFinishTailStopsWhenPersistenceCallbackStartsSuccessorIntent() {
        let fixture = makeFixture()
        let successorURL = URL(string: "https://successor.example/persistence")!
        let properties = NavigationRecordingTabExtensionPropertiesRuntime()
        fixture.tab.navigationRuntime.extensionPropertiesRuntime = properties.runtime
        var persistence = TabRuntimePersistenceCallbacks.inactive
        persistence.scheduleRuntimeStatePersistence = { [weak tab = fixture.tab] _ in
            _ = tab?.beginMainFrameNavigationIntent(to: successorURL)
        }
        fixture.tab.navigationRuntime.persistenceCallbacks = persistence
        fixture.responder.navigationDidFinish(fixture.context)

        XCTAssertEqual(
            fixture.tab.mainFrameLoads.currentIntent.targetURL,
            successorURL
        )
        XCTAssertEqual(fixture.tab.loadingState, .didFinish)
        XCTAssertTrue(fixture.runtime.documentSuspensionReconcileTabIds.isEmpty)
        XCTAssertTrue(fixture.runtime.siteDataPolicyTabIds.isEmpty)
        XCTAssertNotEqual(
            properties.properties.last,
            [.URL, .title, .loading]
        )
    }

    func testFinishTailStopsAfterReentrantFinishLoadingNotification() {
        let fixture = makeFixture()
        let successorURL = URL(string: "https://successor.example/finish-loading")!
        var persistenceScheduleCount = 0
        var persistence = TabRuntimePersistenceCallbacks.inactive
        persistence.scheduleRuntimeStatePersistence = { _ in
            persistenceScheduleCount += 1
        }
        fixture.tab.navigationRuntime.persistenceCallbacks = persistence
        let properties = NavigationRecordingTabExtensionPropertiesRuntime()
        properties.notifyHook = { [weak tab = fixture.tab] _, _ in
            guard tab?.loadingState == .didFinish else { return }
            _ = tab?.beginMainFrameNavigationIntent(to: successorURL)
        }
        fixture.tab.navigationRuntime.extensionPropertiesRuntime = properties.runtime

        fixture.responder.navigationDidFinish(fixture.context)

        XCTAssertEqual(
            fixture.tab.mainFrameLoads.currentIntent.targetURL,
            successorURL
        )
        XCTAssertEqual(fixture.tab.loadingState, .didFinish)
        XCTAssertEqual(persistenceScheduleCount, 0)
        XCTAssertTrue(fixture.runtime.documentSuspensionReconcileTabIds.isEmpty)
        XCTAssertTrue(fixture.runtime.siteDataPolicyTabIds.isEmpty)
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

    func testDuplicateSameDocumentCallbackPublishesTailOnce() {
        let fixture = makeFixture()
        let sameDocumentURL = URL(
            string: "https://target.example/page#section"
        )!
        let webView = fixture.webView as! SumiNavigationURLReportingWebView
        webView.reportedURL = sameDocumentURL
        var persistenceCount = 0
        var persistence = TabRuntimePersistenceCallbacks.inactive
        persistence.scheduleRuntimeStatePersistence = { _ in
            persistenceCount += 1
        }
        fixture.tab.navigationRuntime.persistenceCallbacks = persistence
        var syncCount = 0
        var routing = TabWebViewRoutingRuntime.inactive
        routing.syncTabAcrossWindows = { _, _ in syncCount += 1 }
        fixture.tab.navigationRuntime.webViewRouting = routing
        let context = SumiNavigationContext(
            navigationID: fixture.context.navigationID,
            navigationLifetime: fixture.context.navigationLifetime,
            action: nil,
            url: sameDocumentURL,
            isCurrent: true,
            isMainFrame: true,
            webView: webView
        )

        fixture.responder.navigationDidSameDocumentNavigation(
            type: .anchorNavigation,
            context: context
        )
        fixture.responder.navigationDidSameDocumentNavigation(
            type: .anchorNavigation,
            context: context
        )

        XCTAssertEqual(fixture.tab.url, sameDocumentURL)
        XCTAssertEqual(persistenceCount, 1)
        XCTAssertEqual(syncCount, 1)
    }

    func testSameDocumentTailStopsAfterReentrantStateNotification() {
        let fixture = makeFixture()
        let sameDocumentURL = URL(
            string: "https://target.example/page#reentrant"
        )!
        let successorURL = URL(
            string: "https://successor.example/same-document"
        )!
        let webView = fixture.webView as! SumiNavigationURLReportingWebView
        webView.reportedURL = sameDocumentURL
        var persistenceCount = 0
        var persistence = TabRuntimePersistenceCallbacks.inactive
        persistence.scheduleRuntimeStatePersistence = { _ in
            persistenceCount += 1
        }
        fixture.tab.navigationRuntime.persistenceCallbacks = persistence
        var syncCount = 0
        var routing = TabWebViewRoutingRuntime.inactive
        routing.syncTabAcrossWindows = { _, _ in syncCount += 1 }
        fixture.tab.navigationRuntime.webViewRouting = routing
        let observation = NotificationCenter.default.addObserver(
            forName: .sumiTabNavigationStateDidChange,
            object: fixture.tab,
            queue: nil
        ) { [weak tab = fixture.tab] _ in
            MainActor.assumeIsolated {
                _ = tab?.beginMainFrameNavigationIntent(to: successorURL)
            }
        }
        defer { NotificationCenter.default.removeObserver(observation) }

        fixture.responder.navigationDidSameDocumentNavigation(
            type: .anchorNavigation,
            context: SumiNavigationContext(
                navigationID: fixture.context.navigationID,
                navigationLifetime: fixture.context.navigationLifetime,
                action: nil,
                url: sameDocumentURL,
                isCurrent: true,
                isMainFrame: true,
                webView: webView
            )
        )

        XCTAssertEqual(
            fixture.tab.mainFrameLoads.currentIntent.targetURL,
            successorURL
        )
        XCTAssertEqual(persistenceCount, 0)
        XCTAssertEqual(syncCount, 0)
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
            context: context,
            initialURL: initialURL,
            targetURL: targetURL
        )
    }

    private struct Fixture {
        let tab: Tab
        let runtime: RecordingTabLifecycleNavigationRuntime
        let responder: SumiTabLifecycleNavigationResponder
        let webView: WKWebView
        let context: SumiNavigationContext
        let initialURL: URL
        let targetURL: URL
    }
}
