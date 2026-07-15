import SumiWebRuntime
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class TabManagerClearRegularTabsTests: XCTestCase {
    func testCreatedRegularTabStartsOnInjectedCanonicalWebViewRepository() throws {
        let webViewSessions = WebViewSessionRepository()
        let tabManager = try makeInMemoryTabManager(webViewSessions: webViewSessions)
        let space = tabManager.spaceServices.catalog.createSpace(name: "S", profileId: UUID())

        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com",
            in: space,
            activate: false
        )

        XCTAssertTrue(tab.webViewSession.isBacked(by: webViewSessions))
    }

    func testRemoveTabUsesRequiredRuntimeWebViewCleanup() throws {
        var cleanupCalls: [(tabId: UUID, closeActiveFullscreenMedia: Bool)] = []
        let tabManager = try makeInMemoryTabManager(
            requireRemoveAllWebViews: { tab, closeActiveFullscreenMedia in
                cleanupCalls.append((tab.id, closeActiveFullscreenMedia))
            }
        )
        let space = tabManager.spaceServices.catalog.createSpace(name: "S", profileId: UUID())
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(in: space, activate: true)

        tabManager.tabClosureService.removeTab(tab.id)

        XCTAssertEqual(cleanupCalls.count, 1)
        XCTAssertEqual(cleanupCalls.first?.tabId, tab.id)
        XCTAssertEqual(cleanupCalls.first?.closeActiveFullscreenMedia, true)
    }

    func testClearRegularTabs_secondClearRemovesLastActiveTab() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.spaceServices.catalog.createSpace(name: "S", profileId: profileId)

        _ = tabManager.regularTabLifecycleOwner.createNewTab(in: space, activate: true)
        _ = tabManager.regularTabLifecycleOwner.createNewTab(in: space, activate: false)

        XCTAssertEqual(tabManager.regularTabCollectionOwner.tabs(in: space).count, 2)

        tabManager.tabClosureService.clearRegularTabs(for: space.id)
        XCTAssertEqual(tabManager.regularTabCollectionOwner.tabs(in: space).count, 1)

        tabManager.tabClosureService.clearRegularTabs(for: space.id)
        XCTAssertEqual(tabManager.regularTabCollectionOwner.tabs(in: space).count, 0)
    }

    func testClearRegularTabs_otherSpaceClearsOnlyTargetSpaceTabs() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let spaceA = tabManager.spaceServices.catalog.createSpace(name: "A", profileId: profileId)
        let tabA = tabManager.regularTabLifecycleOwner.createNewTab(in: spaceA, activate: true)
        let spaceB = tabManager.spaceServices.catalog.createSpace(name: "B", profileId: profileId)
        _ = tabManager.regularTabLifecycleOwner.createNewTab(in: spaceB, activate: true)

        tabManager.spaceServices.activation.setActiveSpace(spaceA, preferredTab: tabA)
        XCTAssertEqual(tabManager.selectionStateOwner.currentTab?.id, tabA.id)

        tabManager.tabClosureService.clearRegularTabs(for: spaceB.id)

        XCTAssertTrue(tabManager.regularTabCollectionOwner.tabs(in: spaceB).isEmpty)
        XCTAssertEqual(tabManager.selectionStateOwner.currentTab?.id, tabA.id)
        XCTAssertEqual(tabManager.regularTabCollectionOwner.tabs(in: spaceA).count, 1)
    }

    func testProfileCleanupKeepsReassignedSpacesAndMovesStaleTabsToOwningSpaceProfile() async throws {
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
        let tabManager = try makeInMemoryTabManager(profile: { profiles[$0] })

        let deletedSpace = tabManager.spaceServices.catalog.createSpace(name: "Deleted", profileId: deletedProfileId)
        let reassignedSpace = tabManager.spaceServices.catalog.createSpace(
            name: "Reassigned",
            profileId: reassignedProfileId
        )

        let staleTab = tabManager.regularTabLifecycleOwner.createNewTab(in: reassignedSpace, activate: true)
        staleTab.profileId = deletedProfileId
        let deletedPin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: deletedProfileId,
            index: 0,
            launchURL: URL(string: "https://old.example")!,
            title: "Old"
        )
        tabManager.structuralCollectionMutationOwner.setPinnedTabs([deletedPin], for: deletedProfileId)

        let outcome = await tabManager.profileAssignments.deletion.migrate(
            deletedProfileID: deletedProfileId,
            fallbackProfileID: fallbackProfileId
            )

        XCTAssertEqual(outcome, .committed)
        XCTAssertEqual(deletedSpace.profileId, fallbackProfileId)
        XCTAssertEqual(reassignedSpace.profileId, reassignedProfileId)
        XCTAssertNil(staleTab.profileId)
        XCTAssertEqual(
            tabManager.profileAssignments.policy.resolvedAssignmentProfile(
                for: staleTab,
                desiredProfileID: nil
            )?.id,
            reassignedProfileId
        )
        XCTAssertNil(tabManager.shortcutPinCollectionStateOwner.pinnedByProfileSnapshot()[deletedProfileId])
    }

    func testAssigningRegularTabProfileDoesNotChangeSpaceProfile() throws {
        let spaceProfileId = UUID()
        let tabProfileId = UUID()
        let spaceProfile = Profile(id: spaceProfileId, name: "Space")
        let tabProfile = Profile(id: tabProfileId, name: "Tab")
        let profiles = [spaceProfileId: spaceProfile, tabProfileId: tabProfile]
        let tabManager = try makeInMemoryTabManager(
            profile: { profiles[$0] }
        )
        let space = tabManager.spaceServices.catalog.createSpace(name: "Work", profileId: spaceProfileId)
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(in: space, activate: true)

        XCTAssertTrue(
            tabManager.profileAssignments.tabs.assign(
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
        let tabManager = try makeInMemoryTabManager(
            profile: { profiles[$0] }
        )
        let space = tabManager.spaceServices.catalog.createSpace(
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
            requiresStructuralPersistence: true
        )

        XCTAssertTrue(
            tabManager.profileAssignments.tabs.assign(
                tab,
                toProfile: committedProfile.id
            )
        )

        XCTAssertEqual(tab.profileId, committedProfile.id)
        XCTAssertFalse(tab.profileAssignment.isCurrent(deferredIntent))
        XCTAssertFalse(
            tabManager.profileAssignments.tabs.executeDeferred(
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
        let tabManager = try makeInMemoryTabManager(
            profile: { profiles[$0] }
        )
        let space = tabManager.spaceServices.catalog.createSpace(
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
            requiresStructuralPersistence: true
        )
        profiles.removeValue(forKey: deletedProfile.id)

        XCTAssertFalse(
            tabManager.profileAssignments.tabs.executeDeferred(
                tab: tab,
                intent: deferredIntent
            )
        )

        XCTAssertEqual(tab.profileId, committedProfile.id)
        XCTAssertFalse(tab.profileAssignment.isCurrent(deferredIntent))
    }

    func testCrossProfileSpaceMovePinsOldProfileUntilReplacementCommits() throws {
        let oldProfile = Profile(name: "Old")
        let targetProfile = Profile(name: "Target")
        let profiles = [oldProfile.id: oldProfile, targetProfile.id: targetProfile]
        var shouldDefer = true
        var capturedIntent: DeferredWebViewProfileAssignmentIntent?
        let tabManager = try makeInMemoryTabManager(
            currentProfileId: { oldProfile.id },
            defaultProfileId: { oldProfile.id },
            profile: { profiles[$0] },
            executeProfileAssignment: { tab, _, intent in
                capturedIntent = intent
                if shouldDefer { return .deferred }
                return tab.profileAssignment.commit(intent)
                    ? .committed
                    : .stale
            }
        )
        let oldSpace = tabManager.spaceServices.catalog.createSpace(
            name: "Old",
            profileId: oldProfile.id
        )
        let targetSpace = tabManager.spaceServices.catalog.createSpace(
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
            tabManager.profileAssignments.tabs.executeDeferred(
                tab: tab,
                intent: deferredIntent
            )
        )
        XCTAssertNil(tab.profileId)
        XCTAssertEqual(
            tabManager.profileAssignments.policy.resolvedAssignmentProfile(
                for: tab,
                desiredProfileID: nil
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
        let tabManager = try makeInMemoryTabManager(profile: { profiles[$0] })
        let space = tabManager.spaceServices.catalog.createSpace(name: "Work", profileId: spaceProfileId)
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com", in: space, activate: false)
        let pin = try XCTUnwrap(
            tabManager.shortcutPinCommandOwner.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                at: 0
            )
        )
        let liveTab = tabManager.shortcutTabMaterializer.materialize(pin, in: UUID(), currentSpaceId: space.id)!

        let updatedPin = try XCTUnwrap(
            tabManager.profileAssignments.shortcuts.assign(
                pin,
                toExecutionProfile: pinnedProfileId
            )
        )

        XCTAssertEqual(space.profileId, spaceProfileId)
        XCTAssertNil(updatedPin.profileId)
        XCTAssertEqual(updatedPin.executionProfileId, pinnedProfileId)
        XCTAssertEqual(liveTab.profileId, pinnedProfileId)
    }

    func testAssigningEssentialProfileKeepsEssentialOwnerProfile() throws {
        let ownerProfileId = UUID()
        let executionProfileId = UUID()
        let profiles = [
            ownerProfileId: Profile(id: ownerProfileId, name: "Owner"),
            executionProfileId: Profile(
                id: executionProfileId,
                name: "Execution"
            ),
        ]
        let tabManager = try makeInMemoryTabManager(profile: { profiles[$0] })
        let space = tabManager.spaceServices.catalog.createSpace(name: "Work", profileId: ownerProfileId)
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com", in: space, activate: false)
        let pin = try XCTUnwrap(
            tabManager.shortcutPinCommandOwner.convertTabToShortcutPin(
                tab,
                role: .essential,
                profileId: ownerProfileId,
                spaceId: nil,
                folderId: nil,
                at: 0
            )
        )

        let updatedPin = try XCTUnwrap(
            tabManager.profileAssignments.shortcuts.assign(
                pin,
                toExecutionProfile: executionProfileId
            )
        )

        XCTAssertEqual(updatedPin.profileId, ownerProfileId)
        XCTAssertEqual(updatedPin.executionProfileId, executionProfileId)
        XCTAssertEqual(tabManager.shortcutPinCollectionStateOwner.essentialPins(for: ownerProfileId).first?.id, pin.id)
    }

    func testPinTabConvertsDisplayedTabUsingOwningWindowContext() throws {
        let profileId = UUID()
        let windowState = BrowserWindowState()
        let tabManager = try makeInMemoryTabManager(
            currentProfileId: { profileId },
            windowState: { windowId in
                windowId == windowState.id ? windowState : nil
            },
            windows: { [(windowState.id, windowState)] }
        )
        let space = tabManager.spaceServices.catalog.createSpace(name: "Work", profileId: profileId)
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profileId
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com", in: space, activate: false)
        windowState.currentTabId = tab.id

        tabManager.shortcutPinCommandOwner.pinTab(tab, context: .init(windowState: windowState))

        let pin = try XCTUnwrap(tabManager.shortcutPinCollectionStateOwner.essentialPins(for: profileId).first)
        let liveTab = try XCTUnwrap(tabManager.shortcutPresentationOwner.activeShortcutTab(for: windowState.id))
        XCTAssertEqual(liveTab.id, tab.id)
        XCTAssertEqual(liveTab.shortcutPinId, pin.id)
        XCTAssertEqual(windowState.currentShortcutPinId, pin.id)
        XCTAssertEqual(windowState.currentTabId, tab.id)
        XCTAssertFalse(tabManager.regularTabCollectionOwner.tabs(in: space).contains { $0.id == tab.id })
    }

    func testPinTabPreservesPrimaryOwnerAndMaterializesActionWindow() throws {
        let profileId = UUID()
        let primaryWindow = BrowserWindowState()
        let actionWindow = BrowserWindowState()
        var materializations: [(tabId: UUID, windowId: UUID)] = []
        let windowsById = [
            primaryWindow.id: primaryWindow,
            actionWindow.id: actionWindow,
        ]
        let tabManager = try makeInMemoryTabManager(
            currentProfileId: { profileId },
            windowState: { windowsById[$0] },
            windows: { windowsById.map { ($0.key, $0.value) } },
            primaryTrackedWindowId: { tabId in
                windowsById[primaryWindow.id]?.currentTabId == tabId
                    ? primaryWindow.id
                    : nil
            },
            materializeVisibleTabWebViewIfNeeded: { tab, windowState in
                materializations.append((tab.id, windowState.id))
            }
        )
        let space = tabManager.spaceServices.catalog.createSpace(name: "Work", profileId: profileId)
        primaryWindow.currentSpaceId = space.id
        primaryWindow.currentProfileId = profileId
        actionWindow.currentSpaceId = space.id
        actionWindow.currentProfileId = profileId
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com", in: space, activate: false)
        primaryWindow.currentTabId = tab.id
        actionWindow.currentTabId = tab.id

        tabManager.shortcutPinCommandOwner.pinTab(tab, context: .init(windowState: actionWindow))

        let pin = try XCTUnwrap(tabManager.shortcutPinCollectionStateOwner.essentialPins(for: profileId).first)
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
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Work", profileId: profileId)
        let pin = try XCTUnwrap(tabManager.shortcutPinStoreOwner.insert(ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            launchURL: URL(string: "https://example.com")!,
            title: "Example"
        ), at: 0))
        let liveTab = tabManager.shortcutTabMaterializer.materialize(pin, in: UUID(), currentSpaceId: space.id)!
        tabManager.selectionStateOwner.replaceCurrentTab(liveTab)

        tabManager.profileAssignments.selection.handleProfileSwitch()

        XCTAssertEqual(tabManager.selectionStateOwner.currentTab?.id, liveTab.id)
    }

    func testProfileCleanupDoesNotKeepRemovedEssentialLiveTab() async throws {
        let deletedProfileId = UUID()
        let fallbackProfileId = UUID()
        let profiles = [
            deletedProfileId: Profile(id: deletedProfileId, name: "Deleted"),
            fallbackProfileId: Profile(id: fallbackProfileId, name: "Fallback"),
        ]
        let tabManager = try makeInMemoryTabManager(profile: { profiles[$0] })
        let deletedSpace = tabManager.spaceServices.catalog.createSpace(
            name: "Deleted Work",
            profileId: deletedProfileId
        )
        _ = tabManager.spaceServices.catalog.createSpace(name: "Work", profileId: fallbackProfileId)
        let pin = try XCTUnwrap(tabManager.shortcutPinStoreOwner.insert(ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: deletedProfileId,
            index: 0,
            launchURL: URL(string: "https://example.com")!,
            title: "Example"
        ), at: 0))
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: UUID(),
            currentSpaceId: deletedSpace.id
        )!
        tabManager.selectionStateOwner.replaceCurrentTab(liveTab)

        let outcome = await tabManager.profileAssignments.deletion.migrate(
            deletedProfileID: deletedProfileId,
            fallbackProfileID: fallbackProfileId
            )

        XCTAssertEqual(outcome, .committed)
        XCTAssertNotEqual(tabManager.selectionStateOwner.currentTab?.id, liveTab.id)
        XCTAssertNil(tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id))
    }

    func testLauncherFaviconPartitionFallsBackToContainerProfileWhenExecutionProfileIsImplicit() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Work", profileId: profileId)
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/app", in: space, activate: false)
        tab.profileId = profileId

        let essentialPin = try XCTUnwrap(
            tabManager.shortcutPinCommandOwner.convertTabToShortcutPin(
                tab,
                role: .essential,
                profileId: profileId,
                spaceId: nil,
                folderId: nil,
                at: 0
            )
        )
        XCTAssertNil(essentialPin.executionProfileId)
        XCTAssertEqual(tabManager.shortcutPinRuntimeResolutionOwner.resolvedExecutionProfileId(for: essentialPin), profileId)
        XCTAssertEqual(tabManager.shortcutPinRuntimeResolutionOwner.resolvedFaviconPartition(for: essentialPin), .regular(profileId))

        let spacePinnedTab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/space", in: space, activate: false)
        spacePinnedTab.profileId = profileId
        let spacePin = try XCTUnwrap(
            tabManager.shortcutPinCommandOwner.convertTabToShortcutPin(
                spacePinnedTab,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                at: 0
            )
        )
        XCTAssertNil(spacePin.executionProfileId)
        XCTAssertEqual(tabManager.shortcutPinRuntimeResolutionOwner.resolvedExecutionProfileId(for: spacePin, currentSpaceId: space.id), profileId)
        XCTAssertEqual(tabManager.shortcutPinRuntimeResolutionOwner.resolvedFaviconPartition(for: spacePin, currentSpaceId: space.id), .regular(profileId))
    }
}
