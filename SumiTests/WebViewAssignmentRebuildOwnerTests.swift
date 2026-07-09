import WebKit
import XCTest
import SumiWebRuntime

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
                tab: tab,
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
        XCTAssertIdentical(tab.resolvedAssignedWebView(), webView)
        XCTAssertEqual(tab.resolvedPrimaryWindowId(), windowId)
    }

    func testRefreshPrimaryTrackedWebViewClearsOwnershipWhenCandidateIsMissing() {
        let owner = WebViewAssignmentRebuildOwner()
        let tab = makeTab()
        let originalWindowId = UUID()
        tab.assignWebViewToWindow(WKWebView(frame: .zero), windowId: originalWindowId)

        owner.refreshPrimaryTrackedWebView(
            for: tab,
            runtime: makeRuntime(tab: tab, primaryCandidate: { _ in nil })
        )

        XCTAssertNil(tab.resolvedAssignedWebView())
        XCTAssertNil(tab.resolvedPrimaryWindowId())
    }

    func testRebuildLiveWebViewsDoesNotUseStalePrimaryMirrorAsTargetWindow() {
        let owner = WebViewAssignmentRebuildOwner()
        let tab = makeTab()
        let staleWindowId = UUID()
        tab.assignWebViewToWindow(WKWebView(frame: .zero), windowId: staleWindowId)

        let rebuilt = owner.rebuildLiveWebViews(
            for: tab,
            runtime: makeRuntime(tab: tab)
        )

        XCTAssertFalse(rebuilt)
        XCTAssertEqual(tab.resolvedPrimaryWindowId(), staleWindowId)
    }

    func testRefreshPrimaryUsesRuntimeOwnershipWitnessNotOnlyConcreteFallback() {
        let owner = WebViewAssignmentRebuildOwner()
        let tab = makeTab()
        let windowId = UUID()
        let webView = WKWebView(frame: .zero)
        let ownershipProbe = OwnershipWitnessProbe(backing: tab)

        owner.refreshPrimaryTrackedWebView(
            for: tab,
            runtime: makeRuntime(
                tab: tab,
                primaryCandidate: { _ in
                    (
                        TrackedWebViewOwner(tabID: tab.id, windowID: windowId),
                        webView
                    )
                },
                tabOwnership: ownershipProbe
            )
        )

        XCTAssertEqual(ownershipProbe.assignCallCount, 1)
        XCTAssertEqual(ownershipProbe.lastAssignedWindowId, windowId)
        XCTAssertIdentical(ownershipProbe.lastAssignedWebView, webView)
        XCTAssertIdentical(tab.resolvedAssignedWebView(), webView)
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
        tab.clearCurrentWebViewOwnership()
        tab.parkExistingWebView(parkedWebView)

        let windowId = UUID()
        let registry = WindowWebViewRegistry()
        var registered: [(UUID, UUID, WKWebView)] = []
        let owner = WebViewAssignmentRebuildOwner()

        let created = try XCTUnwrap(
            owner.getOrCreateWebView(
                for: tab,
                in: windowId,
                runtime: makeRuntime(
                    tab: tab,
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
        XCTAssertIdentical(tab.resolvedAssignedWebView(), created)
        XCTAssertEqual(tab.resolvedPrimaryWindowId(), windowId)
        XCTAssertIdentical(tab.resolvedParkedWebView(), parkedWebView)
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
                    tab: tab,
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
        XCTAssertIdentical(tab.resolvedAssignedWebView(), created)
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
                tab: tab,
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
        let recreated = try XCTUnwrap(tab.resolvedAssignedWebView())
        XCTAssertFalse(recreated === stalePrimary)
        XCTAssertEqual(tab.resolvedPrimaryWindowId(), windowId)
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
        tab: Tab? = nil,
        webViewRegistry: WindowWebViewRegistry = WindowWebViewRegistry(),
        registerTrackedWebView: @escaping WebViewAssignmentRebuildOwner.RegisterTrackedWebView = { _, _, _ in },
        unregisterTrackedWebViewSlot: @escaping WebViewAssignmentRebuildOwner.UnregisterTrackedWebViewSlot = { _, _ in nil },
        primaryCandidate: @escaping WebViewAssignmentRebuildOwner.PrimaryCandidateResolver = { _ in nil },
        tabMaterializing: (any WebRuntimeTabMaterializing)? = nil,
        tabOwnership: (any WebRuntimeTabOwnershipMutating)? = nil,
        tabTeardown: (any WebRuntimeTabTeardownLifecycle)? = nil,
        tabSiteReloadPolicy: (any WebRuntimeTabSiteReloadPolicyNotifying)? = nil,
        tabMainFrameLoading: (any WebRuntimeTabMainFrameLoading)? = nil,
        tabAudioMute: (any WebRuntimeTabAudioMuteSnapshotting)? = nil,
        schedulePrimaryInitialDocumentLoad: WebViewAssignmentRebuildOwner.SchedulePrimaryInitialDocumentLoad? = nil,
        scheduleCloneInitialDocumentLoad: WebViewAssignmentRebuildOwner.ScheduleCloneInitialDocumentLoad? = nil
    ) -> WebViewAssignmentRebuildOwner.Runtime {
        // Mirror live assembler wiring: pass Tab as protocol witnesses when available.
        let materializing = tabMaterializing ?? tab
        let ownership = tabOwnership ?? tab
        let teardown = tabTeardown ?? tab
        let siteReload = tabSiteReloadPolicy ?? tab
        let mainFrame = tabMainFrameLoading ?? tab
        let audioMute = tabAudioMute ?? tab
        let primaryLoad = schedulePrimaryInitialDocumentLoad ?? { webView, handle, ownership, mainFrameLoading, reason in
            // Test-local handoff mirroring assembler primary scheduling.
            let targetURL = handle.url
            guard TabNormalWebViewSetupOwner.isInitialDocumentExtensionWarmupURL(targetURL) else {
                mainFrameLoading.registerTabWithExtensionRuntimeIfNeeded(reason: reason)
                return
            }
            Task { @MainActor in
                await NormalTabInitialDocumentRuntimeHandoff.perform {
                    /* No-op wait. */
                } warmInitialDocumentContexts: {
                    /* No-op warm. */
                } isStillValid: {
                    ownership.currentWebViewIsIdentical(to: webView)
                } register: {
                    mainFrameLoading.registerTabWithExtensionRuntimeIfNeeded(
                        reason: "\(reason).beforeInitialLoad"
                    )
                } load: {
                    mainFrameLoading.loadURL(
                        targetURL,
                        resolvedWebView: { webView },
                        reason: "\(reason).initialLoad"
                    )
                }
            }
        }
        let cloneLoad = scheduleCloneInitialDocumentLoad ?? { webView, handle, _, targetURL in
            guard let concrete = handle.concreteTab else { return }
            NormalTabInitialDocumentRuntimeHandoff.scheduleCloneInitialLoad(
                tab: concrete,
                webView: webView,
                targetURL: targetURL,
                profileId: handle.resolvedProfileId,
                registrationReason: "WebViewCoordinator.loadInitialURLIfNeeded"
            )
        }
        return WebViewAssignmentRebuildOwner.Runtime(
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
            notifyTabActivatedIfCurrent: { _, _ in /* No-op. */ },
            tabMaterializing: materializing,
            tabOwnership: ownership,
            tabTeardown: teardown,
            tabSiteReloadPolicy: siteReload,
            tabMainFrameLoading: mainFrame,
            tabAudioMute: audioMute,
            schedulePrimaryInitialDocumentLoad: primaryLoad,
            scheduleCloneInitialDocumentLoad: cloneLoad
        )
    }
}

/// Forwards ownership mutations to a backing Tab while recording protocol-surface calls.
@MainActor
private final class OwnershipWitnessProbe: WebRuntimeTabOwnershipMutating {
    private let backing: Tab
    private(set) var assignCallCount = 0
    private(set) var lastAssignedWebView: WKWebView?
    private(set) var lastAssignedWindowId: UUID?

    init(backing: Tab) {
        self.backing = backing
    }

    func assignWebViewToWindow(_ webView: WKWebView, windowId: UUID) {
        assignCallCount += 1
        lastAssignedWebView = webView
        lastAssignedWindowId = windowId
        backing.assignWebViewToWindow(webView, windowId: windowId)
    }

    func clearCurrentWebViewOwnership() {
        backing.clearCurrentWebViewOwnership()
    }

    func clearAllWebViewOwnership() {
        backing.clearAllWebViewOwnership()
    }

    func currentWebViewIsIdentical(to webView: WKWebView) -> Bool {
        backing.currentWebViewIsIdentical(to: webView)
    }
}
