import WebKit
import SumiWebRuntime
import XCTest

@testable import Sumi

@MainActor
final class SumiTabLifecycleReentrancyTests: XCTestCase {
    func testLifecycleCallbackOrderMatrixPreservesCommitAuthorityAndSettlesOnce() {
        let cases: [([LifecycleCallback], Bool)] = [
            ([.commit, .finish], true),
            ([.finish], true),
            ([.fail], false),
            ([.downloadHandoff], false),
            ([.commit, .fail], true),
            ([.finish, .fail], true),
            ([.commit, .commit, .finish, .finish], true),
        ]

        for (callbacks, expectsTargetCommit) in cases {
            let fixture = makeFixture()
            for callback in callbacks {
                switch callback {
                case .commit:
                    fixture.responder.navigationDidCommit(fixture.context)
                case .finish:
                    fixture.responder.navigationDidFinish(fixture.context)
                case .fail:
                    fixture.responder.navigationDidFail(
                        WKError(.unknown),
                        context: fixture.context
                    )
                case .downloadHandoff:
                    fixture.responder.navigationDidFail(
                        WKError(.frameLoadInterruptedByPolicyChange),
                        context: fixture.context
                    )
                }
            }

            XCTAssertEqual(
                fixture.tab.url,
                expectsTargetCommit ? fixture.targetURL : fixture.initialURL,
                "Unexpected durable URL for callback order \(callbacks)"
            )
            XCTAssertFalse(
                fixture.tab.loadingState.isLoading,
                "Callback order must terminate loading: \(callbacks)"
            )
            XCTAssertLessThanOrEqual(
                fixture.runtime.markedEligibleTabIds.count,
                1,
                "Commit effects must publish once: \(callbacks)"
            )
            XCTAssertLessThanOrEqual(
                fixture.runtime.siteDataPolicyTabIds.count,
                1,
                "Finish effects must publish once: \(callbacks)"
            )
        }
    }

    func testContentPluginHandledLoadSettlesCommittedDocumentAsLive() {
        let fixture = makeFixture()
        let pluginHandledLoad = WKError(
            _nsError: NSError(domain: "WebKitErrorDomain", code: 204)
        )

        fixture.responder.navigationDidCommit(fixture.context)
        fixture.responder.navigationDidFail(
            pluginHandledLoad,
            context: fixture.context
        )

        XCTAssertEqual(fixture.tab.loadingState, .didFinish)
        XCTAssertNotNil(
            fixture.tab.committedDocumentRuntime.lease(for: fixture.webView)
        )
        XCTAssertEqual(fixture.runtime.siteDataPolicyTabIds, [fixture.tab.id])
        XCTAssertEqual(
            PagePresentationResolver.resolve(
                tab: fixture.tab,
                windowState: BrowserWindowState(),
                webView: fixture.webView
            ),
            .live(pageID: fixture.tab.id)
        )
    }

    func testCommittedCancelledBackForwardFailureKeepsDisplayedDocumentLive() {
        let fixture = makeFixture(contextIsCommitted: true)
        fixture.responder.navigationDidCommit(fixture.context)
        XCTAssertNotNil(
            fixture.tab.committedDocumentRuntime.lease(for: fixture.webView)
        )

        fixture.webView.reportedCommittedURL = nil
        fixture.responder.navigationDidFail(
            WKError(
                _nsError: NSError(
                    domain: NSURLErrorDomain,
                    code: NSURLErrorCancelled
                )
            ),
            context: fixture.context
        )

        XCTAssertNotNil(
            fixture.tab.committedDocumentRuntime.lease(for: fixture.webView)
        )
        XCTAssertEqual(fixture.tab.loadingState, .didFinish)
        XCTAssertEqual(
            PagePresentationResolver.resolve(
                tab: fixture.tab,
                windowState: BrowserWindowState(),
                webView: fixture.webView
            ),
            .live(pageID: fixture.tab.id)
        )
    }

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

    func testFirstCommitPublishesOneExactPresentationChange() {
        let fixture = makeFixture()
        var changes: [(UUID, ObjectIdentifier)] = []
        var routing = TabWebViewRoutingRuntime.inactive
        routing.pagePresentationDidChange = { tabID, webView in
            changes.append((tabID, ObjectIdentifier(webView)))
        }
        fixture.tab.navigationRuntime.webViewRouting = routing

        fixture.responder.navigationDidCommit(fixture.context)
        fixture.responder.navigationDidCommit(fixture.context)

        XCTAssertEqual(changes.map(\.0), [fixture.tab.id])
        XCTAssertEqual(
            changes.map(\.1),
            [ObjectIdentifier(fixture.webView)]
        )
    }

    func testTerminalFirstLoadFailurePublishesExactPresentationChange() {
        let fixture = makeFixture()
        var changes: [(UUID, ObjectIdentifier)] = []
        var routing = TabWebViewRoutingRuntime.inactive
        routing.pagePresentationDidChange = { tabID, webView in
            changes.append((tabID, ObjectIdentifier(webView)))
        }
        fixture.tab.navigationRuntime.webViewRouting = routing

        fixture.responder.navigationDidFail(
            WKError(.unknown),
            context: fixture.context
        )

        XCTAssertEqual(changes.map(\.0), [fixture.tab.id])
        XCTAssertEqual(
            changes.map(\.1),
            [ObjectIdentifier(fixture.webView)]
        )
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

    func testFinishCallbackIsTrustedCommitEvidenceWithoutPrivateWebViewURL() {
        let fixture = makeFixture(hasCommittedWebKitEvidence: false)

        fixture.responder.navigationDidFinish(fixture.context)

        XCTAssertEqual(fixture.tab.url, fixture.targetURL)
        XCTAssertEqual(fixture.tab.loadingState, .didFinish)
        XCTAssertNotNil(
            fixture.tab.committedDocumentRuntime.lease(for: fixture.webView)
        )
        XCTAssertEqual(
            fixture.tab.mainFrameLoads.currentIntent.targetURL,
            fixture.targetURL
        )
        XCTAssertEqual(fixture.runtime.siteDataPolicyTabIds, [fixture.tab.id])
    }

    func testUnexpectedUnadmittedBlankCannotReplaceCommittedDestination() {
        let initialURL = URL(string: "https://initial.example/page")!
        let blankURL = URL(string: "about:blank")!
        let tab = Tab(url: initialURL, loadsCachedFaviconOnInit: false)
        let webView = SumiNavigationURLReportingWebView(frame: .zero)
        webView.reportedURL = blankURL
        webView.reportedCommittedURL = blankURL
        let navigation = NSObject()
        let context = SumiNavigationContext(
            navigationID: ObjectIdentifier(navigation),
            navigationLifetime: navigation,
            action: nil,
            url: blankURL,
            isCurrent: true,
            isCommitted: true,
            isMainFrame: true,
            webView: webView
        )
        let responder = tab.makeMainFrameLifecycleResponder()

        responder.navigationWillStart(context)
        XCTAssertNil(tab.mainFrameLoads.currentIntent.blankAdmission)
        XCTAssertFalse(tab.mainFrameLoads.admitsCommit(to: blankURL))
        responder.navigationDidCommit(context)

        XCTAssertEqual(tab.url, initialURL)
        XCTAssertEqual(tab.mainFrameLoads.currentIntent.targetURL, initialURL)
        XCTAssertNil(tab.committedDocumentRuntime.lease(for: webView))
        XCTAssertFalse(tab.loadingState.isLoading)
    }

    func testUnexpectedBlankDuringNativeRestoreAttemptsOneOrdinaryFallback() {
        let destination = URL(string: "https://initial.example/page")!
        let blankURL = URL(string: "about:blank")!
        let tab = Tab(url: destination, loadsCachedFaviconOnInit: false)
        let webView = SuspendedRestoreBlankReportingWebView(frame: .zero)
        webView.reportedURL = blankURL
        webView.reportedCommittedURL = blankURL
        tab.replaceUntrackedWebView(webView)
        _ = tab.installNavigationDelegate(on: webView)

        let residence = WebViewResidence.untracked(tabID: tab.id)
        let snapshot = PageSessionSnapshot(
            residence: residence,
            residenceGeneration: tab.webViewSession.generation,
            profileID: nil,
            dataStoreIdentity: PageSessionDataStoreIdentity(
                webView.configuration.websiteDataStore
            ),
            committedRevision: tab.mainFrameLoads.currentIntent.revision,
            destination: destination,
            data: Data([1])
        )
        tab.markSuspended(sessionSnapshots: [snapshot])
        tab.beginSuspendedRestoreIfNeeded()

        let navigation = NSObject()
        let navigationID = ObjectIdentifier(navigation)
        let submission = try! XCTUnwrap(
            tab.mainFrameLoads.claimDirectSubmission(on: webView)
        )
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: navigation,
            matching: submission
        ))
        XCTAssertTrue(tab.suspensionState.bind(
            snapshot,
            webViewID: ObjectIdentifier(webView),
            navigationID: navigationID
        ))
        let context = SumiNavigationContext(
            navigationID: navigationID,
            navigationLifetime: navigation,
            action: nil,
            url: blankURL,
            isCurrent: true,
            isCommitted: true,
            isMainFrame: true,
            webView: webView
        )
        let responder = tab.makeMainFrameLifecycleResponder()

        XCTAssertEqual(webView.committedURL, blankURL)
        XCTAssertTrue(webView.committedURL?.isSumiBlankDocumentURL == true)
        XCTAssertEqual(tab.mainFrameLoads.currentIntent.targetURL, destination)
        XCTAssertFalse(tab.mainFrameLoads.admitsCommit(to: blankURL))
        XCTAssertTrue(tab.suspensionState.isRestoreInProgress)
        XCTAssertEqual(tab.suspensionState.lastSuspendedURL, destination)
        responder.navigationDidCommit(context)

        XCTAssertEqual(webView.loadedRequests.map(\.url), [destination])
        XCTAssertEqual(tab.suspensionState.phase, .failed)
        XCTAssertTrue(tab.suspensionState.didAttemptFallback)
        XCTAssertEqual(tab.url, destination)
    }

    func testExplicitBlankAdmissionCanCommitOnlyItsBoundNavigation() throws {
        let initialURL = try XCTUnwrap(URL(string: "https://initial.example/page"))
        let blankURL = try XCTUnwrap(URL(string: "about:blank"))
        let tab = Tab(url: initialURL, loadsCachedFaviconOnInit: false)
        let webView = SumiNavigationURLReportingWebView(frame: .zero)
        webView.reportedURL = blankURL
        webView.reportedCommittedURL = blankURL
        let intent = tab.beginMainFrameNavigationIntent(to: blankURL)
        XCTAssertNotNil(intent.blankAdmission)
        let submission = try XCTUnwrap(
            tab.mainFrameLoads.claimDirectSubmission(on: webView)
        )
        let navigation = NSObject()
        let navigationID = ObjectIdentifier(navigation)
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: webView,
            navigationID: navigationID,
            navigationLifetime: navigation,
            matching: submission
        ))
        let context = SumiNavigationContext(
            navigationID: navigationID,
            navigationLifetime: navigation,
            action: nil,
            url: blankURL,
            isCurrent: true,
            isCommitted: true,
            isMainFrame: true,
            webView: webView
        )

        tab.makeMainFrameLifecycleResponder().navigationDidCommit(context)

        XCTAssertEqual(tab.url, blankURL)
        XCTAssertEqual(
            try XCTUnwrap(tab.committedDocumentRuntime.lease(for: webView))
                .committedURL,
            blankURL
        )
    }

    func testDuplicateSameDocumentCallbackPublishesTailOnce() {
        let fixture = makeFixture()
        let sameDocumentURL = URL(
            string: "https://target.example/page#section"
        )!
        let webView = fixture.webView
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
        let webView = fixture.webView
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

    private func makeFixture(
        hasCommittedWebKitEvidence: Bool = true,
        contextIsCommitted: Bool = false
    ) -> Fixture {
        let initialURL = URL(string: "https://initial.example/page")!
        let targetURL = URL(string: "https://target.example/page")!
        let tab = Tab(url: initialURL, loadsCachedFaviconOnInit: false)
        let runtime = RecordingTabLifecycleNavigationRuntime()
        tab.navigationRuntime.lifecycleNavigationRuntime = runtime.runtime
        let webView = SumiNavigationURLReportingWebView(frame: .zero)
        webView.reportedURL = targetURL
        webView.reportedCommittedURL = hasCommittedWebKitEvidence
            ? targetURL
            : nil
        let navigation = NSObject()
        let context = SumiNavigationContext(
            navigationID: ObjectIdentifier(navigation),
            navigationLifetime: navigation,
            action: nil,
            url: targetURL,
            isCurrent: true,
            isCommitted: contextIsCommitted,
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
        let webView: SumiNavigationURLReportingWebView
        let context: SumiNavigationContext
        let initialURL: URL
        let targetURL: URL
    }

    private enum LifecycleCallback: CustomStringConvertible {
        case commit
        case finish
        case fail
        case downloadHandoff

        var description: String {
            switch self {
            case .commit: "commit"
            case .finish: "finish"
            case .fail: "fail"
            case .downloadHandoff: "downloadHandoff"
            }
        }
    }
}

@MainActor
private final class SuspendedRestoreBlankReportingWebView: WKWebView {
    var reportedURL: URL?
    var reportedCommittedURL: URL?
    private(set) var loadedRequests: [URLRequest] = []

    override var url: URL? { reportedURL }

    override func responds(to selector: ObjectiveC.Selector?) -> Bool {
        guard let selector else { return false }
        let name = NSStringFromSelector(selector)
        if name == "committedURL" || name == "_committedURL" {
            return true
        }
        return super.responds(to: selector)
    }

    override func value(forKey key: String) -> Any? {
        if key == "committedURL" {
            return MainActor.assumeIsolated { reportedCommittedURL }
        }
        return super.value(forKey: key)
    }

    override func load(_ request: URLRequest) -> WKNavigation? {
        loadedRequests.append(request)
        return nil
    }
}
