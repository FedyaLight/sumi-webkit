import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class TabManagerClearRegularTabsTests: XCTestCase {
    func testRemoveTabUsesRequiredRuntimeWebViewCleanup() throws {
        var cleanupCalls: [(tabId: UUID, closeActiveFullscreenMedia: Bool)] = []
        let tabManager = try makeInMemoryTabManager(
            requireRemoveAllWebViews: { tab, closeActiveFullscreenMedia in
                cleanupCalls.append((tab.id, closeActiveFullscreenMedia))
            }
        )
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "S", profileId: UUID())
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(in: space, activate: true)

        tabManager.tabRemovalOwner.removeTab(tab.id)

        XCTAssertEqual(cleanupCalls.count, 1)
        XCTAssertEqual(cleanupCalls.first?.tabId, tab.id)
        XCTAssertEqual(cleanupCalls.first?.closeActiveFullscreenMedia, true)
    }

    func testClearRegularTabs_secondClearRemovesLastActiveTab() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "S", profileId: profileId)

        _ = tabManager.regularTabLifecycleOwner.createNewTab(in: space, activate: true)
        _ = tabManager.regularTabLifecycleOwner.createNewTab(in: space, activate: false)

        XCTAssertEqual(tabManager.regularTabCollectionOwner.tabs(in: space).count, 2)

        tabManager.tabRemovalOwner.clearRegularTabs(for: space.id)
        XCTAssertEqual(tabManager.regularTabCollectionOwner.tabs(in: space).count, 1)

        tabManager.tabRemovalOwner.clearRegularTabs(for: space.id)
        XCTAssertEqual(tabManager.regularTabCollectionOwner.tabs(in: space).count, 0)
    }

    func testClearRegularTabs_otherSpaceClearsOnlyTargetSpaceTabs() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let spaceA = tabManager.spaceLifecycleOwner.createSpace(name: "A", profileId: profileId)
        let tabA = tabManager.regularTabLifecycleOwner.createNewTab(in: spaceA, activate: true)
        let spaceB = tabManager.spaceLifecycleOwner.createSpace(name: "B", profileId: profileId)
        _ = tabManager.regularTabLifecycleOwner.createNewTab(in: spaceB, activate: true)

        tabManager.spaceLifecycleOwner.setActiveSpace(spaceA, preferredTab: tabA)
        XCTAssertEqual(tabManager.selectionStateOwner.currentTab?.id, tabA.id)

        tabManager.tabRemovalOwner.clearRegularTabs(for: spaceB.id)

        XCTAssertTrue(tabManager.regularTabCollectionOwner.tabs(in: spaceB).isEmpty)
        XCTAssertEqual(tabManager.selectionStateOwner.currentTab?.id, tabA.id)
        XCTAssertEqual(tabManager.regularTabCollectionOwner.tabs(in: spaceA).count, 1)
    }

    func testProfileCleanupKeepsReassignedSpacesAndMovesStaleTabsToOwningSpaceProfile() throws {
        let tabManager = try makeInMemoryTabManager()
        let deletedProfileId = UUID()
        let fallbackProfileId = UUID()
        let reassignedProfileId = UUID()

        let deletedSpace = tabManager.spaceLifecycleOwner.createSpace(name: "Deleted", profileId: deletedProfileId)
        let reassignedSpace = tabManager.spaceLifecycleOwner.createSpace(name: "Reassigned", profileId: deletedProfileId)
        reassignedSpace.profileId = reassignedProfileId

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

        tabManager.profileAssignmentOwner.cleanupProfileReferences(
            deletedProfileId,
            fallbackProfileId: fallbackProfileId
        )

        XCTAssertEqual(deletedSpace.profileId, fallbackProfileId)
        XCTAssertEqual(reassignedSpace.profileId, reassignedProfileId)
        XCTAssertEqual(staleTab.profileId, reassignedProfileId)
        XCTAssertNil(tabManager.shortcutPinCollectionStateOwner.pinnedByProfileSnapshot()[deletedProfileId])
    }

    func testAssigningRegularTabProfileDoesNotChangeSpaceProfile() throws {
        let tabManager = try makeInMemoryTabManager()
        let spaceProfileId = UUID()
        let tabProfileId = UUID()
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Work", profileId: spaceProfileId)
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(in: space, activate: true)

        XCTAssertTrue(tabManager.profileAssignmentOwner.assign(tab: tab, toProfile: tabProfileId))

        XCTAssertEqual(space.profileId, spaceProfileId)
        XCTAssertEqual(tab.profileId, tabProfileId)
    }

    func testAssigningPinnedTabProfileUpdatesLauncherAndLiveInstanceOnly() throws {
        let tabManager = try makeInMemoryTabManager()
        let spaceProfileId = UUID()
        let pinnedProfileId = UUID()
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Work", profileId: spaceProfileId)
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
        let liveTab = tabManager.shortcutLiveTabOwner.activateShortcutPin(pin, in: UUID(), currentSpaceId: space.id)

        let updatedPin = try XCTUnwrap(
            tabManager.profileAssignmentOwner.assign(shortcutPin: pin, toExecutionProfile: pinnedProfileId)
        )

        XCTAssertEqual(space.profileId, spaceProfileId)
        XCTAssertNil(updatedPin.profileId)
        XCTAssertEqual(updatedPin.executionProfileId, pinnedProfileId)
        XCTAssertEqual(liveTab.profileId, pinnedProfileId)
    }

    func testAssigningEssentialProfileKeepsEssentialOwnerProfile() throws {
        let tabManager = try makeInMemoryTabManager()
        let ownerProfileId = UUID()
        let executionProfileId = UUID()
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Work", profileId: ownerProfileId)
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
            tabManager.profileAssignmentOwner.assign(shortcutPin: pin, toExecutionProfile: executionProfileId)
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
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Work", profileId: profileId)
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
            materializeVisibleTabWebViewIfNeeded: { tab, windowState in
                materializations.append((tab.id, windowState.id))
            }
        )
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Work", profileId: profileId)
        primaryWindow.currentSpaceId = space.id
        primaryWindow.currentProfileId = profileId
        actionWindow.currentSpaceId = space.id
        actionWindow.currentProfileId = profileId
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com", in: space, activate: false)
        tab.assignPrimaryWebView(WKWebView(frame: .zero), windowId: primaryWindow.id)
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

    func testPinTabDoesNotCreateSecondaryLiveInstanceForSplitOnlyWindow() throws {
        let profileId = UUID()
        let actionWindow = BrowserWindowState()
        let splitOnlyWindow = BrowserWindowState()
        let windowsById = [
            actionWindow.id: actionWindow,
            splitOnlyWindow.id: splitOnlyWindow,
        ]
        let tabManager = try makeInMemoryTabManager(
            currentProfileId: { profileId },
            windowState: { windowsById[$0] },
            windows: { windowsById.map { ($0.key, $0.value) } },
            visibleSplitTabIds: { windowId in
                windowId == splitOnlyWindow.id ? [splitOnlyWindow.currentTabId, actionWindow.currentTabId].compactMap(\.self) : []
            }
        )
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Work", profileId: profileId)
        actionWindow.currentSpaceId = space.id
        actionWindow.currentProfileId = profileId
        splitOnlyWindow.currentSpaceId = space.id
        splitOnlyWindow.currentProfileId = profileId
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com", in: space, activate: false)
        let splitActiveTab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://split.example", in: space, activate: false)
        actionWindow.currentTabId = tab.id
        splitOnlyWindow.currentTabId = splitActiveTab.id

        tabManager.shortcutPinCommandOwner.pinTab(tab, context: .init(windowState: actionWindow))

        let pin = try XCTUnwrap(tabManager.shortcutPinCollectionStateOwner.essentialPins(for: profileId).first)
        XCTAssertEqual(tabManager.shortcutPresentationOwner.activeShortcutTab(for: actionWindow.id)?.shortcutPinId, pin.id)
        XCTAssertNil(tabManager.shortcutPresentationOwner.activeShortcutTab(for: splitOnlyWindow.id))
        XCTAssertEqual(splitOnlyWindow.currentTabId, splitActiveTab.id)
    }

    func testContextlessProfileSwitchKeepsCurrentShortcutLiveTab() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Work", profileId: profileId)
        let pin = try XCTUnwrap(tabManager.shortcutPinStoreOwner.insert(ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            launchURL: URL(string: "https://example.com")!,
            title: "Example"
        ), at: 0))
        let liveTab = tabManager.shortcutLiveTabOwner.activateShortcutPin(pin, in: UUID(), currentSpaceId: space.id)
        tabManager.selectionStateOwner.replaceCurrentTab(liveTab)

        tabManager.profileAssignmentOwner.handleProfileSwitch()

        XCTAssertEqual(tabManager.selectionStateOwner.currentTab?.id, liveTab.id)
    }

    func testProfileCleanupDoesNotKeepRemovedEssentialLiveTab() throws {
        let tabManager = try makeInMemoryTabManager()
        let deletedProfileId = UUID()
        let fallbackProfileId = UUID()
        _ = tabManager.spaceLifecycleOwner.createSpace(name: "Work", profileId: fallbackProfileId)
        let pin = try XCTUnwrap(tabManager.shortcutPinStoreOwner.insert(ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: deletedProfileId,
            index: 0,
            launchURL: URL(string: "https://example.com")!,
            title: "Example"
        ), at: 0))
        let liveTab = tabManager.shortcutLiveTabOwner.activateShortcutPin(pin, in: UUID(), currentSpaceId: nil)
        tabManager.selectionStateOwner.replaceCurrentTab(liveTab)

        tabManager.profileAssignmentOwner.cleanupProfileReferences(
            deletedProfileId,
            fallbackProfileId: fallbackProfileId
        )

        XCTAssertNotEqual(tabManager.selectionStateOwner.currentTab?.id, liveTab.id)
        XCTAssertNil(tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id))
    }

    func testLauncherFaviconPartitionFallsBackToContainerProfileWhenExecutionProfileIsImplicit() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Work", profileId: profileId)
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
