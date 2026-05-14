import XCTest

@testable import Sumi

final class SidebarDropProjectionTests: XCTestCase {
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
