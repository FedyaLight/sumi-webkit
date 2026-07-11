import Foundation
import SumiDomain
import XCTest

@testable import Sumi

final class SplitDropGroupAlgebraTests: XCTestCase {
    func testMovingLastViableSourceMemberRemovesSourceAndReplacesTarget() throws {
        let moving = SplitMember.regularTab(UUID())
        let source = try makeGroup([moving, .regularTab(UUID())])
        let unrelated = try makeGroup([.regularTab(UUID()), .regularTab(UUID())])
        let target = try makeGroup([.regularTab(UUID()), .regularTab(UUID())])
        let replacementTarget = try XCTUnwrap(
            target.inserting(
                moving,
                relativeTo: target.memberIDs[0],
                side: .right
            )
        )

        let result = SplitDropGroupAlgebra.replacingGroups(
            [source, unrelated, target],
            sourceGroup: source,
            movingMemberID: moving.memberID,
            targetGroup: target,
            replacementTarget: replacementTarget
        )

        XCTAssertEqual(result, [unrelated, replacementTarget])
        XCTAssertEqual(
            result.flatMap(\.memberIDs).filter { $0 == moving.memberID },
            [moving.memberID]
        )
    }

    func testMovingFromThreeMemberSourceKeepsReducedSourceInPlace() throws {
        let moving = SplitMember.regularTab(UUID())
        let source = try makeGroup([
            .regularTab(UUID()),
            moving,
            .regularTab(UUID()),
        ])
        let target = try makeGroup([.regularTab(UUID()), .regularTab(UUID())])
        let reducedSource = try XCTUnwrap(
            source.removingMember(moving.memberID)
        )
        let replacementTarget = try XCTUnwrap(
            target.inserting(
                moving,
                relativeTo: target.memberIDs[1],
                side: .left
            )
        )

        XCTAssertEqual(
            SplitDropGroupAlgebra.replacingGroups(
                [source, target],
                sourceGroup: source,
                movingMemberID: moving.memberID,
                targetGroup: target,
                replacementTarget: replacementTarget
            ),
            [reducedSource, replacementTarget]
        )
    }

    func testStaleSourceOrTargetSnapshotCannotRewriteCurrentGroups() throws {
        let moving = SplitMember.regularTab(UUID())
        let source = try makeGroup([
            moving,
            .regularTab(UUID()),
            .regularTab(UUID()),
        ])
        let target = try makeGroup([.regularTab(UUID()), .regularTab(UUID())])
        let currentSource = try XCTUnwrap(
            source.changingLayout(to: .horizontal)
        )
        let replacementTarget = try XCTUnwrap(
            target.inserting(
                moving,
                relativeTo: target.memberIDs[0],
                side: .right
            )
        )
        let current = [currentSource, target]

        XCTAssertEqual(
            SplitDropGroupAlgebra.replacingGroups(
                current,
                sourceGroup: source,
                movingMemberID: moving.memberID,
                targetGroup: target,
                replacementTarget: replacementTarget
            ),
            current
        )

        let staleTarget = try XCTUnwrap(
            target.changingLayout(to: .horizontal)
        )
        XCTAssertEqual(
            SplitDropGroupAlgebra.replacingGroups(
                [source, target],
                sourceGroup: source,
                movingMemberID: moving.memberID,
                targetGroup: staleTarget,
                replacementTarget: replacementTarget
            ),
            [source, target]
        )
    }

    private func makeGroup(_ members: [SplitMember]) throws -> SplitGroup {
        try XCTUnwrap(
            SplitGroup.make(members: members, layoutKind: .vertical)
        )
    }
}
