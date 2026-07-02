import Foundation
@testable import Sumi
import XCTest

@MainActor
final class SplitGroupCollectionStateOwnerTests: XCTestCase {
    func testReplaceSplitGroupsRebuildsIndexedLookup() {
        let firstTabId = UUID()
        let secondTabId = UUID()
        let group = Self.makeGroup(tabIds: [firstTabId, secondTabId])
        let owner = SplitGroupCollectionStateOwner()

        owner.replaceSplitGroups([group])

        XCTAssertEqual(owner.splitGroups, [group])
        XCTAssertEqual(owner.group(with: group.id), group)
        XCTAssertEqual(owner.group(containingMemberId: firstTabId), group)
        XCTAssertEqual(owner.groupId(containingMemberId: secondTabId), group.id)
        XCTAssertEqual(owner.index(of: group.id), 0)
        XCTAssertEqual(owner.groupMap[group.id], group)
        XCTAssertEqual(Array(owner.indexedGroups), [group])
    }

    func testRemoveAllClearsSplitGroupsAndIndex() {
        let group = Self.makeGroup(tabIds: [UUID(), UUID()])
        let owner = SplitGroupCollectionStateOwner()
        owner.replaceSplitGroups([group])

        owner.removeAll()

        XCTAssertEqual(owner.splitGroups, [])
        XCTAssertNil(owner.group(with: group.id))
        XCTAssertNil(owner.group(containingMemberId: group.tabIds[0]))
        XCTAssertNil(owner.groupId(containingMemberId: group.tabIds[1]))
        XCTAssertNil(owner.index(of: group.id))
        XCTAssertTrue(owner.groupMap.isEmpty)
        XCTAssertTrue(owner.indexedGroups.isEmpty)
    }

    private static func makeGroup(tabIds: [UUID]) -> SplitGroup {
        SplitGroup(
            layoutKind: .horizontal,
            layoutTree: .split(
                axis: .row,
                size: 1,
                children: tabIds.map { .leaf(tabId: $0, size: 1) }
            ),
            activeTabId: tabIds.first
        )
    }
}
