import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class VisibleWebViewRuntimeOwnerTests: XCTestCase {
    func testPrepareVisibleWebViewsUsesRuntimeWithoutBrowserManager() {
        let owner = VisibleWebViewRuntimeOwner()
        let webViewSessions = WebViewSessionRepository()
        let windowState = BrowserWindowState()
        let currentTab = makeWebTab()
        let splitTab = makeWebTab(urlString: "https://example.com/split")
        let tabsById = [
            currentTab.id: currentTab,
            splitTab.id: splitTab,
        ]

        windowState.currentTabId = currentTab.id

        var markedTabIds: [UUID] = []
        var createdPairs: [(tabId: UUID, windowId: UUID)] = []
        var evictedVisibleTabIds = Set<UUID>()
        var suspensionReasons: [String] = []
        var mediaReasons: [String] = []

        let didCreate = owner.prepareVisibleWebViews(
            for: windowState,
            runtime: makeRuntime(
                windowStatesById: [windowState.id: windowState],
                currentTabId: { $0.concreteWindowState?.currentTabId },
                splitVisibleTabIds: { _ in [currentTab.id, splitTab.id] },
                resolveTab: { tabId, _ in tabsById[tabId] },
                markTabAccessed: { markedTabIds.append($0) },
                evictHiddenWebViews: { _, visibleTabIds in
                    evictedVisibleTabIds = visibleTabIds
                },
                scheduleTabSuspensionReconcile: { suspensionReasons.append($0) },
                scheduleBackgroundMediaReconcile: { mediaReasons.append($0) }
            ),
            webViewSessions: webViewSessions,
            existingWebView: { _, _ in nil },
            createWebView: { tab, window in
                createdPairs.append((tab.id, window.id))
                return WKWebView()
            }
        )

        XCTAssertTrue(didCreate)
        XCTAssertEqual(markedTabIds, [currentTab.id, splitTab.id])
        XCTAssertEqual(
            createdPairs.map(\.tabId),
            [currentTab.id, splitTab.id]
        )
        XCTAssertEqual(
            createdPairs.map(\.windowId),
            [windowState.id, windowState.id]
        )
        XCTAssertEqual(evictedVisibleTabIds, [currentTab.id, splitTab.id])
        XCTAssertEqual(suspensionReasons, ["visible-webviews-prepared"])
        XCTAssertEqual(mediaReasons, ["visible-webviews-prepared"])
    }

    func testPrepareVisibleWebViewsResolvesRegularAndEphemeralTabsExactly() {
        let owner = VisibleWebViewRuntimeOwner()
        let webViewSessions = WebViewSessionRepository()
        let regularWindow = BrowserWindowState()
        let ephemeralWindow = BrowserWindowState()
        ephemeralWindow.isIncognito = true

        let regularTab = makeWebTab()
        let ephemeralTab = makeWebTab(urlString: "https://example.com/private")
        regularWindow.currentTabId = regularTab.id
        ephemeralWindow.currentTabId = ephemeralTab.id
        ephemeralWindow.ephemeralTabs = [ephemeralTab]

        var createdTabs: [Tab] = []
        for (window, expectedTab) in [
            (regularWindow, regularTab),
            (ephemeralWindow, ephemeralTab),
        ] {
            let runtime = makeRuntime(
                windowStatesById: [window.id: window],
                currentTabId: { handle in
                    handle === window ? expectedTab.id : nil
                },
                resolveTab: { tabID, handle in
                    guard handle === window else { return nil }
                    return resolveVisibleTab(
                        tabID,
                        in: window,
                        regularTab: { id in id == regularTab.id ? regularTab : nil }
                    )
                },
                canMaterializeWebViewDuringStartup: { handle, windowHandle in
                    guard windowHandle === window else { return false }
                    return resolveVisibleTab(
                        matching: handle,
                        in: window,
                        regularTab: { id in id == regularTab.id ? regularTab : nil }
                    ) != nil
                }
            )

            let didCreate = owner.prepareVisibleWebViews(
                for: window,
                runtime: runtime,
                webViewSessions: webViewSessions,
                existingWebView: { _, _ in nil },
                createWebView: { handle, windowHandle in
                    guard windowHandle === window,
                          let tab = resolveVisibleTab(
                            matching: handle,
                            in: window,
                            regularTab: { id in
                                id == regularTab.id ? regularTab : nil
                            }
                          ) else {
                        return nil
                    }
                    createdTabs.append(tab)
                    return WKWebView()
                }
            )

            XCTAssertTrue(didCreate)
            XCTAssertIdentical(createdTabs.last, expectedTab)
        }
    }

    func testVisibleStartupPolicyRejectsStaleSameIDTabEvidence() {
        let owner = VisibleWebViewRuntimeOwner()
        let window = BrowserWindowState()
        let tabID = UUID()
        let stale = Tab(
            id: tabID,
            loadsCachedFaviconOnInit: false
        )
        let replacement = Tab(
            id: tabID,
            loadsCachedFaviconOnInit: false
        )
        window.currentTabId = tabID
        var createdCount = 0

        let didCreate = owner.prepareVisibleWebViews(
            for: window,
            runtime: makeRuntime(
                currentTabId: { handle in handle === window ? tabID : nil },
                resolveTab: { id, handle in
                    id == tabID && handle === window ? stale : nil
                },
                canMaterializeWebViewDuringStartup: { handle, windowHandle in
                    guard windowHandle === window else { return false }
                    return resolveVisibleTab(
                        matching: handle,
                        in: window,
                        regularTab: { id in id == tabID ? replacement : nil }
                    ) != nil
                }
            ),
            webViewSessions: WebViewSessionRepository(),
            existingWebView: { _, _ in nil },
            createWebView: { _, _ in
                createdCount += 1
                return WKWebView()
            }
        )

        XCTAssertFalse(didCreate)
        XCTAssertEqual(createdCount, 0)
    }

    func testSchedulePrepareVisibleWebViewsCoalescesAndRefreshesOnce() async {
        let owner = VisibleWebViewRuntimeOwner()
        let windowState = BrowserWindowState()
        var prepareCount = 0
        var refreshedWindowIds: [UUID] = []

        let runtime = makeRuntime(
            windowStatesById: [windowState.id: windowState],
            refreshCompositor: { refreshedWindowIds.append($0) }
        )

        owner.schedulePrepareVisibleWebViews(
            for: windowState,
            runtime: runtime,
            prepareVisibleWebViews: { _ in
                prepareCount += 1
                return true
            }
        )
        owner.schedulePrepareVisibleWebViews(
            for: windowState,
            runtime: runtime,
            prepareVisibleWebViews: { _ in
                XCTFail("Second schedule should coalesce before the main-queue drain")
                return true
            }
        )

        await drainMainQueue()

        XCTAssertEqual(prepareCount, 1)
        XCTAssertEqual(refreshedWindowIds, [windowState.id])
    }

    func testResetCancelsAlreadyEnqueuedPreparationBeforeRuntimeLookup() async {
        let owner = VisibleWebViewRuntimeOwner()
        let windowState = BrowserWindowState()
        var lookupCount = 0
        var prepareCount = 0
        let runtime = makeRuntime(
            windowStateLookup: { _ in
                lookupCount += 1
                return windowState
            }
        )

        owner.schedulePrepareVisibleWebViews(
            for: windowState,
            runtime: runtime,
            prepareVisibleWebViews: { _ in
                prepareCount += 1
                return true
            }
        )
        owner.resetWindowRegistrations()
        await drainMainQueue()

        XCTAssertEqual(lookupCount, 0)
        XCTAssertEqual(prepareCount, 0)
    }

    func testCancelledCallbackCannotConsumeReplacementSchedule() async {
        let owner = VisibleWebViewRuntimeOwner()
        let windowState = BrowserWindowState()
        var lookupCount = 0
        var replacementPrepareCount = 0
        let runtime = makeRuntime(
            windowStateLookup: { _ in
                lookupCount += 1
                return windowState
            }
        )

        owner.schedulePrepareVisibleWebViews(
            for: windowState,
            runtime: runtime,
            prepareVisibleWebViews: { _ in
                XCTFail("Cancelled preparation must not execute")
                return false
            }
        )
        owner.cancelScheduledPreparation(for: windowState.id)
        owner.schedulePrepareVisibleWebViews(
            for: windowState,
            runtime: runtime,
            prepareVisibleWebViews: { _ in
                replacementPrepareCount += 1
                return false
            }
        )
        await drainMainQueue()

        XCTAssertEqual(lookupCount, 1)
        XCTAssertEqual(replacementPrepareCount, 1)
    }

    func testPreferredPrimaryWebViewCandidatePrioritizesVisibleRuntimeWindow() {
        let owner = VisibleWebViewRuntimeOwner()
        let webViewSessions = WebViewSessionRepository()
        let visibleWindow = BrowserWindowState()
        let hiddenWindow = BrowserWindowState()
        let tab = makeWebTab()
        let visibleOwner = TrackedWebViewOwner(tabID: tab.id, windowID: visibleWindow.id)
        let hiddenOwner = TrackedWebViewOwner(tabID: tab.id, windowID: hiddenWindow.id)
        let visibleWebView = WKWebView()
        let hiddenWebView = WKWebView()

        visibleWindow.currentTabId = tab.id
        register(hiddenWebView, owner: hiddenOwner, in: webViewSessions)
        register(visibleWebView, owner: visibleOwner, in: webViewSessions)

        let candidate = owner.preferredPrimaryWebViewCandidate(
            for: tab.id,
            runtime: makeRuntime(
                windowStatesById: [
                    visibleWindow.id: visibleWindow,
                    hiddenWindow.id: hiddenWindow,
                ],
                currentTabId: { $0.concreteWindowState?.currentTabId },
                resolveTab: { tabId, _ in tabId == tab.id ? tab : nil }
            ),
            webViewSessions: webViewSessions
        )

        XCTAssertEqual(candidate?.owner, visibleOwner)
        XCTAssertIdentical(candidate?.webView, visibleWebView)
    }

    private func makeRuntime(
        windowStatesById: [UUID: BrowserWindowState] = [:],
        windowStateLookup: (@MainActor (UUID) -> (any WebRuntimeWindowHandle)?)? = nil,
        currentTabId: @escaping @MainActor (any WebRuntimeWindowHandle) -> UUID? = { _ in nil },
        splitVisibleTabIds: @escaping @MainActor (UUID) -> [UUID] = { _ in [] },
        resolveTab: @escaping @MainActor (UUID, any WebRuntimeWindowHandle) -> (any WebRuntimeTabHandle)? = { _, _ in nil },
        canMaterializeWebViewDuringStartup: @escaping @MainActor (
            any WebRuntimeTabHandle,
            any WebRuntimeWindowHandle
        ) -> Bool = { _, _ in true },
        markTabAccessed: @escaping @MainActor (UUID) -> Void = { _ in /* No-op. */ },
        evictHiddenWebViews: @escaping @MainActor (UUID, Set<UUID>) -> Void = { _, _ in /* No-op. */ },
        scheduleTabSuspensionReconcile: @escaping @MainActor (String) -> Void = { _ in /* No-op. */ },
        scheduleBackgroundMediaReconcile: @escaping @MainActor (String) -> Void = { _ in /* No-op. */ },
        refreshCompositor: @escaping @MainActor (UUID) -> Void = { _ in /* No-op. */ }
    ) -> VisibleWebViewPreparationRuntime {
        VisibleWebViewPreparationRuntime(
            windowState: windowStateLookup ?? { windowStatesById[$0] },
            currentTabId: currentTabId,
            splitVisibleTabIds: splitVisibleTabIds,
            resolveTab: resolveTab,
            canMaterializeWebViewDuringStartup:
                canMaterializeWebViewDuringStartup,
            markTabAccessed: markTabAccessed,
            evictHiddenWebViews: evictHiddenWebViews,
            scheduleTabSuspensionReconcile: scheduleTabSuspensionReconcile,
            scheduleBackgroundMediaReconcile: scheduleBackgroundMediaReconcile,
            refreshCompositor: refreshCompositor
        )
    }

    private func makeWebTab(urlString: String = "https://example.com") -> Tab {
        guard let url = URL(string: urlString) else {
            preconditionFailure("Invalid test URL: \(urlString)")
        }
        return Tab(
            url: url,
            loadsCachedFaviconOnInit: false
        )
    }

    private func register(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner,
        in repository: WebViewSessionRepository
    ) {
        WebViewTrackingLifecycleOwner().registerTrackedWebView(
            webView,
            for: owner,
            in: repository,
            removeFromContainers: { _ in /* No-op. */ },
            installRuntimeObservations: { _ in /* No-op. */ },
            uninstallRuntimeObservationsIfUntracked: { _ in /* No-op. */ },
            pruneInvalidDeferredCommands: { _ in /* No-op. */ },
            canDisplaceWebView: { _ in true },
            removeRecentVisibility: { _ in /* No-op. */ },
            cleanupDisplacedWebView: { _, _ in /* No-op. */ }
        )
    }
}

private func drainMainQueue() async {
    await Task.yield()
    await Task.yield()
}
