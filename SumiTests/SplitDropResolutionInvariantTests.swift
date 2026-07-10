import CoreGraphics
import XCTest

@testable import Sumi

final class SplitDropResolutionInvariantTests: XCTestCase {
    func testResolvedCandidatePublishesCanonicalMutationEvidence() throws {
        let ids = (0..<3).map { _ in UUID() }
        let bounds = CGRect(x: 0, y: 0, width: 900, height: 600)
        let tree = SplitLayoutFactory.equalSplit(
            axis: .row,
            tabIds: Array(ids.prefix(2))
        )
        let previewRect = CGRect(x: 0, y: 300, width: 450, height: 300)
        let target = SplitDropTarget(
            tabId: ids[0],
            side: .top,
            targetRect: bounds,
            scope: .plane,
            planePath: [0],
            intent: .planeEdge
        )

        let resolved = try XCTUnwrap(
            SplitDropCandidate(
                target: target,
                draggedTabId: ids[2],
                previewRect: previewRect
            ).resolved(in: tree, bounds: bounds)
        )
        let resolvedTree = try XCTUnwrap(resolved.resolvedLayoutTree)

        XCTAssertEqual(resolved.targetRect, previewRect)
        XCTAssertEqual(Set(resolvedTree.tabIds), Set(ids))
        XCTAssertEqual(
            SplitLayoutReconciler.canonicalTreePreservingSizes(resolvedTree),
            resolvedTree
        )
    }

    func testResolvedCandidateRejectsNoOpRearrangement() {
        let ids = (0..<2).map { _ in UUID() }
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let tree = SplitLayoutFactory.equalSplit(axis: .row, tabIds: ids)
        let target = SplitDropTarget(
            tabId: ids[0],
            side: .right,
            targetRect: bounds,
            scope: .pane,
            planePath: [0],
            intent: .siblingEdge
        )

        XCTAssertNil(
            SplitDropCandidate(
                target: target,
                draggedTabId: ids[1]
            ).resolved(in: tree, bounds: bounds)
        )
    }

    func testFullGroupCatalogOwnsUniqueCanonicalTopologies() throws {
        let ids = (0..<SplitGroup.maximumTabs).map { _ in UUID() }
        var catalog = SplitFullGroupLayoutCatalog()

        let trees = catalog.trees(for: ids)
        let cachedForDifferentOrder = catalog.trees(for: Array(ids.reversed()))

        XCTAssertFalse(trees.isEmpty)
        XCTAssertEqual(trees, cachedForDifferentOrder)
        XCTAssertEqual(Set(trees).count, trees.count)
        for tree in trees {
            XCTAssertEqual(Set(tree.tabIds), Set(ids))
            XCTAssertEqual(
                SplitLayoutReconciler.canonicalTreePreservingSizes(tree),
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
        let ids = (0..<5).map { _ in UUID() }
        let bounds = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let group = try XCTUnwrap(
            SplitGroup.make(
                tabIds: Array(ids.prefix(4)),
                layoutKind: .grid,
                activeTabId: ids[0]
            )
        )
        let resolver = SplitGroupedDropTargetResolver()
        var catalog = SplitFullGroupLayoutCatalog()
        let scenarios: [(CGPoint, UUID)] = [
            (CGPoint(x: 40, y: 740), ids[3]),
            (CGPoint(x: 460, y: 740), ids[2]),
            (CGPoint(x: 960, y: 60), ids[0]),
        ]

        for (location, draggedTabId) in scenarios {
            let target = try XCTUnwrap(
                resolver.target(
                    in: group,
                    at: location,
                    bounds: bounds,
                    draggedTabId: draggedTabId,
                    fullGroupLayouts: &catalog
                )
            )
            let resolvedTree = try XCTUnwrap(target.resolvedLayoutTree)
            XCTAssertEqual(Set(resolvedTree.tabIds), Set(group.tabIds))
            XCTAssertFalse(
                resolvedTree.hasSameStructure(as: group.layoutTree),
                "Published rearrangement must change the tab topology"
            )
        }
    }
}
