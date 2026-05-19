import XCTest
import CoreGraphics

@testable import Sumi

final class SidebarDropProjectionTests: XCTestCase {
    func testTabListAutoscrollPolicyActivatesOnlyInsideVerticalEdgeBands() {
        let viewport = CGRect(x: 10, y: 100, width: 240, height: 320)

        XCTAssertEqual(
            SidebarTabListAutoscrollPolicy.direction(
                for: CGPoint(x: viewport.midX, y: viewport.maxY - 4),
                in: viewport
            ),
            .up
        )
        XCTAssertEqual(
            SidebarTabListAutoscrollPolicy.direction(
                for: CGPoint(x: viewport.midX, y: viewport.minY + 4),
                in: viewport
            ),
            .down
        )
        XCTAssertNil(
            SidebarTabListAutoscrollPolicy.direction(
                for: CGPoint(x: viewport.midX, y: viewport.midY),
                in: viewport
            )
        )
        XCTAssertNil(
            SidebarTabListAutoscrollPolicy.direction(
                for: CGPoint(x: viewport.maxX + 1, y: viewport.minY + 4),
                in: viewport
            )
        )
    }

    func testTabListAutoscrollPolicyKeepsShortViewportsBoundedToNearestEdge() {
        let viewport = CGRect(x: 0, y: 0, width: 80, height: 40)

        XCTAssertEqual(
            SidebarTabListAutoscrollPolicy.direction(
                for: CGPoint(x: viewport.midX, y: viewport.maxY - 2),
                in: viewport
            ),
            .up
        )
        XCTAssertEqual(
            SidebarTabListAutoscrollPolicy.direction(
                for: CGPoint(x: viewport.midX, y: viewport.minY + 2),
                in: viewport
            ),
            .down
        )
        XCTAssertNil(
            SidebarTabListAutoscrollPolicy.direction(
                for: CGPoint(x: viewport.midX, y: viewport.midY),
                in: viewport
            )
        )
    }

    func testTabListAutoscrollPolicyStepIncreasesTowardEdge() {
        let viewport = CGRect(x: 0, y: 0, width: 100, height: 300)
        let nearEdgeStep = SidebarTabListAutoscrollPolicy.step(
            for: CGPoint(x: viewport.midX, y: viewport.minY + 2),
            in: viewport,
            direction: .down
        )
        let fartherFromEdgeStep = SidebarTabListAutoscrollPolicy.step(
            for: CGPoint(x: viewport.midX, y: viewport.minY + 24),
            in: viewport,
            direction: .down
        )

        XCTAssertGreaterThan(nearEdgeStep, fartherFromEdgeStep)
        XCTAssertGreaterThanOrEqual(fartherFromEdgeStep, SidebarTabListAutoscrollPolicy.minimumStep)
        XCTAssertLessThanOrEqual(nearEdgeStep, SidebarTabListAutoscrollPolicy.maximumStep)
    }

    func testProjectedIndexBeforeSourceMapsDirectlyToModelIndex() {
        XCTAssertEqual(
            SidebarDropProjection.modelInsertionIndex(
                fromProjectedIndex: 0,
                sourceIndex: 2
            ),
            0
        )
        XCTAssertEqual(
            SidebarDropProjection.modelInsertionIndex(
                fromProjectedIndex: 2,
                sourceIndex: 2
            ),
            2
        )
    }

    func testProjectedIndexAfterSourceMapsPastRemovedSourceInModelIndex() {
        XCTAssertEqual(
            SidebarDropProjection.modelInsertionIndex(
                fromProjectedIndex: 2,
                sourceIndex: 0
            ),
            3
        )
        XCTAssertEqual(
            SidebarDropProjection.modelInsertionIndex(
                fromProjectedIndex: 3,
                sourceIndex: 1
            ),
            4
        )
    }

    func testModelIndexConvertsBackToProjectedIndex() {
        for sourceIndex in 0..<4 {
            for projectedIndex in 0...4 {
                let modelIndex = SidebarDropProjection.modelInsertionIndex(
                    fromProjectedIndex: projectedIndex,
                    sourceIndex: sourceIndex
                )
                XCTAssertEqual(
                    SidebarDropProjection.projectedInsertionIndex(
                        fromModelIndex: modelIndex,
                        sourceIndex: sourceIndex
                    ),
                    projectedIndex,
                    "sourceIndex=\(sourceIndex) projectedIndex=\(projectedIndex) modelIndex=\(modelIndex)"
                )
            }
        }
    }

    func testExternalDropIndexMapsDirectly() {
        XCTAssertEqual(
            SidebarDropProjection.modelInsertionIndex(
                fromProjectedIndex: 3,
                sourceIndex: nil
            ),
            3
        )
        XCTAssertEqual(
            SidebarDropProjection.projectedInsertionIndex(
                fromModelIndex: 3,
                sourceIndex: nil
            ),
            3
        )
    }

    func testProjectedItemsRemoveSourceAndInsertPlaceholder() {
        XCTAssertEqual(
            SidebarDropProjection.projectedItems(
                itemIDs: ["A", "B", "C"],
                sourceID: "A",
                projectedInsertionIndex: 2
            ),
            [.item("B"), .item("C"), .placeholder]
        )
        XCTAssertEqual(
            SidebarDropProjection.projectedItems(
                itemIDs: ["A", "B", "C"],
                sourceID: "B",
                projectedInsertionIndex: 0
            ),
            [.placeholder, .item("A"), .item("C")]
        )
    }

    func testProjectedItemsWithoutPlaceholderOnlyRemoveSource() {
        XCTAssertEqual(
            SidebarDropProjection.projectedItems(
                itemIDs: ["A", "B", "C"],
                sourceID: "B",
                projectedInsertionIndex: nil
            ),
            [.item("A"), .item("C")]
        )
    }

    func testProjectedItemsClampPlaceholderSlot() {
        XCTAssertEqual(
            SidebarDropProjection.projectedItems(
                itemIDs: ["A", "B", "C"],
                sourceID: "C",
                projectedInsertionIndex: 99
            ),
            [.item("A"), .item("B"), .placeholder]
        )
    }
}
