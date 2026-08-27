import XCTest

@testable import Sumi
import SumiDomain

@MainActor
final class BrowserTabSelectionOwnerTests: XCTestCase {
    func testAlreadyCurrentSelectionIsUnchangedAndPublishesNothing() throws {
        let harness = try makeHarness()
        let tab = makeTab(in: harness.space, manager: harness.manager)
        installSelection(tab, in: harness.window)
        let compositorVersion = harness.window.compositorInvalidation
            .compositorVersion

        let outcome = harness.owner.applyTabSelection(
            tab,
            in: harness.window,
            updateSpaceFromTab: true,
            updateTheme: true,
            rememberSelection: true,
            persistSelection: true,
            loadPolicy: .immediate
        )

        XCTAssertEqual(outcome, .unchanged)
        XCTAssertEqual(
            harness.window.compositorInvalidation.compositorVersion,
            compositorVersion
        )
        XCTAssertNil(harness.snapshotStore.loadSnapshot())
    }

    func testRegularSelectionCommitsWindowGlobalAndDurableState() throws {
        let harness = try makeHarness()
        let previousTab = makeTab(in: harness.space, manager: harness.manager)
        let selectedTab = makeTab(in: harness.space, manager: harness.manager)
        installSelection(previousTab, in: harness.window)
        harness.window.presentationState.isCommandPaletteVisible = true
        harness.window.commandPalettePresentationReason = .keyboard

        let outcome = harness.owner.applyTabSelection(
            selectedTab,
            in: harness.window,
            updateSpaceFromTab: true,
            updateTheme: true,
            rememberSelection: true,
            persistSelection: true,
            loadPolicy: .immediate
        )

        XCTAssertEqual(outcome, .committed)
        XCTAssertEqual(harness.window.currentTabId, selectedTab.id)
        XCTAssertEqual(harness.window.currentSpaceId, harness.space.id)
        XCTAssertEqual(
            harness.window.activeTabForSpace[harness.space.id],
            selectedTab.id
        )
        XCTAssertIdentical(
            harness.manager.tabStateStore.selection.currentTab,
            selectedTab
        )
        XCTAssertFalse(harness.window.presentationState.isCommandPaletteVisible)
        XCTAssertEqual(
            harness.snapshotStore.loadSnapshot()?.snapshot.currentTabId,
            selectedTab.id
        )
    }

    func testSelectionWithinInteractiveSourcePreservesInteractiveTheme() throws {
        let harness = try makeHarness()
        let destination = makeSpace(
            name: "Destination",
            theme: WorkspaceTheme(gradientTheme: .incognito),
            manager: harness.manager
        )
        let previousTab = makeTab(in: harness.space, manager: harness.manager)
        let selectedTab = makeTab(in: harness.space, manager: harness.manager)
        installSelection(previousTab, in: harness.window)
        let identity = harness.window.windowThemeState.beginInteractive(
            identity: SpaceTransitionIdentity(
                sourceSpaceId: harness.space.id,
                destinationSpaceId: destination.id
            ),
            from: harness.space.workspaceTheme,
            to: destination.workspaceTheme,
            initialProgress: 0.2
        )

        _ = harness.owner.applyTabSelection(
            selectedTab,
            in: harness.window,
            updateSpaceFromTab: true,
            updateTheme: true,
            rememberSelection: true,
            persistSelection: true,
            loadPolicy: .immediate
        )

        XCTAssertEqual(harness.window.currentSpaceId, harness.space.id)
        XCTAssertTrue(
            harness.window.windowThemeState
                .matchesInteractiveSpaceTransition(identity)
        )
    }

    func testSelectionAcrossInteractiveBoundaryPublishesDestinationTheme() throws {
        let harness = try makeHarness()
        let transitionDestination = makeSpace(
            name: "Transition Destination",
            theme: WorkspaceTheme(gradientTheme: .incognito),
            manager: harness.manager
        )
        let committedDestination = makeSpace(
            name: "Committed Destination",
            theme: WorkspaceTheme(
                gradientTheme: WorkspaceGradientTheme(
                    colors: [
                        WorkspaceThemeColor(
                            hex: "#0A84FF",
                            isPrimary: true,
                            position: .topLeft
                        ),
                        WorkspaceThemeColor(
                            hex: "#FFD60A",
                            position: .bottom
                        ),
                    ],
                    opacity: 0.72,
                    texture: 0.1
                )
            ),
            manager: harness.manager
        )
        let previousTab = makeTab(in: harness.space, manager: harness.manager)
        let selectedTab = makeTab(
            in: committedDestination,
            manager: harness.manager
        )
        installSelection(previousTab, in: harness.window)
        harness.window.windowThemeState.beginInteractive(
            identity: SpaceTransitionIdentity(
                sourceSpaceId: harness.space.id,
                destinationSpaceId: transitionDestination.id
            ),
            from: harness.space.workspaceTheme,
            to: transitionDestination.workspaceTheme,
            initialProgress: 0.2
        )

        _ = harness.owner.applyTabSelection(
            selectedTab,
            in: harness.window,
            updateSpaceFromTab: true,
            updateTheme: true,
            rememberSelection: true,
            persistSelection: true,
            loadPolicy: .immediate
        )

        XCTAssertEqual(
            harness.window.currentSpaceId,
            committedDestination.id
        )
        XCTAssertEqual(
            harness.window.windowThemeState.targetTheme,
            committedDestination.workspaceTheme
        )
    }

    func testPreparedSelectionPublishesEffectsWithoutRewritingTopologyOrPersistence() async throws {
        let harness = try makeHarness()
        let previousTab = makeTab(in: harness.space, manager: harness.manager)
        let selectedTab = makeTab(in: harness.space, manager: harness.manager)
        let preparedSplitSelection = WindowSplitSelection(
            groupID: UUID(),
            activeMemberID: .regularTab(selectedTab.id)
        )
        harness.window.currentTabId = selectedTab.id
        harness.window.currentSpaceId = harness.space.id
        harness.window.splitSelection = preparedSplitSelection

        let outcome = harness.owner.publishPreparedSelectionEffects(
            selectedTab,
            in: harness.window,
            previousTabID: previousTab.id,
            previousSpaceID: UUID()
        )

        XCTAssertEqual(outcome, .committed)
        XCTAssertEqual(harness.window.splitSelection, preparedSplitSelection)
        XCTAssertNil(harness.snapshotStore.loadSnapshot())
        await drainScheduledActivationWork()
        XCTAssertGreaterThan(
            harness.window.compositorInvalidation.compositorVersion,
            0
        )
    }

    func testPreparedSelectionRejectsStalePhysicalTabWitness() throws {
        let harness = try makeHarness()
        let currentTab = makeTab(in: harness.space, manager: harness.manager)
        let staleTab = Tab(
            id: currentTab.id,
            url: currentTab.url,
            name: currentTab.name,
            spaceId: currentTab.spaceId,
            loadsCachedFaviconOnInit: false
        )
        harness.window.currentTabId = currentTab.id
        harness.window.currentSpaceId = harness.space.id

        let outcome = harness.owner.publishPreparedSelectionEffects(
            staleTab,
            in: harness.window,
            previousTabID: nil,
            previousSpaceID: nil
        )

        XCTAssertEqual(outcome, .rejected)
        XCTAssertNil(harness.snapshotStore.loadSnapshot())
    }

    func testShortcutSyncUsesExactWindowResidence() throws {
        let harness = try makeHarness()
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: harness.space.id,
            index: 0,
            launchURL: URL(string: "https://example.com/pinned")!,
            title: "Pinned"
        )
        harness.manager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([pin], for: harness.space.id)
        let liveTab = harness.manager.tabFactory.makeTab(
            url: pin.launchURL,
            name: pin.title,
            spaceId: harness.space.id,
            loadsCachedFaviconOnInit: false
        )
        liveTab.bindToShortcutPin(pin)
        XCTAssertTrue(
            harness.manager.liveShortcutTabs.register(
                liveTab,
                for: pin.id,
                in: harness.window.id,
                presentationPage: LiveShortcutPresentationPageReceipt(
                    windowID: harness.window.id,
                    spaceID: harness.space.id,
                    profileID: harness.space.profileId
                )
            )
        )
        harness.window.currentTabId = liveTab.id

        harness.owner.syncShortcutSelectionState(for: harness.window)

        XCTAssertEqual(harness.window.currentShortcutPinId, pin.id)
        XCTAssertEqual(harness.window.currentShortcutPinRole, .spacePinned)
    }

    func testEmptyStateClearsSelectionAndPersistsWithoutOpeningCommandPalette() throws {
        let harness = try makeHarness()
        harness.window.currentSpaceId = harness.space.id
        harness.window.currentTabId = UUID()
        harness.window.currentShortcutPinId = UUID()
        harness.window.currentShortcutPinRole = .spacePinned
        harness.window.isShowingEmptyState = false

        harness.owner.showEmptyState(in: harness.window)

        XCTAssertNil(harness.window.currentTabId)
        XCTAssertNil(harness.window.currentShortcutPinId)
        XCTAssertNil(harness.window.currentShortcutPinRole)
        XCTAssertTrue(harness.window.isShowingEmptyState)
        XCTAssertFalse(harness.window.presentationState.isCommandPaletteVisible)
        XCTAssertEqual(harness.window.commandPalettePresentationReason, .none)
        XCTAssertNil(
            harness.snapshotStore.loadSnapshot()?.snapshot.currentTabId
        )
    }

    func testUserTabActivationAppliesSelectionSynchronously() throws {
        let harness = try makeHarness()
        let firstTab = makeTab(in: harness.space, manager: harness.manager)
        let secondTab = makeTab(in: harness.space, manager: harness.manager)

        let firstOutcome = harness.owner.requestUserTabActivation(
            firstTab,
            in: harness.window,
            loadPolicy: .immediate
        )
        XCTAssertTrue(firstOutcome.wasCommitted)
        XCTAssertEqual(harness.window.currentTabId, firstTab.id)

        let secondOutcome = harness.owner.requestUserTabActivation(
            secondTab,
            in: harness.window,
            loadPolicy: .deferred
        )

        XCTAssertTrue(secondOutcome.wasCommitted)
        XCTAssertEqual(harness.window.currentTabId, secondTab.id)
        XCTAssertEqual(harness.window.currentSpaceId, harness.space.id)
        XCTAssertEqual(
            harness.window.activeTabForSpace[harness.space.id],
            secondTab.id
        )
        XCTAssertEqual(
            harness.snapshotStore.loadSnapshot()?.snapshot.currentTabId,
            secondTab.id
        )
    }

    func testStartupRetryTransfersTheExactAcceptedMaterializationRequest()
        throws {
        let harness = try makeHarness(appliedProtectionLevel: .adblock)
        let tab = harness.manager.tabFactory.makeTab(
            url: try XCTUnwrap(URL(string: "file:///tmp/sumi-materialization.html")),
            name: "Deferred",
            spaceId: harness.space.id,
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = harness.window.currentProfileId
        XCTAssertTrue(harness.manager.regularTabLifecycleOwner.addTab(tab))
        XCTAssertTrue(
            harness.manager.startupMaterializationGate
                .shouldDeferNormalTabMaterialization
        )

        XCTAssertTrue(
            harness.owner.applyTabSelection(
                tab,
                in: harness.window,
                updateSpaceFromTab: true,
                updateTheme: false,
                rememberSelection: true,
                persistSelection: false,
                loadPolicy: .immediate
            ).wasCommitted
        )
        let accepted = try XCTUnwrap(
            harness.window.pageMaterializationRequests.currentRequest(
                in: harness.window.id
            )
        )

        XCTAssertTrue(
            harness.manager.startupMaterializationGate.finishProtectionRestore()
        )
        let settlement = try XCTUnwrap(
            harness.owner.materializeVisibleTabWebViewIfNeeded(
                tab,
                in: harness.window
            )
        )

        XCTAssertEqual(settlement.request.id, accepted.id)
        guard case .transferred = settlement.result else {
            return XCTFail("Expected transfer to one exact navigation attempt")
        }
    }

    func testSelectedLauncherCanRetryMaterializationWithoutGroupUnload()
        throws {
        let harness = try makeHarness(appliedProtectionLevel: .adblock)
        let destination = try XCTUnwrap(
            URL(string: "file:///tmp/sumi-launcher-retry.html")
        )
        let pin = try XCTUnwrap(
            harness.manager.shortcutPinStoreOwner.insert(
                ShortcutPin(
                    id: UUID(),
                    role: .spacePinned,
                    spaceId: harness.space.id,
                    index: 0,
                    launchURL: destination,
                    title: "Deferred Launcher"
                ),
                at: 0
            )
        )
        let liveTab = try XCTUnwrap(
            harness.manager.shortcutTabMaterializer.materialize(
                pin,
                in: harness.window.id,
                currentSpaceId: harness.space.id
            )
        )
        XCTAssertTrue(
            harness.owner.requestUserTabActivation(
                liveTab,
                in: harness.window,
                loadPolicy: .immediate
            ).wasCommitted
        )
        let first = try XCTUnwrap(
            harness.window.pageMaterializationRequests.currentRequest(
                for: liveTab.id,
                in: harness.window.id
            )
        )
        _ = harness.window.pageMaterializationRequests.settle(
            first,
            as: .failed(.residenceUnavailable)
        )
        liveTab.loadingState = .didFinish

        XCTAssertTrue(
            harness.manager.startupMaterializationGate.finishProtectionRestore()
        )
        XCTAssertTrue(
            harness.owner.requestUserTabActivation(
                liveTab,
                in: harness.window,
                loadPolicy: .immediate
            ).wasCommitted
        )

        XCTAssertEqual(harness.window.currentTabId, liveTab.id)
        XCTAssertIdentical(
            harness.manager.liveShortcutTabs.entry(tabId: liveTab.id)?.tab,
            liveTab
        )
        XCTAssertFalse(liveTab.isUnloaded)
        let webView = try XCTUnwrap(liveTab.resolvedCurrentWebView())
        switch liveTab.mainFrameLoads.attemptStatus(on: webView) {
        case .waiting, .submitted:
            break
        case .unsubmitted:
            XCTFail("Retry must transfer to a concrete navigation attempt")
        }
    }

    func testStartupProtectionCompletionLoadsSelectedDriftedLauncher()
        throws {
        let harness = try makeHarness(appliedProtectionLevel: .adblock)
        let launchURL = try XCTUnwrap(
            URL(string: "file:///tmp/sumi-launcher-original.html")
        )
        let driftedURL = try XCTUnwrap(
            URL(string: "file:///tmp/sumi-launcher-drifted.html")
        )
        let pin = try XCTUnwrap(
            harness.manager.shortcutPinStoreOwner.insert(
                ShortcutPin(
                    id: UUID(),
                    role: .favorite,
                    profileId: harness.window.currentProfileId,
                    spaceId: nil,
                    index: 0,
                    launchURL: launchURL,
                    title: "Drifted Launcher"
                ),
                at: 0
            )
        )
        harness.window.currentShortcutPinId = pin.id
        harness.window.currentShortcutPinRole = .favorite
        harness.window.restorationState.stageShortcutLiveSessions([
            ShortcutLiveSessionSnapshot(
                shortcutPinId: pin.id,
                presentationSpaceId: harness.space.id,
                currentURL: driftedURL,
                title: "Drifted Launcher"
            ),
        ])
        let restorer = WindowSessionShortcutRestorer(
            pins: harness.manager.shortcutPinCollectionStateOwner,
            activation: harness.manager.shortcutPresentationActivation
        )
        restorer.materializeRestoredLiveSessions(in: harness.window)
        XCTAssertTrue(restorer.materializeSelectionIfNeeded(in: harness.window))
        let liveTab = try XCTUnwrap(
            harness.manager.liveShortcutTabs.tab(
                for: pin.id,
                in: harness.window.id
            )
        )

        XCTAssertTrue(
            harness.owner.applyTabSelection(
                liveTab,
                in: harness.window,
                updateSpaceFromTab: true,
                updateTheme: false,
                rememberSelection: true,
                persistSelection: false,
                loadPolicy: .immediate
            ).wasCommitted
        )
        XCTAssertTrue(liveTab.isUnloaded)
        XCTAssertNotNil(
            harness.window.pageMaterializationRequests.currentRequest(
                for: liveTab.id,
                in: harness.window.id
            )
        )

        harness.manager.startupProtectionRuntime
            .finishStartupProtectionRestore()

        let webView = try XCTUnwrap(liveTab.resolvedCurrentWebView())
        XCTAssertEqual(liveTab.mainFrameLoads.currentIntent.targetURL, driftedURL)
        switch liveTab.mainFrameLoads.attemptStatus(on: webView) {
        case .waiting, .submitted:
            break
        case .unsubmitted:
            XCTFail("Startup completion must submit the drifted destination")
        }
    }

    private struct Harness {
        let manager: BrowserManager
        let owner: BrowserTabSelectionOwner
        let windowRegistry: WindowRegistry
        let window: BrowserWindowState
        let space: Space
        let snapshotStore: WindowSessionSnapshotStore
    }

    private func makeHarness(
        appliedProtectionLevel: SumiProtectionLevel? = nil
    ) throws -> Harness {
        let snapshotStore = WindowSessionSnapshotStore(
            key: "SumiTests.tab-selection.\(UUID().uuidString)",
            environment: { [:] }
        )
        let windowRegistry = WindowRegistry()
        let manager: BrowserManager
        if let appliedProtectionLevel {
            let defaults = UserDefaults(
                suiteName: "SumiTests.tab-selection.protection.\(UUID().uuidString)"
            )!
            let moduleRegistry = SumiModuleRegistry(
                settingsStore: SumiModuleSettingsStore(userDefaults: defaults)
            )
            let settings = SumiProtectionSettings(userDefaults: defaults)
            settings.setAppliedLevel(appliedProtectionLevel)
            let blocker = SumiAdBlockingModule(
                filterListCatalog: nil,
                compiledRuleListCatalog: SumiCompiledContentRuleListCatalog()
            )
            manager = BrowserManager(
                windowRegistry: windowRegistry,
                moduleRegistry: moduleRegistry,
                windowSessionSnapshotStore: snapshotStore,
                adBlockingModule: blocker,
                protectionCoordinator: SumiProtectionCoordinator(
                    settings: settings,
                    adBlockingModule: blocker,
                    compiledRuleListCatalog: SumiCompiledContentRuleListCatalog()
                )
            )
        } else {
            manager = BrowserManager(
                windowRegistry: windowRegistry,
                windowSessionSnapshotStore: snapshotStore
            )
        }
        let profile = try XCTUnwrap(
            manager.currentProfileAuthority.currentProfile
        )
        let space = makeSpace(
            name: "Selection",
            theme: .default,
            profileID: profile.id,
            manager: manager
        )
        let window = BrowserWindowState()
        manager.tabResidenceAuthority.establishResidenceSession(on: window)
        window.currentProfileId = profile.id
        window.currentSpaceId = space.id
        XCTAssertEqual(windowRegistry.register(window), .registered)
        windowRegistry.setActive(window)
        return Harness(
            manager: manager,
            owner: manager.browserTabSelection,
            windowRegistry: windowRegistry,
            window: window,
            space: space,
            snapshotStore: snapshotStore
        )
    }

    private func makeSpace(
        name: String,
        theme: WorkspaceTheme,
        profileID: UUID? = nil,
        manager: BrowserManager
    ) -> Space {
        let profileID = profileID
            ?? manager.currentProfileAuthority.currentProfile?.id
        let space = Space(
            name: name,
            workspaceTheme: theme,
            profileId: profileID
        )
        manager.spaceStateOwner.append(space)
        return space
    }

    private func makeTab(
        in space: Space,
        manager: BrowserManager
    ) -> Tab {
        manager.regularTabLifecycleOwner.createNewTab(
            in: space,
            activate: false
        )
    }

    private func installSelection(
        _ tab: Tab,
        in windowState: BrowserWindowState
    ) {
        windowState.currentTabId = tab.id
        windowState.currentSpaceId = tab.spaceId
        windowState.isShowingEmptyState = false
        if let spaceID = tab.spaceId {
            windowState.activeTabForSpace[spaceID] = tab.id
            windowState.selectionHistory.recentRegularTabIdsBySpace[spaceID] = [
                tab.id,
            ]
            windowState.selectionHistory.recentSelectionItemsBySpace[spaceID] = [
                .regularTab(tab.id),
            ]
        }
    }

    private func drainScheduledActivationWork() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
        await Task.yield()
    }
}
