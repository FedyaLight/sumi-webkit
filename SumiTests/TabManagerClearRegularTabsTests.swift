import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class TabManagerClearRegularTabsTests: XCTestCase {
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

    private func makeInMemoryTabManager() throws -> TabManager {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return TabManager(context: container.mainContext, loadPersistedState: false)
    }
}
