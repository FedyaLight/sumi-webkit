import CoreGraphics
import SumiDomain
import XCTest

@testable import Sumi

final class SplitGroupLayoutDropTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1_000, height: 800)

    func testFirstSplitResolverUsesTypedMembersForEveryEdge() throws {
        let current = SplitMember.regularTab(UUID())
        let incoming = SplitMember.shortcutPin(UUID())
        let scenarios: [(side: SplitDropSide, location: CGPoint)] = [
            (.left, CGPoint(x: 20, y: 400)),
            (.right, CGPoint(x: 980, y: 400)),
            (.top, CGPoint(x: 500, y: 780)),
            (.bottom, CGPoint(x: 500, y: 20)),
        ]

        for scenario in scenarios {
            let target = try XCTUnwrap(
                SplitFirstDropTargetResolver.target(
                    currentMember: current,
                    at: scenario.location,
                    bounds: bounds,
                    draggedMember: incoming
                )
            )

            XCTAssertEqual(target.targetMemberID, current.memberID)
            XCTAssertEqual(target.side, scenario.side)
            XCTAssertEqual(target.intent, .firstSplit)
            XCTAssertEqual(
                target.targetRect,
                try XCTUnwrap(
                    SplitDropTargetGeometry.firstSplitPreviewRect(
                        currentMember: current,
                        previewMember: incoming,
                        side: scenario.side,
                        bounds: bounds
                    )
                )
            )
        }
    }

    func testFirstSplitResolverRejectsSelfDropAndCenterHit() {
        let member = SplitMember.regularTab(UUID())

        XCTAssertNil(
            SplitFirstDropTargetResolver.target(
                currentMember: member,
                at: CGPoint(x: 20, y: 400),
                bounds: bounds,
                draggedMember: member
            )
        )
        XCTAssertNil(
            SplitFirstDropTargetResolver.target(
                currentMember: member,
                at: CGPoint(x: 500, y: 400),
                bounds: bounds,
                draggedMember: .regularTab(UUID())
            )
        )
    }

    func testGridGeometryProjectsStableMemberIdentityInVisualOrder() throws {
        let members = regularMembers(count: 4)
        let group = try XCTUnwrap(
            SplitGroup.make(members: members, layoutKind: .grid)
        )
        let points = [
            CGPoint(x: 250, y: 700),
            CGPoint(x: 250, y: 100),
            CGPoint(x: 750, y: 700),
            CGPoint(x: 750, y: 100),
        ]

        XCTAssertEqual(
            points.compactMap {
                SplitLayoutGeometry.leafHit(
                    in: group.layoutTree,
                    at: $0,
                    in: bounds
                )?.memberID
            },
            members.map(\.memberID)
        )
        XCTAssertEqual(
            SplitLayoutGeometry.leafRects(
                in: group.layoutTree,
                rect: bounds
            ).keys.sorted(by: stableOrder),
            members.map(\.memberID).sorted(by: stableOrder)
        )
    }

    func testGeometryHonorsNormalizedResizeWeights() throws {
        let members = regularMembers(count: 3)
        let original = try XCTUnwrap(
            SplitLayoutFactory.equalSplit(axis: .row, members: members)
        )
        let resized = SplitLayoutSizing.updatingChildWeights(
            in: original,
            at: [],
            weights: [2, 3, 5]
        )
        let hits = SplitLayoutGeometry.leafHits(in: resized, rect: bounds)

        XCTAssertEqual(hits.map(\.memberID), members.map(\.memberID))
        XCTAssertEqual(hits[0].rect.width, 200, accuracy: 0.001)
        XCTAssertEqual(hits[1].rect.width, 300, accuracy: 0.001)
        XCTAssertEqual(hits[2].rect.width, 500, accuracy: 0.001)
        XCTAssertEqual(hits.reduce(0) { $0 + $1.rect.width }, bounds.width)
    }

    func testExternalDropPreservesMemberIdentity() throws {
        let regular = SplitMember.regularTab(UUID())
        let second = SplitMember.regularTab(UUID())
        let incoming = SplitMember.regularTab(UUID())
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: [regular, second],
                layoutKind: .vertical
            )
        )
        var catalog = SplitFullGroupLayoutCatalog()

        let target = try XCTUnwrap(
            SplitGroupedDropTargetResolver().target(
                in: group,
                at: CGPoint(x: 750, y: 780),
                bounds: bounds,
                draggedMember: incoming,
                fullGroupLayouts: &catalog
            )
        )
        let resolved = try XCTUnwrap(target.resolvedLayoutTree)

        XCTAssertEqual(
            Set(resolved.memberIDs),
            Set([regular.memberID, second.memberID, incoming.memberID])
        )
        XCTAssertEqual(
            resolved.member(for: second.memberID),
            second
        )
        assertCanonical(resolved)
    }

    func testFullGroupRejectsExternalEdgeButAllowsCenterReplacement() throws {
        let members = regularMembers(count: SplitGroup.maximumMembers)
        let incoming = SplitMember.regularTab(UUID())
        let group = try XCTUnwrap(
            SplitGroup.make(members: members, layoutKind: .vertical)
        )
        var catalog = SplitFullGroupLayoutCatalog()

        XCTAssertNil(
            SplitGroupedDropTargetResolver().target(
                in: group,
                at: CGPoint(x: 20, y: 400),
                bounds: bounds,
                draggedMember: incoming,
                fullGroupLayouts: &catalog
            )
        )

        let center = try XCTUnwrap(
            SplitGroupedDropTargetResolver().target(
                in: group,
                at: CGPoint(x: 125, y: 400),
                bounds: bounds,
                draggedMember: incoming,
                fullGroupLayouts: &catalog
            )
        )
        let resolved = try XCTUnwrap(center.resolvedLayoutTree)

        XCTAssertEqual(center.side, .center)
        XCTAssertEqual(center.previewStyle, .center)
        XCTAssertEqual(resolved.memberIDs.count, SplitGroup.maximumMembers)
        XCTAssertTrue(resolved.contains(incoming.memberID))
        XCTAssertFalse(resolved.contains(members[0].memberID))
        assertCanonical(resolved)
    }

    func testInternalFullGroupResolutionMatrixNeverLosesOrDuplicatesMembers() throws {
        let members = regularMembers(count: SplitGroup.maximumMembers)
        let layouts: [SplitLayoutKind] = [.vertical, .horizontal, .grid]
        let points = [
            CGPoint(x: 20, y: 400),
            CGPoint(x: 980, y: 400),
            CGPoint(x: 250, y: 780),
            CGPoint(x: 750, y: 20),
        ]

        for layout in layouts {
            let group = try XCTUnwrap(
                SplitGroup.make(members: members, layoutKind: layout)
            )
            for dragged in members {
                for point in points {
                    var catalog = SplitFullGroupLayoutCatalog()
                    guard let target = SplitGroupedDropTargetResolver().target(
                        in: group,
                        at: point,
                        bounds: bounds,
                        draggedMember: dragged,
                        fullGroupLayouts: &catalog
                    ), let resolved = target.resolvedLayoutTree else {
                        continue
                    }

                    XCTAssertEqual(
                        Set(resolved.memberIDs),
                        Set(group.memberIDs),
                        "\(layout) / \(dragged.memberID) / \(point)"
                    )
                    XCTAssertEqual(
                        resolved.memberIDs.count,
                        Set(resolved.memberIDs).count
                    )
                    assertCanonical(resolved)
                }
            }
        }
    }

    func testResolvedCandidateRejectsNoOpAndPublishesWholeTreeEvidence() throws {
        let members = regularMembers(count: 3)
        let tree = try XCTUnwrap(
            SplitLayoutFactory.equalSplit(
                axis: .row,
                members: Array(members.prefix(2))
            )
        )
        let noOp = SplitDropTarget(
            targetMemberID: members[0].memberID,
            side: .right,
            targetRect: bounds,
            planePath: [0],
            intent: .siblingEdge
        )

        XCTAssertNil(
            SplitDropCandidate(
                target: noOp,
                draggedMember: members[1]
            ).resolved(in: tree, bounds: bounds)
        )

        let insert = SplitDropTarget(
            targetMemberID: members[1].memberID,
            side: .top,
            targetRect: bounds,
            planePath: [1],
            intent: .siblingEdge
        )
        let resolvedTarget = try XCTUnwrap(
            SplitDropCandidate(
                target: insert,
                draggedMember: members[2]
            ).resolved(in: tree, bounds: bounds)
        )
        let resolvedTree = try XCTUnwrap(resolvedTarget.resolvedLayoutTree)

        XCTAssertEqual(
            Set(resolvedTree.memberIDs),
            Set(members.map(\.memberID))
        )
        assertCanonical(resolvedTree)
    }

    func testDropEdgeHitPolicyRanksEdgesAndUsesCenterOnlyForRearrangement() {
        XCTAssertEqual(
            SplitDropEdgeHitPolicy.sides(
                at: CGPoint(x: 10, y: 20),
                in: bounds,
                mode: .create
            ),
            [.left, .bottom]
        )
        XCTAssertNil(
            SplitDropEdgeHitPolicy.side(
                at: CGPoint(x: 500, y: 400),
                in: bounds,
                mode: .create
            )
        )
        XCTAssertEqual(
            SplitDropEdgeHitPolicy.side(
                at: CGPoint(x: 500, y: 400),
                in: bounds,
                mode: .rearrange
            ),
            .center
        )
        XCTAssertEqual(
            SplitDropEdgeHitPolicy.sides(
                at: CGPoint(x: -1, y: 400),
                in: bounds,
                mode: .rearrange
            ),
            []
        )
    }

    private func regularMembers(count: Int) -> [SplitMember] {
        (0..<count).map { _ in .regularTab(UUID()) }
    }

    private func assertCanonical(
        _ tree: SplitLayoutTree,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            SplitLayoutReconciler.canonicalTreePreservingWeights(tree),
            tree,
            file: file,
            line: line
        )
        XCTAssertEqual(
            tree.memberIDs.count,
            Set(tree.memberIDs).count,
            file: file,
            line: line
        )
    }

    private func stableOrder(
        _ lhs: SplitMemberID,
        _ rhs: SplitMemberID
    ) -> Bool {
        String(describing: lhs) < String(describing: rhs)
    }
}
