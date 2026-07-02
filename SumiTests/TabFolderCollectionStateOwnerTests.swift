import Foundation
@testable import Sumi
import XCTest

@MainActor
final class TabFolderCollectionStateOwnerTests: XCTestCase {
    func testQueriesSortAndFindFoldersAcrossSpaces() {
        let firstSpaceId = UUID()
        let secondSpaceId = UUID()
        let parent = Self.makeFolder(name: "Parent", spaceId: firstSpaceId, index: 2)
        let earlier = Self.makeFolder(name: "Earlier", spaceId: firstSpaceId, index: 1)
        let child = Self.makeFolder(
            name: "Child",
            spaceId: firstSpaceId,
            parentFolderId: parent.id,
            index: 0
        )
        let secondSpaceFolder = Self.makeFolder(name: "Second", spaceId: secondSpaceId, index: 0)
        let owner = TabFolderCollectionStateOwner()

        owner.replaceFoldersBySpace([
            firstSpaceId: [parent, child, earlier],
            secondSpaceId: [secondSpaceFolder],
        ])

        XCTAssertEqual(owner.folders(for: firstSpaceId).map(\.id), [child.id, earlier.id, parent.id])
        XCTAssertEqual(owner.childFolders(of: nil, in: firstSpaceId).map(\.id), [earlier.id, parent.id])
        XCTAssertEqual(owner.childFolders(of: parent.id, in: firstSpaceId).map(\.id), [child.id])
        XCTAssertEqual(owner.folder(by: child.id)?.id, child.id)
        XCTAssertEqual(owner.spaceId(for: secondSpaceFolder.id), secondSpaceId)
        XCTAssertNil(owner.folder(by: UUID()))
        XCTAssertNil(owner.spaceId(for: UUID()))
        XCTAssertTrue(owner.hasFolders(in: firstSpaceId))
        XCTAssertFalse(owner.hasFolders(in: UUID()))
    }

    func testRemoveFoldersAndRemoveAllClearOwnedCollections() {
        let firstSpaceId = UUID()
        let secondSpaceId = UUID()
        let owner = TabFolderCollectionStateOwner()
        owner.replaceFoldersBySpace([
            firstSpaceId: [Self.makeFolder(name: "First", spaceId: firstSpaceId, index: 0)],
            secondSpaceId: [Self.makeFolder(name: "Second", spaceId: secondSpaceId, index: 0)],
        ])

        owner.removeFolders(for: firstSpaceId)

        XCTAssertFalse(owner.hasFolders(in: firstSpaceId))
        XCTAssertTrue(owner.hasFolders(in: secondSpaceId))

        owner.removeAll()

        XCTAssertTrue(owner.foldersBySpace.isEmpty)
    }

    private static func makeFolder(
        name: String,
        spaceId: UUID,
        parentFolderId: UUID? = nil,
        index: Int
    ) -> TabFolder {
        TabFolder(
            name: name,
            spaceId: spaceId,
            parentFolderId: parentFolderId,
            index: index
        )
    }
}
