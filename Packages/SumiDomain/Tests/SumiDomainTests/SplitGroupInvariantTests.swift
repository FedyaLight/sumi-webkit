import Foundation
import SumiDomain
import XCTest

final class SplitGroupInvariantTests: XCTestCase {
    private struct GroupWire: Encodable {
        let id: UUID
        let layoutKind: SplitLayoutKind
        let layoutTree: SplitLayoutTree
        let container: SplitGroupContainer
    }

    func testGroupRequiresTwoToFourUniqueDurableMembers() throws {
        let members = regularMembers(count: 5)

        XCTAssertNil(
            SplitGroup(
                layoutKind: .vertical,
                layoutTree: .leaf(member: members[0], weight: 1)
            )
        )
        XCTAssertNil(
            SplitGroup.make(
                members: Array(members.prefix(4)) + [members[0]],
                layoutKind: .grid
            )
        )
        XCTAssertNotNil(
            SplitGroup.make(
                members: Array(members.prefix(2)),
                layoutKind: .vertical
            )
        )
        XCTAssertNotNil(
            SplitGroup.make(
                members: Array(members.prefix(4)),
                layoutKind: .grid
            )
        )
    }

    func testShortcutSidebarRejectsRegularMembersAtInitAndDecode() throws {
        let members = regularMembers(count: 2)
        let tree = try XCTUnwrap(
            SplitLayoutFactory.make(kind: .vertical, members: members)
        )
        let container = SplitGroupContainer.shortcutSidebar(
            spaceId: UUID(),
            profileId: nil,
            folderId: nil,
            index: 0
        )

        XCTAssertNil(
            SplitGroup(
                layoutKind: .vertical,
                layoutTree: tree,
                container: container
            )
        )
        let invalidWire = GroupWire(
            id: UUID(),
            layoutKind: .vertical,
            layoutTree: tree,
            container: container
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                SplitGroup.self,
                from: JSONEncoder().encode(invalidWire)
            )
        )
    }

    func testRegularContainerRejectsMixedRegularAndShortcutMembers() throws {
        let regular = SplitMember.regularTab(UUID())
        let shortcut = SplitMember.shortcutPin(UUID())

        XCTAssertNil(
            SplitGroup.make(
                members: [regular, shortcut],
                layoutKind: .horizontal,
                container: .regularTabs(spaceId: UUID())
            )
        )
    }

    func testGroupCanonicalizesInvalidWeightsAtConstruction() throws {
        let members = regularMembers(count: 3)
        let raw = SplitLayoutTree.split(
            axis: .row,
            weight: .infinity,
            children: [
                .leaf(member: members[0], weight: .nan),
                .leaf(member: members[1], weight: -3),
                .leaf(member: members[2], weight: 8),
            ]
        )
        let group = try XCTUnwrap(
            SplitGroup(layoutKind: .vertical, layoutTree: raw)
        )
        guard case .split(_, let rootWeight, let children) = group.layoutTree else {
            return XCTFail("Expected a canonical split root")
        }
        let weights = children.map(\.weightInParent)

        XCTAssertEqual(rootWeight, 1)
        XCTAssertEqual(weights.reduce(0, +), 1, accuracy: 0.000_001)
        XCTAssertTrue(weights.allSatisfy { $0.isFinite && $0 > 0 })
    }

    func testSanitizedKeepsFirstGroupAndRejectsDuplicateGroupOrMember() throws {
        let members = regularMembers(count: 6)
        let first = try XCTUnwrap(
            SplitGroup.make(
                id: UUID(),
                members: [members[0], members[1]],
                layoutKind: .vertical
            )
        )
        let duplicateGroupID = try XCTUnwrap(
            SplitGroup.make(
                id: first.id,
                members: [members[2], members[3]],
                layoutKind: .horizontal
            )
        )
        let overlappingMember = try XCTUnwrap(
            SplitGroup.make(
                members: [members[1], members[4]],
                layoutKind: .vertical
            )
        )
        let independent = try XCTUnwrap(
            SplitGroup.make(
                members: [members[4], members[5]],
                layoutKind: .grid
            )
        )

        XCTAssertEqual(
            SplitGroup.sanitized([
                first,
                duplicateGroupID,
                overlappingMember,
                independent,
            ]),
            [first, independent]
        )
    }

    func testImmutableMutationsRevalidateGroupCardinality() throws {
        let members = regularMembers(count: 3)
        let group = try XCTUnwrap(
            SplitGroup.make(members: members, layoutKind: .vertical)
        )
        let twoMembers = try XCTUnwrap(
            group.removingMember(members[2].memberID)
        )

        XCTAssertEqual(twoMembers.memberIDs, members.prefix(2).map(\.memberID))
        XCTAssertNil(twoMembers.removingMember(members[1].memberID))
    }

    private func regularMembers(count: Int) -> [SplitMember] {
        (0..<count).map { _ in .regularTab(UUID()) }
    }
}
