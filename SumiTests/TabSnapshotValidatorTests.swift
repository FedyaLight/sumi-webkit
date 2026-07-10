import XCTest

@testable import Sumi

final class TabSnapshotValidatorTests: XCTestCase {
    // MARK: - Fixtures

    private func tab(
        id: UUID = UUID(),
        index: Int = 0,
        spaceId: UUID? = nil,
        isPinned: Bool = false,
        isSpacePinned: Bool = false,
        folderId: UUID? = nil
    ) -> TabPersistenceTab {
        TabPersistenceTab(
            id: id,
            urlString: "https://example.com",
            name: "Tab",
            index: index,
            spaceId: spaceId,
            isPinned: isPinned,
            isSpacePinned: isSpacePinned,
            profileId: nil,
            executionProfileId: nil,
            folderId: folderId,
            iconAsset: nil,
            currentURLString: nil,
            canGoBack: false,
            canGoForward: false
        )
    }

    private func space(id: UUID) -> TabPersistenceSpace {
        TabPersistenceSpace(
            id: id,
            name: "Space",
            icon: "circle",
            index: 0,
            workspaceThemeData: nil,
            profileId: UUID()
        )
    }

    private func folder(
        id: UUID = UUID(),
        spaceId: UUID,
        parentFolderId: UUID? = nil
    ) -> TabPersistenceFolder {
        TabPersistenceFolder(
            id: id,
            name: "Folder",
            icon: "folder",
            color: "blue",
            spaceId: spaceId,
            parentFolderId: parentFolderId,
            isOpen: false,
            index: 0
        )
    }

    private func snapshot(
        spaces: [TabPersistenceSpace],
        tabs: [TabPersistenceTab],
        folders: [TabPersistenceFolder] = []
    ) -> TabPersistenceSnapshot {
        TabPersistenceSnapshot(
            spaces: spaces,
            tabs: tabs,
            folders: folders,
            state: TabPersistenceSelection(currentTabID: nil, currentSpaceID: nil)
        )
    }

    private func assertInvalidModelState(
        _ body: () throws -> Void,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try body(), message, file: file, line: line) { error in
            XCTAssertEqual(
                error as? TabPersistenceError,
                .invalidModelState,
                message,
                file: file,
                line: line
            )
        }
    }

    // MARK: - validateInput

    func testValidSnapshotPasses() throws {
        let spaceId = UUID()
        let s = snapshot(spaces: [space(id: spaceId)], tabs: [tab(spaceId: spaceId)])
        XCTAssertNoThrow(try TabSnapshotValidator.validateInput(s))
    }

    func testTabPinnedAndSpacePinnedIsRejected() {
        let spaceId = UUID()
        let s = snapshot(
            spaces: [space(id: spaceId)],
            tabs: [tab(spaceId: spaceId, isPinned: true, isSpacePinned: true)]
        )
        assertInvalidModelState({ try TabSnapshotValidator.validateInput(s) }, "pinned+spacePinned must be rejected")
    }

    func testDuplicateTabIdsAreRejected() {
        let spaceId = UUID()
        let dup = UUID()
        let s = snapshot(
            spaces: [space(id: spaceId)],
            tabs: [tab(id: dup, spaceId: spaceId), tab(id: dup, index: 1, spaceId: spaceId)]
        )
        assertInvalidModelState({ try TabSnapshotValidator.validateInput(s) }, "duplicate tab ids must be rejected")
    }

    func testTabReferencingUnknownSpaceIsRejected() {
        let s = snapshot(spaces: [space(id: UUID())], tabs: [tab(spaceId: UUID())])
        assertInvalidModelState({ try TabSnapshotValidator.validateInput(s) }, "orphan tab space must be rejected")
    }

    func testNegativeTabIndexIsRejected() {
        let spaceId = UUID()
        let s = snapshot(spaces: [space(id: spaceId)], tabs: [tab(index: -1, spaceId: spaceId)])
        assertInvalidModelState({ try TabSnapshotValidator.validateInput(s) }, "negative index must be rejected")
    }

    func testCyclicFolderHierarchyIsRejected() {
        let spaceId = UUID()
        let a = UUID()
        let b = UUID()
        let s = snapshot(
            spaces: [space(id: spaceId)],
            tabs: [],
            folders: [
                folder(id: a, spaceId: spaceId, parentFolderId: b),
                folder(id: b, spaceId: spaceId, parentFolderId: a)
            ]
        )
        assertInvalidModelState({ try TabSnapshotValidator.validateInput(s) }, "cyclic folder hierarchy must be rejected")
    }

    func testFolderWithMissingParentIsRejectedForFullSnapshot() {
        let spaceId = UUID()
        let s = snapshot(
            spaces: [space(id: spaceId)],
            tabs: [],
            folders: [folder(spaceId: spaceId, parentFolderId: UUID())]
        )
        assertInvalidModelState({ try TabSnapshotValidator.validateInput(s) }, "missing parent must be rejected in full snapshot")
    }

    // MARK: - validateDelta

    func testValidDeltaPasses() throws {
        let spaceId = UUID()
        let delta = TabStructuralPersistenceDelta(
            spaces: [space(id: spaceId)],
            tabs: [tab(spaceId: spaceId)],
            folders: [],
            splitGroups: nil,
            deletedSpaceIds: [],
            deletedTabIds: [],
            deletedFolderIds: [],
            state: TabPersistenceSelection(currentTabID: nil, currentSpaceID: nil)
        )
        XCTAssertNoThrow(try TabSnapshotValidator.validateDelta(delta))
    }

    func testDeltaTabInDeletedSpaceIsRejected() {
        let spaceId = UUID()
        let delta = TabStructuralPersistenceDelta(
            spaces: [],
            tabs: [tab(spaceId: spaceId)],
            folders: [],
            splitGroups: nil,
            deletedSpaceIds: [spaceId],
            deletedTabIds: [],
            deletedFolderIds: [],
            state: TabPersistenceSelection(currentTabID: nil, currentSpaceID: nil)
        )
        assertInvalidModelState({ try TabSnapshotValidator.validateDelta(delta) }, "tab in deleted space must be rejected")
    }

    // Missing parent is allowed for an incremental delta (requiresCompleteParentSet: false).
    func testDeltaFolderWithMissingParentIsAllowed() throws {
        let spaceId = UUID()
        let delta = TabStructuralPersistenceDelta(
            spaces: [space(id: spaceId)],
            tabs: [],
            folders: [folder(spaceId: spaceId, parentFolderId: UUID())],
            splitGroups: nil,
            deletedSpaceIds: [],
            deletedTabIds: [],
            deletedFolderIds: [],
            state: TabPersistenceSelection(currentTabID: nil, currentSpaceID: nil)
        )
        XCTAssertNoThrow(try TabSnapshotValidator.validateDelta(delta))
    }
}
