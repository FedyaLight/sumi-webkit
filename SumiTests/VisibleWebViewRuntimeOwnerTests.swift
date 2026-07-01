import WebKit
import XCTest

@testable import Sumi

@MainActor
final class VisibleWebViewRuntimeOwnerTests: XCTestCase {
    func testPrepareVisibleWebViewsUsesRuntimeWithoutBrowserManager() {
        let owner = VisibleWebViewRuntimeOwner()
        let webViewRegistry = WindowWebViewRegistry()
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
                currentTabId: { $0.currentTabId },
                splitVisibleTabIds: { _ in [currentTab.id, splitTab.id] },
                resolveTab: { tabId, _ in tabsById[tabId] },
                markTabAccessed: { markedTabIds.append($0) },
                evictHiddenWebViews: { _, visibleTabIds in
                    evictedVisibleTabIds = visibleTabIds
                },
                scheduleTabSuspensionReconcile: { suspensionReasons.append($0) },
                scheduleBackgroundMediaReconcile: { mediaReasons.append($0) }
            ),
            webViewRegistry: webViewRegistry,
            existingWebView: { _, _ in nil },
            createWebView: { tab, windowId in
                createdPairs.append((tab.id, windowId))
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

    func testSchedulePrepareVisibleWebViewsCoalescesAndRefreshesOnce() async {
        let owner = VisibleWebViewRuntimeOwner()
        let windowState = BrowserWindowState()
        var prepareCount = 0
        var refreshedWindowIds: [UUID] = []

        let runtime = makeRuntime(
            windowStatesById: [windowState.id: windowState],
            refreshCompositor: { refreshedWindowIds.append($0.id) }
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

    func testPreferredPrimaryWebViewCandidatePrioritizesVisibleRuntimeWindow() {
        let owner = VisibleWebViewRuntimeOwner()
        let webViewRegistry = WindowWebViewRegistry()
        let visibleWindow = BrowserWindowState()
        let hiddenWindow = BrowserWindowState()
        let tab = makeWebTab()
        let visibleOwner = TrackedWebViewOwner(tabID: tab.id, windowID: visibleWindow.id)
        let hiddenOwner = TrackedWebViewOwner(tabID: tab.id, windowID: hiddenWindow.id)
        let visibleWebView = WKWebView()
        let hiddenWebView = WKWebView()

        visibleWindow.currentTabId = tab.id
        webViewRegistry.setWebView(hiddenWebView, for: hiddenOwner)
        webViewRegistry.setWebView(visibleWebView, for: visibleOwner)

        let candidate = owner.preferredPrimaryWebViewCandidate(
            for: tab.id,
            runtime: makeRuntime(
                windowStatesById: [
                    visibleWindow.id: visibleWindow,
                    hiddenWindow.id: hiddenWindow,
                ],
                currentTabId: { $0.currentTabId },
                resolveTab: { tabId, _ in tabId == tab.id ? tab : nil }
            ),
            webViewRegistry: webViewRegistry
        )

        XCTAssertEqual(candidate?.owner, visibleOwner)
        XCTAssertIdentical(candidate?.webView, visibleWebView)
    }

    private func makeRuntime(
        windowStatesById: [UUID: BrowserWindowState] = [:],
        currentTabId: @escaping @MainActor (BrowserWindowState) -> UUID? = { _ in nil },
        splitVisibleTabIds: @escaping @MainActor (UUID) -> [UUID] = { _ in [] },
        resolveTab: @escaping @MainActor (UUID, BrowserWindowState) -> Tab? = { _, _ in nil },
        canMaterializeWebViewDuringStartup: @escaping @MainActor (
            Tab
        ) -> Bool = { _ in true },
        markTabAccessed: @escaping @MainActor (UUID) -> Void = { _ in /* No-op. */ },
        evictHiddenWebViews: @escaping @MainActor (UUID, Set<UUID>) -> Void = { _, _ in /* No-op. */ },
        scheduleTabSuspensionReconcile: @escaping @MainActor (String) -> Void = { _ in /* No-op. */ },
        scheduleBackgroundMediaReconcile: @escaping @MainActor (String) -> Void = { _ in /* No-op. */ },
        refreshCompositor: @escaping @MainActor (BrowserWindowState) -> Void = { _ in /* No-op. */ }
    ) -> VisibleWebViewPreparationRuntime {
        VisibleWebViewPreparationRuntime(
            windowState: { windowStatesById[$0] },
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
        Tab(
            url: URL(string: urlString)!,
            loadsCachedFaviconOnInit: false
        )
    }
}

private func drainMainQueue() async {
    await Task.yield()
    await Task.yield()
}
