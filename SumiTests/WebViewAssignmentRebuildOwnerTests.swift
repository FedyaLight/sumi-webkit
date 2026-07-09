import WebKit
import XCTest

@testable import Sumi

@MainActor
final class WebViewAssignmentRebuildOwnerTests: XCTestCase {
    func testRefreshPrimaryTrackedWebViewUsesInjectedCandidate() {
        let owner = WebViewAssignmentRebuildOwner()
        let tab = makeTab()
        let windowId = UUID()
        let webView = WKWebView(frame: .zero)
        var requestedTabIds: [UUID] = []

        owner.refreshPrimaryTrackedWebView(
            for: tab,
            runtime: makeRuntime(
                primaryCandidate: { tabId in
                    requestedTabIds.append(tabId)
                    return (
                        TrackedWebViewOwner(tabID: tab.id, windowID: windowId),
                        webView
                    )
                }
            )
        )

        XCTAssertEqual(requestedTabIds, [tab.id])
        XCTAssertIdentical(tab.assignedWebView, webView)
        XCTAssertEqual(tab.primaryWindowId, windowId)
    }

    func testRefreshPrimaryTrackedWebViewClearsOwnershipWhenCandidateIsMissing() {
        let owner = WebViewAssignmentRebuildOwner()
        let tab = makeTab()
        let originalWindowId = UUID()
        tab.assignWebViewToWindow(WKWebView(frame: .zero), windowId: originalWindowId)

        owner.refreshPrimaryTrackedWebView(
            for: tab,
            runtime: makeRuntime(primaryCandidate: { _ in nil })
        )

        XCTAssertNil(tab.assignedWebView)
        XCTAssertNil(tab.primaryWindowId)
    }

    func testRebuildLiveWebViewsDoesNotUseStalePrimaryMirrorAsTargetWindow() {
        let owner = WebViewAssignmentRebuildOwner()
        let tab = makeTab()
        let staleWindowId = UUID()
        tab.assignWebViewToWindow(WKWebView(frame: .zero), windowId: staleWindowId)

        let rebuilt = owner.rebuildLiveWebViews(
            for: tab,
            runtime: makeRuntime()
        )

        XCTAssertFalse(rebuilt)
        XCTAssertEqual(tab.primaryWindowId, staleWindowId)
    }

    func testCreatePrimaryUsesFactoryInsteadOfParkedEnsureWebViewReuse() async throws {
        let browserManager = BrowserManager()
        await waitForInitialTabManagerDataLoad(on: browserManager)
        let tab = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/create-primary-factory",
            in: browserManager.tabManager.spaceStateOwner.currentSpace,
            activate: false
        )
        let parkedWebView = try XCTUnwrap(
            tab.makeNormalTabWebView(
                reason: "WebViewAssignmentRebuildOwnerTests.parkedForCreatePrimary"
            )
        )
        tab._webView = nil
        tab._existingWebView = parkedWebView
        tab.primaryWindowId = nil

        let windowId = UUID()
        let registry = WindowWebViewRegistry()
        var registered: [(UUID, UUID, WKWebView)] = []
        let owner = WebViewAssignmentRebuildOwner()

        let created = try XCTUnwrap(
            owner.getOrCreateWebView(
                for: tab,
                in: windowId,
                runtime: makeRuntime(
                    webViewRegistry: registry,
                    registerTrackedWebView: { webView, tabId, registeredWindowId in
                        registered.append((tabId, registeredWindowId, webView))
                        registry.setWebView(
                            webView,
                            for: TrackedWebViewOwner(tabID: tabId, windowID: registeredWindowId)
                        )
                    }
                )
            )
        )

        XCTAssertFalse(
            created === parkedWebView,
            "createPrimary must use makeNormalTabWebView, not ensureWebView/setupWebView parked reuse"
        )
        XCTAssertIdentical(tab.assignedWebView, created)
        XCTAssertEqual(tab.primaryWindowId, windowId)
        XCTAssertIdentical(tab.parkedWebView, parkedWebView)
        XCTAssertEqual(registered.count, 1)
        XCTAssertEqual(registered[0].0, tab.id)
        XCTAssertEqual(registered[0].1, windowId)
        XCTAssertIdentical(registered[0].2, created)
        XCTAssertIdentical(registry.webView(for: tab.id, in: windowId), created)
    }

    func testCreatePrimarySchedulesInitialDocumentLoadHandoff() async throws {
        let browserManager = BrowserManager()
        await waitForInitialTabManagerDataLoad(on: browserManager)
        let targetURL = URL(string: "https://example.com/create-primary-initial-load")!
        let tab = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: targetURL.absoluteString,
            in: browserManager.tabManager.spaceStateOwner.currentSpace,
            activate: false
        )

        var registeredReasons: [String] = []
        let previousRuntime = tab.navigationRuntime.normalWebViewExtensionRuntime
        tab.navigationRuntime.normalWebViewExtensionRuntime = TabNormalWebViewExtensionRuntime(
            registerTabWithExtensionRuntimeIfNeeded: { _, reason in
                registeredReasons.append(reason)
            },
            prepareWebViewForExtensionRuntime: previousRuntime.prepareWebViewForExtensionRuntime,
            ensureInitialExtensionContextsIfNeeded: previousRuntime.ensureInitialExtensionContextsIfNeeded
        )
        defer {
            tab.navigationRuntime.normalWebViewExtensionRuntime = previousRuntime
        }

        let windowId = UUID()
        let registry = WindowWebViewRegistry()
        let owner = WebViewAssignmentRebuildOwner()
        let created = try XCTUnwrap(
            owner.getOrCreateWebView(
                for: tab,
                in: windowId,
                runtime: makeRuntime(
                    webViewRegistry: registry,
                    registerTrackedWebView: { webView, tabId, registeredWindowId in
                        registry.setWebView(
                            webView,
                            for: TrackedWebViewOwner(tabID: tabId, windowID: registeredWindowId)
                        )
                    }
                )
            )
        )

        for _ in 0..<40 {
            await Task.yield()
            if registeredReasons.contains(where: { $0.contains("createPrimaryWebView.beforeInitialLoad") }) {
                break
            }
        }

        XCTAssertTrue(
            registeredReasons.contains(where: { $0.contains("createPrimaryWebView.beforeInitialLoad") }),
            "Factory createPrimary must schedule the initial-document handoff that ensureWebView used to run; reasons=\(registeredReasons)"
        )
        XCTAssertIdentical(tab.assignedWebView, created)
        XCTAssertEqual(tab.url, targetURL)
    }

    func testRebuildLiveWebViewsRecreatesPrimaryViaFactoryAndRegisters() async throws {
        let browserManager = BrowserManager()
        await waitForInitialTabManagerDataLoad(on: browserManager)
        let tab = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/rebuild-primary-factory",
            in: browserManager.tabManager.spaceStateOwner.currentSpace,
            activate: false
        )
        let windowId = UUID()
        let stalePrimary = try XCTUnwrap(
            tab.makeNormalTabWebView(
                reason: "WebViewAssignmentRebuildOwnerTests.stalePrimaryForRebuild"
            )
        )
        tab.assignWebViewToWindow(stalePrimary, windowId: windowId)

        let registry = WindowWebViewRegistry()
        registry.setWebView(
            stalePrimary,
            for: TrackedWebViewOwner(tabID: tab.id, windowID: windowId)
        )
        var registered: [(UUID, UUID, WKWebView)] = []
        let owner = WebViewAssignmentRebuildOwner()

        let rebuilt = owner.rebuildLiveWebViews(
            for: tab,
            preferredPrimaryWindowId: windowId,
            runtime: makeRuntime(
                webViewRegistry: registry,
                registerTrackedWebView: { webView, tabId, registeredWindowId in
                    registered.append((tabId, registeredWindowId, webView))
                    registry.setWebView(
                        webView,
                        for: TrackedWebViewOwner(tabID: tabId, windowID: registeredWindowId)
                    )
                },
                unregisterTrackedWebViewSlot: { owner, expected in
                    let removed = registry.webView(for: owner)
                    registry.removeWebView(
                        owner: owner,
                        resolvedWebView: expected ?? removed,
                        removeRecentVisibility: true
                    )
                    return removed
                },
                primaryCandidate: { tabId in
                    guard let webView = registry.webView(for: tabId, in: windowId) else { return nil }
                    return (
                        TrackedWebViewOwner(tabID: tabId, windowID: windowId),
                        webView
                    )
                }
            )
        )

        XCTAssertTrue(rebuilt)
        let recreated = try XCTUnwrap(tab.assignedWebView)
        XCTAssertFalse(recreated === stalePrimary)
        XCTAssertEqual(tab.primaryWindowId, windowId)
        XCTAssertEqual(registered.count, 1)
        XCTAssertIdentical(registered[0].2, recreated)
        XCTAssertIdentical(registry.webView(for: tab.id, in: windowId), recreated)
    }

    private func makeTab() -> Tab {
        Tab(
            url: URL(string: "https://example.com")!,
            loadsCachedFaviconOnInit: false
        )
    }

    private func waitForInitialTabManagerDataLoad(on browserManager: BrowserManager) async {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if browserManager.tabManager.hasLoadedInitialData { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for initial tab manager data load")
    }

    private func makeRuntime(
        webViewRegistry: WindowWebViewRegistry = WindowWebViewRegistry(),
        registerTrackedWebView: @escaping WebViewAssignmentRebuildOwner.RegisterTrackedWebView = { _, _, _ in },
        unregisterTrackedWebViewSlot: @escaping WebViewAssignmentRebuildOwner.UnregisterTrackedWebViewSlot = { _, _ in nil },
        primaryCandidate: @escaping WebViewAssignmentRebuildOwner.PrimaryCandidateResolver = { _ in nil }
    ) -> WebViewAssignmentRebuildOwner.Runtime {
        WebViewAssignmentRebuildOwner.Runtime(
            webViewRegistry: webViewRegistry,
            tabWebViewSessionStore: TabWebViewSessionStore(webViewRegistry: webViewRegistry),
            initialDocumentWarmupRuntime: nil,
            registerTrackedWebView: registerTrackedWebView,
            unregisterTrackedWebViewSlot: unregisterTrackedWebViewSlot,
            removeFromContainers: { _ in /* No-op. */ },
            isWebViewProtectedFromCompositorMutation: { _ in false },
            deferProtectedRebuild: { _, _, _ in /* No-op. */ },
            primaryCandidate: primaryCandidate,
            liveWindowSelection: { .allTrackedWindows },
            refreshCompositor: { _ in /* No-op. */ },
            notifyTabActivatedIfCurrent: { _, _ in /* No-op. */ }
        )
    }
}
