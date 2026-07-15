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
        let tabManager = try makeInMemoryTabManager()
        let defaultProfileId = UUID()
        let currentProfileId = UUID()
        let defaultProfileSpace = tabManager.spaceServices.catalog.createSpace(
            name: "Default",
            profileId: defaultProfileId
        )
        let currentProfileSpace = tabManager.spaceServices.catalog.createSpace(
            name: "Current",
            profileId: currentProfileId
        )
        tabManager.spaceStateOwner.replaceCurrentSpace(defaultProfileSpace)
        tabManager.runtimePortsAttachmentOwner.attach(
            TestRuntimePorts.make(
                currentProfileId: { currentProfileId },
                defaultProfileId: { defaultProfileId }
            )
        )

        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            in: nil,
            activate: false
        )

        XCTAssertEqual(tab.spaceId, currentProfileSpace.id)
        XCTAssertNil(tab.profileId)
    }

    func testTabCreationBackfillsUnassignedSpace() throws {
        let tabManager = try makeInMemoryTabManager()
        let currentProfileId = UUID()
        let currentProfile = Profile(
            id: currentProfileId,
            name: "Current"
        )
        let unassigned = Space(name: "Unassigned")
        tabManager.spaceStateOwner.replaceSpaces([unassigned])
        tabManager.runtimePortsAttachmentOwner.attach(
            TestRuntimePorts.make(
                currentProfileId: { currentProfileId },
                profile: { profileId in
                    profileId == currentProfileId ? currentProfile : nil
                }
            )
        )

        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            in: nil,
            activate: false
        )

        XCTAssertEqual(tab.spaceId, unassigned.id)
        XCTAssertNil(tab.profileId)
        XCTAssertEqual(unassigned.profileId, currentProfileId)
        XCTAssertEqual(tabManager.spaceStateOwner.spaces.count, 1)
    }

    func testTabCreationCreatesPersonalSpaceWhenNoSpaceExists() throws {
        let tabManager = try makeInMemoryTabManager()
        let currentProfileId = UUID()
        tabManager.spaceStateOwner.removeAll()
        tabManager.runtimePortsAttachmentOwner.attach(
            TestRuntimePorts.make(currentProfileId: { currentProfileId })
        )

        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            in: nil,
            activate: false
        )
        let resolved = try XCTUnwrap(tabManager.spaceStateOwner.firstSpace)

        XCTAssertEqual(resolved.name, "Personal")
        XCTAssertEqual(resolved.profileId, currentProfileId)
        XCTAssertEqual(resolved.icon, SumiPersistentGlyph.spaceDefaultIconValue)
        XCTAssertEqual(SumiPersistentGlyph.resolvedSpaceIconPresentation(resolved.icon), .defaultDot)
        XCTAssertIdentical(tabManager.spaceStateOwner.currentSpace, resolved)
        XCTAssertEqual(tabManager.spaceStateOwner.spaces.map(\.id), [resolved.id])
        XCTAssertEqual(
            tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[resolved.id]?.map(\.id),
            [tab.id]
        )
    }

    func testRenameSpacePresentsNotificationOnlyWhenNameChanges() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Work")
        let spy = NotificationPresentingSpy()
        tabManager.runtimePortsAttachmentOwner.attach(
            TestRuntimePorts.make(
                notifications: { spy }
            )
        )

        try tabManager.spaceServices.catalog.renameSpace(spaceId: space.id, newName: "Work")
        XCTAssertTrue(spy.presentSpaceRenamedNotificationCalls.isEmpty)

        try tabManager.spaceServices.catalog.renameSpace(spaceId: space.id, newName: "Focus")
        XCTAssertEqual(spy.presentSpaceRenamedNotificationCalls.map(\.name), ["Focus"])
        XCTAssertEqual(space.name, "Focus")
    }
}
