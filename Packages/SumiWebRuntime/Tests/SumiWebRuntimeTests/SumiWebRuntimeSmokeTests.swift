import XCTest
import WebKit
import SumiWebRuntime

final class SumiWebRuntimeSmokeTests: XCTestCase {
    @MainActor
    func testRegistryStartsEmpty() {
        let registry = WindowWebViewRegistry()
        XCTAssertTrue(registry.isEmpty)
        XCTAssertEqual(registry.totalTrackedWebViewCount, 0)
    }

    func testVisibleTabPreparationPlanOrdersSplitTabs() {
        let tabA = UUID()
        let tabB = UUID()
        let ordered = VisibleTabPreparationPlan.visibleTabIDs(
            currentTabId: tabA,
            splitTabIds: [tabB, tabA]
        )
        XCTAssertEqual(ordered, [tabB, tabA])
    }

    @MainActor
    func testWebRuntimeBoundaryProtocolsExposeSessionAccessors() {
        final class StubTab: WebRuntimeTabHandle {
            let id: UUID
            let localSession: TabWebViewSession
            let requiresPrimaryWebView = true
            var url = URL(string: "https://example.com")!
            let isEphemeral = false
            let resolvedProfileId: UUID? = nil

            init() {
                let id = UUID()
                self.id = id
                self.localSession = TabWebViewSession(tabId: id)
            }
        }

        final class StubWindow: WebRuntimeWindowHandle {
            let id = UUID()
            var ephemeralTabHandles: [any WebRuntimeTabHandle] = []
        }

        struct StubResolver: WebRuntimeTabResolving {
            let tab: any WebRuntimeTabHandle
            func resolveWebRuntimeTab(_ id: UUID) -> (any WebRuntimeTabHandle)? {
                tab.id == id ? tab : nil
            }
        }

        let tab = StubTab()
        let window = StubWindow()
        window.ephemeralTabHandles = [tab]
        let resolver = StubResolver(tab: tab)

        XCTAssertEqual(tab.localSession.tabId, tab.id)
        XCTAssertEqual(window.ephemeralTabHandles.first?.id, tab.id)
        XCTAssertIdentical(resolver.resolveWebRuntimeTab(tab.id) as AnyObject?, tab)
        XCTAssertNil(resolver.resolveWebRuntimeTab(UUID()))
    }

    @MainActor
    func testWebRuntimeTabMaterializingAndOwnershipMutatingSurfaces() {
        final class StubMaterializingTab: WebRuntimeTabMaterializing, WebRuntimeTabOwnershipMutating {
            private(set) var makeCallCount = 0
            private(set) var assignedWindowId: UUID?
            private(set) var clearedCurrent = false
            private(set) var clearedAll = false
            private var current: WKWebView?

            func makeNormalTabWebView(
                reason: String,
                prepareConfiguration: ((WKWebViewConfiguration) -> Void)?
            ) -> WKWebView? {
                makeCallCount += 1
                XCTAssertEqual(reason, "smoke")
                let configuration = WKWebViewConfiguration()
                prepareConfiguration?(configuration)
                let webView = WKWebView(frame: .zero, configuration: configuration)
                current = webView
                return webView
            }

            func assignWebViewToWindow(_ webView: WKWebView, windowId: UUID) {
                current = webView
                assignedWindowId = windowId
            }

            func clearCurrentWebViewOwnership() {
                clearedCurrent = true
                current = nil
            }

            func clearAllWebViewOwnership() {
                clearedAll = true
                current = nil
            }

            func currentWebViewIsIdentical(to webView: WKWebView) -> Bool {
                current === webView
            }
        }

        let stub = StubMaterializingTab()
        let materializing: any WebRuntimeTabMaterializing = stub
        let ownership: any WebRuntimeTabOwnershipMutating = stub

        guard let webView = materializing.makeNormalTabWebView(reason: "smoke") else {
            return XCTFail("Expected materializing stub to return a WebView")
        }
        XCTAssertEqual(stub.makeCallCount, 1)

        let windowId = UUID()
        ownership.assignWebViewToWindow(webView, windowId: windowId)
        XCTAssertEqual(stub.assignedWindowId, windowId)
        XCTAssertTrue(ownership.currentWebViewIsIdentical(to: webView))

        ownership.clearCurrentWebViewOwnership()
        XCTAssertTrue(stub.clearedCurrent)
        XCTAssertFalse(ownership.currentWebViewIsIdentical(to: webView))

        ownership.clearAllWebViewOwnership()
        XCTAssertTrue(stub.clearedAll)
    }

    @MainActor
    func testWebRuntimeTabTeardownLifecycleSurface() {
        final class StubTeardownTab: WebRuntimeTabHandle, WebRuntimeTabTeardownLifecycle {
            let id: UUID
            let localSession: TabWebViewSession
            let requiresPrimaryWebView = true
            var url = URL(string: "https://example.com")!
            let isEphemeral = false
            let resolvedProfileId: UUID? = nil
            private(set) var cleanedWebViews: [ObjectIdentifier] = []
            private(set) var cancelledNavigation = false
            private(set) var clearedAll = false

            init() {
                let id = UUID()
                self.id = id
                self.localSession = TabWebViewSession(tabId: id)
            }

            func cleanupCloneWebView(_ webView: WKWebView) {
                cleanedWebViews.append(ObjectIdentifier(webView))
            }

            func cancelPendingMainFrameNavigation() {
                cancelledNavigation = true
            }

            func clearAllWebViewOwnership() {
                clearedAll = true
            }
        }

        let stub = StubTeardownTab()
        let lifecycle: any WebRuntimeTabTeardownLifecycle = stub
        let webView = WKWebView()

        lifecycle.cleanupCloneWebView(webView)
        lifecycle.cancelPendingMainFrameNavigation()
        lifecycle.clearAllWebViewOwnership()

        XCTAssertEqual(stub.cleanedWebViews, [ObjectIdentifier(webView)])
        XCTAssertTrue(stub.cancelledNavigation)
        XCTAssertTrue(stub.clearedAll)
    }

    @MainActor
    func testTabTeardownOwnerSuspendsViaLifecycleProtocol() {
        final class StubTeardownTab: WebRuntimeTabHandle, WebRuntimeTabTeardownLifecycle {
            let id: UUID
            let localSession: TabWebViewSession
            let requiresPrimaryWebView = true
            var url = URL(string: "https://example.com")!
            let isEphemeral = false
            let resolvedProfileId: UUID? = nil
            private(set) var cleanedCount = 0
            private(set) var cancelledNavigation = false
            private(set) var clearedAll = false

            init() {
                let id = UUID()
                self.id = id
                self.localSession = TabWebViewSession(tabId: id)
            }

            func cleanupCloneWebView(_ webView: WKWebView) {
                cleanedCount += 1
            }

            func cancelPendingMainFrameNavigation() {
                cancelledNavigation = true
            }

            func clearAllWebViewOwnership() {
                clearedAll = true
            }
        }

        let registry = WindowWebViewRegistry()
        let sessionStore = TabWebViewSessionStore(webViewRegistry: registry)
        let mediaProtectionOwner = WebViewMediaProtectionOwner()
        let tab = StubTeardownTab()
        let webView = WKWebView()
        sessionStore.noteUntrackedWebView(webView, for: tab.id)

        let owner = WebViewTabTeardownOwner(
            webViewRegistry: registry,
            tabWebViewSessionStore: sessionStore,
            mediaProtectionOwner: mediaProtectionOwner,
            isWebViewProtectedFromCompositorMutation: { _ in false },
            enqueueDeferredProtectedCommand: { _, _, _ in false },
            cleanupUnprotectedTrackedWebView: { _, _, _ in },
            refreshPrimaryTrackedWebView: { _ in },
            removeWebViewFromContainers: { _ in },
            unregisterTrackedWebViewSlot: { _, _ in nil }
        )

        XCTAssertTrue(owner.suspendWebViews(for: tab, reason: "smoke"))
        XCTAssertEqual(tab.cleanedCount, 1)
        XCTAssertTrue(tab.cancelledNavigation)
        XCTAssertTrue(tab.clearedAll)
        XCTAssertTrue(owner.allKnownWebViews(for: tab).isEmpty)
    }

    @MainActor
    func testWebRuntimeTabSiteReloadMainFrameAndMuteSurfaces() {
        final class StubTab:
            WebRuntimeTabHandle,
            WebRuntimeTabSiteReloadPolicyNotifying,
            WebRuntimeTabMainFrameLoading,
            WebRuntimeTabAudioMuteSnapshotting
        {
            let id: UUID
            let localSession: TabWebViewSession
            let requiresPrimaryWebView = true
            var url = URL(string: "https://example.com")!
            let isEphemeral = false
            let resolvedProfileId: UUID? = nil
            var isAudioMuted = true
            private(set) var safariReloadCount = 0
            private(set) var protectionReloadCount = 0
            private(set) var autoplayReloadCount = 0
            private(set) var registerReasons: [String] = []
            private(set) var loadedURLs: [URL] = []

            init() {
                let id = UUID()
                self.id = id
                self.localSession = TabWebViewSession(tabId: id)
            }

            func updateSafariContentBlockerReloadRequirementForCurrentSite() {
                safariReloadCount += 1
            }

            func updateProtectionReloadRequirementForCurrentSite() {
                protectionReloadCount += 1
            }

            func updateAutoplayReloadRequirementForCurrentSite() {
                autoplayReloadCount += 1
            }

            func performMainFrameNavigationAfterContentBlockingAssetsIfNeeded(
                on webView: WKWebView,
                waitForContentBlockingAssets: Bool,
                performLoad: @escaping @MainActor @Sendable (WKWebView) -> Void
            ) {
                performLoad(webView)
            }

            func loadURL(
                _ url: URL,
                resolvedWebView: @escaping @MainActor @Sendable () -> WKWebView?,
                reason: String
            ) {
                loadedURLs.append(url)
                _ = resolvedWebView()
                _ = reason
            }

            func registerTabWithExtensionRuntimeIfNeeded(reason: String) {
                registerReasons.append(reason)
            }
        }

        let stub = StubTab()
        let handle: any WebRuntimeTabHandle = stub
        handle.url = URL(string: "https://example.com/updated")!
        XCTAssertEqual(stub.url.absoluteString, "https://example.com/updated")

        let reload: any WebRuntimeTabSiteReloadPolicyNotifying = stub
        reload.updateSafariContentBlockerReloadRequirementForCurrentSite()
        reload.updateProtectionReloadRequirementForCurrentSite()
        reload.updateAutoplayReloadRequirementForCurrentSite()
        XCTAssertEqual(stub.safariReloadCount, 1)
        XCTAssertEqual(stub.protectionReloadCount, 1)
        XCTAssertEqual(stub.autoplayReloadCount, 1)

        let loading: any WebRuntimeTabMainFrameLoading = stub
        let webView = WKWebView()
        loading.performMainFrameNavigationAfterContentBlockingAssetsIfNeeded(
            on: webView,
            waitForContentBlockingAssets: false
        ) { _ in }
        loading.loadURL(
            URL(string: "https://example.com/load")!,
            resolvedWebView: { webView },
            reason: "smoke"
        )
        loading.registerTabWithExtensionRuntimeIfNeeded(reason: "smoke.register")
        XCTAssertEqual(stub.loadedURLs.count, 1)
        XCTAssertEqual(stub.registerReasons, ["smoke.register"])

        let mute: any WebRuntimeTabAudioMuteSnapshotting = stub
        XCTAssertTrue(mute.isAudioMuted)
    }

    @MainActor
    func testRuntimeContextStoreStartsEmpty() {
        let store = WebViewRuntimeContextStore()
        XCTAssertNil(store.visible)
        XCTAssertNil(store.browser)
        XCTAssertNil(store.initialDocument)
        XCTAssertNil(store.shutdown)
    }

    @MainActor
    func testCompositorHandoffStateStoresPromotedHostAsProtocol() {
        final class StubHost: WebRuntimePromotedHost {
            let tabID = UUID()
            let webView = WKWebView()
            private(set) var prepareCount = 0

            func prepareForSuperviewTransferPreservingDisplayedContent() {
                prepareCount += 1
            }
        }

        let handoffState = WebViewCompositorHandoffState()
        let host = StubHost()
        let windowID = UUID()

        handoffState.registerPromotedHost(host, for: host.tabID, in: windowID)

        let taken = handoffState.takePromotedHost(
            for: host.tabID,
            in: windowID,
            expectedWebView: host.webView
        )
        XCTAssertIdentical(taken as AnyObject?, host)
        XCTAssertEqual(host.prepareCount, 1)
        XCTAssertNil(
            handoffState.takePromotedHost(
                for: host.tabID,
                in: windowID,
                expectedWebView: host.webView
            )
        )
    }

    @MainActor
    func testVisibleWebViewRuntimeOwnerConformsToPreparationControlling() {
        final class StubWindow: WebRuntimeWindowHandle {
            let id = UUID()
            var ephemeralTabHandles: [any WebRuntimeTabHandle] = []
        }

        final class StubTab: WebRuntimeTabHandle {
            let id: UUID
            let localSession: TabWebViewSession
            let requiresPrimaryWebView = true
            var url = URL(string: "https://example.com")!
            let isEphemeral = false
            let resolvedProfileId: UUID? = nil

            init() {
                let id = UUID()
                self.id = id
                self.localSession = TabWebViewSession(tabId: id)
            }
        }

        let owner = VisibleWebViewRuntimeOwner()
        let controlling: any WebRuntimeVisiblePreparationControlling = owner
        let window = StubWindow()
        let tab = StubTab()
        let registry = WindowWebViewRegistry()
        var marked: [UUID] = []
        var created = 0

        let runtime = VisibleWebViewPreparationRuntime(
            windowState: { $0 == window.id ? window : nil },
            currentTabId: { $0.id == window.id ? tab.id : nil },
            splitVisibleTabIds: { _ in [] },
            resolveTab: { tabId, _ in tabId == tab.id ? tab : nil },
            canMaterializeWebViewDuringStartup: { _ in true },
            markTabAccessed: { marked.append($0) },
            evictHiddenWebViews: { _, _ in },
            scheduleTabSuspensionReconcile: { _ in },
            scheduleBackgroundMediaReconcile: { _ in },
            refreshCompositor: { _ in }
        )

        let didCreate = owner.prepareVisibleWebViews(
            for: window,
            runtime: runtime,
            webViewRegistry: registry,
            existingWebView: { _, _ in nil },
            createWebView: { _, _ in
                created += 1
                return WKWebView()
            }
        )

        XCTAssertTrue(didCreate)
        XCTAssertEqual(created, 1)
        XCTAssertEqual(marked, [tab.id])

        controlling.cancelScheduledPreparation(for: window.id)
        controlling.resetWindowRegistrations()
    }

    @MainActor
    func testWindowCleanupOwnerUsesVisiblePreparationControlling() {
        final class StubVisiblePreparation: WebRuntimeVisiblePreparationControlling {
            var cancelledWindowIDs: [UUID] = []
            var didReset = false

            func cancelScheduledPreparation(for windowId: UUID) {
                cancelledWindowIDs.append(windowId)
            }

            func resetWindowRegistrations() {
                didReset = true
            }
        }

        let registry = WindowWebViewRegistry()
        let visible = StubVisiblePreparation()
        let media = WebViewMediaProtectionOwner()
        let scope = WebViewCleanupScopeOwner()
        var removedContainers: [UUID] = []
        var finishedSuppression = false

        let owner = WebViewWindowCleanupOwner(
            cleanupScopeOwner: scope,
            webViewRegistry: registry,
            visibleWebViewRuntimeOwner: visible,
            mediaProtectionOwner: media,
            browserRuntimeContext: { nil },
            isWebViewProtectedFromCompositorMutation: { _ in false },
            enqueueDeferredProtectedCommand: { _, _, _ in false },
            cleanupUnprotectedTrackedWebView: { _, _, _ in },
            refreshPrimaryTrackedWebView: { _ in },
            removeCompositorContainerView: { removedContainers.append($0) },
            finishCleanupSuppression: { _ in finishedSuppression = true }
        )

        let windowID = UUID()
        owner.cleanupWindow(windowID)
        XCTAssertEqual(visible.cancelledWindowIDs, [windowID])
        XCTAssertEqual(removedContainers, [windowID])

        owner.cleanupAllWebViews()
        XCTAssertTrue(visible.didReset)
        XCTAssertTrue(finishedSuppression)
    }
}
