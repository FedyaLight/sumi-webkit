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

    func testTitleUpdateUsesInjectedPersistenceWithoutBrowserManager() {
        let tab = Tab(
            url: URL(string: "https://example.com")!,
            name: "Original",
            loadsCachedFaviconOnInit: false
        )
        let persistence = RecordingTabPersistenceCallbacks()
        tab.persistenceRuntimeCallbacks = persistence.runtime

        XCTAssertTrue(tab.acceptResolvedDisplayTitle("Updated"))

        XCTAssertEqual(persistence.persistedTabIds, [tab.id])
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
