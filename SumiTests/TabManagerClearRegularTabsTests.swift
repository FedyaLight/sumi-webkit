import SumiWebRuntime
import XCTest

@testable import Sumi
import SumiDomain

@MainActor
final class TabManagerClearRegularTabsTests: XCTestCase {
    func testCreatedRegularTabStartsOnInjectedCanonicalWebViewRepository() throws {
        let tabManager = BrowserManager()
        let webViewSessions = tabManager.webViewSessions
        let space = try makeSpace(tabManager, name: "S", profileId: UUID())

        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com",
            in: space,
            activate: false
        )

        XCTAssertTrue(tab.webViewSession.isBacked(by: webViewSessions))
    }

    func testRemoveTabUsesRequiredRuntimeWebViewCleanup() throws {
        var cleanupCalls: [UUID] = []
        let tabManager = makeBrowser(
            runtimePorts: TestRuntimePorts.make(
                webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                    retirement: .rejecting,
                    requireRemoveAllWebViews: { tab in
                        cleanupCalls.append(tab.id)
                    }
                )
            )
        )
        let space = try makeSpace(tabManager, name: "S", profileId: UUID())
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(in: space, activate: true)

        tabManager.tabClosureService.removeTab(tab.id)

        XCTAssertEqual(cleanupCalls.count, 1)
        XCTAssertEqual(cleanupCalls.first, tab.id)
    }

    func testClearRegularTabs_secondClearRemovesLastActiveTab() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "S", profileId: profileId)

        _ = tabManager.regularTabLifecycleOwner.createNewTab(in: space, activate: true)
        _ = tabManager.regularTabLifecycleOwner.createNewTab(in: space, activate: false)

        XCTAssertEqual(tabManager.regularTabCollectionOwner.tabs(in: space).count, 2)

        tabManager.tabClosureService.clearRegularTabs(for: space.id)
        XCTAssertEqual(tabManager.regularTabCollectionOwner.tabs(in: space).count, 1)

        tabManager.tabClosureService.clearRegularTabs(for: space.id)
        XCTAssertEqual(tabManager.regularTabCollectionOwner.tabs(in: space).count, 0)
    }

    func testClearRegularTabs_otherSpaceClearsOnlyTargetSpaceTabs() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let spaceA = try makeSpace(tabManager, name: "A", profileId: profileId)
        let tabA = tabManager.regularTabLifecycleOwner.createNewTab(in: spaceA, activate: true)
        let spaceB = try makeSpace(tabManager, name: "B", profileId: profileId)
        _ = tabManager.regularTabLifecycleOwner.createNewTab(in: spaceB, activate: true)

        tabManager.spaceActivation.setActiveSpace(spaceA, preferredTab: tabA)
        XCTAssertEqual(tabManager.tabStateStore.selection.currentTab?.id, tabA.id)

        tabManager.tabClosureService.clearRegularTabs(for: spaceB.id)

        XCTAssertTrue(tabManager.regularTabCollectionOwner.tabs(in: spaceB).isEmpty)
        XCTAssertEqual(tabManager.tabStateStore.selection.currentTab?.id, tabA.id)
        XCTAssertEqual(tabManager.regularTabCollectionOwner.tabs(in: spaceA).count, 1)
    }

    func testProfileCleanupDeletesOwnedSpacesAndMovesStaleTabsToOwningSpaceProfile() async throws {
        let deletedProfileId = UUID()
        let fallbackProfileId = UUID()
        let reassignedProfileId = UUID()
        let profiles = [
            deletedProfileId: Profile(id: deletedProfileId, name: "Deleted"),
            fallbackProfileId: Profile(id: fallbackProfileId, name: "Fallback"),
            reassignedProfileId: Profile(
                id: reassignedProfileId,
                name: "Reassigned"
            ),
        ]
        let tabManager = makeBrowser(
            runtimePorts: TestRuntimePorts.make(profile: { profiles[$0] })
        )

        let deletedSpace = try makeSpace(tabManager, name: "Deleted", profileId: deletedProfileId)
        let reassignedSpace = try makeSpace(
            tabManager,
            name: "Reassigned",
            profileId: reassignedProfileId
        )

        let staleTab = tabManager.regularTabLifecycleOwner.createNewTab(in: reassignedSpace, activate: true)
        staleTab.profileId = deletedProfileId
        let deletedPin = ShortcutPin(
            id: UUID(),
            role: .favorite,
            profileId: deletedProfileId,
            index: 0,
            launchURL: URL(string: "https://old.example")!,
            title: "Old"
        )
        tabManager.structuralCollectionMutationOwner.setPinnedTabs([deletedPin], for: deletedProfileId)

        let outcome = await tabManager.profileDeletion.migrate(
            deletedProfileID: deletedProfileId,
            fallbackProfileID: fallbackProfileId
            )

        XCTAssertEqual(outcome, .committed)
        XCTAssertNil(tabManager.spaceStateOwner.space(with: deletedSpace.id))
        XCTAssertEqual(reassignedSpace.profileId, reassignedProfileId)
        XCTAssertNil(staleTab.profileId)
        XCTAssertEqual(
            resolvedAssignmentProfile(
                for: staleTab,
                desiredProfileID: nil,
                in: tabManager
            )?.id,
            reassignedProfileId
        )
        XCTAssertNil(
            tabManager.shortcutPinCollectionStateOwner
                .pinnedByProfileSnapshot()[deletedProfileId]
        )
    }

    func testAssigningRegularTabProfileDoesNotChangeSpaceProfile() throws {
        let spaceProfileId = UUID()
        let tabProfileId = UUID()
        let spaceProfile = Profile(id: spaceProfileId, name: "Space")
        let tabProfile = Profile(id: tabProfileId, name: "Tab")
        let profiles = [spaceProfileId: spaceProfile, tabProfileId: tabProfile]
        let tabManager = makeBrowser(
            runtimePorts: TestRuntimePorts.make(profile: { profiles[$0] })
        )
        let space = try makeSpace(tabManager, name: "Work", profileId: spaceProfileId)
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(in: space, activate: true)

        XCTAssertTrue(
            tabManager.tabProfileTransitions.assign(
                tab,
                toProfile: tabProfileId
            )
        )

        XCTAssertEqual(space.profileId, spaceProfileId)
        XCTAssertEqual(tab.profileId, tabProfileId)
    }

    func testSelectingCommittedProfileCancelsPendingDeferredAssignment() throws {
        let committedProfile = Profile(name: "Committed")
        let deferredProfile = Profile(name: "Deferred")
        let profiles = [
            committedProfile.id: committedProfile,
            deferredProfile.id: deferredProfile,
        ]
        let tabManager = makeBrowser(
            runtimePorts: TestRuntimePorts.make(profile: { profiles[$0] })
        )
        let space = try makeSpace(
            tabManager,
            name: "Work",
            profileId: committedProfile.id
        )
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            in: space,
            activate: false
        )
        tab.profileId = committedProfile.id
        let deferredIntent = tab.profileAssignment.begin(
            desiredProfileID: deferredProfile.id,
            resolvedProfileID: deferredProfile.id,
            targetURL: tab.url,
            navigationRevision: tab.mainFrameLoads.currentIntent.revision,
            requiresStructuralPersistence: true
        )

        XCTAssertTrue(
            tabManager.tabProfileTransitions.assign(
                tab,
                toProfile: committedProfile.id
            )
        )

        XCTAssertEqual(tab.profileId, committedProfile.id)
        XCTAssertFalse(tab.profileAssignment.isCurrent(deferredIntent))
        XCTAssertFalse(
            tabManager.tabProfileTransitions.executeDeferred(
                tab: tab,
                intent: deferredIntent
            )
        )
        XCTAssertEqual(tab.profileId, committedProfile.id)
    }

    func testDeletedDeferredTargetAbortsExactPendingIntent() throws {
        let committedProfile = Profile(name: "Committed")
        let deletedProfile = Profile(name: "Deleted")
        var profiles = [
            committedProfile.id: committedProfile,
            deletedProfile.id: deletedProfile,
        ]
        let tabManager = makeBrowser(
            runtimePorts: TestRuntimePorts.make(profile: { profiles[$0] })
        )
        let space = try makeSpace(
            tabManager,
            name: "Work",
            profileId: committedProfile.id
        )
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            in: space,
            activate: false
        )
        tab.profileId = committedProfile.id
        let deferredIntent = tab.profileAssignment.begin(
            desiredProfileID: deletedProfile.id,
            resolvedProfileID: deletedProfile.id,
            targetURL: tab.url,
            navigationRevision: tab.mainFrameLoads.currentIntent.revision,
            requiresStructuralPersistence: true
        )
        profiles.removeValue(forKey: deletedProfile.id)

        XCTAssertFalse(
            tabManager.tabProfileTransitions.executeDeferred(
                tab: tab,
                intent: deferredIntent
            )
        )

        XCTAssertEqual(tab.profileId, committedProfile.id)
        XCTAssertFalse(tab.profileAssignment.isCurrent(deferredIntent))
    }

    func testDeferredRegularProfileReplayRejectsNavigationDriftBeforeRuntimeExecution()
        throws {
        let sourceProfile = Profile(name: "Source")
        let targetProfile = Profile(name: "Target")
        let profiles = [
            sourceProfile.id: sourceProfile,
            targetProfile.id: targetProfile,
        ]
        var executionCount = 0
        var executedIntent: DeferredWebViewProfileAssignmentIntent?
        let tabManager = makeBrowser(
            runtimePorts: TestRuntimePorts.make(
                currentProfileId: { sourceProfile.id },
                defaultProfileId: { sourceProfile.id },
                profile: { profiles[$0] },
                webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                    retirement: .rejecting,
                    executeProfileAssignment: { _, _, intent in
                        executionCount += 1
                        executedIntent = intent
                        return .deferred
                    }
                )
            )
        )
        let space = try makeSpace(
            tabManager,
            name: "Work",
            profileId: sourceProfile.id
        )
        let capturedURL = try XCTUnwrap(
            URL(string: "https://example.com/captured-profile-document")
        )
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: capturedURL.absoluteString,
            in: space,
            activate: false
        )
        let sourceProfileID = tab.profileId
        let capturedNavigation = tab.beginMainFrameNavigationIntent(
            to: capturedURL
        )
        var observedIntent: DeferredWebViewProfileAssignmentIntent?

        let outcome = tabManager.tabProfileTransitions.start(
            desiredProfileID: targetProfile.id,
            tab: tab,
            requiresStructuralPersistence: true,
            capturingIntent: { observedIntent = $0 }
        )

        let deferredIntent = try XCTUnwrap(observedIntent)
        XCTAssertEqual(outcome, .deferred)
        XCTAssertEqual(executionCount, 1)
        XCTAssertEqual(executedIntent, deferredIntent)
        XCTAssertEqual(deferredIntent.targetURL, capturedNavigation.targetURL)
        XCTAssertEqual(
            deferredIntent.navigationRevision,
            capturedNavigation.revision
        )
        XCTAssertTrue(tab.profileAssignment.isCurrent(deferredIntent))

        _ = tab.beginMainFrameNavigationIntent(
            to: URL(string: "https://example.com/newer-document")!
        )

        XCTAssertFalse(
            tabManager.tabProfileTransitions.executeDeferred(
                tab: tab,
                intent: deferredIntent
            )
        )
        XCTAssertEqual(executionCount, 1)
        XCTAssertEqual(tab.profileId, sourceProfileID)
        XCTAssertFalse(tab.profileAssignment.isCurrent(deferredIntent))
        XCTAssertFalse(tab.profileAssignment.hasUnsettledAssignment)
    }

    func testCrossProfileSpaceMovePinsOldProfileUntilReplacementCommits() throws {
        let oldProfile = Profile(name: "Old")
        let targetProfile = Profile(name: "Target")
        let profiles = [oldProfile.id: oldProfile, targetProfile.id: targetProfile]
        var shouldDefer = true
        var capturedIntent: DeferredWebViewProfileAssignmentIntent?
        let tabManager = makeBrowser(
            runtimePorts: TestRuntimePorts.make(
                currentProfileId: { oldProfile.id },
                defaultProfileId: { oldProfile.id },
                profile: { profiles[$0] },
                webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                    retirement: .rejecting,
                    executeProfileAssignment: { tab, _, intent in
                        capturedIntent = intent
                        if shouldDefer { return .deferred }
                        return tab.profileAssignment.commit(intent)
                            ? .committed
                            : .stale
                    }
                )
            )
        )
        let oldSpace = try makeSpace(
            tabManager,
            name: "Old",
            profileId: oldProfile.id
        )
        let targetSpace = try makeSpace(
            tabManager,
            name: "Target",
            profileId: targetProfile.id
        )
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            in: oldSpace,
            activate: false
        )
        XCTAssertNil(tab.profileId)
        _ = tabManager.regularTabCollectionOwner.remove(
            tab.id,
            from: oldSpace.id,
            currentSpaceId: oldSpace.id
        )

        tabManager.regularTabCollectionOwner.insert(
            tab,
            in: targetSpace.id,
            at: 0
        )

        let deferredIntent = try XCTUnwrap(capturedIntent)
        XCTAssertEqual(tab.spaceId, targetSpace.id)
        XCTAssertEqual(
            tab.profileId,
            oldProfile.id,
            "The structural move must preserve the old effective profile while replacement is deferred"
        )
        XCTAssertNil(deferredIntent.desiredProfileID)
        XCTAssertEqual(deferredIntent.resolvedProfileID, targetProfile.id)
        XCTAssertTrue(tab.profileAssignment.isCurrent(deferredIntent))

        shouldDefer = false
        XCTAssertTrue(
            tabManager.tabProfileTransitions.executeDeferred(
                tab: tab,
                intent: deferredIntent
            )
        )
        XCTAssertNil(tab.profileId)
        XCTAssertEqual(
            resolvedAssignmentProfile(
                for: tab,
                desiredProfileID: nil,
                in: tabManager
            )?.id,
            targetProfile.id
        )
    }

    func testAssigningPinnedTabProfileUpdatesLauncherAndLiveInstanceOnly() throws {
        let spaceProfileId = UUID()
        let pinnedProfileId = UUID()
        let profiles = [
            spaceProfileId: Profile(id: spaceProfileId, name: "Space"),
            pinnedProfileId: Profile(id: pinnedProfileId, name: "Pinned"),
        ]
        let tabManager = makeBrowser(
            runtimePorts: TestRuntimePorts.make(
                profileExists: { profiles[$0] != nil },
                profile: { profiles[$0] },
                webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                    retirement: .accepting
                )
            )
        )
        let space = try makeSpace(tabManager, name: "Work", profileId: spaceProfileId)
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com", in: space, activate: false)
        let pin = try XCTUnwrap(
            convert(
                tab,
                to: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                in: tabManager
            )
        )
        let liveTab = tabManager.shortcutTabMaterializer.materialize(pin, in: UUID(), currentSpaceId: space.id)!

        let updatedPin = try XCTUnwrap(
            tabManager.shortcutExecutionProfileAssignments.assign(
                pin,
                toExecutionProfile: pinnedProfileId
            )
        )

        XCTAssertEqual(space.profileId, spaceProfileId)
        XCTAssertNil(updatedPin.profileId)
        XCTAssertEqual(updatedPin.executionProfileId, pinnedProfileId)
        XCTAssertEqual(liveTab.profileId, pinnedProfileId)
    }

    func testAssigningFavoriteProfileKeepsFavoriteOwnerProfile() throws {
        let ownerProfileId = UUID()
        let executionProfileId = UUID()
        let profiles = [
            ownerProfileId: Profile(id: ownerProfileId, name: "Owner"),
            executionProfileId: Profile(
                id: executionProfileId,
                name: "Execution"
            ),
        ]
        let tabManager = makeBrowser(
            runtimePorts: TestRuntimePorts.make(
                profileExists: { profiles[$0] != nil },
                profile: { profiles[$0] },
                webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                    retirement: .accepting
                )
            )
        )
        let space = try makeSpace(tabManager, name: "Work", profileId: ownerProfileId)
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com", in: space, activate: false)
        let pin = try XCTUnwrap(
            convert(
                tab,
                to: .favorite,
                profileId: ownerProfileId,
                spaceId: nil,
                in: tabManager
            )
        )

        let updatedPin = try XCTUnwrap(
            tabManager.shortcutExecutionProfileAssignments.assign(
                pin,
                toExecutionProfile: executionProfileId
            )
        )

        XCTAssertEqual(updatedPin.profileId, ownerProfileId)
        XCTAssertEqual(updatedPin.executionProfileId, executionProfileId)
        XCTAssertEqual(
            tabManager.shortcutPinCollectionStateOwner
                .favoritePins(for: ownerProfileId).first?.id,
            pin.id
        )
    }

    func testPinTabConvertsDisplayedTabUsingOwningWindowContext() throws {
        let profileId = UUID()
        let profile = Profile(id: profileId, name: "Profile")
        let windowState = BrowserWindowState()
        let tabManager = makeBrowser(
            runtimePorts: TestRuntimePorts.make(
                currentProfileId: { profileId },
                profileExists: { $0 == profileId },
                profile: { $0 == profileId ? profile : nil },
                windowState: { windowId in
                    windowId == windowState.id ? windowState : nil
                },
                windows: { [(windowState.id, windowState)] },
                webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                    retirement: .accepting
                )
            )
        )
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profileId
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com", in: space, activate: false)
        windowState.currentTabId = tab.id

        tabManager.sidebarPinCommands.pinTab(
            tab,
            context: .init(windowState: windowState)
        )

        let pin = try XCTUnwrap(
            tabManager.shortcutPinCollectionStateOwner
                .favoritePins(for: profileId).first
        )
        let liveTab = try XCTUnwrap(tabManager.shortcutPresentationOwner.activeShortcutTab(for: windowState.id))
        XCTAssertEqual(liveTab.id, tab.id)
        XCTAssertEqual(liveTab.shortcutPinId, pin.id)
        XCTAssertEqual(windowState.currentShortcutPinId, pin.id)
        XCTAssertEqual(windowState.currentTabId, tab.id)
        XCTAssertFalse(tabManager.regularTabCollectionOwner.tabs(in: space).contains { $0.id == tab.id })
    }

    func testPinTabPreservesPrimaryOwnerAndMaterializesActionWindow() throws {
        let profileId = UUID()
        let profile = Profile(id: profileId, name: "Profile")
        let primaryWindow = BrowserWindowState()
        let actionWindow = BrowserWindowState()
        var materializations: [(tabId: UUID, windowId: UUID)] = []
        let windowsById = [
            primaryWindow.id: primaryWindow,
            actionWindow.id: actionWindow,
        ]
        let tabManager = makeBrowser(
            runtimePorts: TestRuntimePorts.make(
                currentProfileId: { profileId },
                profileExists: { $0 == profileId },
                profile: { $0 == profileId ? profile : nil },
                windowState: { windowsById[$0] },
                windows: { windowsById.map { ($0.key, $0.value) } },
                webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                    retirement: .accepting,
                    materializeVisibleTabWebViewIfNeeded: { tab, windowState in
                        materializations.append((tab.id, windowState.id))
                    },
                    primaryTrackedWindowId: { tabId in
                        windowsById[primaryWindow.id]?.currentTabId == tabId
                            ? primaryWindow.id
                            : nil
                    }
                )
            )
        )
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        primaryWindow.currentSpaceId = space.id
        primaryWindow.currentProfileId = profileId
        actionWindow.currentSpaceId = space.id
        actionWindow.currentProfileId = profileId
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com", in: space, activate: false)
        primaryWindow.currentTabId = tab.id
        actionWindow.currentTabId = tab.id

        tabManager.sidebarPinCommands.pinTab(
            tab,
            context: .init(windowState: actionWindow)
        )

        let pin = try XCTUnwrap(
            tabManager.shortcutPinCollectionStateOwner
                .favoritePins(for: profileId).first
        )
        let primaryLiveTab = try XCTUnwrap(tabManager.shortcutPresentationOwner.activeShortcutTab(for: primaryWindow.id))
        XCTAssertEqual(primaryLiveTab.id, tab.id)
        XCTAssertEqual(primaryLiveTab.shortcutPinId, pin.id)
        XCTAssertEqual(primaryWindow.currentTabId, tab.id)
        XCTAssertEqual(primaryWindow.currentShortcutPinId, pin.id)
        let liveTab = try XCTUnwrap(tabManager.shortcutPresentationOwner.activeShortcutTab(for: actionWindow.id))
        XCTAssertNotEqual(liveTab.id, tab.id)
        XCTAssertEqual(liveTab.shortcutPinId, pin.id)
        XCTAssertEqual(materializations.map(\.tabId), [liveTab.id])
        XCTAssertEqual(materializations.map(\.windowId), [actionWindow.id])
        XCTAssertEqual(actionWindow.currentShortcutPinId, pin.id)
        XCTAssertEqual(actionWindow.currentTabId, liveTab.id)
    }

    func testContextlessProfileSwitchKeepsCurrentShortcutLiveTab() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let pin = try XCTUnwrap(tabManager.shortcutPinStoreOwner.insert(ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            launchURL: URL(string: "https://example.com")!,
            title: "Example"
        ), at: 0))
        let liveTab = tabManager.shortcutTabMaterializer.materialize(pin, in: UUID(), currentSpaceId: space.id)!
        tabManager.activeSelectionOwner.setActiveTab(liveTab)

        tabManager.profileSelection.handleProfileSwitch()

        XCTAssertEqual(tabManager.tabStateStore.selection.currentTab?.id, liveTab.id)
    }

    func testProfileCleanupDoesNotKeepRemovedFavoriteLiveTab() async throws {
        let deletedProfileId = UUID()
        let fallbackProfileId = UUID()
        let profiles = [
            deletedProfileId: Profile(id: deletedProfileId, name: "Deleted"),
            fallbackProfileId: Profile(id: fallbackProfileId, name: "Fallback"),
        ]
        let windowState = BrowserWindowState()
        let tabManager = makeBrowser(
            runtimePorts: TestRuntimePorts.make(
                profileExists: { profiles[$0] != nil },
                profile: { profiles[$0] },
                windowState: { $0 == windowState.id ? windowState : nil },
                windows: { [(windowState.id, windowState)] },
                webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                    retirement: .accepting
                )
            )
        )
        let deletedSpace = try makeSpace(
            tabManager,
            name: "Deleted Work",
            profileId: deletedProfileId
        )
        _ = try makeSpace(tabManager, name: "Work", profileId: fallbackProfileId)
        windowState.currentSpaceId = deletedSpace.id
        windowState.currentProfileId = deletedProfileId
        let pin = try XCTUnwrap(tabManager.shortcutPinStoreOwner.insert(ShortcutPin(
            id: UUID(),
            role: .favorite,
            profileId: deletedProfileId,
            index: 0,
            launchURL: URL(string: "https://example.com")!,
            title: "Example"
        ), at: 0))
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: windowState.id,
            currentSpaceId: deletedSpace.id
        )!
        tabManager.activeSelectionOwner.setActiveTab(liveTab)

        let outcome = await tabManager.profileDeletion.migrate(
            deletedProfileID: deletedProfileId,
            fallbackProfileID: fallbackProfileId
            )

        XCTAssertEqual(outcome, .committed)
        XCTAssertNotEqual(tabManager.tabStateStore.selection.currentTab?.id, liveTab.id)
        XCTAssertNil(
            tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id)
        )
    }

    func testLauncherFaviconPartitionFallsBackToContainerProfileWhenExecutionProfileIsImplicit() throws {
        let profileId = UUID()
        let profile = Profile(id: profileId, name: "Profile")
        let tabManager = makeBrowser(
            runtimePorts: TestRuntimePorts.make(
                profileExists: { $0 == profileId },
                profile: { $0 == profileId ? profile : nil },
                webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                    retirement: .accepting
                )
            )
        )
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/app", in: space, activate: false)
        tab.profileId = profileId

        let favoritePin = try XCTUnwrap(
            convert(
                tab,
                to: .favorite,
                profileId: profileId,
                spaceId: nil,
                in: tabManager
            )
        )
        XCTAssertNil(favoritePin.executionProfileId)
        XCTAssertEqual(tabManager.shortcutPinRuntimeResolutionOwner.resolvedExecutionProfileId(for: favoritePin), profileId)
        XCTAssertEqual(tabManager.shortcutPinRuntimeResolutionOwner.resolvedFaviconPartition(for: favoritePin), .regular())

        let spacePinnedTab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/space", in: space, activate: false)
        spacePinnedTab.profileId = profileId
        let spacePin = try XCTUnwrap(
            convert(
                spacePinnedTab,
                to: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                in: tabManager
            )
        )
        XCTAssertNil(spacePin.executionProfileId)
        XCTAssertEqual(tabManager.shortcutPinRuntimeResolutionOwner.resolvedExecutionProfileId(for: spacePin, currentSpaceId: space.id), profileId)
        XCTAssertEqual(tabManager.shortcutPinRuntimeResolutionOwner.resolvedFaviconPartition(for: spacePin, currentSpaceId: space.id), .regular())
    }

    private func makeBrowser(
        runtimePorts: RuntimePortRegistry
    ) -> BrowserManager {
        let browser = BrowserManager(runtimePorts: runtimePorts)
        return browser
    }

    private func makeSpace(
        _ browser: BrowserManager,
        name: String,
        profileId: UUID
    ) throws -> Space {
        try XCTUnwrap(
            browser.sidebarSpaceLifecycle.createSpace(
                name: name,
                icon: "square",
                profileID: profileId
            )
        )
    }

    private func convert(
        _ tab: Tab,
        to role: SumiDomain.ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        in browser: BrowserManager
    ) -> ShortcutPin? {
        browser.regularTabShortcutConversion.convert(
            tab,
            destination: TabShortcutPinDestination(
                role: role,
                profileId: profileId,
                spaceId: spaceId,
                folderId: nil,
                index: 0,
                opensFolder: false
            )
        )
    }

    private func resolvedAssignmentProfile(
        for tab: Tab,
        desiredProfileID: UUID?,
        in browser: BrowserManager
    ) -> Profile? {
        ProfileAssignmentPolicy(
            runtimeConnection: browser.runtimePortConnection,
            spaces: browser.spaceStateOwner,
            membership: browser.tabCollectionMembershipOwner,
            transientTabs: browser.tabStateStore.transientTabs
        ).resolvedAssignmentProfile(
            for: tab,
            desiredProfileID: desiredProfileID
        )
    }
}
