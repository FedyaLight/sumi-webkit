import AppKit
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionRequestedTabServicesTests:
    SafariExtensionWebViewControllerWiringTestCase {
    private final class CountingCallbackPreloader:
        ExtensionRequestedTabCallbackPreloading {
        private(set) var callCount = 0

        func prepare(
            load _: ExtensionRequestedTabLoad,
            requestedWindow _: (any WKWebExtensionWindow)?,
            controller _: WKWebExtensionController,
            extensionContext _: WKWebExtensionContext?
        ) async throws -> UUID? {
            callCount += 1
            return nil
        }
    }

    private final class CountingCallbackOpening:
        ExtensionRequestedTabCallbackOpening {
        private(set) var callCount = 0

        func open(
            url: URL?,
            shouldBeActive _: Bool,
            shouldBePinned _: Bool,
            requestedWindow _: (any WKWebExtensionWindow)?,
            controller _: WKWebExtensionController,
            extensionContext _: WKWebExtensionContext?,
            evidence _: ExtensionControllerCallbackEvidence?,
            callbackAdmission _: ExtensionControllerCallbackAdmission?,
            reason _: String
        ) throws -> Tab {
            callCount += 1
            return Tab(
                url: url ?? URL(string: "about:blank")!,
                name: "Unexpected"
            )
        }
    }

    private final class CountingAdapterResolver: ExtensionTabAdapterResolving {
        private(set) var callCount = 0

        func stableAdapter(for _: Tab) -> ExtensionTabAdapter? {
            callCount += 1
            return nil
        }
    }

    func testLoadResolverKeepsUnresolvedExtensionURLFailClosed() {
        let controller = WKWebExtensionController(configuration: .nonPersistent())
        let load = ExtensionRequestedTabLoadResolver().resolve(
            URL(string: "safari-web-extension://unloaded/options.html"),
            controller: controller
        )

        XCTAssertTrue(load.hasUnresolvedExtensionOwnership)
        XCTAssertFalse(load.isOrdinaryBrowserRequest)
        XCTAssertNil(load.extensionContext)
    }

    func testLoadResolverClassifiesExternalWebURLAsOrdinaryBrowserRequest() {
        let controller = WKWebExtensionController(configuration: .nonPersistent())
        let load = ExtensionRequestedTabLoadResolver().resolve(
            URL(string: "https://account.example/login"),
            controller: controller
        )

        XCTAssertFalse(load.hasUnresolvedExtensionOwnership)
        XCTAssertTrue(load.isOrdinaryBrowserRequest)
        XCTAssertNil(load.extensionContext)
    }

    func testUnresolvedExtensionOwnedRequestFailsBeforeCreatingTab()
        async throws {
        let harness = try await makeRequestedPublicationHarness()
        let spaceID = try XCTUnwrap(harness.sourceTab.spaceId)
        let originalTabIDs = harness.browserManager.tabStateStore.regularTabs
            .tabsBySpaceSnapshot()[spaceID]?
            .map(\.id)
        var lifecycleEvents: [String] = []
        harness.manager.testHooks.didOpenTab = { tabID in
            guard tabID != harness.sourceTab.id else { return }
            lifecycleEvents.append("didOpen")
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
            try harness.attachedRuntime.requestedTabs.opening.open(
                url: URL(
                    string: "safari-web-extension://unloaded/options.html"
                ),
                shouldBeActive: true,
                shouldBePinned: false,
                requestedWindow: nil,
                controller: harness.controller,
                extensionContext: harness.extensionContext,
                reason: #function
            )
        )

        XCTAssertEqual(
            harness.browserManager.tabStateStore.regularTabs
                .tabsBySpaceSnapshot()[spaceID]?.map(\.id),
            originalTabIDs
        )
        XCTAssertEqual(harness.window.currentTabId, harness.sourceTab.id)
        XCTAssertTrue(lifecycleEvents.isEmpty)
    }

    func testFullCallbackRejectsUnresolvedOwnershipBeforePreloadOrMaterialization()
        async throws {
        let harness = try await makeRequestedPublicationHarness()
        let evidence = try XCTUnwrap(
            harness.inspection.controller.callbackAdmission.capture(
                context: harness.extensionContext,
                controller: harness.controller
            )
        )
        let preloader = CountingCallbackPreloader()
        let opening = CountingCallbackOpening()
        let adapters = CountingAdapterResolver()
        let runtime = ExtensionControllerTabOpeningCallbackRuntime(
            admission: harness.inspection.controller.callbackAdmission,
            loadResolver: ExtensionRequestedTabLoadResolver(),
            contextPreloader: preloader,
            tabOpening: opening,
            adapterResolver: adapters
        )
        let configuration = RequestedTabConfigurationMock(
            url: URL(
                string: "safari-web-extension://unresolved-owner/page.html"
            )!,
            shouldBeActive: true,
            shouldBePinned: false
        ).tabConfiguration
        let completed = expectation(description: "callback rejected")
        var callbackTab: (any WKWebExtensionTab)?
        var callbackError: (any Error)?

        ExtensionControllerOpeningCallbackHandler().openNewTab(
            configuration: configuration,
            evidence: evidence,
            runtime: runtime
        ) { tab, error in
            callbackTab = tab
            callbackError = error
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 1.0)

        XCTAssertNil(callbackTab)
        XCTAssertNotNil(callbackError)
        XCTAssertEqual(preloader.callCount, 0)
        XCTAssertEqual(opening.callCount, 0)
        XCTAssertEqual(adapters.callCount, 0)
    }

    func testSameProfileExtensionCannotOpenAnotherExtensionsOwnedURL()
        async throws {
        let harness = try await makeRequestedPublicationHarness()
        let scratchDirectory = try makeScratchDirectory()
        let second = try await installUnpackedExtension(
            manager: harness.manager,
            scratchDirectory: scratchDirectory,
            name: "RequestedTabSecondExtension"
        )
        _ = try await harness.inspection.installation.lifecycle.enable(
            second.id
        )
        let loadedSecondContext = try await harness.inspection
            .contextCoordination.residency.ensureExtensionLoaded(
                extensionId: second.id,
                profileId: harness.profile.id
            )
        let secondContext = try XCTUnwrap(
            loadedSecondContext
        )
        let crossExtensionURL = try XCTUnwrap(
            URL(
                string: "options.html",
                relativeTo: secondContext.baseURL
            )?.absoluteURL
        )
        let spaceID = try XCTUnwrap(harness.sourceTab.spaceId)
        let originalTabIDs = harness.browserManager.tabStateStore.regularTabs
            .tabsBySpaceSnapshot()[spaceID]?
            .map(\.id)

        XCTAssertThrowsError(
            try harness.attachedRuntime.requestedTabs.opening.open(
                url: crossExtensionURL,
                shouldBeActive: true,
                shouldBePinned: false,
                requestedWindow: nil,
                controller: harness.controller,
                extensionContext: harness.extensionContext,
                reason: #function
            )
        )
        XCTAssertEqual(
            harness.browserManager.tabStateStore.regularTabs
                .tabsBySpaceSnapshot()[spaceID]?.map(\.id),
            originalTabIDs
        )
        XCTAssertEqual(harness.window.currentTabId, harness.sourceTab.id)
    }

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
        let attachedRuntime = ExtensionAttachedRuntimeCapture()
        let inspection = ExtensionManagerInspectionCapture()
        let manager = makeSafariExtensionTestExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            attachedRuntimeCapture: attachedRuntime,
            inspectionCapture: inspection
        )
        _ = inspection.inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .install
        )
        let expectedController = inspection.inspection.controller.provisioning
            .ensureExtensionController(for: profile.id)
        let browserManager = makeSafariExtensionTestBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)
        let materializer = attachedRuntime.runtime.normalTabs
            .requestedTabWebViewMaterializer
        let space = browserManager.spaceStateOwner.firstSpace(
            forProfile: profile.id
        ) ?? installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "Extension requested",
            profileID: profile.id
        )
        let tab = browserManager.regularTabLifecycleOwner
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
            attachedRuntime.runtime.controller.webViews.untrackedWebView(for: tab),
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
        let resolver = harness.attachedRuntime.requestedTabs.targetResolver

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
        let tab = harness.browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/current",
            in: harness.spaceA,
            activate: true
        )

        XCTAssertEqual(harness.browserManager.tabStateStore.selection.currentTab?.id, tab.id)
        XCTAssertNil(
            harness.browserManager.extensionBridgeComposition.windows
                .currentExtensionTabForActiveWindow()
        )
    }

    func testPreferredExtensionWindowStateResolvesTransientTabFromDisplayedSpace() throws {
        let harness = try makeProfileRoutingHarness()
        let windowState = BrowserWindowState()
        harness.browserManager.tabResidenceAuthority.establishResidenceSession(
            on: windowState
        )
        windowState.currentProfileId = harness.profileA.id
        windowState.currentSpaceId = harness.spaceA.id
        harness.windowRegistry.register(windowState)
        harness.windowRegistry.setActive(windowState)

        let tab = harness.browserManager.extensionTabCommands.createTransient(
            url: try XCTUnwrap(URL(string: "safari-web-extension://extension-id/popup.html")),
            in: harness.spaceA,
            webExtensionContextOverride: nil
        )

        XCTAssertTrue(harness.browserManager.extensionTabCommands.containsTransient(tab))
        XCTAssertFalse(
            harness.browserManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[harness.spaceA.id]?.contains { $0.id == tab.id }
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
                  let tab = harness.browserManager.tabCollectionMembershipOwner
                    .tab(for: tabID)
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
                ) === harness.attachedRuntime.controller.webViews
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

        let tab = try harness.attachedRuntime.requestedTabs.opening.open(
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
                for: harness.inspection.runtimeAuthorities.tabPublicationRevisions.issue()
            )
        )
    }

    func testDidOpenReentrancyFailureDiscardsTabAdapterAndEligibilityWithoutSelection() async throws {
        let harness = try await makeRequestedPublicationHarness()
        let originalGeneration = harness.inspection.runtimeAuthorities.tabPublicationRevisions.issue()
        var rejectedTab: Tab?
        var rejectedAdapter: ExtensionTabAdapter?
        var lifecycleEvents: [String] = []
        var activatedTabIDs: [UUID] = []

        harness.manager.testHooks.didOpenTab = { tabID in
            guard tabID != harness.sourceTab.id,
                  let tab = harness.browserManager.tabCollectionMembershipOwner
                    .tab(for: tabID)
            else {
                return
            }
            rejectedTab = tab
            rejectedAdapter = harness.inspection.normalTabs.adapters.tabAdapters[tabID]
            lifecycleEvents.append("didOpen")
            harness.browserManager.selectTab(tab, in: harness.window)
            XCTAssertEqual(harness.window.currentTabId, tab.id)
            _ = harness.inspection.runtimeAuthorities.tabPublicationRevisions.advance(
                ifCurrent: harness.inspection.runtimeAuthorities.tabPublicationRevisions.issue()
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
            try harness.attachedRuntime.requestedTabs.opening.open(
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
            harness.browserManager.tabCollectionMembershipOwner
                .tab(for: tab.id)
        )
        XCTAssertNil(harness.inspection.normalTabs.adapters.tabAdapters[tab.id])
        XCTAssertNil(tab.extensionPageRuntimeOwner.currentEligibleGeneration())
        XCTAssertFalse(tab.extensionPageRuntimeOwner.hasAnyDidOpenTabNotification())
        XCTAssertFalse(tab.isPinned)
        XCTAssertFalse(
            harness.extensionContext.openTabs.contains { openTab in
                (openTab as AnyObject) === adapter
            }
        )
        XCTAssertEqual(
            harness.inspection.runtimeAuthorities.tabPublicationRevisions.issue().generation,
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
            _ = harness.inspection.runtimeAuthorities.tabPublicationRevisions.advance(
                ifCurrent: harness.inspection.runtimeAuthorities.tabPublicationRevisions.issue()
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
            try harness.attachedRuntime.requestedTabs.opening.open(
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
            harness.browserManager.tabCollectionMembershipOwner
                .tab(for: tabID)
        )
        XCTAssertNil(harness.inspection.normalTabs.adapters.tabAdapters[tabID])
    }

    func testExplicitStaleNormalWindowAdapterWithSameUUIDIsRejectedWithoutFallback() async throws {
        let harness = try await makeRequestedPublicationHarness()
        let windowQuery = harness.attachedRuntime.bridge.windows
        let activation = harness.attachedRuntime.bridge.windowActivation
        let attached = harness.attachedRuntime
        let staleAdapter = ExtensionWindowAdapter(
            windowState: harness.window,
            windowQuery: windowQuery,
            windowActivation: activation,
            identity: ExtensionWindowAdapterIdentityProjection(
                contextPublications: harness.inspection.contextState.publications,
                profileIDForWindow: {
                    $0.isIncognito
                        ? $0.ephemeralProfile?.id
                        : $0.currentProfileId
                            ?? attached.profileQuery.currentProfile()?.id
                },
                profileIDForTab: attached.controller.profiles.profileID,
                extensionIDForContext: harness.inspection.contextState.profiles.extensionId
            ),
            preparedTabVisibility: ExtensionPreparedTabVisibility(
                gate: ExtensionRuntimePublicationGate()
            ),
            windowPublications: attached.publications.windowPublications,
            tabAdapters: attached.adapters,
            publishedTabs: attached.normalTabs.publishedTabs,
            preparedTabs: attached.normalTabs.preparedTabs
        )

        XCTAssertEqual(staleAdapter.windowId, harness.publishedWindow.windowId)
        XCTAssertFalse(staleAdapter === harness.publishedWindow)
        XCTAssertThrowsError(
            try harness.attachedRuntime.requestedTabs.targetResolver.resolve(
                requestedWindow: staleAdapter,
                extensionContext: harness.extensionContext
            )
        )
        XCTAssertIdentical(
            harness.attachedRuntime.publications.windowPublications
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
            harness.inspection.contextState.profiles.exactContextIdentity(
                for: staleContext
            )
        )
        let replacementContext = WKWebExtensionContext(
            for: harness.extensionContext.webExtension
        )
        harness.inspection.contextState.profiles.setContext(
            replacementContext,
            extensionId: identity.extensionId,
            profileId: identity.profileId
        )
        defer {
            harness.inspection.contextState.profiles.setContext(
                staleContext,
                extensionId: identity.extensionId,
                profileId: identity.profileId
            )
        }

        XCTAssertThrowsError(
            try harness.attachedRuntime.requestedTabs.targetResolver.resolve(
                requestedWindow: harness.publishedWindow,
                extensionContext: staleContext
            )
        )
        XCTAssertThrowsError(
            try harness.attachedRuntime.requestedTabs.targetResolver.resolve(
                requestedWindow: nil,
                extensionContext: staleContext
            )
        )
        XCTAssertIdentical(
            harness.attachedRuntime.publications.windowPublications
                .publishedWindowAdapter(
                    for: harness.window,
                    profileID: harness.profile.id
                ),
            harness.publishedWindow
        )
    }

    func testNormalWindowStateCompletionFollowsNativeSettlement() async throws {
        let harness = try await makeRequestedPublicationHarness()
        let window = try XCTUnwrap(
            harness.attachedRuntime.bridge.windows.appKitWindow(
                for: harness.window
            )
        )
        window.orderFront(nil)
        var didSettle = false
        let nativeSettlement = expectation(
            description: "normal window miniaturized"
        )
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didMiniaturizeNotification,
            object: window,
            queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                didSettle = true
                nativeSettlement.fulfill()
            }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
            window.deminiaturize(nil)
        }

        var completionError: Error?
        var completionObservedSettlement = false
        let completion = expectation(description: "state callback")
        harness.publishedWindow.setWindowState(
            .minimized,
            for: harness.extensionContext
        ) {
            completionError = $0
            completionObservedSettlement = didSettle
            completion.fulfill()
        }

        await fulfillment(of: [nativeSettlement, completion], timeout: 5)
        XCTAssertNil(completionError)
        XCTAssertTrue(completionObservedSettlement)
        XCTAssertTrue(window.isMiniaturized)
    }

    func testReplacedNormalContextLosesEveryTabAndWindowCapability()
        async throws {
        let harness = try await makeRequestedPublicationHarness()
        let staleContext = harness.extensionContext
        let identity = try XCTUnwrap(
            harness.inspection.contextState.profiles.exactContextIdentity(
                for: staleContext
            )
        )
        let replacementContext = WKWebExtensionContext(
            for: staleContext.webExtension
        )
        harness.inspection.contextState.profiles.setContext(
            replacementContext,
            extensionId: identity.extensionId,
            profileId: identity.profileId
        )
        defer {
            harness.inspection.contextState.profiles.setContext(
                staleContext,
                extensionId: identity.extensionId,
                profileId: identity.profileId
            )
        }

        let tabAdapter = try XCTUnwrap(
            harness.inspection.normalTabs.adapters.tabAdapters[harness.sourceTab.id]
        )
        let appKitWindow = try XCTUnwrap(
            harness.attachedRuntime.bridge.windows.appKitWindow(
                for: harness.window
            )
        )
        let sourceWebView = try XCTUnwrap(
            harness.attachedRuntime.controller.webViews.liveWebView(
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
            harness.browserManager.tabCollectionMembershipOwner
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
            harness.attachedRuntime.bridge.windows.extensionWindowState(
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
            harness.inspection.normalTabs.adapters.tabAdapters[staleTab.id]
        )
        let spaceID = try XCTUnwrap(staleTab.spaceId)
        harness.browserManager.tabClosureService.removeTab(
            staleTab.id
        )
        XCTAssertNil(
            harness.inspection.normalTabs.adapters.existingTabAdapter(
                for: staleTab.id
            )
        )

        let replacementTab = harness.browserManager.tabFactory
            .makeTab(
            id: staleTab.id,
            url: URL(string: "https://replacement.example/same-id")!,
            name: "Replacement",
            spaceId: spaceID,
            index: staleTab.index
        )
        replacementTab.profileId = harness.profile.id
        harness.browserManager.regularTabLifecycleOwner.addTab(
            replacementTab
        )

        let replacementAdapter = try XCTUnwrap(
            harness.attachedRuntime.adapters.stableAdapter(
                for: replacementTab
            )
        )
        replacementTab.extensionPageRuntimeOwner.markEligible(
            for: harness.inspection.runtimeAuthorities
                .tabPublicationRevisions.issue()
        )
        let replacementWebView = attachUsableExtensionWebView(
            to: replacementTab,
            inspection: harness.inspection,
            profile: harness.profile
        )

        XCTAssertEqual(staleAdapter.tabId, replacementAdapter.tabId)
        XCTAssertFalse(staleAdapter === replacementAdapter)
        XCTAssertNil(staleAdapter.tab)
        XCTAssertIdentical(replacementAdapter.tab, replacementTab)
        XCTAssertIdentical(
            harness.inspection.normalTabs.adapters.tabAdapters[replacementTab.id],
            replacementAdapter
        )
        XCTAssertNil(staleAdapter.url(for: harness.extensionContext))
        XCTAssertNil(staleAdapter.window(for: harness.extensionContext))
        XCTAssertNil(
            harness.attachedRuntime.controller.tabWebViewResolver.extensionWebView(
                for: staleTab,
                extensionContext: harness.extensionContext
            )
        )
        XCTAssertIdentical(
            harness.attachedRuntime.controller.tabWebViewResolver.extensionWebView(
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
        let inspection: ExtensionManagerTestInspection
        let attachedRuntime: ExtensionAttachedBrowserRuntimeInspection
        let browserManager: BrowserManager
        let windowRegistry: WindowRegistry
        let profileA: Profile
        let profileB: Profile
        let spaceA: Space
        let spaceB: Space
    }

    struct RequestedPublicationHarness {
        let manager: ExtensionManager
        let inspection: ExtensionManagerTestInspection
        let attachedRuntime: ExtensionAttachedBrowserRuntimeInspection
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
        let attachedRuntime = ExtensionAttachedRuntimeCapture()
        let inspection = ExtensionManagerInspectionCapture()
        let manager = makeSafariExtensionTestExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: browserConfiguration,
            moduleRegistry: moduleRegistry,
            attachedRuntimeCapture: attachedRuntime,
            inspectionCapture: inspection
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
        browserManager.spaceStateOwner.replaceSpaces([space])
        browserManager.spaceStateOwner.replaceCurrentSpace(space)

        let window = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: window)
        window.currentProfileId = profile.id
        window.currentSpaceId = space.id
        let appKitWindow = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 960, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
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

        let sourceTab = browserManager.regularTabLifecycleOwner
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
        _ = try await inspection.inspection.installation.lifecycle.enable(
            installed.id
        )
        let loadedContext = try await inspection.inspection
            .contextCoordination.residency.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        let extensionContext = try XCTUnwrap(loadedContext)
        let controller = try XCTUnwrap(
            inspection.inspection.contextState.profiles.controller(
                for: profile.id
            )
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
            attachedRuntime.runtime.requestedTabs.initialTabPreparer.prepare(
                window: window,
                tab: sourceTab,
                webView: sourceWebView,
                reason: "ExtensionRequestedTabServicesTests.source"
            )
        )
        XCTAssertTrue(
            attachedRuntime.runtime.publications.normalWindows.opened(window)
        )
        XCTAssertTrue(
            sourcePublication.publishInitialTab(
                afterWindowOpened: window
            )
        )
        let publishedWindow = try XCTUnwrap(
            attachedRuntime.runtime.publications.windowPublications
                .publishedWindowAdapter(
                    for: window,
                    profileID: profile.id
                )
        )

        return RequestedPublicationHarness(
            manager: manager,
            inspection: inspection.inspection,
            attachedRuntime: attachedRuntime.runtime,
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
        let windowRegistry = WindowRegistry()
        let attachedRuntime = ExtensionAttachedRuntimeCapture()
        let inspection = ExtensionManagerInspectionCapture()
        let manager = makeSafariExtensionTestExtensionManager(
            context: container.mainContext,
            initialProfile: profileA,
            attachedRuntimeCapture: attachedRuntime,
            inspectionCapture: inspection
        )
        let browserManager = makeSafariExtensionTestBrowserManager(
            profile: profileA,
            windowRegistry: windowRegistry
        )
        browserManager.profileManager.profiles = [profileA, profileB]
        browserManager.currentProfile = profileA

        let spaceA = Space(name: "Space A", profileId: profileA.id)
        let spaceB = Space(name: "Space B", profileId: profileB.id)
        browserManager.spaceStateOwner.replaceSpaces([spaceA, spaceB])
        browserManager.spaceStateOwner.replaceCurrentSpace(spaceA)
        manager.attach(browserManager: browserManager)

        return ProfileRoutingHarness(
            manager: manager,
            inspection: inspection.inspection,
            attachedRuntime: attachedRuntime.runtime,
            browserManager: browserManager,
            windowRegistry: windowRegistry,
            profileA: profileA,
            profileB: profileB,
            spaceA: spaceA,
            spaceB: spaceB
        )
    }
}

@available(macOS 15.5, *)
@MainActor
private final class RequestedTabConfigurationMock: NSObject {
    @objc let window: NSObject? = nil
    @objc let index = 0
    @objc let parentTab: NSObject? = nil
    @objc let url: URL?
    @objc let shouldBeActive: Bool
    @objc let shouldAddToSelection = false
    @objc let shouldBePinned: Bool
    @objc let shouldBeMuted = false
    @objc let shouldReaderModeBeActive = false

    init(url: URL?, shouldBeActive: Bool, shouldBePinned: Bool) {
        self.url = url
        self.shouldBeActive = shouldBeActive
        self.shouldBePinned = shouldBePinned
    }

    var tabConfiguration: WKWebExtension.TabConfiguration {
        withUnsafePointer(to: self) {
            $0.withMemoryRebound(
                to: WKWebExtension.TabConfiguration.self,
                capacity: 1
            ) { $0 }
        }.pointee
    }
}
