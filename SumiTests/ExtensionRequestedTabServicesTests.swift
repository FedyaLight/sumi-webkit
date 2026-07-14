import AppKit
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionRequestedTabServicesTests:
    SafariExtensionWebViewControllerWiringTestCase {
    func testRecentOpenRequestTrackerConsumesOnlyRecordedWebURLsOnce() {
        let history = ExtensionRecentTabRequestHistory()
        let url = URL(string: "https://example.com/login")!

        XCTAssertFalse(history.consume(url))

        history.record(url)

        XCTAssertTrue(history.consume(url))
        XCTAssertFalse(history.consume(url))
    }

    func testRecentOpenRequestTrackerIgnoresNonWebURLs() {
        let history = ExtensionRecentTabRequestHistory()
        let extensionURL = URL(string: "safari-web-extension://ext-id/popup.html")!

        history.record(extensionURL)

        XCTAssertFalse(history.consume(extensionURL))
    }

    func testActiveNormalTabWithoutTargetWindowKeepsMaterializedUntrackedWebView() throws {
        SafariExtensionLiveWebKitTestLease.holdForProcess()
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeSafariExtensionTestExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )
        _ = manager.runtimeDemandCoordinator.request(
            reason: .install,
            allowWithoutEnabledExtensions: true
        )
        let expectedController = manager.ensureExtensionController(for: profile.id)
        let browserManager = makeSafariExtensionTestBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)
        let materializer = manager.requestedTabWebViewMaterializer
        let space = browserManager.tabManager.spaceStateOwner.firstSpace(
            forProfile: profile.id
        ) ?? browserManager.tabManager.spaceServices.catalog.createSpace(
            name: "Extension requested",
            profileId: profile.id
        )
        let tab = browserManager.tabManager.regularTabLifecycleOwner
            .createNewTab(
                url: "https://example.com",
                in: space,
                activate: true
            )
        tab.profileId = profile.id
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))

        materializer.materializeNormalTabIfNeeded(
            tab,
            targetWindow: nil
        )

        let materializedWebView = try XCTUnwrap(tab.resolvedCurrentWebView())
        XCTAssertNil(tab.resolvedPrimaryWindowId())
        XCTAssertIdentical(
            manager.exactExtensionTabWebViews.untrackedWebView(for: tab),
            materializedWebView
        )
        XCTAssertIdentical(
            materializedWebView.configuration.webExtensionController,
            expectedController
        )

        materializer.materializeNormalTabIfNeeded(
            tab,
            targetWindow: nil
        )

        XCTAssertIdentical(tab.resolvedCurrentWebView(), materializedWebView)
    }

    func testRequestedTargetSpaceUsesContextProfileWhenCurrentSpaceBelongsToAnotherProfile() throws {
        let harness = try makeProfileRoutingHarness()
        let resolver = harness.manager.requestedTabTargetResolver

        let targetSpace = resolver.targetSpace(
            for: nil,
            contextProfileId: harness.profileB.id
        )

        XCTAssertEqual(targetSpace?.id, harness.spaceB.id)
    }

    func testRegularExtensionTabInheritsTargetSpaceProfileIdentity() throws {
        let harness = try makeProfileRoutingHarness()

        let tab = harness.browserManager.extensionBridgeComposition.tabMutation
            .createExtensionTab(
                url: URL(string: "https://example.com/profile-b")!,
                in: harness.spaceB,
                activate: false,
                webExtensionContextOverride: nil
            )

        XCTAssertEqual(tab.spaceId, harness.spaceB.id)
        XCTAssertNil(tab.profileId)
        XCTAssertIdentical(tab.resolveProfile(), harness.profileB)
    }

    func testExtensionTargetSpaceWithoutWindowDoesNotFallbackToGlobalCurrentSpace() throws {
        let harness = try makeProfileRoutingHarness()

        let targetSpace = harness.browserManager.extensionBridgeComposition
            .requestedTabTargets.extensionTargetSpace(
            for: nil as BrowserWindowState?
        )

        XCTAssertNil(targetSpace)
    }

    func testExtensionTargetSpaceForTabWithoutSpaceDoesNotFallbackToGlobalCurrentSpace() throws {
        let harness = try makeProfileRoutingHarness()
        let tab = Tab(
            url: URL(string: "https://example.com/no-space")!,
            name: "No Space"
        )

        let targetSpace = harness.browserManager.extensionBridgeComposition
            .requestedTabTargets.extensionTargetSpace(for: tab)

        XCTAssertNil(targetSpace)
    }

    func testActiveWindowCurrentTabDoesNotFallbackToGlobalTabManagerCurrentTab() throws {
        let harness = try makeProfileRoutingHarness()
        let tab = harness.browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/current",
            in: harness.spaceA,
            activate: true
        )

        XCTAssertEqual(harness.browserManager.tabManager.selectionStateOwner.currentTab?.id, tab.id)
        XCTAssertNil(
            harness.browserManager.extensionBridgeComposition.windows
                .currentExtensionTabForActiveWindow()
        )
    }

    func testPreferredExtensionWindowStateResolvesTransientTabFromDisplayedSpace() throws {
        let harness = try makeProfileRoutingHarness()
        let windowRegistry = WindowRegistry()
        harness.browserManager.windowRegistry = windowRegistry
        let windowState = BrowserWindowState()
        windowState.currentProfileId = harness.profileA.id
        windowState.currentSpaceId = harness.spaceA.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let tab = harness.browserManager.tabManager.transientWebKitTabLifecycleOwner.createTransientExtensionTab(
            url: "safari-web-extension://extension-id/popup.html",
            in: harness.spaceA,
            webExtensionContextOverride: nil
        )

        XCTAssertTrue(harness.browserManager.tabManager.transientWebKitTabLifecycleOwner.isTransientExtensionTab(tab))
        XCTAssertFalse(
            harness.browserManager.tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[harness.spaceA.id]?.contains { $0.id == tab.id }
                ?? false
        )
        XCTAssertEqual(
            harness.browserManager.extensionBridgeComposition.windows
                .preferredExtensionWindowState(containing: tab)?.id,
            windowState.id
        )
    }

    func testExtensionTargetSpaceUsesWindowProfileBeforeCurrentSpaceFallback() throws {
        let harness = try makeProfileRoutingHarness()
        let windowState = BrowserWindowState()
        windowState.currentProfileId = harness.profileB.id
        windowState.currentSpaceId = harness.spaceA.id

        let targetSpace = harness.browserManager.extensionBridgeComposition
            .requestedTabTargets.extensionTargetSpace(for: windowState)

        XCTAssertEqual(targetSpace?.id, harness.spaceB.id)
    }

    func testTargetlessActivePinnedRequestCommitsOpenBeforeSelection() async throws {
        let harness = try await makeRequestedPublicationHarness()
        var events: [String] = []
        var openedTab: Tab?
        var wasInactiveAtOpen = false
        var hadExactWindowWebViewAtOpen = false

        harness.manager.testHooks.didOpenTab = { tabID in
            guard tabID != harness.sourceTab.id,
                  let tab = harness.browserManager.tabManager
                    .tabCollectionMembershipOwner.tab(for: tabID)
            else {
                return
            }
            openedTab = tab
            events.append("didOpen")
            wasInactiveAtOpen = harness.window.currentTabId
                == harness.sourceTab.id
            hadExactWindowWebViewAtOpen = harness.browserManager
                .webViewRuntime.ownershipQuery.webView(
                    for: tab.id,
                    in: harness.window.id
                ) === harness.manager.exactExtensionTabWebViews
                    .liveWebView(for: tab)
        }
        harness.manager.testHooks.didActivateTab = { tabID in
            guard tabID != harness.sourceTab.id else { return }
            events.append("didActivate")
        }
        defer {
            harness.manager.testHooks.didOpenTab = nil
            harness.manager.testHooks.didActivateTab = nil
        }

        let tab = try harness.manager.requestedTabOpening.open(
            url: URL(string: "https://requested.example/active")!,
            shouldBeActive: true,
            shouldBePinned: true,
            requestedWindow: nil,
            controller: harness.controller,
            extensionContext: harness.extensionContext,
            reason: #function
        )

        XCTAssertIdentical(openedTab, tab)
        XCTAssertTrue(wasInactiveAtOpen)
        XCTAssertTrue(hadExactWindowWebViewAtOpen)
        XCTAssertEqual(events, ["didOpen", "didActivate"])
        XCTAssertEqual(harness.window.currentTabId, tab.id)
        XCTAssertNotNil(tab.shortcutPinId)
        XCTAssertTrue(
            tab.extensionPageRuntimeOwner.hasDidOpenTabNotification(
                for: harness.manager.tabPublicationRevisions.issue()
            )
        )
    }

    func testDidOpenReentrancyFailureDiscardsTabAdapterAndEligibilityWithoutSelection() async throws {
        let harness = try await makeRequestedPublicationHarness()
        let originalGeneration = harness.manager.tabPublicationRevisions.issue()
        var rejectedTab: Tab?
        var rejectedAdapter: ExtensionTabAdapter?
        var lifecycleEvents: [String] = []
        var activatedTabIDs: [UUID] = []

        harness.manager.testHooks.didOpenTab = { tabID in
            guard tabID != harness.sourceTab.id,
                  let tab = harness.browserManager.tabManager
                    .tabCollectionMembershipOwner.tab(for: tabID)
            else {
                return
            }
            rejectedTab = tab
            rejectedAdapter = harness.manager.adapterStore.tabAdapters[tabID]
            lifecycleEvents.append("didOpen")
            harness.browserManager.selectTab(tab, in: harness.window)
            XCTAssertEqual(harness.window.currentTabId, tab.id)
            _ = harness.manager.tabPublicationRevisions.advance(
                ifCurrent: harness.manager.tabPublicationRevisions.issue()
            )
        }
        harness.manager.testHooks.didCloseTab = { tabID in
            guard tabID != harness.sourceTab.id else { return }
            lifecycleEvents.append("didClose")
        }
        harness.manager.testHooks.didActivateTab = {
            activatedTabIDs.append($0)
        }
        defer {
            harness.manager.testHooks.didOpenTab = nil
            harness.manager.testHooks.didCloseTab = nil
            harness.manager.testHooks.didActivateTab = nil
        }

        XCTAssertThrowsError(
            try harness.manager.requestedTabOpening.open(
                url: URL(string: "https://requested.example/rejected")!,
                shouldBeActive: true,
                shouldBePinned: true,
                requestedWindow: nil,
                controller: harness.controller,
                extensionContext: harness.extensionContext,
                reason: #function
            )
        )

        let tab = try XCTUnwrap(rejectedTab)
        let adapter = try XCTUnwrap(rejectedAdapter)
        XCTAssertEqual(lifecycleEvents, ["didOpen", "didClose"])
        XCTAssertTrue(activatedTabIDs.isEmpty)
        XCTAssertEqual(harness.window.currentTabId, harness.sourceTab.id)
        XCTAssertNil(
            harness.browserManager.tabManager.tabCollectionMembershipOwner
                .tab(for: tab.id)
        )
        XCTAssertNil(harness.manager.adapterStore.tabAdapters[tab.id])
        XCTAssertNil(tab.extensionPageRuntimeOwner.currentEligibleGeneration())
        XCTAssertFalse(tab.extensionPageRuntimeOwner.hasAnyDidOpenTabNotification())
        XCTAssertFalse(tab.isPinned)
        XCTAssertFalse(
            harness.extensionContext.openTabs.contains { openTab in
                (openTab as AnyObject) === adapter
            }
        )
        XCTAssertEqual(
            harness.manager.tabPublicationRevisions.issue().generation,
            originalGeneration.generation + 1
        )
    }

    func testTransientDidOpenFailureBalancesCloseExactlyOnce() async throws {
        let harness = try await makeRequestedPublicationHarness()
        var rejectedTabID: UUID?
        var lifecycleEvents: [String] = []

        harness.manager.testHooks.didOpenTab = { tabID in
            guard tabID != harness.sourceTab.id else { return }
            rejectedTabID = tabID
            lifecycleEvents.append("didOpen")
            _ = harness.manager.tabPublicationRevisions.advance(
                ifCurrent: harness.manager.tabPublicationRevisions.issue()
            )
        }
        harness.manager.testHooks.didCloseTab = { tabID in
            guard tabID != harness.sourceTab.id else { return }
            lifecycleEvents.append("didClose")
        }
        defer {
            harness.manager.testHooks.didOpenTab = nil
            harness.manager.testHooks.didCloseTab = nil
        }

        XCTAssertThrowsError(
            try harness.manager.requestedTabOpening.open(
                url: harness.extensionContext.baseURL
                    .appendingPathComponent("transient.html"),
                shouldBeActive: false,
                shouldBePinned: false,
                requestedWindow: nil,
                controller: harness.controller,
                extensionContext: harness.extensionContext,
                reason: #function
            )
        )

        let tabID = try XCTUnwrap(rejectedTabID)
        XCTAssertEqual(lifecycleEvents, ["didOpen", "didClose"])
        XCTAssertNil(
            harness.browserManager.tabManager.tabCollectionMembershipOwner
                .tab(for: tabID)
        )
        XCTAssertNil(harness.manager.adapterStore.tabAdapters[tabID])
    }

    func testExplicitStaleNormalWindowAdapterWithSameUUIDIsRejectedWithoutFallback() async throws {
        let harness = try await makeRequestedPublicationHarness()
        let windowQuery = try XCTUnwrap(harness.manager.extensionWindowQuery)
        let activation = try XCTUnwrap(
            harness.manager.extensionWindowActivation
        )
        let staleAdapter = ExtensionWindowAdapter(
            windowState: harness.window,
            windowQuery: windowQuery,
            windowActivation: activation,
            contextPublications: harness.manager.contextPublications,
            preparedTabVisibility: ExtensionPreparedTabVisibility(
                gate: ExtensionRuntimePublicationGate()
            ),
            extensionManager: harness.manager
        )

        XCTAssertEqual(staleAdapter.windowId, harness.publishedWindow.windowId)
        XCTAssertFalse(staleAdapter === harness.publishedWindow)
        XCTAssertThrowsError(
            try harness.manager.requestedTabTargetResolver.resolve(
                requestedWindow: staleAdapter,
                extensionContext: harness.extensionContext
            )
        )
        XCTAssertIdentical(
            harness.manager.windowPublications
                .publishedWindowAdapter(
                    for: harness.window,
                    profileID: harness.profile.id
                ),
            harness.publishedWindow
        )
    }

    func testCurrentWindowRejectsReplacedExtensionContextWithoutFallback() async throws {
        let harness = try await makeRequestedPublicationHarness()
        let staleContext = harness.extensionContext
        let identity = try XCTUnwrap(
            harness.manager.profileRuntime.exactContextIdentity(
                for: staleContext
            )
        )
        let replacementContext = WKWebExtensionContext(
            for: harness.extensionContext.webExtension
        )
        harness.manager.profileRuntime.setContext(
            replacementContext,
            extensionId: identity.extensionId,
            profileId: identity.profileId
        )
        defer {
            harness.manager.profileRuntime.setContext(
                staleContext,
                extensionId: identity.extensionId,
                profileId: identity.profileId
            )
        }

        XCTAssertThrowsError(
            try harness.manager.requestedTabTargetResolver.resolve(
                requestedWindow: harness.publishedWindow,
                extensionContext: staleContext
            )
        )
        XCTAssertThrowsError(
            try harness.manager.requestedTabTargetResolver.resolve(
                requestedWindow: nil,
                extensionContext: staleContext
            )
        )
        XCTAssertIdentical(
            harness.manager.windowPublications
                .publishedWindowAdapter(
                    for: harness.window,
                    profileID: harness.profile.id
                ),
            harness.publishedWindow
        )
    }

    func testReplacedNormalContextLosesEveryTabAndWindowCapability()
        async throws {
        let harness = try await makeRequestedPublicationHarness()
        let staleContext = harness.extensionContext
        let identity = try XCTUnwrap(
            harness.manager.profileRuntime.exactContextIdentity(
                for: staleContext
            )
        )
        let replacementContext = WKWebExtensionContext(
            for: staleContext.webExtension
        )
        harness.manager.profileRuntime.setContext(
            replacementContext,
            extensionId: identity.extensionId,
            profileId: identity.profileId
        )
        defer {
            harness.manager.profileRuntime.setContext(
                staleContext,
                extensionId: identity.extensionId,
                profileId: identity.profileId
            )
        }

        let tabAdapter = try XCTUnwrap(
            harness.manager.adapterStore.tabAdapters[harness.sourceTab.id]
        )
        let appKitWindow = try XCTUnwrap(
            harness.manager.extensionWindowQuery?.appKitWindow(
                for: harness.window
            )
        )
        let sourceWebView = try XCTUnwrap(
            harness.manager.exactExtensionTabWebViews.liveWebView(
                for: harness.sourceTab
            )
        )
        let originalURL = harness.sourceTab.url
        let originalFrame = appKitWindow.frame
        let wasMiniaturized = appKitWindow.isMiniaturized

        XCTAssertNil(tabAdapter.url(for: staleContext))
        XCTAssertNil(tabAdapter.title(for: staleContext))
        XCTAssertNil(tabAdapter.webView(for: staleContext))
        XCTAssertNil(tabAdapter.window(for: staleContext))
        XCTAssertFalse(
            tabAdapter.shouldGrantPermissionsOnUserGesture(
                for: staleContext
            )
        )
        XCTAssertNil(harness.publishedWindow.activeTab(for: staleContext))
        XCTAssertTrue(harness.publishedWindow.tabs(for: staleContext).isEmpty)
        XCTAssertEqual(harness.publishedWindow.frame(for: staleContext), .zero)
        XCTAssertEqual(
            harness.publishedWindow.screenFrame(for: staleContext),
            .zero
        )

        let rejectedURL = URL(string: "https://stale.example/rejected")!
        var staleLoadError: Error?
        tabAdapter.loadURL(rejectedURL, for: staleContext) {
            staleLoadError = $0
        }
        XCTAssertNotNil(staleLoadError)
        XCTAssertEqual(harness.sourceTab.url, originalURL)

        var staleTabCloseError: Error?
        tabAdapter.close(for: staleContext) {
            staleTabCloseError = $0
        }
        XCTAssertNotNil(staleTabCloseError)
        XCTAssertIdentical(
            harness.browserManager.tabManager.tabCollectionMembershipOwner
                .tab(for: harness.sourceTab.id),
            harness.sourceTab
        )

        let rejectedFrame = originalFrame.offsetBy(dx: 55, dy: 34)
        var staleFocusError: Error?
        harness.publishedWindow.focus(for: staleContext) {
            staleFocusError = $0
        }
        XCTAssertNotNil(staleFocusError)

        var staleFrameError: Error?
        harness.publishedWindow.setFrame(
            rejectedFrame,
            for: staleContext
        ) {
            staleFrameError = $0
        }
        XCTAssertNotNil(staleFrameError)
        XCTAssertEqual(appKitWindow.frame, originalFrame)

        var staleStateError: Error?
        harness.publishedWindow.setWindowState(
            .minimized,
            for: staleContext
        ) {
            staleStateError = $0
        }
        XCTAssertNotNil(staleStateError)
        XCTAssertEqual(appKitWindow.isMiniaturized, wasMiniaturized)

        var staleWindowCloseError: Error?
        harness.publishedWindow.close(for: staleContext) {
            staleWindowCloseError = $0
        }
        XCTAssertNotNil(staleWindowCloseError)
        XCTAssertIdentical(
            harness.manager.extensionWindowQuery?.extensionWindowState(
                for: harness.window.id
            ),
            harness.window
        )

        XCTAssertEqual(tabAdapter.url(for: replacementContext), originalURL)
        XCTAssertEqual(
            tabAdapter.title(for: replacementContext),
            harness.sourceTab.name
        )
        XCTAssertIdentical(
            tabAdapter.webView(for: replacementContext),
            sourceWebView
        )
        XCTAssertTrue(
            (tabAdapter.window(for: replacementContext) as AnyObject?)
                === harness.publishedWindow
        )
        XCTAssertTrue(
            tabAdapter.shouldGrantPermissionsOnUserGesture(
                for: replacementContext
            )
        )
        XCTAssertTrue(
            (harness.publishedWindow.activeTab(for: replacementContext)
                as AnyObject?) === tabAdapter
        )
        XCTAssertTrue(
            harness.publishedWindow.tabs(for: replacementContext).contains {
                ($0 as AnyObject) === tabAdapter
            }
        )
        XCTAssertEqual(
            harness.publishedWindow.frame(for: replacementContext),
            originalFrame
        )

        let acceptedFrame = originalFrame.offsetBy(dx: 17, dy: 11)
        var replacementFrameError: Error?
        harness.publishedWindow.setFrame(
            acceptedFrame,
            for: replacementContext
        ) {
            replacementFrameError = $0
        }
        XCTAssertNil(replacementFrameError)
        XCTAssertEqual(appKitWindow.frame, acceptedFrame)

        var replacementFocusError: Error?
        harness.publishedWindow.focus(for: replacementContext) {
            replacementFocusError = $0
        }
        XCTAssertNil(replacementFocusError)

        let acceptedURL = URL(string: "https://replacement.example/accepted")!
        var replacementLoadError: Error?
        tabAdapter.loadURL(acceptedURL, for: replacementContext) {
            replacementLoadError = $0
        }
        XCTAssertNil(replacementLoadError)
        XCTAssertEqual(harness.sourceTab.url, acceptedURL)
    }

    func testNormalTabAdapterNeverRebindsToReplacementTabWithSameID()
        async throws {
        let harness = try await makeRequestedPublicationHarness()
        let staleTab = harness.sourceTab
        let staleAdapter = try XCTUnwrap(
            harness.manager.adapterStore.tabAdapters[staleTab.id]
        )
        let spaceID = try XCTUnwrap(staleTab.spaceId)
        harness.browserManager.tabManager.tabClosureService.removeTab(
            staleTab.id
        )
        XCTAssertNil(
            harness.manager.adapterStore.existingTabAdapter(
                for: staleTab.id
            )
        )

        let replacementTab = harness.browserManager.tabManager.tabFactory
            .makeTab(
            id: staleTab.id,
            url: URL(string: "https://replacement.example/same-id")!,
            name: "Replacement",
            spaceId: spaceID,
            index: staleTab.index
        )
        replacementTab.profileId = harness.profile.id
        harness.browserManager.tabManager.regularTabLifecycleOwner.addTab(
            replacementTab
        )

        let replacementAdapter = try XCTUnwrap(
            harness.manager.adapterCatalog.stableAdapter(
                for: replacementTab
            )
        )
        replacementTab.extensionPageRuntimeOwner.markEligible(
            for: harness.manager.tabPublicationRevisions.issue()
        )
        let replacementWebView = attachUsableExtensionWebView(
            to: replacementTab,
            manager: harness.manager,
            profile: harness.profile
        )

        XCTAssertEqual(staleAdapter.tabId, replacementAdapter.tabId)
        XCTAssertFalse(staleAdapter === replacementAdapter)
        XCTAssertNil(staleAdapter.tab)
        XCTAssertIdentical(replacementAdapter.tab, replacementTab)
        XCTAssertIdentical(
            harness.manager.adapterStore.tabAdapters[replacementTab.id],
            replacementAdapter
        )
        XCTAssertNil(staleAdapter.url(for: harness.extensionContext))
        XCTAssertNil(staleAdapter.window(for: harness.extensionContext))
        XCTAssertNil(
            harness.manager.tabWebViewResolver.extensionWebView(
                for: staleTab,
                extensionContext: harness.extensionContext
            )
        )
        XCTAssertIdentical(
            harness.manager.tabWebViewResolver.extensionWebView(
                for: replacementTab,
                extensionContext: harness.extensionContext
            ),
            replacementWebView
        )
        XCTAssertFalse(
            staleAdapter.shouldGrantPermissionsOnUserGesture(
                for: harness.extensionContext
            )
        )
    }

    func testContextPublicationQueryFailsClosedAfterRuntimeRelease()
        async throws {
        let directory = try makeScratchDirectory()
        try JSONSerialization.data(
            withJSONObject: [
                "manifest_version": 3,
                "name": "Context Publication Query",
                "version": "1.0",
            ],
            options: [.sortedKeys]
        ).write(
            to: directory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        let webExtension = try await WKWebExtension(
            resourceBaseURL: directory
        )
        let context = WKWebExtensionContext(for: webExtension)
        let profileID = UUID()
        var runtime: ExtensionProfileRuntime? = ExtensionProfileRuntime(
            initialProfileId: profileID
        )
        runtime?.setContext(
            context,
            extensionId: "released-runtime-extension",
            profileId: profileID
        )
        let query = ExtensionContextPublicationQuery(
            profileRuntime: try XCTUnwrap(runtime)
        )

        XCTAssertEqual(query.currentIdentity(for: context)?.profileID, profileID)

        weak let releasedRuntime = runtime
        runtime = nil

        XCTAssertNil(releasedRuntime)
        XCTAssertNil(query.currentIdentity(for: context))
        XCTAssertFalse(
            query.isCurrent(
                context,
                extensionID: "released-runtime-extension",
                profileID: profileID
            )
        )
    }

    private struct ProfileRoutingHarness {
        let manager: ExtensionManager
        let browserManager: BrowserManager
        let profileA: Profile
        let profileB: Profile
        let spaceA: Space
        let spaceB: Space
    }

    struct RequestedPublicationHarness {
        let manager: ExtensionManager
        let browserManager: BrowserManager
        let profile: Profile
        let window: BrowserWindowState
        let sourceTab: Tab
        let extensionContext: WKWebExtensionContext
        let controller: WKWebExtensionController
        let publishedWindow: ExtensionWindowAdapter
    }

    func makeRequestedPublicationHarness() async throws
        -> RequestedPublicationHarness {
        SafariExtensionLiveWebKitTestLease.holdForProcess()
        let container = try makeTestContainer()
        addTeardownBlock {
            _ = container
        }
        let profile = Profile(name: "Requested Tab Transaction")
        let browserConfiguration = BrowserConfiguration()
        let moduleRegistry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        moduleRegistry.enable(.extensions)
        let manager = makeSafariExtensionTestExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: browserConfiguration,
            moduleRegistry: moduleRegistry
        )
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: moduleRegistry,
            context: container.mainContext,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in manager }
        )
        let windowRegistry = WindowRegistry()
        let browserManager = makeSafariExtensionTestBrowserManager(
            moduleRegistry: moduleRegistry,
            extensionsModule: extensionsModule,
            profile: profile,
            windowRegistry: windowRegistry
        )
        extensionsModule.attach(
            runtime: BrowserExtensionsModuleRuntimeFactory.runtime(
                for: browserManager
            )
        )
        manager.attach(browserManager: browserManager)

        let space = Space(name: "Primary", profileId: profile.id)
        browserManager.tabManager.spaceStateOwner.replaceSpaces([space])
        browserManager.tabManager.spaceStateOwner.replaceCurrentSpace(space)

        let window = BrowserWindowState()
        window.tabManager = browserManager.tabManager
        window.currentProfileId = profile.id
        window.currentSpaceId = space.id
        let appKitWindow = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 960, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        appKitWindow.isReleasedWhenClosed = false
        windowRegistry.bindAppKitWindow(appKitWindow, to: window)
        windowRegistry.register(window)
        windowRegistry.setActive(window)
        addTeardownBlock {
            windowRegistry.unregister(window.id)
            appKitWindow.close()
        }

        let sourceTab = browserManager.tabManager.regularTabLifecycleOwner
            .createNewTab(
                url: "https://source.example/page",
                in: space,
                activate: false
            )
        browserManager.selectTab(sourceTab, in: window)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "RequestedTabTransactionExtension"
        )
        _ = try await manager.installedExtensionLifecycle.enable(installed.id)
        let loadedContext = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        let extensionContext = try XCTUnwrap(loadedContext)
        let controller = try XCTUnwrap(
            manager.profileRuntime.controller(for: profile.id)
        )

        browserManager.materializeVisibleTabWebViewIfNeeded(
            sourceTab,
            in: window
        )
        let sourceWebView = try XCTUnwrap(
            browserManager.webViewRuntime.ownershipQuery.webView(
                for: sourceTab.id,
                in: window.id
            ) as? FocusableWKWebView
        )
        let sourcePublication = try XCTUnwrap(
            manager.initialTabPublicationPreparer.prepare(
                window: window,
                tab: sourceTab,
                webView: sourceWebView,
                runtime: manager.runtime,
                windowRegistry: browserManager.extensionBridgeComposition.windows,
                reason: "ExtensionRequestedTabServicesTests.source"
            )
        )
        XCTAssertTrue(manager.normalWindowLifecycle.opened(window))
        XCTAssertTrue(
            sourcePublication.publishInitialTab(
                afterWindowOpened: window
            )
        )
        let publishedWindow = try XCTUnwrap(
            manager.windowPublications
                .publishedWindowAdapter(
                    for: window,
                    profileID: profile.id
                )
        )

        return RequestedPublicationHarness(
            manager: manager,
            browserManager: browserManager,
            profile: profile,
            window: window,
            sourceTab: sourceTab,
            extensionContext: extensionContext,
            controller: controller,
            publishedWindow: publishedWindow
        )
    }

    private func makeProfileRoutingHarness() throws -> ProfileRoutingHarness {
        let container = try makeTestContainer()
        let profileA = Profile(name: "Profile A")
        let profileB = Profile(name: "Profile B")
        let manager = makeSafariExtensionTestExtensionManager(
            context: container.mainContext,
            initialProfile: profileA
        )
        let browserManager = makeSafariExtensionTestBrowserManager(profile: profileA)
        browserManager.profileManager.profiles = [profileA, profileB]
        browserManager.currentProfile = profileA

        let spaceA = Space(name: "Space A", profileId: profileA.id)
        let spaceB = Space(name: "Space B", profileId: profileB.id)
        browserManager.tabManager.spaceStateOwner.replaceSpaces([spaceA, spaceB])
        browserManager.tabManager.spaceStateOwner.replaceCurrentSpace(spaceA)
        manager.attach(browserManager: browserManager)

        return ProfileRoutingHarness(
            manager: manager,
            browserManager: browserManager,
            profileA: profileA,
            profileB: profileB,
            spaceA: spaceA,
            spaceB: spaceB
        )
    }
}
