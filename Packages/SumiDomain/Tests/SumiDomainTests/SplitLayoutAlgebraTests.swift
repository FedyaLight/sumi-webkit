import Foundation
import SumiDomain
import XCTest

final class SplitLayoutAlgebraTests: XCTestCase {
    func testFactoryBuildsExpectedAxesAndNormalizedWeights() throws {
        let members = regularMembers(count: 4)
        let vertical = try XCTUnwrap(
            SplitLayoutFactory.make(kind: .vertical, members: members)
        )
        let horizontal = try XCTUnwrap(
            SplitLayoutFactory.make(kind: .horizontal, members: members)
        )
        let grid = try XCTUnwrap(
            SplitLayoutFactory.make(kind: .grid, members: members)
        )

        assertRoot(vertical, axis: .row, childCount: 4)
        assertRoot(horizontal, axis: .column, childCount: 4)
        assertRoot(grid, axis: .row, childCount: 2)
        XCTAssertEqual(vertical.memberIDs, members.map(\.memberID))
        XCTAssertEqual(grid.memberIDs, members.map(\.memberID))
    }

    func testReplacementChangesDurableKindWithoutChangingLeafPosition() throws {
        let members = regularMembers(count: 3)
        let tree = try XCTUnwrap(
            SplitLayoutFactory.make(kind: .vertical, members: members)
        )
        let pinID = UUID()
        let replacement = SplitMember.shortcutPin(pinID)
        let replaced = try XCTUnwrap(
            tree.replacingMember(members[1].memberID, with: replacement)
        )

        XCTAssertEqual(
            replaced.memberIDs,
            [members[0].memberID, .shortcutPin(pinID), members[2].memberID]
        )
        XCTAssertEqual(
            replaced.member(for: .shortcutPin(pinID)),
            replacement
        )
        XCTAssertFalse(replaced.contains(members[1].memberID))
    }

    func testInsertMoveSwapAndRemovePreserveWholeMembers() throws {
        let members = regularMembers(count: 4)
        let initial = try XCTUnwrap(
            SplitLayoutFactory.make(
                kind: .vertical,
                members: Array(members.prefix(2))
            )
        )
        let inserted = try XCTUnwrap(
            initial.inserting(
                members[2],
                relativeTo: members[1].memberID,
                side: .left
            )
        )
        XCTAssertEqual(
            inserted.memberIDs,
            [members[0].memberID, members[2].memberID, members[1].memberID]
        )

        let moved = try XCTUnwrap(
            inserted.movingMember(
                members[0].memberID,
                relativeTo: members[1].memberID,
                side: .right
            )
        )
        XCTAssertEqual(
            moved.memberIDs,
            [members[2].memberID, members[1].memberID, members[0].memberID]
        )

        let swapped = try XCTUnwrap(
            moved.swappingMembers(
                members[2].memberID,
                members[0].memberID
            )
        )
        XCTAssertEqual(
            swapped.memberIDs,
            [members[0].memberID, members[1].memberID, members[2].memberID]
        )

        let removed = try XCTUnwrap(
            swapped.removing(memberID: members[1].memberID)
        )
        XCTAssertEqual(
            removed.memberIDs,
            [members[0].memberID, members[2].memberID]
        )
    }

    func testRootEdgeMoveChangesPlaneWithoutChangingMemberOrderWithinRemainder() throws {
        let members = regularMembers(count: 3)
        let tree = try XCTUnwrap(
            SplitLayoutFactory.make(kind: .vertical, members: members)
        )
        let moved = try XCTUnwrap(
            tree.movingMemberToRootEdge(members[2].memberID, side: .top)
        )

        assertRoot(moved, axis: .column, childCount: 2)
        XCTAssertEqual(
            moved.memberIDs,
            [members[2].memberID, members[0].memberID, members[1].memberID]
        )
    }

    func testFullGroupAllowsCenterReplacementButRejectsFifthInsertion() throws {
        let members = regularMembers(count: 5)
        let tree = try XCTUnwrap(
            SplitLayoutFactory.make(
                kind: .grid,
                members: Array(members.prefix(4))
            )
        )

        XCTAssertNotNil(
            tree.inserting(
                members[4],
                relativeTo: members[1].memberID,
                side: .center
            )
        )
        XCTAssertNil(
            tree.inserting(
                members[4],
                relativeTo: members[1].memberID,
                side: .right
            )
        )
    }

    func testReconcilerFlattensSameAxisAndPreservesRelativeWeights() throws {
        let members = regularMembers(count: 3)
        let raw = SplitLayoutTree.split(
            axis: .row,
            weight: 1,
            children: [
                .split(
                    axis: .row,
                    weight: 0.25,
                    children: [
                        .leaf(member: members[0], weight: 0.25),
                        .leaf(member: members[1], weight: 0.75),
                    ]
                ),
                .leaf(member: members[2], weight: 0.75),
            ]
        )
        let canonical = try XCTUnwrap(
            SplitLayoutReconciler.canonicalizedForTiles(raw)
        )
        guard case .split(.row, _, let children) = canonical else {
            return XCTFail("Expected a flattened row")
        }

        XCTAssertEqual(children.count, 3)
        XCTAssertEqual(children[0].weightInParent, 0.0625, accuracy: 0.000_001)
        XCTAssertEqual(children[1].weightInParent, 0.1875, accuracy: 0.000_001)
        XCTAssertEqual(children[2].weightInParent, 0.75, accuracy: 0.000_001)
    }

    func testSizingSanitizesNonFiniteAndNonPositiveWeights() {
        let weights = SplitLayoutSizing.normalizedWeights([
            .nan,
            -.infinity,
            0,
            10,
        ])

        XCTAssertEqual(weights.reduce(0, +), 1, accuracy: 0.000_001)
        XCTAssertTrue(weights.allSatisfy { $0.isFinite && $0 > 0 })
    }

    private func regularMembers(count: Int) -> [SplitMember] {
        (0..<count).map { _ in .regularTab(UUID()) }
    }

    private func assertRoot(
        _ tree: SplitLayoutTree,
        axis: SplitAxis,
        childCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .split(let actualAxis, _, let children) = tree else {
            return XCTFail("Expected split root", file: file, line: line)
        }
        XCTAssertEqual(actualAxis, axis, file: file, line: line)
        XCTAssertEqual(children.count, childCount, file: file, line: line)
        XCTAssertEqual(
            children.map(\.weightInParent).reduce(0, +),
            1,
            accuracy: 0.000_001,
            file: file,
            line: line
        )
    }
}
