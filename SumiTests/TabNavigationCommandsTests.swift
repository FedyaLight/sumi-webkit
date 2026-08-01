import Combine
import Foundation
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabNavigationCommandsTests: XCTestCase {
    func testExactSubmittedNavigationRevisionCannotBeRelabeledByNewerSameURLIntent() throws {
        let targetURL = try XCTUnwrap(
            URL(string: "https://example.com/same-url-overlap")
        )
        let webView = WKWebView()
        let tab = Tab(
            url: targetURL,
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(webView)
        let firstIntent = tab.beginMainFrameNavigationIntent(to: targetURL)
        XCTAssertTrue(tab.mainFrameLoads.markDeferredLoad(on: webView, intent: firstIntent))
        XCTAssertEqual(
            tab.mainFrameLoads.claimDeferredSubmission(
                on: webView,
                revision: firstIntent.revision,
                targetURL: targetURL
            ),
            .claimed
        )
        let lease = try XCTUnwrap(
            tab.mainFrameLoads.submittedLease(
                on: webView,
                revision: firstIntent.revision,
                targetURL: targetURL
            )
        )
        let firstLifetime = NSObject()
        let firstNavigationID = ObjectIdentifier(firstLifetime)
        XCTAssertTrue(
            tab.mainFrameSubmission.bindSubmittedLoad(
                on: webView,
                navigationID: firstNavigationID,
                navigationLifetime: firstLifetime,
                matching: lease
            )
        )
        XCTAssertEqual(
            tab.mainFrameSubmission.semanticRevision(
                for: webView,
                navigationID: firstNavigationID,
                navigationLifetime: firstLifetime
            ),
            firstIntent.revision
        )

        let newerIntent = tab.beginMainFrameNavigationIntent(to: targetURL)
        XCTAssertGreaterThan(newerIntent.revision, firstIntent.revision)
        XCTAssertNotEqual(
            tab.mainFrameSubmission.semanticRevision(
                for: webView,
                navigationID: firstNavigationID,
                navigationLifetime: firstLifetime
            ),
            newerIntent.revision
        )
    }

    func testWebsiteDataMutationDefersPhysicalSubmissionAndReplaysCurrentIntent() throws {
        let targetURL = try XCTUnwrap(
            URL(string: "https://example.com/deferred-cleanup-intent")
        )
        let webView = NavigationRecordingWebView()
        let tab = Tab(
            url: targetURL,
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(webView)
        _ = tab.installNavigationDelegate(on: webView)
        _ = tab.beginMainFrameNavigationIntent(to: targetURL)
        var shouldDefer = true
        var replay: (@MainActor () -> Void)?
        var cleanupRuntime = TabWebViewCleanupRuntime.inactive
        cleanupRuntime.deferWebsiteDataMutationMainFrameSubmission = {
            _, _, _, candidateReplay in
            guard shouldDefer else { return false }
            replay = candidateReplay
            return true
        }
        tab.navigationRuntime.webViewCleanupRuntime = cleanupRuntime

        let initialOutcome = tab.performMainFrameNavigation(on: webView) {
            $0.load(URLRequest(url: targetURL))
        }
        XCTAssertEqual(initialOutcome, .alreadyScheduled)
        XCTAssertTrue(webView.loadedRequests.isEmpty)

        shouldDefer = false
        replay?()
        XCTAssertEqual(webView.loadedRequests.map(\.url), [targetURL])
    }


    func testRefreshMaterializesEmptyUntrackedWebViewAtExactTarget() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/empty-untracked"))
        let webView = NavigationRecordingWebView()
        let tab = Tab(
            url: targetURL,
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(webView)
        _ = tab.installNavigationDelegate(on: webView)

        tab.refresh()

        XCTAssertEqual(webView.standardReloadCount, 1)
        XCTAssertEqual(webView.loadedRequests.map(\.url), [targetURL])
        XCTAssertEqual(
            webView.loadedRequests.map(\.cachePolicy),
            [.useProtocolCachePolicy]
        )
    }

    func testDeferredHardReloadMaterializesEmptyCloneWithBypassPolicy() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/empty-protected"))
        let webView = NavigationRecordingWebView()
        let tab = Tab(
            url: targetURL,
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(webView)
        _ = tab.installNavigationDelegate(on: webView)
        let intent = tab.beginMainFrameNavigationIntent(to: targetURL)
        XCTAssertTrue(tab.mainFrameLoads.markDeferredLoad(on: webView, intent: intent))

        let result = tab.performDeferredMainFrameNavigation(
            on: webView,
            revision: intent.revision,
            targetURL: targetURL
        ) {
            WebRuntimeMainFrameReloader.reloadOrLoad(
                targetURL,
                on: $0,
                policy: .fromOrigin
            )
        }

        XCTAssertEqual(result, .submissionFailed)
        XCTAssertEqual(webView.fromOriginReloadCount, 1)
        XCTAssertEqual(webView.loadedRequests.map(\.url), [targetURL])
        XCTAssertEqual(
            webView.loadedRequests.map(\.cachePolicy),
            [.reloadIgnoringLocalAndRemoteCacheData]
        )
    }

    func testScopedLoadCreatesNavigationAndRebuildIntentsBeforePolicyReplacement() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/same-target"))
        let webView = NavigationRecordingWebView()
        let tab = Tab(
            url: targetURL,
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(webView)
        var navigationRevisions: [UInt64] = []
        var rebuildRevisions: [UInt64] = []

        for _ in 0..<2 {
            tab.navigationCommandOwner.loadURL(
                targetURL,
                for: tab,
                resolvedWebView: { webView },
                reason: "TabNavigationCommandsTests.scopedLoad",
                configurationPolicyRebuilder: { candidateURL, _ in
                    guard let intent = tab.mainFrameLoads.currentIntent(
                        matching: candidateURL
                    ) else {
                        XCTFail("Expected navigation intent before policy replacement")
                        return .failed
                    }
                    navigationRevisions.append(intent.revision)
                    rebuildRevisions.append(tab.webViewRebuildEpoch.current)
                    return .replacedAndScheduledNavigation
                }
            )
        }

        XCTAssertEqual(navigationRevisions.count, 2)
        XCTAssertEqual(navigationRevisions[1], navigationRevisions[0] + 1)
        XCTAssertEqual(rebuildRevisions.count, 2)
        XCTAssertEqual(rebuildRevisions[1], rebuildRevisions[0] + 1)
        XCTAssertTrue(webView.loadedRequests.isEmpty)
    }

    func testWindowScopedHardReloadOwnsFreshSemanticRevisionBeforeDelivery() throws {
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/hard-reload"))
        let webView = NavigationRecordingWebView()
        let tab = Tab(
            url: targetURL,
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(webView)
        var policyRevision: UInt64?
        var policyRebuildRevision: UInt64?
        var deliveredIntent: TabMainFrameNavigationIntent?
        var deliveredPolicy: WebRuntimeMainFrameReloadPolicy?

        tab.navigationCommandOwner.refresh(
            tab,
            resolvedWebView: { webView },
            reason: "TabNavigationCommandsTests.hardReload",
            policy: .fromOrigin,
            configurationPolicyRebuilder: { candidateURL, _ in
                policyRevision = tab.mainFrameLoads.currentIntent(
                    matching: candidateURL
                )?.revision
                policyRebuildRevision = tab.webViewRebuildEpoch.current
                return .notNeeded
            },
            deliverTrackedReload: { intent, policy in
                deliveredIntent = intent
                deliveredPolicy = policy
                return .accepted
            }
        )

        XCTAssertEqual(policyRevision, deliveredIntent?.revision)
        XCTAssertEqual(policyRebuildRevision, 1)
        XCTAssertEqual(deliveredIntent?.targetURL, targetURL)
        XCTAssertEqual(deliveredPolicy, .fromOrigin)
    }

    func testTrackedReplacementWithScheduledNavigationDoesNotLoadAgainInCaller() throws {
        let webView = NavigationRecordingWebView()
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/start")),
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(webView)
        tab.navigationRuntime.navigationCommandRuntime = TabNavigationCommandRuntime(
            resolvedSearchEngineTemplate: { nil },
            prepareExtensionPageNavigation: { _, _, _ in
                .replacedAndScheduledNavigation
            }
        )
        let targetURL = try XCTUnwrap(
            URL(string: "safari-web-extension://extension-id/page.html")
        )

        tab.navigationCommandOwner.loadURL(
            targetURL,
            for: tab,
            resolvedWebView: { webView },
            reason: "TabNavigationCommandsTests.scheduledReplacement"
        )

        XCTAssertEqual(tab.url, targetURL)
        XCTAssertTrue(webView.loadedRequests.isEmpty)
    }

    func testResolverBasedLoadURLRollsBackWhenNoWebViewCanReceiveIt() throws {
        let originalURL = try XCTUnwrap(URL(string: "https://example.com/start"))
        let targetURL = try XCTUnwrap(URL(string: "https://target.example/path"))
        let tab = Tab(url: originalURL, loadsCachedFaviconOnInit: false)
        var resolverCallCount = 0

        tab.navigationCommandOwner.loadURL(
            targetURL,
            for: tab,
            resolvedWebView: {
                resolverCallCount += 1
                return nil
            },
            reason: "TabNavigationCommandsTests.deferredResolver"
        )

        XCTAssertEqual(resolverCallCount, 1)
        XCTAssertEqual(tab.url, originalURL)
        XCTAssertNotNil(tab.mainFrameLoads.currentIntent(matching: originalURL))
        XCTAssertNil(tab.resolvedCurrentWebView())
    }

    func testFailedChainedSubmissionRollsBackToLastCommittedDocument() throws {
        let committedURL = try XCTUnwrap(URL(string: "https://example.com/committed"))
        let firstPendingURL = try XCTUnwrap(URL(string: "https://example.com/first-pending"))
        let failedURL = try XCTUnwrap(URL(string: "https://example.com/failed"))
        let webView = NavigationRecordingWebView()
        let transaction = TabMainFrameRuntimeTransaction(initialURL: committedURL)
        let tab = Tab(
            url: committedURL,
            existingWebView: webView,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
        tab.replaceUntrackedWebView(webView)
        _ = tab.installNavigationDelegate(on: webView)
        webView.reportedCommittedURL = committedURL
        let committedNavigation = NSObject()
        let committedNavigationID = ObjectIdentifier(committedNavigation)
        XCTAssertEqual(tab.beginMainFrameLifecycle(
            from: webView,
            navigationID: committedNavigationID,
            navigationLifetime: committedNavigation,
            targetURL: committedURL,
            allowsUserInitiatedSupersession: true,
            continuationKind: nil
        ), .authority)
        guard case .publish = transaction.settleCommit(
            from: webView,
            navigationID: committedNavigationID,
            navigationLifetime: committedNavigation,
            committedURL: committedURL
        ) else {
            return XCTFail("Expected the durable document commit to publish")
        }
        _ = transaction.settleFinish(
            from: webView,
            navigationID: committedNavigationID,
            navigationLifetime: committedNavigation,
            terminalURL: nil
        )
        _ = tab.beginMainFrameNavigationIntent(to: firstPendingURL)
        tab.url = firstPendingURL

        tab.navigationCommandOwner.loadURL(
            failedURL,
            for: tab,
            resolvedWebView: { webView },
            reason: "TabNavigationCommandsTests.failedChainedSubmission",
            configurationPolicyRebuilder: { _, _ in .notNeeded }
        )

        XCTAssertEqual(webView.loadedRequests.map(\.url), [failedURL])
        XCTAssertEqual(tab.url, committedURL)
        XCTAssertNotNil(tab.mainFrameLoads.currentIntent(matching: committedURL))
        let restoredDocument = try XCTUnwrap(
            tab.committedDocumentRuntime.lease(for: webView)
        )
        XCTAssertEqual(restoredDocument.committedURL, committedURL)
        XCTAssertTrue(restoredDocument.isAuthority)
        XCTAssertFalse(tab.loadingState.isLoading)
    }

    func testRollbackRejectsSameURLReplicaWithDifferentDocumentKind() throws {
        let committedURL = try XCTUnwrap(URL(string: "https://example.com/document"))
        let pendingURL = try XCTUnwrap(URL(string: "https://example.com/pending"))
        let htmlWebView = NavigationRecordingWebView()
        let pdfWebView = NavigationRecordingWebView()
        htmlWebView.reportedCommittedURL = committedURL
        pdfWebView.reportedCommittedURL = committedURL
        let transaction = TabMainFrameRuntimeTransaction(initialURL: committedURL)
        let tab = Tab(
            url: committedURL,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
        _ = tab.beginMainFrameNavigationIntent(to: committedURL)

        let htmlNavigation = NSObject()
        let pdfNavigation = NSObject()
        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: htmlWebView))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: htmlWebView,
            navigationID: ObjectIdentifier(htmlNavigation),
            navigationLifetime: htmlNavigation,
            matching: nil
        ))
        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: pdfWebView))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: pdfWebView,
            navigationID: ObjectIdentifier(pdfNavigation),
            navigationLifetime: pdfNavigation,
            matching: nil
        ))
        guard case .publish = transaction.settleCommit(
            from: htmlWebView,
            navigationID: ObjectIdentifier(htmlNavigation),
            navigationLifetime: htmlNavigation,
            committedURL: committedURL
        ) else {
            return XCTFail("Expected HTML authority commit to publish")
        }
        transaction.noteResponse(
            isPDF: true,
            from: pdfWebView,
            navigationID: ObjectIdentifier(pdfNavigation),
            navigationLifetime: pdfNavigation
        )
        guard case .participant = transaction.settleCommit(
            from: pdfWebView,
            navigationID: ObjectIdentifier(pdfNavigation),
            navigationLifetime: pdfNavigation,
            committedURL: committedURL
        ) else {
            return XCTFail("PDF mismatch must remain a non-canonical replica")
        }
        _ = transaction.settleFinish(
            from: htmlWebView,
            navigationID: ObjectIdentifier(htmlNavigation),
            navigationLifetime: htmlNavigation,
            terminalURL: nil
        )
        _ = transaction.settleFinish(
            from: pdfWebView,
            navigationID: ObjectIdentifier(pdfNavigation),
            navigationLifetime: pdfNavigation,
            terminalURL: nil
        )

        _ = tab.beginMainFrameNavigationIntent(to: pendingURL)
        tab.cancelMainFrameNavigationIntent()

        let restoredLease = try XCTUnwrap(
            tab.committedDocumentRuntime.lease(for: htmlWebView)
        )
        XCTAssertEqual(restoredLease.committedURL, committedURL)
        XCTAssertFalse(restoredLease.isPDF)
        XCTAssertTrue(restoredLease.isAuthority)
        XCTAssertNil(tab.committedDocumentRuntime.lease(for: pdfWebView))
        XCTAssertNotNil(tab.mainFrameLoads.currentIntent(matching: committedURL))
    }

    func testFailedSubmissionDoesNotReapplyTargetFaviconAfterRollback() throws {
        let committedURL = try XCTUnwrap(URL(string: "sumi://history?range=all"))
        let failedURL = try XCTUnwrap(URL(string: "sumi://bookmarks"))
        let webView = NavigationRecordingWebView()
        let tab = Tab(
            url: committedURL,
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(webView)
        _ = tab.installNavigationDelegate(on: webView)
        tab.applyCachedFaviconOrPlaceholder(for: committedURL)
        XCTAssertEqual(tab.faviconPresentation, .systemSymbol("clock.arrow.circlepath"))

        tab.navigationCommandOwner.loadURL(
            failedURL,
            for: tab,
            resolvedWebView: { webView },
            reason: "TabNavigationCommandsTests.failedFaviconRollback",
            configurationPolicyRebuilder: { _, _ in .notNeeded }
        )

        XCTAssertEqual(tab.url, committedURL)
        XCTAssertEqual(tab.faviconPresentation, .systemSymbol("clock.arrow.circlepath"))
    }

    func testInitialExtensionLoadRollsBackIfMaterializationFailsAfterPolicy() throws {
        let initialURL = try XCTUnwrap(URL(string: "https://example.com/start"))
        let extensionURL = try XCTUnwrap(
            URL(string: "safari-web-extension://extension-id/page.html")
        )
        let tab = Tab(url: initialURL, loadsCachedFaviconOnInit: false)
        var preparedURLs: [URL] = []
        tab.navigationRuntime.navigationCommandRuntime = TabNavigationCommandRuntime(
            resolvedSearchEngineTemplate: { nil },
            prepareExtensionPageNavigation: { _, url, _ in
                preparedURLs.append(url)
                return .notNeeded
            }
        )

        tab.loadURL(extensionURL)

        XCTAssertEqual(preparedURLs, [extensionURL])
        XCTAssertEqual(tab.url, initialURL)
        XCTAssertNil(tab.mainFrameLoads.currentIntent(matching: extensionURL))
        XCTAssertNotNil(tab.mainFrameLoads.currentIntent(matching: initialURL))
    }

    func testContentBlockingAssetWaitDelaysMainFrameLoad() async throws {
        let controller = DelayedNavigationUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/start")),
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(webView)
        _ = tab.installNavigationDelegate(on: webView)
        var didLoad = false

        tab.performMainFrameNavigationAfterContentBlockingAssetsIfNeeded(
            on: webView,
            waitForContentBlockingAssets: true
        ) { resolvedWebView, _ in
            XCTAssertIdentical(resolvedWebView, webView)
            didLoad = true
            return resolvedWebView.loadHTMLString("", baseURL: nil)
        }

        for _ in 0..<20 where controller.waitCallCount == 0 {
            await Task.yield()
        }

        XCTAssertEqual(controller.waitCallCount, 1)
        XCTAssertFalse(didLoad)

        controller.finishInitialUserContentInstallation()

        for _ in 0..<20 where !didLoad {
            await Task.yield()
        }

        XCTAssertTrue(didLoad)
    }

    func testContentBlockingAssetWaitBypassesPreparationWhenNotRequested() throws {
        let controller = DelayedNavigationUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/start")),
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(webView)
        _ = tab.installNavigationDelegate(on: webView)
        var didLoad = false

        tab.performMainFrameNavigationAfterContentBlockingAssetsIfNeeded(
            on: webView,
            waitForContentBlockingAssets: false
        ) { resolvedWebView, _ in
            XCTAssertIdentical(resolvedWebView, webView)
            didLoad = true
            return resolvedWebView.loadHTMLString("", baseURL: nil)
        }

        XCTAssertEqual(controller.waitCallCount, 0)
        XCTAssertTrue(didLoad)
    }
}

@MainActor
private final class NavigationRecordingWebView: WKWebView {
    private(set) var loadedRequests: [URLRequest] = []
    private(set) var standardReloadCount = 0
    private(set) var fromOriginReloadCount = 0
    var reportedCommittedURL: URL?

    override func responds(to selector: Selector!) -> Bool {
        if selector == NSSelectorFromString("_committedURL")
            || selector == NSSelectorFromString("committedURL") {
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

    override func reload() -> WKNavigation? {
        standardReloadCount += 1
        return nil
    }

    override func reloadFromOrigin() -> WKNavigation? {
        fromOriginReloadCount += 1
        return nil
    }

    override func load(_ request: URLRequest) -> WKNavigation? {
        loadedRequests.append(request)
        return nil
    }
}

@MainActor
private final class DelayedNavigationUserContentController:
    WKUserContentController,
    SumiNormalTabUserContentControlling {
    var normalTabUserScriptsProvider: SumiNormalTabUserScripts?
    var contentBlockingAssetSummary = SumiNormalTabContentBlockingAssetSummary(
        isInstalled: false,
        globalRuleListCount: 0,
        updateRuleCount: 0,
        isContentBlockingFeatureEnabled: false
    )
    var hasInstalledInitialUserContent = false
    private(set) var waitCallCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    var wkUserContentController: WKUserContentController {
        self
    }

    #if DEBUG
        var contentBlockingAssetSummaryPublisher: AnyPublisher<SumiNormalTabContentBlockingAssetSummary, Never> {
            Just(contentBlockingAssetSummary).eraseToAnyPublisher()
        }
    #endif

    func replaceNormalTabUserScripts(with provider: SumiNormalTabUserScripts) async {
        normalTabUserScriptsProvider = provider
    }

    func waitForContentBlockingAssetsInstalled() async {
        waitCallCount += 1
        guard hasInstalledInitialUserContent == false else { return }

        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finishInitialUserContentInstallation() {
        hasInstalledInitialUserContent = true
        continuation?.resume()
        continuation = nil
    }

    func cleanUpBeforeClosing() { /* No-op. */ }
}
