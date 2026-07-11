import CoreGraphics
import SumiDomain
import XCTest

@testable import Sumi

final class SplitDropResolutionInvariantTests: XCTestCase {
    func testResolvedCandidatePublishesCanonicalMutationEvidence() throws {
        let members = makeMembers(3)
        let bounds = CGRect(x: 0, y: 0, width: 900, height: 600)
        let tree = try XCTUnwrap(
            SplitLayoutFactory.equalSplit(
                axis: .row,
                members: Array(members.prefix(2))
            )
        )
        let previewRect = CGRect(x: 0, y: 300, width: 450, height: 300)
        let target = SplitDropTarget(
            targetMemberID: members[0].memberID,
            side: .top,
            targetRect: bounds,
            scope: .plane,
            planePath: [0],
            intent: .planeEdge
        )

        let resolved = try XCTUnwrap(
            SplitDropCandidate(
                target: target,
                draggedMember: members[2],
                previewRect: previewRect
            ).resolved(in: tree, bounds: bounds)
        )
        let resolvedTree = try XCTUnwrap(resolved.resolvedLayoutTree)

        XCTAssertEqual(resolved.targetRect, previewRect)
        XCTAssertEqual(
            Set(resolvedTree.memberIDs),
            Set(members.map(\.memberID))
        )
        XCTAssertEqual(
            SplitLayoutReconciler.canonicalTreePreservingWeights(resolvedTree),
            resolvedTree
        )
    }

    func testResolvedCandidateRejectsNoOpRearrangement() throws {
        let members = makeMembers(2)
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let tree = try XCTUnwrap(
            SplitLayoutFactory.equalSplit(axis: .row, members: members)
        )
        let target = SplitDropTarget(
            targetMemberID: members[0].memberID,
            side: .right,
            targetRect: bounds,
            scope: .pane,
            planePath: [0],
            intent: .siblingEdge
        )

        XCTAssertNil(
            SplitDropCandidate(
                target: target,
                draggedMember: members[1]
            ).resolved(in: tree, bounds: bounds)
        )
    }

    func testFullGroupCatalogOwnsUniqueCanonicalTopologies() {
        let members = makeMembers(SplitGroup.maximumMembers)
        var catalog = SplitFullGroupLayoutCatalog()

        let trees = catalog.trees(for: members)
        let cachedForDifferentOrder = catalog.trees(
            for: Array(members.reversed())
        )

        XCTAssertFalse(trees.isEmpty)
        XCTAssertEqual(trees, cachedForDifferentOrder)
        XCTAssertEqual(Set(trees).count, trees.count)
        for tree in trees {
            XCTAssertEqual(Set(tree.memberIDs), Set(members.map(\.memberID)))
            XCTAssertEqual(
                SplitLayoutReconciler.canonicalTreePreservingWeights(tree),
                tree
            )
        }
    }

    func testPointerGeometryRanksCornerEdgesDeterministically() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 300)

        XCTAssertEqual(
            SplitDropTargetGeometry.rankedEdgeSides(
                at: CGPoint(x: 30, y: 30),
                in: rect
            ),
            [.bottom, .left]
        )
        XCTAssertTrue(
            SplitDropTargetGeometry.isNearInternalDivider(
                location: CGPoint(x: 490, y: 300),
                leafRect: CGRect(x: 0, y: 0, width: 500, height: 600),
                bounds: CGRect(x: 0, y: 0, width: 1_000, height: 600),
                rootAxis: .row
            )
        )
        XCTAssertFalse(
            SplitDropTargetGeometry.isNearInternalDivider(
                location: CGPoint(x: 450, y: 300),
                leafRect: CGRect(x: 0, y: 0, width: 500, height: 600),
                bounds: CGRect(x: 0, y: 0, width: 1_000, height: 600),
                rootAxis: .row
            )
        )
    }

    func testGroupedResolverNeverPublishesUnresolvedMutationTarget() throws {
        let members = makeMembers(5)
        let bounds = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: Array(members.prefix(4)),
                layoutKind: .grid
            )
        )
        let resolver = SplitGroupedDropTargetResolver()
        var catalog = SplitFullGroupLayoutCatalog()
        let scenarios: [(CGPoint, SplitMember)] = [
            (CGPoint(x: 40, y: 740), members[3]),
            (CGPoint(x: 460, y: 740), members[2]),
            (CGPoint(x: 960, y: 60), members[0]),
        ]

        for (location, draggedMember) in scenarios {
            let target = try XCTUnwrap(
                resolver.target(
                    in: group,
                    at: location,
                    bounds: bounds,
                    draggedMember: draggedMember,
                    fullGroupLayouts: &catalog
                )
            )
            let resolvedTree = try XCTUnwrap(target.resolvedLayoutTree)
            XCTAssertEqual(Set(resolvedTree.memberIDs), Set(group.memberIDs))
            XCTAssertFalse(
                resolvedTree.hasSameStructure(as: group.layoutTree),
                "Published rearrangement must change the member topology"
            )
        }
    }

    func testTypedTargetAndMutationPreserveShortcutPlacementMetadata() throws {
        let regular = SplitMember.regularTab(UUID())
        let pinID = UUID()
        let placement = SplitShortcutReturnPlacement.spacePinned(
            spaceId: UUID(),
            folderId: UUID(),
            index: 7
        )
        let shortcut = SplitMember.shortcutPin(
            pinID,
            returnPlacement: placement
        )
        let incoming = SplitMember.regularTab(UUID())
        let tree = try XCTUnwrap(
            SplitLayoutFactory.equalSplit(
                axis: .row,
                members: [regular, shortcut]
            )
        )
        let target = SplitDropTarget(
            targetMemberID: .shortcutPin(pinID),
            side: .top,
            targetRect: CGRect(x: 0, y: 0, width: 800, height: 600),
            planePath: [1],
            intent: .siblingEdge
        )

        let resolved = try XCTUnwrap(
            SplitLayoutDropMutation.resolve(
                in: tree,
                draggedMember: incoming,
                target: target,
                bounds: target.targetRect
            )
        )

        XCTAssertEqual(resolved.target.targetMemberID, .shortcutPin(pinID))
        XCTAssertEqual(
            resolved.layoutTree.member(for: .shortcutPin(pinID))?
                .returnPlacement,
            placement
        )
    }

    private func makeMembers(_ count: Int) -> [SplitMember] {
        (0..<count).map { _ in .regularTab(UUID()) }
    }
}
