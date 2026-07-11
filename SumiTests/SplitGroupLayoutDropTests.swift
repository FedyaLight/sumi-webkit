import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class SplitGroupLayoutDropTests: SplitGroupTestCase {
    func testVerticalHorizontalAndGridTreeShapes() throws {
        let ids = makeIDs(4)

        let vertical = try XCTUnwrap(SplitGroup.make(tabIds: ids, layoutKind: .vertical))
        assertSplit(vertical.layoutTree, axis: .row, tabIds: ids, childCount: 4)

        let horizontal = try XCTUnwrap(SplitGroup.make(tabIds: ids, layoutKind: .horizontal))
        assertSplit(horizontal.layoutTree, axis: .column, tabIds: ids, childCount: 4)

        let grid = try XCTUnwrap(SplitGroup.make(tabIds: ids, layoutKind: .grid))
        guard case .split(let rootAxis, _, let columns) = grid.layoutTree else {
            return XCTFail("Expected a split root for grid layout.")
        }
        XCTAssertEqual(rootAxis, .row)
        XCTAssertEqual(columns.count, 2)
        XCTAssertEqual(columns.flatMap(\.tabIds), ids)
        for column in columns {
            guard case .split(let columnAxis, _, let leaves) = column else {
                return XCTFail("Expected two stacked panes per grid column.")
            }
            XCTAssertEqual(columnAxis, .column)
            XCTAssertEqual(leaves.count, 2)
        }
    }

    func testInsertCapsAtFourAndRemoveDeletesBelowMinimum() throws {
        let ids = makeIDs(5)
        let initial = try XCTUnwrap(SplitGroup.make(tabIds: Array(ids.prefix(2)), layoutKind: .vertical))
        let three = try XCTUnwrap(initial.inserting(tabId: ids[2], relativeTo: ids[1], side: .right))
        let four = try XCTUnwrap(three.inserting(tabId: ids[3], relativeTo: ids[2], side: .bottom))

        XCTAssertEqual(three.tabIds, Array(ids.prefix(3)))
        XCTAssertEqual(four.tabIds.count, 4)
        XCTAssertNil(four.inserting(tabId: ids[4], relativeTo: ids[0], side: .left))

        let reduced = try XCTUnwrap(four.removing(tabId: ids[1]))
        XCTAssertEqual(reduced.tabIds.count, 3)
        XCTAssertNil(initial.removing(tabId: ids[0]))
    }

    func testAddingThirdSplitAlongExistingAxisEqualizesRootSiblings() throws {
        let ids = makeIDs(3)
        let initial = try XCTUnwrap(SplitGroup.make(tabIds: Array(ids.prefix(2)), layoutKind: .vertical))
        let resized = SplitGroup(
            id: initial.id,
            layoutKind: initial.layoutKind,
            layoutTree: SplitLayoutSizing.updatingChildSizes(
                in: initial.layoutTree,
                at: [],
                sizes: [0.8, 0.2]
            ),
            activeTabId: ids[0]
        )

        let inserted = try XCTUnwrap(resized.inserting(tabId: ids[2], relativeTo: ids[0], side: .right))

        XCTAssertEqual(inserted.tabIds, [ids[0], ids[2], ids[1]])
        assertImmediateChildSizes(inserted.layoutTree, [1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0])
    }

    func testAddingFourthSplitAlongExistingAxisEqualizesRootSiblings() throws {
        let ids = makeIDs(4)
        let initial = try XCTUnwrap(SplitGroup.make(tabIds: Array(ids.prefix(3)), layoutKind: .vertical))
        let resized = SplitGroup(
            id: initial.id,
            layoutKind: initial.layoutKind,
            layoutTree: SplitLayoutSizing.updatingChildSizes(
                in: initial.layoutTree,
                at: [],
                sizes: [0.2, 0.5, 0.3]
            ),
            activeTabId: ids[1]
        )

        let inserted = try XCTUnwrap(resized.inserting(tabId: ids[3], relativeTo: ids[1], side: .right))

        XCTAssertEqual(inserted.tabIds, [ids[0], ids[1], ids[3], ids[2]])
        assertImmediateChildSizes(inserted.layoutTree, [0.25, 0.25, 0.25, 0.25])
    }

    func testCenterDropReplacesPaneAndResizePersistsNormalizedSizes() throws {
        let ids = makeIDs(4)
        let group = try XCTUnwrap(SplitGroup.make(tabIds: Array(ids.prefix(3)), layoutKind: .vertical))
        let replacedTree = group.layoutTree.inserting(
            tabId: ids[3],
            relativeTo: ids[1],
            side: .center
        )
        let resizedTree = SplitLayoutSizing.updatingChildSizes(
            in: replacedTree,
            at: [],
            sizes: [0.2, 0.3, 0.5]
        )

        XCTAssertEqual(replacedTree.tabIds, [ids[0], ids[3], ids[2]])
        guard case .split(_, _, let children) = resizedTree else {
            return XCTFail("Expected resized split tree.")
        }
        zip(children.map(\.sizeInParent), [0.2, 0.3, 0.5]).forEach { actual, expected in
            XCTAssertEqual(actual, expected, accuracy: 0.0001)
        }
    }

    func testLayoutStructureIgnoresResizeSizes() throws {
        let ids = makeIDs(3)
        let group = try XCTUnwrap(SplitGroup.make(tabIds: ids, layoutKind: .vertical))
        let resized = SplitLayoutSizing.updatingChildSizes(
            in: group.layoutTree,
            at: [],
            sizes: [0.2, 0.3, 0.5]
        )

        XCTAssertTrue(group.layoutTree.hasSameStructure(as: resized))
        XCTAssertFalse(group.layoutTree.hasSameStructure(as: group.layoutTree.swappingTabs(ids[0], ids[1])))
    }

    func testMoveExistingSplitTabReordersWithoutDuplicating() throws {
        let ids = makeIDs(3)
        let group = try XCTUnwrap(SplitGroup.make(tabIds: ids, layoutKind: .vertical))
        let moved = try XCTUnwrap(group.movingTab(ids[2], relativeTo: ids[0], side: .left))

        XCTAssertEqual(moved.tabIds, [ids[2], ids[0], ids[1]])
        XCTAssertEqual(Set(moved.tabIds).count, 3)
        XCTAssertEqual(moved.activeTabId, ids[2])
    }

    func testSplitDropHitPolicyUsesZenEdgeZonesForCreateMode() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

        XCTAssertEqual(SplitDropCaptureHitPolicy.side(at: CGPoint(x: 200, y: 400), in: bounds, mode: .create), .left)
        XCTAssertEqual(SplitDropCaptureHitPolicy.side(at: CGPoint(x: 800, y: 400), in: bounds, mode: .create), .right)
        XCTAssertEqual(SplitDropCaptureHitPolicy.side(at: CGPoint(x: 500, y: 700), in: bounds, mode: .create), .top)
        XCTAssertEqual(SplitDropCaptureHitPolicy.side(at: CGPoint(x: 500, y: 100), in: bounds, mode: .create), .bottom)
        XCTAssertNil(SplitDropCaptureHitPolicy.side(at: CGPoint(x: 500, y: 400), in: bounds, mode: .create))
    }

    func testSplitDropHitPolicyAllowsCenterOnlyForSplitRearrange() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

        XCTAssertNil(SplitDropCaptureHitPolicy.side(at: CGPoint(x: 500, y: 400), in: bounds, mode: .create))
        XCTAssertEqual(SplitDropCaptureHitPolicy.side(at: CGPoint(x: 500, y: 400), in: bounds, mode: .rearrange), .center)
    }

    func testSplitDropCaptureMoveOperationRequiresMoveMask() {
        XCTAssertEqual(SplitDropCaptureHitPolicy.validatedMoveOperation(sourceMask: .move), .move)
        XCTAssertEqual(SplitDropCaptureHitPolicy.validatedMoveOperation(sourceMask: .copy), [])
    }

    func testSplitDropCaptureCanReceiveInitialDragBeforePreviewIsActive() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)

        XCTAssertTrue(SplitDropCaptureHitPolicy.shouldCaptureHit(at: CGPoint(x: 400, y: 300), in: bounds))
        XCTAssertTrue(SplitDropCaptureHitPolicy.shouldCaptureHit(at: CGPoint(x: 4, y: 300), in: bounds))
        XCTAssertFalse(SplitDropCaptureHitPolicy.shouldCaptureHit(at: CGPoint(x: -1, y: 300), in: bounds))
    }

    func testColumnLeafHitMapsFirstChildToVisualTopPane() throws {
        let ids = makeIDs(2)
        let group = try XCTUnwrap(SplitGroup.make(tabIds: ids, layoutKind: .horizontal))
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)

        XCTAssertEqual(
            SplitLayoutGeometry.leafHit(
                in: group.layoutTree,
                at: CGPoint(x: 400, y: 500),
                in: bounds
            )?.tabId,
            ids[0]
        )
        XCTAssertEqual(
            SplitLayoutGeometry.leafHit(
                in: group.layoutTree,
                at: CGPoint(x: 400, y: 100),
                in: bounds
            )?.tabId,
            ids[1]
        )
    }

    func testNestedLeafHitReturnsPaneRect() throws {
        let ids = makeIDs(4)
        let group = try XCTUnwrap(SplitGroup.make(tabIds: ids, layoutKind: .grid))
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

        let topLeft = try XCTUnwrap(
            SplitLayoutGeometry.leafHit(
                in: group.layoutTree,
                at: CGPoint(x: 250, y: 700),
                in: bounds
            )
        )
        let bottomLeft = try XCTUnwrap(
            SplitLayoutGeometry.leafHit(
                in: group.layoutTree,
                at: CGPoint(x: 250, y: 100),
                in: bounds
            )
        )
        let topRight = try XCTUnwrap(
            SplitLayoutGeometry.leafHit(
                in: group.layoutTree,
                at: CGPoint(x: 750, y: 700),
                in: bounds
            )
        )
        let bottomRight = try XCTUnwrap(
            SplitLayoutGeometry.leafHit(
                in: group.layoutTree,
                at: CGPoint(x: 750, y: 100),
                in: bounds
            )
        )

        XCTAssertEqual(topLeft.tabId, ids[0])
        XCTAssertEqual(topLeft.rect, CGRect(x: 0, y: 400, width: 500, height: 400))
        XCTAssertEqual(bottomLeft.tabId, ids[1])
        XCTAssertEqual(bottomLeft.rect, CGRect(x: 0, y: 0, width: 500, height: 400))
        XCTAssertEqual(topRight.tabId, ids[2])
        XCTAssertEqual(topRight.rect, CGRect(x: 500, y: 400, width: 500, height: 400))
        XCTAssertEqual(bottomRight.tabId, ids[3])
        XCTAssertEqual(bottomRight.rect, CGRect(x: 500, y: 0, width: 500, height: 400))
    }

    func testGridTilePlanesExposeRootAndImmediateChildRects() throws {
        let ids = makeIDs(4)
        let group = try XCTUnwrap(SplitGroup.make(tabIds: ids, layoutKind: .grid))
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

        let planes = SplitLayoutGeometry.tilePlanes(
            in: group.layoutTree,
            rect: bounds,
            includeChildPlanes: SplitLayoutGeometry.hasSecondaryPlane(in: group.layoutTree)
        )

        XCTAssertEqual(planes.count, 3)
        XCTAssertEqual(
            planes[0],
            SplitLayoutGeometry.TilePlane(path: [], rect: bounds, tabIds: ids)
        )
        XCTAssertEqual(
            planes[1],
            SplitLayoutGeometry.TilePlane(
                path: [0],
                rect: CGRect(x: 0, y: 0, width: 500, height: 800),
                tabIds: Array(ids[0...1])
            )
        )
        XCTAssertEqual(
            planes[2],
            SplitLayoutGeometry.TilePlane(
                path: [1],
                rect: CGRect(x: 500, y: 0, width: 500, height: 800),
                tabIds: Array(ids[2...3])
            )
        )
    }

    func testDropTargetInsertionAlongExistingAxisUsesEqualRootThirds() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let top = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://top.example", in: space)
        let bottom = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://bottom.example", in: space, activate: false)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = top.id

        let group = try XCTUnwrap(SplitGroup.make(tabIds: [top.id, bottom.id], layoutKind: .horizontal, activeTabId: top.id))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let target = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 400, y: 320),
                in: bounds,
                for: harness.windowState.id
            )
        )

        XCTAssertEqual(target.tabId, top.id)
        XCTAssertEqual(target.side, .bottom)
        XCTAssertEqual(target.targetRect, CGRect(x: 0, y: 200, width: 800, height: 200))
    }

    func testFirstSplitPreviewRectMatchesIncomingHalf() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let current = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://current.example", in: space)
        let incoming = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://incoming.example", in: space, activate: false)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = current.id

        let target = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 20, y: 300),
                in: CGRect(x: 0, y: 0, width: 900, height: 600),
                for: harness.windowState.id,
                draggedTabId: incoming.id
            )
        )

        XCTAssertEqual(target.side, .left)
        XCTAssertEqual(target.targetRect, CGRect(x: 0, y: 0, width: 450, height: 600))
    }

    func testThirdVerticalSplitPreviewUsesOneThirdOfWindow() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let left = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://left.example", in: space)
        let right = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://right.example", in: space, activate: false)
        let incoming = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://incoming.example", in: space, activate: false)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = left.id

        let group = try XCTUnwrap(SplitGroup.make(tabIds: [left.id, right.id], layoutKind: .vertical, activeTabId: left.id))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        let target = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 20, y: 300),
                in: CGRect(x: 0, y: 0, width: 900, height: 600),
                for: harness.windowState.id,
                draggedTabId: incoming.id
            )
        )

        XCTAssertEqual(target.side, .left)
        XCTAssertEqual(target.scope, .group)
        XCTAssertEqual(target.targetRect, CGRect(x: 0, y: 0, width: 300, height: 600))
    }

    func testThirdSplitCanSplitOneVerticalPaneHorizontally() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let left = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://left.example", in: space)
        let right = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://right.example", in: space, activate: false)
        let incoming = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://incoming.example", in: space, activate: false)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = left.id

        let group = try XCTUnwrap(SplitGroup.make(tabIds: [left.id, right.id], layoutKind: .vertical, activeTabId: left.id))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        let target = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 225, y: 580),
                in: CGRect(x: 0, y: 0, width: 900, height: 600),
                for: harness.windowState.id,
                draggedTabId: incoming.id
            )
        )

        XCTAssertEqual(target.side, .top)
        XCTAssertEqual(target.scope, .plane)
        XCTAssertEqual(target.planePath, [0])
        XCTAssertEqual(target.targetRect, CGRect(x: 0, y: 300, width: 450, height: 300))

        XCTAssertTrue(harness.browserManager.splitManager.dropTab(incoming, on: target, in: harness.windowState))
        let updated = try XCTUnwrap(harness.tabManager.splitGroupStructureOwner.splitGroup(containing: incoming.id))
        guard case .split(let rootAxis, _, let rootChildren) = updated.layoutTree else {
            return XCTFail("Expected two-plane split.")
        }
        XCTAssertEqual(rootAxis, .row)
        XCTAssertEqual(rootChildren.count, 2)
        XCTAssertEqual(rootChildren[0].tabIds, [incoming.id, left.id])
        XCTAssertEqual(rootChildren[1].tabIds, [right.id])
        guard case .split(let nestedAxis, _, let nestedChildren) = rootChildren[0] else {
            return XCTFail("Expected left pane to split horizontally.")
        }
        XCTAssertEqual(nestedAxis, .column)
        XCTAssertEqual(nestedChildren.count, 2)
    }

    func testFourthGridRootPreviewCanonicalizesMixedRootToEqualQuarter() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let tabs = (0..<3).map { index in
            harness.tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://tab\(index).example",
                in: space,
                activate: index == 0
            )
        }
        let incoming = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://incoming.example", in: space, activate: false)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = tabs[0].id

        let group = try XCTUnwrap(SplitGroup.make(tabIds: tabs.map(\.id), layoutKind: .grid, activeTabId: tabs[0].id))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        let target = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 880, y: 300),
                in: CGRect(x: 0, y: 0, width: 900, height: 600),
                for: harness.windowState.id,
                draggedTabId: incoming.id
            )
        )

        XCTAssertEqual(target.side, .right)
        XCTAssertEqual(target.scope, .group)
        XCTAssertEqual(target.targetRect, CGRect(x: 675, y: 0, width: 225, height: 600))
    }

    func testFourthVerticalRootPreviewUsesOneQuarterOfWindow() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let tabs = (0..<3).map { index in
            harness.tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://vertical\(index).example",
                in: space,
                activate: index == 0
            )
        }
        let incoming = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://incoming.example", in: space, activate: false)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = tabs[0].id

        let group = try XCTUnwrap(SplitGroup.make(tabIds: tabs.map(\.id), layoutKind: .vertical, activeTabId: tabs[0].id))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        let target = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 980, y: 300),
                in: CGRect(x: 0, y: 0, width: 1000, height: 600),
                for: harness.windowState.id,
                draggedTabId: incoming.id
            )
        )

        XCTAssertEqual(target.side, .right)
        XCTAssertEqual(target.scope, .group)
        XCTAssertEqual(target.targetRect, CGRect(x: 750, y: 0, width: 250, height: 600))
    }

    func testFourthTabCanSplitOneOfThreeVerticalPanesIntoTwoByTwo() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let tabs = (0..<3).map { index in
            harness.tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://three-pair\(index).example",
                in: space,
                activate: index == 0
            )
        }
        let incoming = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://incoming-pair.example", in: space, activate: false)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = tabs[0].id

        let group = try XCTUnwrap(SplitGroup.make(tabIds: tabs.map(\.id), layoutKind: .vertical, activeTabId: tabs[0].id))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        let bounds = CGRect(x: 0, y: 0, width: 900, height: 600)
        let target = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 450, y: 580),
                in: bounds,
                for: harness.windowState.id,
                draggedTabId: incoming.id
            )
        )

        XCTAssertEqual(target.side, .top)
        XCTAssertEqual(target.intent, .flatThreePair)
        XCTAssertEqual(target.targetRect, CGRect(x: 300, y: 300, width: 300, height: 300))

        XCTAssertTrue(harness.browserManager.splitManager.dropTab(incoming, on: target, in: harness.windowState))
        let updated = try XCTUnwrap(harness.tabManager.splitGroupStructureOwner.splitGroup(containing: incoming.id))
        guard case .split(let rootAxis, _, let planes) = updated.layoutTree else {
            return XCTFail("Expected two-plane root.")
        }
        XCTAssertEqual(rootAxis, .row)
        XCTAssertEqual(planes.count, 3)
        assertImmediateChildSizes(updated.layoutTree, [1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0])
        XCTAssertEqual(planes[0].tabIds, [tabs[0].id])
        XCTAssertEqual(planes[1].tabIds, [incoming.id, tabs[1].id])
        XCTAssertEqual(planes[2].tabIds, [tabs[2].id])
        guard case .split(let pairedAxis, _, let pairedChildren) = planes[1] else {
            return XCTFail("Expected paired plane.")
        }
        XCTAssertEqual(pairedAxis, .column)
        XCTAssertEqual(pairedChildren.count, 2)
    }

    func testMovingOneOfThreeVerticalPanesPairsWithSpecificTargetPane() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let tabs = (0..<3).map { index in
            harness.tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://three-internal-vertical\(index).example",
                in: space,
                activate: index == 0
            )
        }
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = tabs[0].id

        let group = try XCTUnwrap(SplitGroup.make(tabIds: tabs.map(\.id), layoutKind: .vertical, activeTabId: tabs[0].id))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        let bounds = CGRect(x: 0, y: 0, width: 900, height: 600)
        let target = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 450, y: 580),
                in: bounds,
                for: harness.windowState.id,
                draggedTabId: tabs[2].id
            )
        )

        XCTAssertEqual(target.side, .top)
        XCTAssertEqual(target.intent, .flatThreePair)
        XCTAssertEqual(target.targetRect, CGRect(x: 300, y: 300, width: 300, height: 300))

        XCTAssertTrue(harness.browserManager.splitManager.dropTab(tabs[2], on: target, in: harness.windowState))
        let updated = try XCTUnwrap(harness.tabManager.splitGroupStructureOwner.splitGroup(containing: tabs[2].id))
        guard case .split(let rootAxis, _, let planes) = updated.layoutTree else {
            return XCTFail("Expected constrained two-plane root.")
        }
        XCTAssertEqual(rootAxis, .row)
        XCTAssertEqual(planes.count, 2)
        assertImmediateChildSizes(updated.layoutTree, [0.5, 0.5])
        XCTAssertEqual(planes[0].tabIds, [tabs[0].id])
        XCTAssertEqual(planes[1].tabIds, [tabs[2].id, tabs[1].id])
        guard case .split(let pairedAxis, _, let pairedChildren) = planes[1] else {
            return XCTFail("Expected dragged and target panes to pair.")
        }
        XCTAssertEqual(pairedAxis, .column)
        XCTAssertEqual(pairedChildren.map(\.tabIds), [[tabs[2].id], [tabs[1].id]])
    }

    func testMovingOneOfThreeHorizontalPanesPairsWithSpecificTargetPane() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let tabs = (0..<3).map { index in
            harness.tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://three-internal-horizontal\(index).example",
                in: space,
                activate: index == 0
            )
        }
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = tabs[0].id

        let group = try XCTUnwrap(SplitGroup.make(tabIds: tabs.map(\.id), layoutKind: .horizontal, activeTabId: tabs[0].id))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        let bounds = CGRect(x: 0, y: 0, width: 900, height: 600)
        let target = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 880, y: 300),
                in: bounds,
                for: harness.windowState.id,
                draggedTabId: tabs[2].id
            )
        )

        XCTAssertEqual(target.side, .right)
        XCTAssertEqual(target.intent, .flatThreePair)
        XCTAssertEqual(target.targetRect, CGRect(x: 450, y: 200, width: 450, height: 200))

        XCTAssertTrue(harness.browserManager.splitManager.dropTab(tabs[2], on: target, in: harness.windowState))
        let updated = try XCTUnwrap(harness.tabManager.splitGroupStructureOwner.splitGroup(containing: tabs[2].id))
        guard case .split(let rootAxis, _, let planes) = updated.layoutTree else {
            return XCTFail("Expected constrained two-plane root.")
        }
        XCTAssertEqual(rootAxis, .column)
        XCTAssertEqual(planes.count, 2)
        assertImmediateChildSizes(updated.layoutTree, [0.5, 0.5])
        XCTAssertEqual(planes[0].tabIds, [tabs[0].id])
        XCTAssertEqual(planes[1].tabIds, [tabs[1].id, tabs[2].id])
        guard case .split(let pairedAxis, _, let pairedChildren) = planes[1] else {
            return XCTFail("Expected dragged and target panes to pair.")
        }
        XCTAssertEqual(pairedAxis, .row)
        XCTAssertEqual(pairedChildren.map(\.tabIds), [[tabs[1].id], [tabs[2].id]])
    }

    func testFourthRootPreviewCanonicalizesMixedColumnToEqualQuarter() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let left = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://left.example", in: space)
        let right = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://right.example", in: space, activate: false)
        let top = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://top.example", in: space, activate: false)
        let incoming = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://incoming.example", in: space, activate: false)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = left.id

        let baseGroup = try XCTUnwrap(SplitGroup.make(tabIds: [left.id, right.id], layoutKind: .vertical, activeTabId: left.id))
        let threePaneGroup = try XCTUnwrap(baseGroup.insertingAtRoot(tabId: top.id, side: .top))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(threePaneGroup)

        let target = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 500, y: 20),
                in: CGRect(x: 0, y: 0, width: 1000, height: 600),
                for: harness.windowState.id,
                draggedTabId: incoming.id
            )
        )

        XCTAssertEqual(target.side, .bottom)
        XCTAssertEqual(target.scope, .group)
        XCTAssertEqual(target.targetRect, CGRect(x: 0, y: 0, width: 1000, height: 150))
    }

    func testMovingOneOfFourVerticalTabsToBottomFromOwnPaneCreatesThreePlusOne() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let tabs = (0..<4).map { index in
            harness.tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://vertical\(index).example",
                in: space,
                activate: index == 0
            )
        }
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = tabs[0].id

        let group = try XCTUnwrap(SplitGroup.make(tabIds: tabs.map(\.id), layoutKind: .vertical, activeTabId: tabs[0].id))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let target = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 875, y: 20),
                in: bounds,
                for: harness.windowState.id,
                draggedTabId: tabs[3].id
            )
        )

        XCTAssertEqual(target.side, .bottom)
        XCTAssertEqual(target.scope, .group)
        XCTAssertEqual(target.targetRect, CGRect(x: 0, y: 0, width: 1000, height: 400))

        XCTAssertTrue(harness.browserManager.splitManager.dropTab(tabs[3], on: target, in: harness.windowState))
        let updated = try XCTUnwrap(harness.tabManager.splitGroupStructureOwner.splitGroup(containing: tabs[3].id))

        guard case .split(let rootAxis, _, let planes) = updated.layoutTree else {
            return XCTFail("Expected a two-plane root.")
        }
        XCTAssertEqual(rootAxis, .column)
        XCTAssertEqual(planes.count, 2)
        assertImmediateChildSizes(updated.layoutTree, [0.5, 0.5])
        XCTAssertEqual(planes[0].tabIds, [tabs[0].id, tabs[1].id, tabs[2].id])
        XCTAssertEqual(planes[1].tabIds, [tabs[3].id])
        guard case .split(let topAxis, _, let topChildren) = planes[0] else {
            return XCTFail("Expected the top plane to stay a flat vertical split.")
        }
        XCTAssertEqual(topAxis, .row)
        XCTAssertEqual(topChildren.count, 3)
        for child in topChildren {
            XCTAssertEqual(child.sizeInParent, 1.0 / 3.0, accuracy: 0.0001)
        }
    }

    func testMovingOneOfFourHorizontalTabsToRightFromOwnPaneCreatesThreePlusOne() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let tabs = (0..<4).map { index in
            harness.tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://horizontal\(index).example",
                in: space,
                activate: index == 0
            )
        }
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = tabs[0].id

        let group = try XCTUnwrap(SplitGroup.make(tabIds: tabs.map(\.id), layoutKind: .horizontal, activeTabId: tabs[0].id))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let target = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 980, y: 100),
                in: bounds,
                for: harness.windowState.id,
                draggedTabId: tabs[3].id
            )
        )

        XCTAssertEqual(target.side, .right)
        XCTAssertEqual(target.scope, .group)
        XCTAssertEqual(target.targetRect, CGRect(x: 500, y: 0, width: 500, height: 800))

        XCTAssertTrue(harness.browserManager.splitManager.dropTab(tabs[3], on: target, in: harness.windowState))
        let updated = try XCTUnwrap(harness.tabManager.splitGroupStructureOwner.splitGroup(containing: tabs[3].id))

        guard case .split(let rootAxis, _, let planes) = updated.layoutTree else {
            return XCTFail("Expected a two-plane root.")
        }
        XCTAssertEqual(rootAxis, .row)
        XCTAssertEqual(planes.count, 2)
        assertImmediateChildSizes(updated.layoutTree, [0.5, 0.5])
        XCTAssertEqual(planes[0].tabIds, [tabs[0].id, tabs[1].id, tabs[2].id])
        XCTAssertEqual(planes[1].tabIds, [tabs[3].id])
        guard case .split(let leftAxis, _, let leftChildren) = planes[0] else {
            return XCTFail("Expected the left plane to stay a flat horizontal split.")
        }
        XCTAssertEqual(leftAxis, .column)
        XCTAssertEqual(leftChildren.count, 3)
        for child in leftChildren {
            XCTAssertEqual(child.sizeInParent, 1.0 / 3.0, accuracy: 0.0001)
        }
    }

    func testFlatFourVerticalLeafLocalOrthogonalDropSplitsTargetPaneInPlace() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let tabs = (0..<4).map { index in
            harness.tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://vertical-pair\(index).example",
                in: space,
                activate: index == 0
            )
        }
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = tabs[0].id

        let group = try XCTUnwrap(SplitGroup.make(tabIds: tabs.map(\.id), layoutKind: .vertical, activeTabId: tabs[0].id))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let target = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 375, y: 780),
                in: bounds,
                for: harness.windowState.id,
                draggedTabId: tabs[3].id
            )
        )

        XCTAssertEqual(target.side, .top)
        XCTAssertEqual(target.scope, .pane)
        XCTAssertEqual(target.intent, .flatFourPair)
        XCTAssertEqual(target.targetRect, CGRect(x: 250, y: 400, width: 250, height: 400))

        XCTAssertTrue(harness.browserManager.splitManager.dropTab(tabs[3], on: target, in: harness.windowState))
        let updated = try XCTUnwrap(harness.tabManager.splitGroupStructureOwner.splitGroup(containing: tabs[3].id))

        guard case .split(let rootAxis, _, let planes) = updated.layoutTree else {
            return XCTFail("Expected constrained mixed root.")
        }
        XCTAssertEqual(rootAxis, .row)
        XCTAssertEqual(planes.count, 3)
        assertImmediateChildSizes(updated.layoutTree, [1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0])
        XCTAssertEqual(planes[0].tabIds, [tabs[0].id])
        XCTAssertEqual(planes[1].tabIds, [tabs[3].id, tabs[1].id])
        XCTAssertEqual(planes[2].tabIds, [tabs[2].id])
        guard case .split(let pairedAxis, _, let pairedChildren) = planes[1] else {
            return XCTFail("Expected the paired plane to split horizontally.")
        }
        XCTAssertEqual(pairedAxis, .column)
        XCTAssertEqual(pairedChildren.count, 2)
        XCTAssertEqual(pairedChildren[0].sizeInParent, 0.5, accuracy: 0.0001)
        XCTAssertEqual(pairedChildren[1].sizeInParent, 0.5, accuracy: 0.0001)
    }

    func testFlatFourHorizontalLeafLocalOrthogonalDropSplitsTargetPaneInPlace() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let tabs = (0..<4).map { index in
            harness.tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://horizontal-pair\(index).example",
                in: space,
                activate: index == 0
            )
        }
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = tabs[0].id

        let group = try XCTUnwrap(SplitGroup.make(tabIds: tabs.map(\.id), layoutKind: .horizontal, activeTabId: tabs[0].id))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let target = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 980, y: 500),
                in: bounds,
                for: harness.windowState.id,
                draggedTabId: tabs[3].id
            )
        )

        XCTAssertEqual(target.side, .right)
        XCTAssertEqual(target.scope, .pane)
        XCTAssertEqual(target.intent, .flatFourPair)
        XCTAssertEqual(target.targetRect, CGRect(x: 500, y: 400, width: 500, height: 200))

        XCTAssertTrue(harness.browserManager.splitManager.dropTab(tabs[3], on: target, in: harness.windowState))
        let updated = try XCTUnwrap(harness.tabManager.splitGroupStructureOwner.splitGroup(containing: tabs[3].id))

        guard case .split(let rootAxis, _, let planes) = updated.layoutTree else {
            return XCTFail("Expected constrained mixed root.")
        }
        XCTAssertEqual(rootAxis, .column)
        XCTAssertEqual(planes.count, 3)
        assertImmediateChildSizes(updated.layoutTree, [1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0])
        XCTAssertEqual(planes[0].tabIds, [tabs[0].id])
        XCTAssertEqual(planes[1].tabIds, [tabs[1].id, tabs[3].id])
        XCTAssertEqual(planes[2].tabIds, [tabs[2].id])
        guard case .split(let pairedAxis, _, let pairedChildren) = planes[1] else {
            return XCTFail("Expected the paired plane to split vertically.")
        }
        XCTAssertEqual(pairedAxis, .row)
        XCTAssertEqual(pairedChildren.count, 2)
        XCTAssertEqual(pairedChildren[0].sizeInParent, 0.5, accuracy: 0.0001)
        XCTAssertEqual(pairedChildren[1].sizeInParent, 0.5, accuracy: 0.0001)
    }

    func testFullFlatFourSameAxisDropReordersIntoQuarterPreview() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let tabs = (0..<4).map { index in
            harness.tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://flat-reorder\(index).example",
                in: space,
                activate: index == 0
            )
        }
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = tabs[0].id

        let group = try XCTUnwrap(SplitGroup.make(tabIds: tabs.map(\.id), layoutKind: .vertical, activeTabId: tabs[0].id))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let target = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 8, y: 400),
                in: bounds,
                for: harness.windowState.id,
                draggedTabId: tabs[3].id
            )
        )

        XCTAssertEqual(target.side, .left)
        XCTAssertEqual(target.intent, .flatFourReorder)
        XCTAssertEqual(target.targetRect, CGRect(x: 0, y: 0, width: 250, height: 800))

        XCTAssertTrue(harness.browserManager.splitManager.dropTab(tabs[3], on: target, in: harness.windowState))
        let updated = try XCTUnwrap(harness.tabManager.splitGroupStructureOwner.splitGroup(containing: tabs[3].id))
        XCTAssertEqual(updated.layoutTree.tabIds, [tabs[3].id, tabs[0].id, tabs[1].id, tabs[2].id])
    }

    func testFullFlatFourOtherPaneMiddleShowsRootThreePlusOneZone() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let tabs = (0..<4).map { index in
            harness.tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://flat-middle\(index).example",
                in: space,
                activate: index == 0
            )
        }
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = tabs[0].id

        let group = try XCTUnwrap(SplitGroup.make(tabIds: tabs.map(\.id), layoutKind: .vertical, activeTabId: tabs[0].id))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        let target = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 375, y: 390),
                in: CGRect(x: 0, y: 0, width: 1000, height: 800),
                for: harness.windowState.id,
                draggedTabId: tabs[3].id
            )
        )

        XCTAssertEqual(target.side, .bottom)
        XCTAssertEqual(target.intent, .rootEdge)
        XCTAssertEqual(target.targetRect, CGRect(x: 0, y: 0, width: 1000, height: 400))
    }

    func testFullFlatFourOtherPaneOuterThirdShowsLocalHalfPairingZone() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let tabs = (0..<4).map { index in
            harness.tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://flat-third\(index).example",
                in: space,
                activate: index == 0
            )
        }
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = tabs[0].id

        let group = try XCTUnwrap(SplitGroup.make(tabIds: tabs.map(\.id), layoutKind: .vertical, activeTabId: tabs[0].id))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        let target = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 375, y: 250),
                in: CGRect(x: 0, y: 0, width: 1000, height: 800),
                for: harness.windowState.id,
                draggedTabId: tabs[3].id
            )
        )

        XCTAssertEqual(target.side, .bottom)
        XCTAssertEqual(target.intent, .flatFourPair)
        XCTAssertEqual(target.targetRect, CGRect(x: 250, y: 0, width: 250, height: 400))
    }

    func testMovingSecondTabIntoExistingBottomPlaneScopesPreviewToBottomQuarter() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let tabs = (0..<4).map { index in
            harness.tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://tile\(index).example",
                in: space,
                activate: index == 0
            )
        }
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = tabs[0].id

        let vertical = try XCTUnwrap(SplitGroup.make(tabIds: tabs.map(\.id), layoutKind: .vertical, activeTabId: tabs[0].id))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(vertical)
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let bottomTarget = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 875, y: 20),
                in: bounds,
                for: harness.windowState.id,
                draggedTabId: tabs[3].id
            )
        )
        XCTAssertTrue(harness.browserManager.splitManager.dropTab(tabs[3], on: bottomTarget, in: harness.windowState))

        let rightTarget = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 980, y: 100),
                in: bounds,
                for: harness.windowState.id,
                draggedTabId: tabs[2].id
            )
        )

        XCTAssertEqual(rightTarget.side, .right)
        XCTAssertEqual(rightTarget.scope, .pane)
        XCTAssertEqual(rightTarget.intent, .mixedThreeOnePair)
        XCTAssertEqual(rightTarget.planePath, [1])
        XCTAssertEqual(rightTarget.targetRect, CGRect(x: 500, y: 0, width: 500, height: 400))

        XCTAssertTrue(harness.browserManager.splitManager.dropTab(tabs[2], on: rightTarget, in: harness.windowState))
        let updated = try XCTUnwrap(harness.tabManager.splitGroupStructureOwner.splitGroup(containing: tabs[2].id))

        guard case .split(let rootAxis, _, let planes) = updated.layoutTree else {
            return XCTFail("Expected a two-plane root.")
        }
        XCTAssertEqual(rootAxis, .column)
        XCTAssertEqual(planes.count, 2)
        assertImmediateChildSizes(updated.layoutTree, [0.5, 0.5])
        XCTAssertEqual(planes[0].tabIds, [tabs[0].id, tabs[1].id])
        XCTAssertEqual(planes[1].tabIds, [tabs[3].id, tabs[2].id])
        for plane in planes {
            guard case .split(let axis, _, let children) = plane else {
                return XCTFail("Expected both planes to be flat rows.")
            }
            XCTAssertEqual(axis, .row)
            XCTAssertEqual(children.count, 2)
            XCTAssertEqual(children[0].sizeInParent, 0.5, accuracy: 0.0001)
            XCTAssertEqual(children[1].sizeInParent, 0.5, accuracy: 0.0001)
        }
    }

    func testMovingSinglePaneFromThreePlusOneBackIntoThreePlaneCreatesTwoByTwo() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let tabs = (0..<4).map { index in
            harness.tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://reverse-tile\(index).example",
                in: space,
                activate: index == 0
            )
        }
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = tabs[0].id

        let vertical = try XCTUnwrap(SplitGroup.make(tabIds: tabs.map(\.id), layoutKind: .vertical, activeTabId: tabs[0].id))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(vertical)
        let bounds = CGRect(x: 0, y: 0, width: 900, height: 600)
        let bottomTarget = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 825, y: 20),
                in: bounds,
                for: harness.windowState.id,
                draggedTabId: tabs[3].id
            )
        )
        XCTAssertTrue(harness.browserManager.splitManager.dropTab(tabs[3], on: bottomTarget, in: harness.windowState))

        let pairTarget = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 590, y: 500),
                in: bounds,
                for: harness.windowState.id,
                draggedTabId: tabs[3].id
            )
        )

        XCTAssertEqual(pairTarget.side, .right)
        XCTAssertEqual(pairTarget.intent, .mixedThreeOnePair)
        XCTAssertEqual(pairTarget.targetRect.origin.x, 450, accuracy: 0.0001)
        XCTAssertEqual(pairTarget.targetRect.origin.y, 300, accuracy: 0.0001)
        XCTAssertEqual(pairTarget.targetRect.width, 150, accuracy: 0.0001)
        XCTAssertEqual(pairTarget.targetRect.height, 300, accuracy: 0.0001)

        XCTAssertTrue(harness.browserManager.splitManager.dropTab(tabs[3], on: pairTarget, in: harness.windowState))
        let updated = try XCTUnwrap(harness.tabManager.splitGroupStructureOwner.splitGroup(containing: tabs[3].id))
        guard case .split(let rootAxis, _, let planes) = updated.layoutTree else {
            return XCTFail("Expected a two-plane root.")
        }
        XCTAssertEqual(rootAxis, .column)
        XCTAssertEqual(planes.count, 2)
        assertImmediateChildSizes(updated.layoutTree, [0.5, 0.5])
        XCTAssertEqual(planes[0].tabIds, [tabs[1].id, tabs[3].id])
        XCTAssertEqual(planes[1].tabIds, [tabs[0].id, tabs[2].id])
        for plane in planes {
            guard case .split(let axis, _, let children) = plane else {
                return XCTFail("Expected both planes to be flat rows.")
            }
            XCTAssertEqual(axis, .row)
            XCTAssertEqual(children.count, 2)
            XCTAssertEqual(children[0].sizeInParent, 0.5, accuracy: 0.0001)
            XCTAssertEqual(children[1].sizeInParent, 0.5, accuracy: 0.0001)
        }
    }

    func testMixedLeafSplitLeafCanBecomeTwoByTwoWithoutLosingExistingPair() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let tabs = (0..<4).map { index in
            harness.tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://mixed-two-by-two\(index).example",
                in: space,
                activate: index == 0
            )
        }
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = tabs[0].id

        let tree = SplitLayoutTree.split(
            axis: .row,
            size: 1,
            children: [
                .leaf(tabId: tabs[0].id, size: 1.0 / 3.0),
                .split(
                    axis: .column,
                    size: 1.0 / 3.0,
                    children: [
                        .leaf(tabId: tabs[1].id, size: 0.5),
                        .leaf(tabId: tabs[2].id, size: 0.5),
                    ]
                ),
                .leaf(tabId: tabs[3].id, size: 1.0 / 3.0),
            ]
        )
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(
            SplitGroup(layoutKind: .grid, layoutTree: tree, activeTabId: tabs[0].id)
        )

        let bounds = CGRect(x: 0, y: 0, width: 900, height: 600)
        let target = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 750, y: 20),
                in: bounds,
                for: harness.windowState.id,
                draggedTabId: tabs[0].id
            )
        )

        XCTAssertEqual(target.side, .bottom)
        XCTAssertEqual(target.intent, .fullGroupPanePair)
        XCTAssertEqual(target.targetRect, CGRect(x: 600, y: 0, width: 300, height: 300))

        XCTAssertTrue(harness.browserManager.splitManager.dropTab(tabs[0], on: target, in: harness.windowState))
        let updated = try XCTUnwrap(harness.tabManager.splitGroupStructureOwner.splitGroup(containing: tabs[0].id))

        guard case .split(let rootAxis, _, let planes) = updated.layoutTree else {
            return XCTFail("Expected two-by-two root.")
        }
        XCTAssertEqual(rootAxis, .row)
        XCTAssertEqual(planes.count, 2)
        assertImmediateChildSizes(updated.layoutTree, [0.5, 0.5])
        XCTAssertEqual(planes[0].tabIds, [tabs[1].id, tabs[2].id])
        XCTAssertEqual(planes[1].tabIds, [tabs[3].id, tabs[0].id])
        for plane in planes {
            guard case .split(let axis, _, let children) = plane else {
                return XCTFail("Expected both panes to remain paired.")
            }
            XCTAssertEqual(axis, .column)
            XCTAssertEqual(children.map(\.sizeInParent), [0.5, 0.5])
        }
    }

    func testStructuralDropFromOneTwoOneIntoFlatVerticalEqualizesQuarters() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let tabs = (0..<4).map { index in
            harness.tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://one-two-one-vertical\(index).example",
                in: space,
                activate: index == 0
            )
        }
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = tabs[0].id

        let tree = SplitLayoutTree.split(
            axis: .row,
            size: 1,
            children: [
                .leaf(tabId: tabs[0].id, size: 1.0 / 3.0),
                .split(
                    axis: .column,
                    size: 1.0 / 3.0,
                    children: [
                        .leaf(tabId: tabs[1].id, size: 0.5),
                        .leaf(tabId: tabs[2].id, size: 0.5),
                    ]
                ),
                .leaf(tabId: tabs[3].id, size: 1.0 / 3.0),
            ]
        )
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(
            SplitGroup(layoutKind: .grid, layoutTree: tree, activeTabId: tabs[0].id)
        )

        let bounds = CGRect(x: 0, y: 0, width: 900, height: 600)
        let target = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 890, y: 300),
                in: bounds,
                for: harness.windowState.id,
                draggedTabId: tabs[1].id
            )
        )

        XCTAssertEqual(target.side, .right)
        XCTAssertEqual(target.intent, .siblingEdge)
        XCTAssertEqual(target.targetRect, CGRect(x: 675, y: 0, width: 225, height: 600))
        XCTAssertTrue(harness.browserManager.splitManager.dropTab(tabs[1], on: target, in: harness.windowState))

        let updated = try XCTUnwrap(harness.tabManager.splitGroupStructureOwner.splitGroup(containing: tabs[1].id))
        guard case .split(let axis, _, let children) = updated.layoutTree else {
            return XCTFail("Expected flat vertical split.")
        }
        XCTAssertEqual(axis, .row)
        XCTAssertEqual(children.map(\.tabIds), [[tabs[0].id], [tabs[2].id], [tabs[3].id], [tabs[1].id]])
        assertImmediateChildSizes(updated.layoutTree, [0.25, 0.25, 0.25, 0.25])
    }

    func testStructuralDropFromOneTwoOneIntoFlatHorizontalEqualizesQuarters() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let tabs = (0..<4).map { index in
            harness.tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://one-two-one-horizontal\(index).example",
                in: space,
                activate: index == 0
            )
        }
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = tabs[0].id

        let tree = SplitLayoutTree.split(
            axis: .column,
            size: 1,
            children: [
                .leaf(tabId: tabs[0].id, size: 1.0 / 3.0),
                .split(
                    axis: .row,
                    size: 1.0 / 3.0,
                    children: [
                        .leaf(tabId: tabs[1].id, size: 0.5),
                        .leaf(tabId: tabs[2].id, size: 0.5),
                    ]
                ),
                .leaf(tabId: tabs[3].id, size: 1.0 / 3.0),
            ]
        )
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(
            SplitGroup(layoutKind: .grid, layoutTree: tree, activeTabId: tabs[0].id)
        )

        let bounds = CGRect(x: 0, y: 0, width: 900, height: 600)
        let target = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 450, y: 10),
                in: bounds,
                for: harness.windowState.id,
                draggedTabId: tabs[1].id
            )
        )

        XCTAssertEqual(target.side, .bottom)
        XCTAssertEqual(target.intent, .siblingEdge)
        XCTAssertEqual(target.targetRect, CGRect(x: 0, y: 0, width: 900, height: 150))
        XCTAssertTrue(harness.browserManager.splitManager.dropTab(tabs[1], on: target, in: harness.windowState))

        let updated = try XCTUnwrap(harness.tabManager.splitGroupStructureOwner.splitGroup(containing: tabs[1].id))
        guard case .split(let axis, _, let children) = updated.layoutTree else {
            return XCTFail("Expected flat horizontal split.")
        }
        XCTAssertEqual(axis, .column)
        XCTAssertEqual(children.map(\.tabIds), [[tabs[0].id], [tabs[2].id], [tabs[3].id], [tabs[1].id]])
        assertImmediateChildSizes(updated.layoutTree, [0.25, 0.25, 0.25, 0.25])
    }

    func testTwoByTwoCanBecomeThreePlusOneFromEitherPlane() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let tabs = (0..<4).map { index in
            harness.tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://two-by-two-to-three\(index).example",
                in: space,
                activate: index == 0
            )
        }
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = tabs[0].id

        let tree = SplitLayoutTree.split(
            axis: .column,
            size: 1,
            children: [
                .split(
                    axis: .row,
                    size: 0.5,
                    children: [
                        .leaf(tabId: tabs[0].id, size: 0.5),
                        .leaf(tabId: tabs[1].id, size: 0.5),
                    ]
                ),
                .split(
                    axis: .row,
                    size: 0.5,
                    children: [
                        .leaf(tabId: tabs[2].id, size: 0.5),
                        .leaf(tabId: tabs[3].id, size: 0.5),
                    ]
                ),
            ]
        )
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(
            SplitGroup(layoutKind: .grid, layoutTree: tree, activeTabId: tabs[0].id)
        )

        let bounds = CGRect(x: 0, y: 0, width: 900, height: 600)
        let target = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 890, y: 450),
                in: bounds,
                for: harness.windowState.id,
                draggedTabId: tabs[3].id
            )
        )

        XCTAssertEqual(target.side, .right)
        XCTAssertEqual(target.scope, .plane)

        XCTAssertTrue(harness.browserManager.splitManager.dropTab(tabs[3], on: target, in: harness.windowState))
        let updated = try XCTUnwrap(harness.tabManager.splitGroupStructureOwner.splitGroup(containing: tabs[3].id))

        guard case .split(let rootAxis, _, let planes) = updated.layoutTree else {
            return XCTFail("Expected three-plus-one root.")
        }
        XCTAssertEqual(rootAxis, .column)
        XCTAssertEqual(planes.count, 2)
        XCTAssertEqual(planes[0].tabIds, [tabs[0].id, tabs[1].id, tabs[3].id])
        XCTAssertEqual(planes[1].tabIds, [tabs[2].id])
        guard case .split(let topAxis, _, let topChildren) = planes[0] else {
            return XCTFail("Expected top plane to hold three panes.")
        }
        XCTAssertEqual(topAxis, .row)
        XCTAssertEqual(topChildren.count, 3)
    }

    func testEveryCanonicalFourPaneTopologyOffersInternalEdgeTargets() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let tabs = (0..<4).map { index in
            harness.tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://topology\(index).example",
                in: space,
                activate: index == 0
            )
        }
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = tabs[0].id

        let ids = tabs.map(\.id)
        let idNames = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, "tab\($0.offset)") })
        let topologies = canonicalFourPaneTopologies(ids: ids)

        let bounds = CGRect(x: 0, y: 0, width: 900, height: 600)
        let sides: [SplitDropSide] = [.left, .right, .top, .bottom]
        for (name, tree) in topologies {
            let group = SplitGroup(id: UUID(), layoutKind: .grid, layoutTree: tree, activeTabId: ids[0])
            harness.tabManager.splitGroupStructureOwner.replaceSplitGroups([group], schedulePersistence: false)
            let canonical = try XCTUnwrap(group.canonicalizedForTiles(), "Invalid topology \(name)")
            assertZenCanonicalTree(canonical.layoutTree, name)
            let hits = SplitLayoutGeometry.leafHits(in: canonical.layoutTree, rect: bounds)
            for dragged in ids {
                for hit in hits where hit.tabId != dragged {
                    for side in sides {
                        let point = edgePoint(for: side, in: hit.rect)
                        let target = harness.browserManager.splitManager.dropTarget(
                            at: point,
                            in: bounds,
                            for: harness.windowState.id,
                            draggedTabId: dragged
                        )
                        if target == nil {
                            XCTAssertTrue(
                                isSameSlotNoOp(
                                    in: canonical.layoutTree,
                                    draggedTabId: dragged,
                                    targetTabId: hit.tabId,
                                    side: side
                                ),
                                "Missing \(side) target for topology \(name), dragged \(idNames[dragged] ?? dragged.uuidString), hit \(idNames[hit.tabId] ?? hit.tabId.uuidString)"
                            )
                        } else if let target {
                            let resolvedTree = try XCTUnwrap(
                                target.resolvedLayoutTree,
                                "Missing resolved tree for topology \(name), side \(side), dragged \(idNames[dragged] ?? dragged.uuidString), hit \(idNames[hit.tabId] ?? hit.tabId.uuidString)"
                            )
                            assertZenCanonicalTree(resolvedTree, "\(name) -> \(side)")
                            assertEqualChildSizesRecursively(resolvedTree, "\(name) -> \(side)")
                            let expectedRect = try XCTUnwrap(
                                SplitLayoutGeometry.leafRect(
                                    for: dragged,
                                    in: resolvedTree,
                                    rect: bounds
                                ),
                                "Missing dragged rect for topology \(name), side \(side), dragged \(idNames[dragged] ?? dragged.uuidString), hit \(idNames[hit.tabId] ?? hit.tabId.uuidString)"
                            )
                            if target.usesPaneLocalPreview {
                                assertRectContained(
                                    target.targetRect,
                                    in: hit.rect,
                                    "Pane-local preview escaped hit pane for topology \(name), side \(side), dragged \(idNames[dragged] ?? dragged.uuidString), hit \(idNames[hit.tabId] ?? hit.tabId.uuidString)"
                                )
                                assertRectEqual(
                                    target.targetRect,
                                    localHalfRect(for: target.side, in: hit.rect),
                                    "Pane-local preview is not the active half of the hit pane for topology \(name), side \(side), dragged \(idNames[dragged] ?? dragged.uuidString), hit \(idNames[hit.tabId] ?? hit.tabId.uuidString)"
                                )
                            } else {
                                assertRectEqual(
                                    target.targetRect,
                                    expectedRect,
                                    "Preview rect diverged from resolved rect for topology \(name), side \(side), dragged \(idNames[dragged] ?? dragged.uuidString), hit \(idNames[hit.tabId] ?? hit.tabId.uuidString)"
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    func testMixedLeafSplitLeafTreeRestoresPreservingPaneBounds() throws {
        let ids = makeIDs(4)
        let mixedTree = SplitLayoutTree.split(
            axis: .column,
            size: 1,
            children: [
                .leaf(tabId: ids[0], size: 1.0 / 3.0),
                .split(
                    axis: .row,
                    size: 1.0 / 3.0,
                    children: [
                        .leaf(tabId: ids[1], size: 0.5),
                        .leaf(tabId: ids[2], size: 0.5),
                    ]
                ),
                .leaf(tabId: ids[3], size: 1.0 / 3.0),
            ]
        )

        let canonical = try XCTUnwrap(
            SplitLayoutReconciler.canonicalizedForTiles(mixedTree)
        )

        guard case .split(let axis, _, let children) = canonical else {
            return XCTFail("Expected mixed tree to restore as a constrained split.")
        }
        XCTAssertEqual(axis, .column)
        XCTAssertEqual(children.flatMap(\.tabIds), ids)
        XCTAssertEqual(children.count, 3)
        for child in children {
            XCTAssertEqual(child.sizeInParent, 1.0 / 3.0, accuracy: 0.0001)
        }
        guard case .split(let childAxis, _, let pairedChildren) = children[1] else {
            return XCTFail("Expected middle plane to stay split.")
        }
        XCTAssertEqual(childAxis, .row)
        XCTAssertEqual(pairedChildren.map(\.sizeInParent), [0.5, 0.5])
    }

    func testFourthTabPreviewWhenSplittingOneOfThreePanesStaysInsideOriginalPane() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let tabs = (0..<3).map { index in
            harness.tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://three-bottom-pair\(index).example",
                in: space,
                activate: index == 0
            )
        }
        let incoming = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://incoming-bottom-pair.example", in: space, activate: false)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = tabs[0].id

        let group = try XCTUnwrap(SplitGroup.make(tabIds: tabs.map(\.id), layoutKind: .vertical, activeTabId: tabs[0].id))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        let bounds = CGRect(x: 0, y: 0, width: 900, height: 600)
        let target = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 450, y: 20),
                in: bounds,
                for: harness.windowState.id,
                draggedTabId: incoming.id
            )
        )

        XCTAssertEqual(target.side, .bottom)
        XCTAssertEqual(target.intent, .flatThreePair)
        XCTAssertEqual(target.targetRect, CGRect(x: 300, y: 0, width: 300, height: 300))
        XCTAssertTrue(harness.browserManager.splitManager.dropTab(incoming, on: target, in: harness.windowState))

        let updated = try XCTUnwrap(harness.tabManager.splitGroupStructureOwner.splitGroup(containing: incoming.id))
        guard case .split(let rootAxis, _, let children) = updated.layoutTree else {
            return XCTFail("Expected constrained mixed root.")
        }
        XCTAssertEqual(rootAxis, .row)
        for child in children {
            XCTAssertEqual(child.sizeInParent, 1.0 / 3.0, accuracy: 0.0001)
        }
        guard case .split(let pairedAxis, _, let pairedChildren) = children[1] else {
            return XCTFail("Expected selected middle pane to split.")
        }
        XCTAssertEqual(pairedAxis, .column)
        XCTAssertEqual(pairedChildren.map(\.tabIds), [[tabs[1].id], [incoming.id]])
    }

    func testManualResizeSurvivesCanonicalTileNormalization() throws {
        let ids = makeIDs(4)
        let group = try XCTUnwrap(SplitGroup.make(tabIds: ids, layoutKind: .vertical))
        let resized = SplitLayoutSizing.updatingChildSizes(
            in: group.layoutTree,
            at: [],
            sizes: [0.1, 0.2, 0.3, 0.4]
        )
        let canonical = try XCTUnwrap(
            SplitLayoutReconciler.canonicalizedForTiles(resized)
        )

        guard case .split(_, _, let children) = canonical else {
            return XCTFail("Expected a flat split.")
        }
        zip(children.map(\.sizeInParent), [0.1, 0.2, 0.3, 0.4]).forEach { actual, expected in
            XCTAssertEqual(actual, expected, accuracy: 0.0001)
        }
    }

    func testExistingSplitTabUsesGroupEdgeTarget() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let left = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://left.example", in: space)
        let right = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://right.example", in: space, activate: false)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = left.id

        let group = try XCTUnwrap(SplitGroup.make(tabIds: [left.id, right.id], layoutKind: .vertical, activeTabId: left.id))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let target = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 400, y: 40),
                in: bounds,
                for: harness.windowState.id,
                draggedTabId: right.id
            )
        )

        XCTAssertEqual(target.side, .bottom)
        XCTAssertEqual(target.scope, .group)
        XCTAssertEqual(target.previewStyle, .edge)
        XCTAssertEqual(target.targetRect, CGRect(x: 0, y: 0, width: 800, height: 300))
    }

    func testExistingSplitTabHoveringOwnPaneAndOwnRootEdgeDoesNotShowDuplicateTarget() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let left = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://left.example", in: space)
        let right = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://right.example", in: space, activate: false)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = left.id

        let group = try XCTUnwrap(SplitGroup.make(tabIds: [left.id, right.id], layoutKind: .vertical, activeTabId: left.id))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        XCTAssertNil(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 520, y: 300),
                in: CGRect(x: 0, y: 0, width: 800, height: 600),
                for: harness.windowState.id,
                draggedTabId: right.id
            )
        )
        XCTAssertNil(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 780, y: 300),
                in: CGRect(x: 0, y: 0, width: 800, height: 600),
                for: harness.windowState.id,
                draggedTabId: right.id
            )
        )
    }

    func testExistingSplitTabCenterHoverDoesNotShowGapPreview() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let left = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://left.example", in: space)
        let right = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://right.example", in: space, activate: false)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = left.id

        let group = try XCTUnwrap(SplitGroup.make(tabIds: [left.id, right.id], layoutKind: .vertical, activeTabId: left.id))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        XCTAssertNil(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 300, y: 300),
                in: CGRect(x: 0, y: 0, width: 800, height: 600),
                for: harness.windowState.id,
                draggedTabId: right.id
            )
        )
    }

    func testExistingSplitTabSkipsNoOpEdgeAndUsesNextValidEdgeAtCorner() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let left = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://left.example", in: space)
        let right = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://right.example", in: space, activate: false)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = left.id

        let group = try XCTUnwrap(SplitGroup.make(tabIds: [left.id, right.id], layoutKind: .vertical, activeTabId: left.id))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        let target = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 780, y: 40),
                in: CGRect(x: 0, y: 0, width: 800, height: 600),
                for: harness.windowState.id,
                draggedTabId: right.id
            )
        )

        XCTAssertEqual(target.side, .bottom)
        XCTAssertEqual(target.scope, .group)
        XCTAssertEqual(target.previewStyle, .edge)
        XCTAssertEqual(target.targetRect, CGRect(x: 0, y: 0, width: 800, height: 300))
    }

    func testGroupEdgeDropMovesExistingSplitTabAtRoot() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let left = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://left.example", in: space)
        let right = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://right.example", in: space, activate: false)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = left.id

        let group = try XCTUnwrap(SplitGroup.make(tabIds: [left.id, right.id], layoutKind: .vertical, activeTabId: left.id))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        let target = SplitDropTarget(
            tabId: left.id,
            side: .left,
            targetRect: CGRect(x: 0, y: 0, width: 800, height: 600),
            scope: .group,
            previewStyle: .edge
        )
        harness.browserManager.splitManager.dropTab(right, on: target, in: harness.windowState)

        let updated = try XCTUnwrap(harness.tabManager.splitGroupStructureOwner.splitGroup(containing: left.id))
        XCTAssertEqual(updated.tabIds, [right.id, left.id])
        XCTAssertEqual(updated.activeTabId, right.id)
    }

    func testExternalTabGroupEdgeDropInsertsAtRoot() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let left = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://left.example", in: space)
        let right = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://right.example", in: space, activate: false)
        let incoming = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://incoming.example", in: space, activate: false)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = left.id

        let group = try XCTUnwrap(SplitGroup.make(tabIds: [left.id, right.id], layoutKind: .vertical, activeTabId: left.id))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let target = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 400, y: 40),
                in: bounds,
                for: harness.windowState.id,
                draggedTabId: incoming.id
            )
        )
        XCTAssertEqual(target.scope, .group)
        XCTAssertEqual(target.previewStyle, .edge)
        XCTAssertEqual(target.targetRect, CGRect(x: 0, y: 0, width: 800, height: 300))

        harness.browserManager.splitManager.dropTab(incoming, on: target, in: harness.windowState)

        let updated = try XCTUnwrap(harness.tabManager.splitGroupStructureOwner.splitGroup(containing: incoming.id))
        XCTAssertEqual(updated.tabIds, [left.id, right.id, incoming.id])
        guard case .split(let axis, _, let children) = updated.layoutTree else {
            return XCTFail("Expected root split.")
        }
        XCTAssertEqual(axis, .column)
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(children[0].tabIds, [left.id, right.id])
        XCTAssertEqual(children[1].tabIds, [incoming.id])
    }

    func testFullSplitRejectsExternalEdgeInsertPreviewButAllowsCenterReplace() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceServices.catalog.createSpace(name: "Work")
        let tabs = (0..<4).map { index in
            harness.tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://tab\(index).example",
                in: space,
                activate: index == 0
            )
        }
        let incoming = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://incoming.example", in: space, activate: false)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = tabs[0].id

        let group = try XCTUnwrap(SplitGroup.make(tabIds: tabs.map(\.id), layoutKind: .grid, activeTabId: tabs[0].id))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)

        XCTAssertNil(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 20, y: 300),
                in: bounds,
                for: harness.windowState.id,
                draggedTabId: incoming.id
            )
        )

        let centerReplace = try XCTUnwrap(
            harness.browserManager.splitManager.dropTarget(
                at: CGPoint(x: 250, y: 400),
                in: bounds,
                for: harness.windowState.id,
                draggedTabId: incoming.id
            )
        )
        XCTAssertEqual(centerReplace.side, .center)
        XCTAssertEqual(centerReplace.previewStyle, .center)
    }

    func testPreviewRectAndStyleUpdateTogether() throws {
        let harness = try makeHarness()
        let firstRect = CGRect(x: 0, y: 0, width: 500, height: 600)
        let secondRect = CGRect(x: 500, y: 0, width: 500, height: 600)

        harness.browserManager.splitManager.beginPreview(
            targetRect: firstRect,
            for: harness.windowState.id
        )
        var state = harness.browserManager.splitManager.previewState(for: harness.windowState.id)
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.targetRect, firstRect)

        harness.browserManager.splitManager.updatePreview(
            targetRect: secondRect,
            style: .center,
            for: harness.windowState.id
        )
        state = harness.browserManager.splitManager.previewState(for: harness.windowState.id)
        XCTAssertEqual(state.targetRect, secondRect)
        XCTAssertEqual(state.style, .center)

        harness.browserManager.splitManager.endPreview(for: harness.windowState.id)
        state = harness.browserManager.splitManager.previewState(for: harness.windowState.id)
        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.targetRect)
        XCTAssertEqual(state.style, .edge)
    }

    func testSplitDropCaptureCancelClearsStalePreviewWithoutExitEvent() throws {
        let harness = try makeHarness()
        let captureView = SplitDropCaptureView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        configure(captureView, harness: harness)

        harness.browserManager.splitManager.beginPreview(
            targetRect: CGRect(x: 500, y: 0, width: 500, height: 800),
            for: harness.windowState.id
        )

        XCTAssertTrue(harness.browserManager.splitManager.previewState(for: harness.windowState.id).isActive)

        captureView.cancelActiveDragPreview()

        let state = harness.browserManager.splitManager.previewState(for: harness.windowState.id)
        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.targetRect)
    }

    func testSplitDropCaptureClearsStalePreviewWhenDragSessionEndsElsewhere() throws {
        let harness = try makeHarness()
        let captureView = SplitDropCaptureView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        configure(captureView, harness: harness)

        harness.browserManager.splitManager.beginPreview(
            targetRect: CGRect(x: 0, y: 0, width: 1000, height: 400),
            for: harness.windowState.id
        )

        NotificationCenter.default.post(name: .tabDragDidEnd, object: nil)

        let state = harness.browserManager.splitManager.previewState(for: harness.windowState.id)
        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.targetRect)
    }

}
