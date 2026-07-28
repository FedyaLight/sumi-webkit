import AppKit
import SumiDomain
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabRuntimeRoutingTests: XCTestCase {
    func testPerTabRuntimeOverrideDoesNotMutateSharedBrowserRuntime() {
        var runtime = TabBrowserRuntime.inactive
        runtime.navigationCommandRuntime = TabNavigationCommandRuntime(
            resolvedSearchEngineTemplate: { "shared" }
        )
        let sharedRuntime = TabBrowserRuntimeReference(runtime)
        let first = Tab(loadsCachedFaviconOnInit: false)
        let second = Tab(loadsCachedFaviconOnInit: false)
        first.attachBrowserRuntime(sharedRuntime)
        second.attachBrowserRuntime(sharedRuntime)

        first.navigationRuntime.navigationCommandRuntime =
            TabNavigationCommandRuntime(
                resolvedSearchEngineTemplate: { "first-only" }
            )

        XCTAssertEqual(
            first.navigationRuntime.navigationCommandRuntime
                .resolvedSearchEngineTemplate(),
            "first-only"
        )
        XCTAssertEqual(
            second.navigationRuntime.navigationCommandRuntime
                .resolvedSearchEngineTemplate(),
            "shared"
        )
    }

    func testSetMutedUsesInjectedRoutingWithoutBrowserManager() {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let routing = RecordingTabWebViewRouting()
        tab.navigationRuntime.webViewRouting = routing.runtime

        tab.setMuted(true)

        XCTAssertEqual(routing.muteCalls, [.init(muted: true, tabId: tab.id)])
        XCTAssertTrue(tab.audioState.isMuted)
    }

    func testProcessRecoveryUsesUnifiedRoutingWithoutConsumingMarker() {
        let targetURL = URL(string: "https://example.com/recovery")!
        let transaction = TabMainFrameRuntimeTransaction(initialURL: targetURL)
        let tab = Tab(
            url: targetURL,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
        let webView = WKWebView()
        tab.replaceUntrackedWebView(webView)
        let routing = RecordingTabWebViewRouting()
        tab.navigationRuntime.webViewRouting = routing.runtime
        _ = transaction.beginRecovery(on: webView)

        let outcome = tab.navigationRuntime.webViewRouting
            .recoverWebContentProcess(tab.id, webView)

        XCTAssertEqual(outcome, .scheduled)
        XCTAssertEqual(routing.processRecoveryCalls.count, 1)
        XCTAssertEqual(routing.processRecoveryCalls.first?.0, tab.id)
        XCTAssertEqual(
            routing.processRecoveryCalls.first?.1,
            ObjectIdentifier(webView)
        )
        XCTAssertTrue(tab.webContentRecoveryMarkers.isRecoveryRequired(on: webView))
    }

    func testGlobalProcessRecoveryRetainsOwnerBeforeConfigurationFailure() {
        let targetURL = URL(string: "https://example.com/recovery-failure")!
        let transaction = TabMainFrameRuntimeTransaction(initialURL: targetURL)
        let tab = Tab(
            url: targetURL,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
        let webView = WKWebView()
        tab.replaceUntrackedWebView(webView)
        let routing = RecordingTabWebViewRouting()
        tab.navigationRuntime.webViewRouting = routing.runtime
        _ = transaction.beginRecovery(on: webView)

        let outcome = tab.navigationCommandOwner.recoverWebContentProcess(
            tab,
            targetURL: targetURL,
            sourceWebView: webView,
            configurationPolicyRebuilder: { _, _ in .failed }
        )

        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(routing.retainedProcessRecoveryCalls.count, 1)
        XCTAssertEqual(routing.retainedProcessRecoveryCalls.first?.0, tab.id)
        XCTAssertEqual(
            routing.retainedProcessRecoveryCalls.first?.1,
            ObjectIdentifier(webView)
        )
        XCTAssertTrue(routing.processRecoveryCalls.isEmpty)
        XCTAssertTrue(tab.webContentRecoveryMarkers.isRecoveryRequired(on: webView))
    }

    func testWebViewDepartureCancelsRetainedProcessRecoveryBeforeRetiringMarker() {
        let targetURL = URL(string: "https://example.com/departure")!
        let transaction = TabMainFrameRuntimeTransaction(initialURL: targetURL)
        let tab = Tab(
            url: targetURL,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
        let webView = WKWebView()
        tab.replaceUntrackedWebView(webView)
        let routing = RecordingTabWebViewRouting()
        tab.navigationRuntime.webViewRouting = routing.runtime
        _ = transaction.beginRecovery(on: webView)

        tab.webViewDidLeaveNavigationRuntime(webView)

        XCTAssertEqual(
            routing.cancelledProcessRecoveryWebViewIDs,
            [ObjectIdentifier(webView)]
        )
        XCTAssertFalse(tab.webContentRecoveryMarkers.isRecoveryRequired(on: webView))
    }

    func testRecoveryAdmissionIsOwnedByExactLifecycleResponderCallback() {
        let targetURL = URL(string: "https://example.com/admission-boundary")!
        let transaction = TabMainFrameRuntimeTransaction(initialURL: targetURL)
        let tab = Tab(
            url: targetURL,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
        let ownedWebView = WKWebView()
        let foreignWebView = WKWebView()
        tab.replaceUntrackedWebView(ownedWebView)
        let routing = RecordingTabWebViewRouting()
        tab.navigationRuntime.webViewRouting = routing.runtime
        let responder = tab.makeMainFrameLifecycleResponder()
        let initialIntent = tab.mainFrameLoads.currentIntent

        responder.webContentProcessDidTerminate(on: foreignWebView)

        XCTAssertEqual(tab.mainFrameLoads.currentIntent, initialIntent)
        XCTAssertFalse(
            tab.webContentRecoveryMarkers.isRecoveryRequired(on: foreignWebView)
        )
        XCTAssertFalse(
            tab.webContentRecoveryMarkers.isRecoveryRequired(on: ownedWebView)
        )
        XCTAssertTrue(routing.processRecoveryCalls.isEmpty)

        responder.webContentProcessDidTerminate(on: ownedWebView)

        XCTAssertTrue(
            tab.webContentRecoveryMarkers.isRecoveryRequired(on: ownedWebView)
        )
        XCTAssertEqual(routing.processRecoveryCalls.count, 1)
        XCTAssertEqual(
            routing.processRecoveryCalls.first?.1,
            ObjectIdentifier(ownedWebView)
        )
    }

    func testReplicaProcessTerminationKeepsSemanticRevisionAndRepairsExactReplica() {
        let targetURL = URL(string: "https://example.com/replica-recovery")!
        let transaction = TabMainFrameRuntimeTransaction(initialURL: targetURL)
        let tab = Tab(
            url: targetURL,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
        let authorityWebView = WKWebView()
        let crashedReplica = WKWebView()
        tab.replaceUntrackedWebView(authorityWebView)
        tab.parkExistingWebView(crashedReplica)
        let routing = RecordingTabWebViewRouting()
        tab.navigationRuntime.webViewRouting = routing.runtime
        let intent = tab.beginMainFrameNavigationIntent(to: targetURL)
        let authorityNavigation = NSObject()
        let replicaNavigation = NSObject()
        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: authorityWebView))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: authorityWebView,
            navigationID: ObjectIdentifier(authorityNavigation),
            navigationLifetime: authorityNavigation,
            matching: nil
        ))
        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: crashedReplica))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: crashedReplica,
            navigationID: ObjectIdentifier(replicaNavigation),
            navigationLifetime: replicaNavigation,
            matching: nil
        ))

        tab.makeMainFrameLifecycleResponder()
            .webContentProcessDidTerminate(on: crashedReplica)

        XCTAssertEqual(tab.mainFrameLoads.currentIntent, intent)
        XCTAssertEqual(routing.processRecoveryCalls.count, 1)
        XCTAssertEqual(
            routing.processRecoveryCalls.first?.1,
            ObjectIdentifier(crashedReplica)
        )
        XCTAssertTrue(transaction.role(
            from: authorityWebView,
            navigationID: ObjectIdentifier(authorityNavigation),
            isCurrent: true
        ).isAuthority)
        XCTAssertTrue(tab.webContentRecoveryMarkers.isRecoveryRequired(on: crashedReplica))
    }

    func testAuthorityProcessTerminationStartsGlobalRevisionAndRetainsExactRepair() {
        let targetURL = URL(string: "https://example.com/global-recovery")!
        let transaction = TabMainFrameRuntimeTransaction(initialURL: targetURL)
        let tab = Tab(
            url: targetURL,
            loadsCachedFaviconOnInit: false,
            mainFrameRuntimeTransaction: transaction
        )
        let crashedWebView = WKWebView()
        tab.replaceUntrackedWebView(crashedWebView)
        let routing = RecordingTabWebViewRouting()
        tab.navigationRuntime.webViewRouting = routing.runtime
        let crashedIntent = tab.beginMainFrameNavigationIntent(to: targetURL)
        let navigation = NSObject()
        XCTAssertNotNil(tab.mainFrameLoads.claimDirectSubmission(on: crashedWebView))
        XCTAssertTrue(tab.mainFrameSubmission.bindSubmittedLoad(
            on: crashedWebView,
            navigationID: ObjectIdentifier(navigation),
            navigationLifetime: navigation,
            matching: nil
        ))

        tab.makeMainFrameLifecycleResponder()
            .webContentProcessDidTerminate(on: crashedWebView)

        let recoveryIntent = tab.mainFrameLoads.currentIntent
        XCTAssertEqual(recoveryIntent.revision, crashedIntent.revision + 1)
        XCTAssertEqual(recoveryIntent.targetURL, targetURL)
        XCTAssertEqual(routing.processRecoveryCalls.count, 1)
        XCTAssertEqual(
            routing.processRecoveryCalls.first?.1,
            ObjectIdentifier(crashedWebView)
        )
        XCTAssertTrue(tab.webContentRecoveryMarkers.isRecoveryRequired(on: crashedWebView))

        tab.makeMainFrameLifecycleResponder()
            .webContentProcessDidTerminate(on: crashedWebView)

        XCTAssertEqual(tab.mainFrameLoads.currentIntent, recoveryIntent)
        XCTAssertEqual(routing.processRecoveryCalls.count, 2)
    }

    func testRefreshCreatesExactSemanticDeliveryWithoutBrowserManager() {
        let tab = Tab(
            url: URL(string: "https://example.com")!,
            loadsCachedFaviconOnInit: false
        )
        var reloadCalls: [RecordingTabWebViewRouting.ReloadCall] = []

        let outcome = tab.navigationCommandOwner.refresh(
            tab,
            resolvedWebView: { nil },
            reason: "TabRuntimeRoutingTests.refresh",
            configurationPolicyRebuilder: { _, _ in .notNeeded },
            deliverTrackedReload: { intent, policy in
                reloadCalls.append(.init(
                    tabId: tab.id,
                    revision: intent.revision,
                    targetURL: intent.targetURL,
                    policy: policy
                ))
                return .accepted
            }
        )

        XCTAssertEqual(outcome, .accepted)
        XCTAssertEqual(reloadCalls.map(\.tabId), [tab.id])
        XCTAssertEqual(reloadCalls.first?.targetURL, tab.url)
        XCTAssertEqual(reloadCalls.first?.policy, .standard)
        XCTAssertEqual(
            reloadCalls.first?.revision,
            tab.mainFrameLoads.currentIntent(matching: tab.url)?.revision
        )
    }

    func testRepeatedRefreshCreatesFreshSemanticRevisionForSameURL() {
        let tab = Tab(
            url: URL(string: "https://example.com/same-document")!,
            loadsCachedFaviconOnInit: false
        )
        var reloadCalls: [RecordingTabWebViewRouting.ReloadCall] = []

        for _ in 0..<2 {
            tab.navigationCommandOwner.refresh(
                tab,
                resolvedWebView: { nil },
                reason: "TabRuntimeRoutingTests.repeatedRefresh",
                configurationPolicyRebuilder: { _, _ in .notNeeded },
                deliverTrackedReload: { intent, policy in
                    reloadCalls.append(.init(
                        tabId: tab.id,
                        revision: intent.revision,
                        targetURL: intent.targetURL,
                        policy: policy
                    ))
                    return .accepted
                }
            )
        }

        XCTAssertEqual(reloadCalls.count, 2)
        XCTAssertEqual(
            reloadCalls.map(\.targetURL),
            [tab.url, tab.url]
        )
        XCTAssertEqual(
            reloadCalls[1].revision,
            reloadCalls[0].revision + 1
        )
    }

    func testAudioStateUsesInjectedMediaCallbacksWithoutBrowserManager() {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let callbacks = RecordingTabMediaCallbacks()
        tab.mediaRuntime.callbacks = callbacks.runtime

        tab.applyAudioState(.unmuted(isPlayingAudio: true))

        XCTAssertEqual(callbacks.nowPlayingRefreshDelays, [0])
        XCTAssertEqual(callbacks.backgroundMediaReasons, ["tab-audio-state-changed"])
    }

    func testUnloadWebViewUsesInjectedMediaCallbacksWithoutBrowserManager() {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let callbacks = RecordingTabMediaCallbacks()
        tab.mediaRuntime.callbacks = callbacks.runtime

        tab.unloadWebView()

        XCTAssertEqual(callbacks.unloadedTabIds, [tab.id])
    }

    func testCleanupCloneWebViewUsesInjectedCleanupRuntimeWithoutBrowserManager() {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let webView = WKWebView()
        var permissionLifecycleEventCount = 0
        var deferredTabIds: [UUID] = []
        var deferredReasons: [String] = []
        var removedWebViewFromContainers = false
        var removeAllWebViewsCallCount = 0
        tab.navigationRuntime.permissionRuntime = TabPermissionRuntime(
            permissionBridges: { nil },
            handlePermissionLifecycleEvent: { _ in
                permissionLifecycleEventCount += 1
            },
            isActiveGlancePreviewSurface: { _, _ in false },
            surfaceState: { _, _ in .inactive },
            profile: { _, _ in nil }
        )
        tab.navigationRuntime.webViewCleanupRuntime = TabWebViewCleanupRuntime(
            deferProtectedWebViewCleanup: { candidateWebView, tabId, reason in
                XCTAssertIdentical(candidateWebView, webView)
                deferredTabIds.append(tabId)
                deferredReasons.append(reason)
                return false
            },
            deferWebsiteDataMutationWebViewMaterialization: { _, _ in false },
            deferWebsiteDataMutationMainFrameSubmission: { _, _, _, _ in false },
            retireParkedWebView: { _, _, _ in false },
            removeWebViewFromContainers: { candidateWebView in
                removedWebViewFromContainers = candidateWebView === webView
            },
            removeAllWebViews: { _, _, _ in
                removeAllWebViewsCallCount += 1
                return .none
            }
        )

        tab.cleanupCloneWebView(webView)

        XCTAssertFalse(tab.hasBrowserRuntime)
        XCTAssertEqual(permissionLifecycleEventCount, 1)
        XCTAssertEqual(deferredTabIds, [tab.id])
        XCTAssertEqual(deferredReasons, ["Tab.cleanupCloneWebView"])
        XCTAssertTrue(removedWebViewFromContainers)
        XCTAssertEqual(removeAllWebViewsCallCount, 0)
    }

    func testNormalWebViewExtensionRegistrationUsesInjectedRuntimeWithoutBrowserManager() {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        var registeredTabIds: [UUID] = []
        var registrationReasons: [String] = []
        tab.navigationRuntime.normalWebViewExtensionRuntime = TabNormalWebViewExtensionRuntime(
            registerTabWithExtensionRuntimeIfNeeded: { registeredTab, reason in
                registeredTabIds.append(registeredTab.id)
                registrationReasons.append(reason)
            },
            prepareWebViewForExtensionRuntime: { _, _, _ in /* No-op. */ },
            ensureInitialExtensionContextsIfNeeded: { _ in /* No-op. */ },
            warmInitialDocumentNativeMessagingIfNeeded: { _ in /* No-op. */ }
        )

        tab.normalWebViewInitialDocumentStage()
            .registerExtensionRuntime("test.registration")

        XCTAssertFalse(tab.hasBrowserRuntime)
        XCTAssertEqual(registeredTabIds, [tab.id])
        XCTAssertEqual(registrationReasons, ["test.registration"])
    }

    func testOwnedWebViewPreparationUsesInjectedExtensionRuntimeWithoutBrowserManager() {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let webView = FocusableWKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let targetURL = URL(string: "https://example.com/runtime")!
        var preparedWebViews: [WKWebView] = []
        var preparedURLs: [URL?] = []
        var preparedReasons: [String] = []
        tab.navigationRuntime.normalWebViewExtensionRuntime = TabNormalWebViewExtensionRuntime(
            registerTabWithExtensionRuntimeIfNeeded: { _, _ in /* No-op. */ },
            prepareWebViewForExtensionRuntime: { webView, currentURL, reason in
                preparedWebViews.append(webView)
                preparedURLs.append(currentURL)
                preparedReasons.append(reason)
            },
            ensureInitialExtensionContextsIfNeeded: { _ in /* No-op. */ },
            warmInitialDocumentNativeMessagingIfNeeded: { _ in /* No-op. */ }
        )

        tab.ownedWebViewPreparationOwner.prepareCreatedFocusableWebView(
            webView,
            currentURL: targetURL,
            reason: "test.extension-runtime",
            installFaviconRuntime: false
        )

        XCTAssertFalse(tab.hasBrowserRuntime)
        XCTAssertEqual(preparedWebViews.count, 1)
        XCTAssertIdentical(preparedWebViews.first, webView)
        XCTAssertEqual(preparedURLs, [targetURL])
        XCTAssertEqual(preparedReasons, ["test.extension-runtime"])
    }

    func testExtensionPageFaviconUsesInjectedRuntimeWithoutBrowserManager() async throws {
        let extensionId = "ext-\(UUID().uuidString)"
        let pageURL = try XCTUnwrap(URL(string: "safari-web-extension://\(extensionId)/popup.html"))
        let tab = Tab(
            url: pageURL,
            loadsCachedFaviconOnInit: false
        )
        var installedExtensionsLookupCount = 0
        tab.navigationRuntime.faviconExtensionRuntime = TabFaviconExtensionRuntime(
            installedExtensions: {
                installedExtensionsLookupCount += 1
                return []
            }
        )

        await tab.fetchFaviconForVisiblePresentation()

        XCTAssertFalse(tab.hasBrowserRuntime)
        XCTAssertEqual(installedExtensionsLookupCount, 1)
    }

    func testCloseTabUsesInjectedLifecycleRuntimeWithoutBrowserManager() {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let lifecycle = RecordingTabCloseLifecycleRuntime()
        tab.navigationRuntime.closeLifecycleRuntime = lifecycle.runtime

        tab.closeTab()

        XCTAssertFalse(tab.hasBrowserRuntime)
        XCTAssertEqual(lifecycle.cleanedZoomTabIds, [tab.id])
        XCTAssertEqual(lifecycle.visibilityUpdateCount, 1)
        XCTAssertEqual(lifecycle.removedTabIds, [tab.id])
    }

    func testTitleUpdateUsesInjectedPersistenceWithoutBrowserManager() {
        let tab = Tab(
            url: URL(string: "https://example.com")!,
            name: "Original",
            loadsCachedFaviconOnInit: false
        )
        let persistence = RecordingTabPersistenceCallbacks()
        let extensionProperties = RecordingTabExtensionPropertiesRuntime()
        tab.navigationRuntime.persistenceCallbacks = persistence.runtime
        tab.navigationRuntime.extensionPropertiesRuntime = extensionProperties.runtime

        XCTAssertTrue(tab.acceptResolvedDisplayTitle("Updated"))

        XCTAssertEqual(persistence.persistedTabIds, [tab.id])
        XCTAssertEqual(extensionProperties.tabIds, [tab.id])
        XCTAssertEqual(extensionProperties.properties, [[.title]])
    }

    func testHistoryRecorderUsesInjectedRuntimeWithoutBrowserManager() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/history"))
        let profileId = UUID()
        let tab = Tab(
            url: pageURL,
            name: "History Title",
            loadsCachedFaviconOnInit: false
        )
        let history = RecordingTabHistoryRecordingRuntime(currentProfileId: profileId)
        tab.navigationRuntime.historyRecordingRuntime = history.runtime

        tab.navigationRuntime.historyRecorder.didCommitMainFrameNavigation(
            to: pageURL,
            kind: .regular,
            tab: tab
        )
        tab.navigationRuntime.historyRecorder.updateTitle("Resolved Title", tab: tab)

        XCTAssertFalse(tab.hasBrowserRuntime)
        XCTAssertEqual(history.visitURLs, [pageURL])
        XCTAssertEqual(history.visitTabIds, [tab.id])
        XCTAssertEqual(history.visitProfileIds, [profileId])
        XCTAssertEqual(tab.navigationRuntime.historyRecorder.localVisitIDs, [history.visitId])
        XCTAssertEqual(history.titleUpdateTitles, ["Resolved Title"])
        XCTAssertEqual(history.titleUpdateURLs, [pageURL])
        XCTAssertEqual(history.titleUpdateProfileIds, [profileId])
    }

    func testFindInPageUsesInjectedWindowScopedWebViewWithoutBrowserManager() {
        let existingWebView = FocusableWKWebView()
        let windowScopedWebView = FocusableWKWebView()
        let windowId = UUID()
        let tab = Tab(existingWebView: existingWebView, loadsCachedFaviconOnInit: false)
        var lookup: (tabId: UUID, windowId: UUID)?
        tab.navigationRuntime.findInPageRuntime = TabFindInPageRuntime(
            webView: { tabId, resolvedWindowId in
                lookup = (tabId, resolvedWindowId)
                return windowScopedWebView
            }
        )

        XCTAssertFalse(tab.hasBrowserRuntime)
        XCTAssertIdentical(tab.targetFindWebView(in: windowId), windowScopedWebView)
        XCTAssertEqual(lookup?.tabId, tab.id)
        XCTAssertEqual(lookup?.windowId, windowId)
    }

    func testFindInPageTargetsReaderPresentationInsteadOfHiddenCanonicalWebView() throws {
        let canonicalWebView = FocusableWKWebView()
        let windowId = UUID()
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://example.com/article")),
            existingWebView: canonicalWebView,
            loadsCachedFaviconOnInit: false
        )
        let host = SumiWebViewContainerView(tabID: tab.id, webView: canonicalWebView)
        let lease = TabMainFrameDocumentLease(
            revision: 1,
            documentGeneration: 1,
            webViewID: ObjectIdentifier(canonicalWebView),
            participantID: UUID(),
            committedURL: tab.url,
            presentationURL: tab.url,
            isPDF: false,
            isAuthority: true
        )
        XCTAssertTrue(host.presentReader(
            html: "<html><body><article>Reader</article></body></html>",
            sourceDocument: SumiReaderSourceDocument(
                webView: canonicalWebView,
                lease: lease,
                sourceURL: tab.url,
                remoteResourcePolicy: .denyRemoteResources,
                currentLease: { lease },
                routeWebLink: { _, _ in false },
                routeExternalLink: { _ in }
            )
        ))
        tab.navigationRuntime.findInPageRuntime = TabFindInPageRuntime(
            webView: { _, _ in canonicalWebView }
        )

        let target = try XCTUnwrap(tab.targetFindWebView(in: windowId))

        XCTAssertIdentical(target, host.activePresentationWebView)
        XCTAssertFalse(target === canonicalWebView)
    }

    func testHistorySwipeUsesInjectedRuntimeWithoutBrowserManager() {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let webView = WKWebView()
        let historySwipe = RecordingTabHistorySwipeRuntime()
        tab.navigationRuntime.historySwipeRuntime = historySwipe.runtime

        tab.beginBackForwardNavigationTracking(on: webView)
        tab.finishBackForwardNavigationTracking(using: webView)

        XCTAssertFalse(tab.hasBrowserRuntime)
        XCTAssertEqual(historySwipe.beginTabIds, [tab.id])
        XCTAssertEqual(historySwipe.finishTabIds, [tab.id])
        XCTAssertEqual(historySwipe.windowLookupWebViews, [ObjectIdentifier(webView)])
        XCTAssertEqual(historySwipe.flushedWindowIds, [historySwipe.windowId])
        XCTAssertTrue(historySwipe.cancelledWindowIds.isEmpty)
    }

    func testLiveHistorySwipeRuntimeUsesInjectedOwnershipAndProtectionServices() {
        let webView = WKWebView()
        let tabId = UUID()
        let windowId = UUID()
        let webViewSessions = WebViewSessionRepository()
        let webViewRuntime = makeTestWebViewRuntimeGraph(
            webViewSessions: webViewSessions
        )
        let runtime = TabHistorySwipeRuntime.make(
            ownershipQuery: webViewRuntime.ownershipQuery,
            protection: webViewRuntime.protectionRuntime,
            cancelWindowMutationsAfterHistorySwipe: { _ in /* No-op. */ },
            flushWindowMutationsAfterHistorySwipe: { _ in /* No-op. */ }
        )

        XCTAssertNil(runtime.windowIDContaining(webView))

        WebViewTrackingLifecycleOwner().registerTrackedWebView(
            webView,
            for: TrackedWebViewOwner(tabID: tabId, windowID: windowId),
            in: webViewSessions,
            removeFromContainers: { _ in },
            installRuntimeObservations: { _ in },
            uninstallRuntimeObservationsIfUntracked: { _ in },
            pruneInvalidDeferredCommands: { _ in },
            canDisplaceWebView: { _ in true },
            removeRecentVisibility: { _ in },
            cleanupDisplacedWebView: { _, _ in }
        )

        XCTAssertEqual(runtime.windowIDContaining(webView), windowId)
    }

    func testReloadPolicyUsesInjectedRuntimeWithoutBrowserManager() throws {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/article"))
        let safariState = SumiSafariContentBlockerAttachmentState(
            siteHost: "example.com",
            isEnabledForSite: true,
            enabledContentBlockerIds: ["blocker"]
        )
        let protectionState = SumiProtectionAttachmentState(
            siteHost: "example.com",
            requestedLevel: .protection,
            effectiveLevel: .protection,
            activeGroups: [.trackingNetwork],
            attachedRuleListIdentifiers: ["tracking-rule"],
            activeGenerationId: "generation-1"
        )
        tab.navigationRuntime.reloadPolicies = TabReloadPolicies(
            safariContentBlockers: RuntimeRoutingSafariPolicy(
                state: safariState
            ),
            protection: RuntimeRoutingProtectionPolicy(
                state: protectionState
            ),
            autoplay: InactiveAutoplayPolicy()
        )

        XCTAssertFalse(tab.hasBrowserRuntime)
        XCTAssertEqual(
            tab.safariBlockerDesiredAttachmentState(for: pageURL),
            safariState
        )
        XCTAssertEqual(
            tab.protectionDesiredAttachmentState(for: pageURL),
            protectionState
        )
    }

    func testNavigateToURLUsesInjectedSearchTemplateWithoutBrowserManager() {
        let webView = WKWebView()
        let tab = Tab(existingWebView: webView, loadsCachedFaviconOnInit: false)
        tab.adoptParkedWebViewAsCurrent(webView)
        tab.installNavigationDelegate(on: webView)
        tab.navigationRuntime.navigationCommandRuntime = TabNavigationCommandRuntime(
            resolvedSearchEngineTemplate: {
                "https://search.example/?q=%@"
            }
        )

        tab.navigationCommandOwner.navigateToURL("sumi browser", for: tab)

        XCTAssertFalse(tab.hasBrowserRuntime)
        XCTAssertEqual(
            tab.url.absoluteString,
            "https://search.example/?q=sumi%20browser"
        )
    }
}

@MainActor
private final class RecordingTabCloseLifecycleRuntime {
    private(set) var cleanedZoomTabIds: [UUID] = []
    private(set) var visibilityUpdateCount = 0
    private(set) var removedTabIds: [UUID] = []

    var runtime: TabCloseLifecycleRuntime {
        TabCloseLifecycleRuntime(
            cleanupZoomForTab: { [weak self] tabId in
                self?.cleanedZoomTabIds.append(tabId)
            },
            updateTabVisibility: { [weak self] in
                self?.visibilityUpdateCount += 1
            },
            removeTab: { [weak self] tabId in
                self?.removedTabIds.append(tabId)
            }
        )
    }
}

@MainActor
private final class RecordingTabExtensionPropertiesRuntime {
    private(set) var tabIds: [UUID] = []
    private(set) var properties: [WKWebExtension.TabChangedProperties] = []

    var runtime: TabExtensionPropertiesRuntime {
        TabExtensionPropertiesRuntime(
            notifyTabPropertiesChanged: { [weak self] tab, properties in
                self?.tabIds.append(tab.id)
                self?.properties.append(properties)
            }
        )
    }
}

@MainActor
private final class RecordingTabHistoryRecordingRuntime {
    let visitId = UUID()
    let profileId: UUID?
    private(set) var visitURLs: [URL] = []
    private(set) var visitTabIds: [UUID] = []
    private(set) var visitProfileIds: [UUID?] = []
    private(set) var titleUpdateTitles: [String] = []
    private(set) var titleUpdateURLs: [URL] = []
    private(set) var titleUpdateProfileIds: [UUID?] = []

    init(currentProfileId: UUID?) {
        self.profileId = currentProfileId
    }

    var runtime: TabHistoryRecordingRuntime {
        TabHistoryRecordingRuntime(
            updateTitleIfNeeded: { [weak self] title, url, profileId, _ in
                self?.titleUpdateTitles.append(title)
                self?.titleUpdateURLs.append(url)
                self?.titleUpdateProfileIds.append(profileId)
            },
            addVisit: { [weak self] url, _, _, tabId, profileId, _ in
                self?.visitURLs.append(url)
                self?.visitTabIds.append(tabId)
                self?.visitProfileIds.append(profileId)
                return self?.visitId
            },
            currentProfileId: { [weak self] in
                self?.profileId
            }
        )
    }
}

@MainActor
private final class RecordingTabWebViewRouting {
    struct MuteCall: Equatable {
        let muted: Bool
        let tabId: UUID
    }

    struct ReloadCall: Equatable {
        let tabId: UUID
        let revision: UInt64
        let targetURL: URL
        let policy: WebRuntimeMainFrameReloadPolicy
    }

    private(set) var syncCalls: [(UUID, ObjectIdentifier?)] = []
    private(set) var reloadCalls: [ReloadCall] = []
    private(set) var retainedProcessRecoveryCalls: [(UUID, ObjectIdentifier)] = []
    private(set) var processRecoveryCalls: [(UUID, ObjectIdentifier)] = []
    private(set) var cancelledProcessRecoveryWebViewIDs: [ObjectIdentifier] = []
    private(set) var muteCalls: [MuteCall] = []

    var runtime: TabWebViewRoutingRuntime {
        TabWebViewRoutingRuntime(
            syncTabAcrossWindows: { [weak self] tabId, webView in
                self?.syncCalls.append(
                    (tabId, webView.map(ObjectIdentifier.init))
                )
            },
            reloadTabAcrossWindows: { [weak self] tabId, intent, policy in
                self?.reloadCalls.append(.init(
                    tabId: tabId,
                    revision: intent.revision,
                    targetURL: intent.targetURL,
                    policy: policy
                ))
            },
            reloadTabInWindow: { [weak self] tabId, _, intent, policy in
                self?.reloadCalls.append(.init(
                    tabId: tabId,
                    revision: intent.revision,
                    targetURL: intent.targetURL,
                    policy: policy
                ))
                return .accepted
            },
            retainWebContentProcessRecovery: { [weak self] tabId, webView in
                self?.retainedProcessRecoveryCalls.append(
                    (tabId, ObjectIdentifier(webView))
                )
                return true
            },
            recoverWebContentProcess: { [weak self] tabId, webView in
                self?.processRecoveryCalls.append(
                    (tabId, ObjectIdentifier(webView))
                )
                return .scheduled
            },
            cancelWebContentProcessRecovery: { [weak self] webView in
                self?.cancelledProcessRecoveryWebViewIDs.append(
                    ObjectIdentifier(webView)
                )
            },
            setMuteState: { [weak self] muted, tabId in
                self?.muteCalls.append(.init(muted: muted, tabId: tabId))
            },
            bindWebViewSession: { _ in /* No-op. */ }
        )
    }
}

@MainActor
private struct RuntimeRoutingSafariPolicy:
    SafariContentBlockerPolicyReading {
    let state: SumiSafariContentBlockerAttachmentState

    func attachmentState(
        for url: URL?
    ) -> SumiSafariContentBlockerAttachmentState {
        state
    }
}

@MainActor
private struct RuntimeRoutingProtectionPolicy: ProtectionPolicyReading {
    let state: SumiProtectionAttachmentState

    func attachmentState(
        for url: URL?
    ) -> SumiProtectionAttachmentState {
        state
    }

    func surfaceHost(for url: URL?) -> String? { "example.com" }

    func diagnostics(
        _ context: ReloadProtectionDiagnosticsContext
    ) -> SumiProtectionCurrentTabDiagnostics? {
        nil
    }
}

@MainActor
private final class RecordingTabMediaCallbacks {
    private(set) var nowPlayingRefreshDelays: [UInt64] = []
    private(set) var backgroundMediaReasons: [String] = []
    private(set) var unloadedTabIds: [UUID] = []

    var runtime: TabMediaRuntimeCallbacks {
        TabMediaRuntimeCallbacks(
            scheduleNowPlayingRefresh: { [weak self] delay in
                self?.nowPlayingRefreshDelays.append(delay)
            },
            scheduleBackgroundMediaReconcile: { [weak self] reason in
                self?.backgroundMediaReasons.append(reason)
            },
            invalidateBackgroundMediaCommand: { _ in /* No-op. */ },
            notifyNowPlayingTabUnloaded: { [weak self] tabId in
                self?.unloadedTabIds.append(tabId)
            }
        )
    }
}

@MainActor
private final class RecordingTabPersistenceCallbacks {
    private(set) var navigationStateTabIds: [UUID] = []
    private(set) var persistedTabIds: [UUID] = []

    var runtime: TabRuntimePersistenceCallbacks {
        TabRuntimePersistenceCallbacks(
            updateNavigationState: { [weak self] tab in
                self?.navigationStateTabIds.append(tab.id)
            },
            scheduleRuntimeStatePersistence: { [weak self] tab in
                self?.persistedTabIds.append(tab.id)
            }
        )
    }
}

@MainActor
private final class RecordingTabHistorySwipeRuntime {
    let windowId = UUID()
    private(set) var beginTabIds: [UUID] = []
    private(set) var finishTabIds: [UUID] = []
    private(set) var windowLookupWebViews: [ObjectIdentifier] = []
    private(set) var cancelledWindowIds: [UUID] = []
    private(set) var flushedWindowIds: [UUID] = []

    var runtime: TabHistorySwipeRuntime {
        TabHistorySwipeRuntime(
            windowIDContaining: { [weak self] webView in
                self?.windowLookupWebViews.append(ObjectIdentifier(webView))
                return self?.windowId
            },
            beginHistorySwipeProtection: { [weak self] tabId, _, _, _ in
                self?.beginTabIds.append(tabId)
            },
            finishHistorySwipeProtection: { [weak self] tabId, _, _, _ in
                self?.finishTabIds.append(tabId)
                return false
            },
            cancelWindowMutationsAfterHistorySwipe: { [weak self] windowId in
                self?.cancelledWindowIds.append(windowId)
            },
            flushWindowMutationsAfterHistorySwipe: { [weak self] windowId in
                self?.flushedWindowIds.append(windowId)
            }
        )
    }
}
