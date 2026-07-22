import Foundation
@testable import Sumi
import XCTest

@MainActor
final class TabSpaceCollectionStateOwnerTests: XCTestCase {
    func testReplacesSpacesAndQueriesSelection() {
        let profileId = UUID()
        let first = Space(name: "First", profileId: profileId)
        let second = Space(name: "Second")
        let owner = TabSpaceCollectionStateOwner()

        owner.replaceSpaces([first, second])
        owner.replaceCurrentSpace(second)

        XCTAssertEqual(owner.count, 2)
        XCTAssertIdentical(owner.firstSpace, first)
        XCTAssertIdentical(owner.currentSpace, second)
        XCTAssertEqual(owner.currentSpaceId, second.id)
        XCTAssertEqual(first.icon, SumiPersistentGlyph.spaceDefaultIconValue)
        XCTAssertEqual(SumiPersistentGlyph.resolvedSpaceIconPresentation(first.icon), .defaultDot)
        XCTAssertTrue(owner.contains(spaceId: first.id))
        XCTAssertIdentical(owner.space(with: second.id), second)
        XCTAssertIdentical(owner.first(where: { $0.profileId == profileId }), first)
        XCTAssertEqual(owner.profileId(for: first.id), profileId)
        XCTAssertNil(owner.space(with: UUID()))
    }

    func testReorderPreservesCurrentSpaceByIdentity() {
        let first = Space(name: "First")
        let second = Space(name: "Second")
        let third = Space(name: "Third")
        let owner = TabSpaceCollectionStateOwner()
        owner.replaceSpaces([first, second, third])
        owner.replaceCurrentSpace(second)

        XCTAssertTrue(owner.reorderSpace(spaceId: first.id, to: 2))

        XCTAssertEqual(owner.spaces.map(\.id), [second.id, third.id, first.id])
        XCTAssertIdentical(owner.currentSpace, second)
        XCTAssertFalse(owner.reorderSpace(spaceId: first.id, to: 2))
        XCTAssertFalse(owner.reorderSpace(spaceId: UUID(), to: 0))
    }

    func testSpaceMutationsUpdateDetachedCurrentSpaceReference() {
        let sharedId = UUID()
        let stored = Space(id: sharedId, name: "Stored")
        let selected = Space(id: sharedId, name: "Selected")
        let normalizedIcon = SumiPersistentGlyph.normalizedSpaceIconValue("house")
        let owner = TabSpaceCollectionStateOwner()
        owner.replaceSpaces([stored])
        owner.replaceCurrentSpace(selected)

        owner.renameSpace(spaceId: sharedId, to: "Renamed")
        owner.updateIcon(spaceId: sharedId, to: "house")

        XCTAssertEqual(stored.name, "Renamed")
        XCTAssertEqual(selected.name, "Renamed")
        XCTAssertEqual(stored.icon, normalizedIcon)
        XCTAssertEqual(selected.icon, normalizedIcon)
    }

    func testRemoveAllClearsSpacesAndSelection() {
        let owner = TabSpaceCollectionStateOwner()
        let space = Space(name: "Workspace")
        owner.replaceSpaces([space])
        owner.replaceCurrentSpace(space)

        owner.removeAll()

        XCTAssertTrue(owner.spaces.isEmpty)
        XCTAssertNil(owner.currentSpace)
    }
}

@MainActor
final class TabSpaceServiceIntegrationTests: XCTestCase {
    func testTabCreationUsesCurrentProfileSpaceBeforeSelectedSpace() throws {
        let defaultProfileId = UUID()
        let currentProfileId = UUID()
        let runtime = TestRuntimePorts.make(
            currentProfileId: { currentProfileId },
            defaultProfileId: { defaultProfileId }
        )
        let tabManager = BrowserManager(runtimePorts: runtime)
        let defaultProfileSpace = try createSpace(
            in: tabManager,
            name: "Default",
            profileID: defaultProfileId
        )
        let currentProfileSpace = try createSpace(
            in: tabManager,
            name: "Current",
            profileID: currentProfileId
        )
        tabManager.spaceStateOwner.replaceCurrentSpace(defaultProfileSpace)

        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            in: nil,
            activate: false
        )

        XCTAssertEqual(tab.spaceId, currentProfileSpace.id)
        XCTAssertNil(tab.profileId)
    }

    func testTabCreationBackfillsUnassignedSpace() throws {
        let currentProfileId = UUID()
        let currentProfile = Profile(
            id: currentProfileId,
            name: "Current"
        )
        let runtime = TestRuntimePorts.make(
            currentProfileId: { currentProfileId },
            profile: { profileId in
                profileId == currentProfileId ? currentProfile : nil
            }
        )
        let tabManager = BrowserManager(runtimePorts: runtime)
        let unassigned = Space(name: "Unassigned")
        tabManager.spaceStateOwner.replaceSpaces([unassigned])

        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            in: nil,
            activate: false
        )

        XCTAssertEqual(tab.spaceId, unassigned.id)
        XCTAssertNil(tab.profileId)
        XCTAssertEqual(unassigned.profileId, currentProfileId)
        XCTAssertEqual(tabManager.spaceStateOwner.spaces.count, 1)
    }

    func testTabCreationCreatesDefaultSpaceWhenNoSpaceExists() throws {
        let currentProfileId = UUID()
        let runtime = TestRuntimePorts.make(
            currentProfileId: { currentProfileId }
        )
        let tabManager = BrowserManager(runtimePorts: runtime)
        tabManager.spaceStateOwner.removeAll()

        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            in: nil,
            activate: false
        )
        let resolved = try XCTUnwrap(tabManager.spaceStateOwner.firstSpace)

        XCTAssertEqual(resolved.name, "Space")
        XCTAssertEqual(resolved.profileId, currentProfileId)
        XCTAssertEqual(resolved.icon, SumiPersistentGlyph.spaceDefaultIconValue)
        XCTAssertEqual(SumiPersistentGlyph.resolvedSpaceIconPresentation(resolved.icon), .defaultDot)
        XCTAssertIdentical(tabManager.spaceStateOwner.currentSpace, resolved)
        XCTAssertEqual(tabManager.spaceStateOwner.spaces.map(\.id), [resolved.id])
        XCTAssertEqual(
            tabManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[resolved.id]?.map(\.id),
            [tab.id]
        )
    }

    func testRenameSpacePresentsNotificationOnlyWhenNameChanges() throws {
        let spy = NotificationPresentingSpy()
        let runtime = TestRuntimePorts.make(
            notifications: { spy }
        )
        let tabManager = BrowserManager(runtimePorts: runtime)
        let space = try createSpace(in: tabManager, name: "Work")

        try tabManager.sidebarSpaceLifecycle.renameSpace(space.id, to: "Work")
        XCTAssertTrue(spy.presentSpaceRenamedNotificationCalls.isEmpty)

        try tabManager.sidebarSpaceLifecycle.renameSpace(space.id, to: "Focus")
        XCTAssertEqual(spy.presentSpaceRenamedNotificationCalls.map(\.name), ["Focus"])
        XCTAssertEqual(space.name, "Focus")
    }

    private func createSpace(
        in browser: BrowserManager,
        name: String,
        profileID: UUID? = nil
    ) throws -> Space {
        try XCTUnwrap(browser.sidebarSpaceLifecycle.createSpace(
            name: name,
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileID: profileID
        ))
    }
}
