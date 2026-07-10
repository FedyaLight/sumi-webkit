import Foundation
import XCTest

@testable import Sumi

final class TabRestoreRepairTests: XCTestCase {
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

    // MARK: - repairedFolderHierarchy

    func testValidHierarchyIsUnchanged() {
        let spaceId = UUID()
        let parent = folder(spaceId: spaceId)
        let child = folder(spaceId: spaceId, parentFolderId: parent.id)
        var reasons: Set<String> = []

        let repaired = TabRestoreRepair.repairedFolderHierarchy([parent, child], repairReasons: &reasons)

        XCTAssertEqual(repaired.first(where: { $0.id == child.id })?.parentFolderId, parent.id)
        XCTAssertTrue(reasons.isEmpty)
    }

    func testMissingParentIsDetached() {
        let spaceId = UUID()
        let orphan = folder(spaceId: spaceId, parentFolderId: UUID())
        var reasons: Set<String> = []

        let repaired = TabRestoreRepair.repairedFolderHierarchy([orphan], repairReasons: &reasons)

        XCTAssertNil(repaired.first?.parentFolderId)
        XCTAssertTrue(reasons.contains("moved folder out of invalid parent"))
    }

    func testCrossSpaceParentIsDetached() {
        let spaceId = UUID()
        let parent = folder(spaceId: UUID()) // different space
        let child = folder(spaceId: spaceId, parentFolderId: parent.id)
        var reasons: Set<String> = []

        let repaired = TabRestoreRepair.repairedFolderHierarchy([parent, child], repairReasons: &reasons)

        XCTAssertNil(repaired.first(where: { $0.id == child.id })?.parentFolderId)
        XCTAssertTrue(reasons.contains("moved folder out of invalid parent"))
    }

    func testCyclicHierarchyIsBrokenAndPreservesFolders() {
        let spaceId = UUID()
        let a = UUID()
        let b = UUID()
        let fa = folder(id: a, spaceId: spaceId, parentFolderId: b)
        let fb = folder(id: b, spaceId: spaceId, parentFolderId: a)
        var reasons: Set<String> = []

        let repaired = TabRestoreRepair.repairedFolderHierarchy([fa, fb], repairReasons: &reasons)

        // Both folders survive, cycle is broken (at least one detached).
        XCTAssertEqual(repaired.count, 2)
        XCTAssertTrue(repaired.contains { $0.parentFolderId == nil })
        XCTAssertTrue(reasons.contains("moved folder out of invalid parent"))
    }

    // MARK: - restoreSplitGroups

    func testRestoreSplitGroupsReturnsEmptyForNilData() {
        var reasons: Set<String> = []
        XCTAssertTrue(TabRestoreRepair.restoreSplitGroups(from: nil, validTabIds: [], repairReasons: &reasons).isEmpty)
        XCTAssertTrue(reasons.isEmpty)
    }

    func testRestoreSplitGroupsReturnsEmptyForEmptyData() {
        var reasons: Set<String> = []
        XCTAssertTrue(TabRestoreRepair.restoreSplitGroups(from: Data(), validTabIds: [], repairReasons: &reasons).isEmpty)
        XCTAssertTrue(reasons.isEmpty)
    }

    func testRestoreSplitGroupsRecordsReasonForUnreadableData() {
        var reasons: Set<String> = []
        let garbage = Data("not json".utf8)

        let result = TabRestoreRepair.restoreSplitGroups(from: garbage, validTabIds: [], repairReasons: &reasons)

        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(reasons.contains("removed unreadable split groups"))
    }
}
