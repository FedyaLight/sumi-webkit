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
