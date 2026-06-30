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
        let space = tabManager.createSpace(name: "S", profileId: UUID())
        let tab = tabManager.createNewTab(in: space, activate: true)

        tabManager.removeTab(tab.id)

        XCTAssertEqual(cleanupCalls.count, 1)
        XCTAssertEqual(cleanupCalls.first?.tabId, tab.id)
        XCTAssertEqual(cleanupCalls.first?.closeActiveFullscreenMedia, true)
    }

    func testClearRegularTabs_secondClearRemovesLastActiveTab() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.createSpace(name: "S", profileId: profileId)

        _ = tabManager.createNewTab(in: space, activate: true)
        _ = tabManager.createNewTab(in: space, activate: false)

        XCTAssertEqual(tabManager.tabs(in: space).count, 2)

        tabManager.clearRegularTabs(for: space.id)
        XCTAssertEqual(tabManager.tabs(in: space).count, 1)

        tabManager.clearRegularTabs(for: space.id)
        XCTAssertEqual(tabManager.tabs(in: space).count, 0)
    }

    func testClearRegularTabs_otherSpaceClearsOnlyTargetSpaceTabs() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let spaceA = tabManager.createSpace(name: "A", profileId: profileId)
        let tabA = tabManager.createNewTab(in: spaceA, activate: true)
        let spaceB = tabManager.createSpace(name: "B", profileId: profileId)
        _ = tabManager.createNewTab(in: spaceB, activate: true)

        tabManager.setActiveSpace(spaceA, preferredTab: tabA)
        XCTAssertEqual(tabManager.currentTab?.id, tabA.id)

        tabManager.clearRegularTabs(for: spaceB.id)

        XCTAssertTrue(tabManager.tabs(in: spaceB).isEmpty)
        XCTAssertEqual(tabManager.currentTab?.id, tabA.id)
        XCTAssertEqual(tabManager.tabs(in: spaceA).count, 1)
    }

    func testProfileCleanupKeepsReassignedSpacesAndMovesStaleTabsToOwningSpaceProfile() throws {
        let tabManager = try makeInMemoryTabManager()
        let deletedProfileId = UUID()
        let fallbackProfileId = UUID()
        let reassignedProfileId = UUID()

        let deletedSpace = tabManager.createSpace(name: "Deleted", profileId: deletedProfileId)
        let reassignedSpace = tabManager.createSpace(name: "Reassigned", profileId: deletedProfileId)
        reassignedSpace.profileId = reassignedProfileId

        let staleTab = tabManager.createNewTab(in: reassignedSpace, activate: true)
        staleTab.profileId = deletedProfileId
        let deletedPin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: deletedProfileId,
            index: 0,
            launchURL: URL(string: "https://old.example")!,
            title: "Old"
        )
        tabManager.pinnedByProfile[deletedProfileId] = [deletedPin]

        tabManager.cleanupProfileReferences(
            deletedProfileId,
            fallbackProfileId: fallbackProfileId
        )

        XCTAssertEqual(deletedSpace.profileId, fallbackProfileId)
        XCTAssertEqual(reassignedSpace.profileId, reassignedProfileId)
        XCTAssertEqual(staleTab.profileId, reassignedProfileId)
        XCTAssertNil(tabManager.pinnedByProfile[deletedProfileId])
    }

    func testAssigningRegularTabProfileDoesNotChangeSpaceProfile() throws {
        let tabManager = try makeInMemoryTabManager()
        let spaceProfileId = UUID()
        let tabProfileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: spaceProfileId)
        let tab = tabManager.createNewTab(in: space, activate: true)

        XCTAssertTrue(tabManager.assign(tab: tab, toProfile: tabProfileId))

        XCTAssertEqual(space.profileId, spaceProfileId)
        XCTAssertEqual(tab.profileId, tabProfileId)
    }

    func testAssigningPinnedTabProfileUpdatesLauncherAndLiveInstanceOnly() throws {
        let tabManager = try makeInMemoryTabManager()
        let spaceProfileId = UUID()
        let pinnedProfileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: spaceProfileId)
        let tab = tabManager.createNewTab(url: "https://example.com", in: space, activate: false)
        let pin = try XCTUnwrap(
            tabManager.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                at: 0
            )
        )
        let liveTab = tabManager.activateShortcutPin(pin, in: UUID(), currentSpaceId: space.id)

        let updatedPin = try XCTUnwrap(
            tabManager.assign(shortcutPin: pin, toExecutionProfile: pinnedProfileId)
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
        let space = tabManager.createSpace(name: "Work", profileId: ownerProfileId)
        let tab = tabManager.createNewTab(url: "https://example.com", in: space, activate: false)
        let pin = try XCTUnwrap(
            tabManager.convertTabToShortcutPin(
                tab,
                role: .essential,
                profileId: ownerProfileId,
                spaceId: nil,
                folderId: nil,
                at: 0
            )
        )

        let updatedPin = try XCTUnwrap(
            tabManager.assign(shortcutPin: pin, toExecutionProfile: executionProfileId)
        )

        XCTAssertEqual(updatedPin.profileId, ownerProfileId)
        XCTAssertEqual(updatedPin.executionProfileId, executionProfileId)
        XCTAssertEqual(tabManager.essentialPins(for: ownerProfileId).first?.id, pin.id)
    }

    func testLauncherFaviconPartitionFallsBackToContainerProfileWhenExecutionProfileIsImplicit() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Work", profileId: profileId)
        let tab = tabManager.createNewTab(url: "https://example.com/app", in: space, activate: false)
        tab.profileId = profileId

        let essentialPin = try XCTUnwrap(
            tabManager.convertTabToShortcutPin(
                tab,
                role: .essential,
                profileId: profileId,
                spaceId: nil,
                folderId: nil,
                at: 0
            )
        )
        XCTAssertNil(essentialPin.executionProfileId)
        XCTAssertEqual(tabManager.resolvedExecutionProfileId(for: essentialPin), profileId)
        XCTAssertEqual(tabManager.resolvedFaviconPartition(for: essentialPin), .regular(profileId))

        let spacePinnedTab = tabManager.createNewTab(url: "https://example.com/space", in: space, activate: false)
        spacePinnedTab.profileId = profileId
        let spacePin = try XCTUnwrap(
            tabManager.convertTabToShortcutPin(
                spacePinnedTab,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                at: 0
            )
        )
        XCTAssertNil(spacePin.executionProfileId)
        XCTAssertEqual(tabManager.resolvedExecutionProfileId(for: spacePin, currentSpaceId: space.id), profileId)
        XCTAssertEqual(tabManager.resolvedFaviconPartition(for: spacePin, currentSpaceId: space.id), .regular(profileId))
    }

    private func makeInMemoryTabManager(
        requireRemoveAllWebViews: @escaping (Tab, Bool) -> Void = { _, _ in }
    ) throws -> TabManager {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        tabManager.attachRuntimeContext(
            TabManagerRuntimeContext(
                requireRemoveAllWebViews: requireRemoveAllWebViews
            )
        )
        return tabManager
    }
}
