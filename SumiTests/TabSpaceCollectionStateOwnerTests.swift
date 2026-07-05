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
        let profileId = UUID()
        let normalizedIcon = SumiPersistentGlyph.normalizedSpaceIconValue("house")
        let owner = TabSpaceCollectionStateOwner()
        owner.replaceSpaces([stored])
        owner.replaceCurrentSpace(selected)

        owner.renameSpace(spaceId: sharedId, to: "Renamed")
        owner.updateIcon(spaceId: sharedId, to: "house")
        owner.assignProfile(spaceId: sharedId, profileId: profileId)

        XCTAssertEqual(stored.name, "Renamed")
        XCTAssertEqual(selected.name, "Renamed")
        XCTAssertEqual(stored.icon, normalizedIcon)
        XCTAssertEqual(selected.icon, normalizedIcon)
        XCTAssertEqual(stored.profileId, profileId)
        XCTAssertEqual(selected.profileId, profileId)
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
final class TabSpaceLifecycleOwnerTests: XCTestCase {
    func testResolvedTargetSpaceUsesCurrentProfileSpaceBeforeSelectedSpace() throws {
        let tabManager = try makeInMemoryTabManager()
        let defaultProfileId = UUID()
        let currentProfileId = UUID()
        let defaultProfileSpace = tabManager.spaceLifecycleOwner.createSpace(
            name: "Default",
            profileId: defaultProfileId
        )
        let currentProfileSpace = tabManager.spaceLifecycleOwner.createSpace(
            name: "Current",
            profileId: currentProfileId
        )
        tabManager.spaceStateOwner.replaceCurrentSpace(defaultProfileSpace)
        tabManager.runtimeContextAttachmentOwner.attach(
            TabManagerRuntimeContext(
                currentProfileId: { currentProfileId },
                defaultProfileId: { defaultProfileId }
            )
        )

        let resolved = tabManager.spaceLifecycleOwner.resolvedTargetSpace(preferred: nil)

        XCTAssertIdentical(resolved, currentProfileSpace)
    }

    func testResolvedTargetSpaceBackfillsUnassignedSpaceForCurrentProfile() throws {
        let tabManager = try makeInMemoryTabManager()
        let currentProfileId = UUID()
        let unassigned = Space(name: "Unassigned")
        tabManager.spaceStateOwner.replaceSpaces([unassigned])
        tabManager.runtimeContextAttachmentOwner.attach(
            TabManagerRuntimeContext(currentProfileId: { currentProfileId })
        )

        let resolved = tabManager.spaceLifecycleOwner.resolvedTargetSpace(preferred: nil)

        XCTAssertIdentical(resolved, unassigned)
        XCTAssertEqual(unassigned.profileId, currentProfileId)
        XCTAssertEqual(tabManager.spaceStateOwner.spaces.count, 1)
    }

    func testResolvedTargetSpaceCreatesPersonalSpaceWhenNoSpaceExists() throws {
        let tabManager = try makeInMemoryTabManager()
        let currentProfileId = UUID()
        tabManager.spaceStateOwner.removeAll()
        tabManager.runtimeContextAttachmentOwner.attach(
            TabManagerRuntimeContext(currentProfileId: { currentProfileId })
        )

        let resolved = tabManager.spaceLifecycleOwner.resolvedTargetSpace(preferred: nil)

        XCTAssertEqual(resolved.name, "Personal")
        XCTAssertEqual(resolved.profileId, currentProfileId)
        XCTAssertEqual(resolved.icon, SumiPersistentGlyph.spaceDefaultIconValue)
        XCTAssertEqual(SumiPersistentGlyph.resolvedSpaceIconPresentation(resolved.icon), .defaultDot)
        XCTAssertIdentical(tabManager.spaceStateOwner.currentSpace, resolved)
        XCTAssertEqual(tabManager.spaceStateOwner.spaces.map(\.id), [resolved.id])
        XCTAssertEqual(
            tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[resolved.id] ?? [],
            []
        )
    }
}
