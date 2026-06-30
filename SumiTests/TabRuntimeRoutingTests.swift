import XCTest
import WebKit

@testable import Sumi

@MainActor
final class TabRuntimeRoutingTests: XCTestCase {
    func testSetMutedUsesInjectedRoutingWithoutBrowserManager() {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let routing = RecordingTabWebViewRouting()
        tab.webViewRoutingRuntime = routing.runtime

        tab.setMuted(true)

        XCTAssertEqual(routing.muteCalls, [.init(muted: true, tabId: tab.id)])
        XCTAssertTrue(tab.audioState.isMuted)
    }

    func testRefreshUsesInjectedRoutingWithoutBrowserManager() {
        let tab = Tab(
            url: URL(string: "https://example.com")!,
            loadsCachedFaviconOnInit: false
        )
        let routing = RecordingTabWebViewRouting()
        tab.webViewRoutingRuntime = routing.runtime

        tab.navigationCommandOwner.refresh(tab)

        XCTAssertEqual(routing.reloadCalls, [tab.id])
    }

    func testAudioStateUsesInjectedMediaCallbacksWithoutBrowserManager() {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let callbacks = RecordingTabMediaCallbacks()
        tab.mediaRuntimeCallbacks = callbacks.runtime

        tab.applyAudioState(.unmuted(isPlayingAudio: true))

        XCTAssertEqual(callbacks.nowPlayingRefreshDelays, [0])
        XCTAssertEqual(callbacks.backgroundMediaReasons, ["tab-audio-state-changed"])
    }

    func testUnloadWebViewUsesInjectedMediaCallbacksWithoutBrowserManager() {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let callbacks = RecordingTabMediaCallbacks()
        tab.mediaRuntimeCallbacks = callbacks.runtime

        tab.unloadWebView()

        XCTAssertEqual(callbacks.unloadedTabIds, [tab.id])
    }

    func testCleanupCloneWebViewUsesInjectedCleanupRuntimeWithoutBrowserManager() {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let webView = WKWebView()
        var permissionLifecycleEventCount = 0
        var deferredTabIds: [UUID] = []
        var deferredReasons: [String] = []
        var cleanedUserScriptWebViewIds: [UUID] = []
        var removedWebViewFromContainers = false
        var removeAllWebViewsCallCount = 0
        tab.permissionRuntime = TabPermissionRuntime(
            permissionBridges: { nil },
            handlePermissionLifecycleEvent: { _ in
                permissionLifecycleEventCount += 1
            },
            isActiveGlancePreviewSurface: { _, _ in false }
        )
        tab.webViewCleanupRuntime = TabWebViewCleanupRuntime(
            deferProtectedWebViewCleanup: { candidateWebView, tabId, reason in
                XCTAssertTrue(candidateWebView === webView)
                deferredTabIds.append(tabId)
                deferredReasons.append(reason)
                return false
            },
            cleanupUserScripts: { _, webViewId in
                cleanedUserScriptWebViewIds.append(webViewId)
            },
            removeWebViewFromContainers: { candidateWebView in
                removedWebViewFromContainers = candidateWebView === webView
            },
            removeAllWebViews: { _, _ in
                removeAllWebViewsCallCount += 1
                return false
            }
        )

        tab.cleanupCloneWebView(webView)

        XCTAssertNil(tab.browserManager)
        XCTAssertEqual(permissionLifecycleEventCount, 1)
        XCTAssertEqual(deferredTabIds, [tab.id])
        XCTAssertEqual(deferredReasons, ["Tab.cleanupCloneWebView"])
        XCTAssertEqual(cleanedUserScriptWebViewIds, [tab.id])
        XCTAssertTrue(removedWebViewFromContainers)
        XCTAssertEqual(removeAllWebViewsCallCount, 0)
    }

    func testCloseTabUsesInjectedLifecycleRuntimeWithoutBrowserManager() {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let lifecycle = RecordingTabCloseLifecycleRuntime()
        tab.closeLifecycleRuntime = lifecycle.runtime

        tab.closeTab()

        XCTAssertNil(tab.browserManager)
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
        tab.persistenceRuntimeCallbacks = persistence.runtime
        tab.extensionPropertiesRuntime = extensionProperties.runtime

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
        tab.historyRecordingRuntime = history.runtime

        tab.historyRecorder.didCommitMainFrameNavigation(
            to: pageURL,
            kind: .regular,
            tab: tab
        )
        tab.historyRecorder.updateTitle("Resolved Title", tab: tab)

        XCTAssertNil(tab.browserManager)
        XCTAssertEqual(history.visitURLs, [pageURL])
        XCTAssertEqual(history.visitTabIds, [tab.id])
        XCTAssertEqual(history.visitProfileIds, [profileId])
        XCTAssertEqual(tab.historyRecorder.localVisitIDs, [history.visitId])
        XCTAssertEqual(history.titleUpdateTitles, ["Resolved Title"])
        XCTAssertEqual(history.titleUpdateURLs, [pageURL])
        XCTAssertEqual(history.titleUpdateProfileIds, [profileId])
    }

    func testFindInPageUsesInjectedActiveWindowWebViewWithoutBrowserManager() {
        let existingWebView = FocusableWKWebView()
        let activeWindowWebView = FocusableWKWebView()
        let windowId = UUID()
        let tab = Tab(existingWebView: existingWebView, loadsCachedFaviconOnInit: false)
        var lookup: (tabId: UUID, windowId: UUID)?
        tab.findInPageRuntime = TabFindInPageRuntime(
            activeWindowId: { windowId },
            webView: { tabId, resolvedWindowId in
                lookup = (tabId, resolvedWindowId)
                return activeWindowWebView
            }
        )

        XCTAssertNil(tab.browserManager)
        XCTAssertIdentical(tab.targetFindWebView(), activeWindowWebView)
        XCTAssertEqual(lookup?.tabId, tab.id)
        XCTAssertEqual(lookup?.windowId, windowId)
    }

    func testHistorySwipeUsesInjectedRuntimeWithoutBrowserManager() {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let webView = WKWebView()
        let historySwipe = RecordingTabHistorySwipeRuntime()
        tab.historySwipeRuntime = historySwipe.runtime

        tab.beginBackForwardNavigationTracking(on: webView)
        tab.finishBackForwardNavigationTracking(using: webView)

        XCTAssertNil(tab.browserManager)
        XCTAssertEqual(historySwipe.beginTabIds, [tab.id])
        XCTAssertEqual(historySwipe.finishTabIds, [tab.id])
        XCTAssertEqual(historySwipe.windowLookupWebViews, [ObjectIdentifier(webView)])
        XCTAssertEqual(historySwipe.flushedWindowIds, [historySwipe.windowId])
        XCTAssertTrue(historySwipe.cancelledWindowIds.isEmpty)
    }

    func testLiveHistorySwipeRuntimeUsesLateBoundCoordinator() {
        var coordinator: WebViewCoordinator?
        let webView = WKWebView()
        let tabId = UUID()
        let windowId = UUID()
        let runtime = TabHistorySwipeRuntime.live(
            webViewCoordinator: { coordinator },
            cancelWindowMutationsAfterHistorySwipe: { _ in },
            flushWindowMutationsAfterHistorySwipe: { _ in }
        )

        XCTAssertNil(runtime.windowIDContaining(webView))

        let resolvedCoordinator = WebViewCoordinator()
        resolvedCoordinator.setWebView(webView, for: tabId, in: windowId)
        coordinator = resolvedCoordinator

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
        tab.reloadPolicyRuntime = TabReloadPolicyRuntime(
            safariContentBlockerAttachmentState: { _ in safariState },
            protectionAttachmentState: { _ in protectionState },
            protectionSurfaceHost: { _ in "example.com" },
            protectionCurrentTabDiagnostics: { _ in nil },
            evaluateAutoplayPolicyChange: { _, _ in .noOp }
        )

        XCTAssertNil(tab.browserManager)
        XCTAssertEqual(
            tab.safariContentBlockerDesiredAttachmentState(for: pageURL),
            safariState
        )
        XCTAssertEqual(
            tab.protectionDesiredAttachmentState(for: pageURL),
            protectionState
        )
    }

    func testNavigateToURLUsesInjectedSearchTemplateWithoutBrowserManager() throws {
        let webView = WKWebView()
        let tab = Tab(existingWebView: webView, loadsCachedFaviconOnInit: false)
        tab.navigationCommandRuntime = TabNavigationCommandRuntime(
            resolvedSearchEngineTemplate: {
                "https://search.example/?q=%@"
            }
        )

        tab.navigationCommandOwner.navigateToURL("sumi browser", for: tab)

        XCTAssertNil(tab.browserManager)
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

    private(set) var syncCalls: [(UUID, ObjectIdentifier?)] = []
    private(set) var reloadCalls: [UUID] = []
    private(set) var muteCalls: [MuteCall] = []

    var runtime: TabWebViewRoutingRuntime {
        TabWebViewRoutingRuntime(
            syncTabAcrossWindows: { [weak self] tabId, webView in
                self?.syncCalls.append(
                    (tabId, webView.map(ObjectIdentifier.init))
                )
            },
            reloadTabAcrossWindows: { [weak self] tabId in
                self?.reloadCalls.append(tabId)
            },
            setMuteState: { [weak self] muted, tabId in
                self?.muteCalls.append(.init(muted: muted, tabId: tabId))
            }
        )
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
