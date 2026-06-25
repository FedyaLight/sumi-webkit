import XCTest
import AppKit
import CoreGraphics
import Foundation

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

    @MainActor
    func testRegisteredScrollViewPrefersSmallestViewportContainingPoint() {
        let registry = SidebarTabListDragAutoscrollRegistry.shared
        registry.stop()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 320),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        let rootView = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = rootView

        let largeScrollView = makeScrollView(frame: NSRect(x: 20, y: 20, width: 260, height: 260))
        let smallScrollView = makeScrollView(frame: NSRect(x: 80, y: 80, width: 90, height: 90))

        rootView.addSubview(largeScrollView)
        rootView.addSubview(smallScrollView)
        registry.register(largeScrollView)
        registry.register(smallScrollView)

        defer {
            registry.unregister(largeScrollView)
            registry.unregister(smallScrollView)
            registry.stop()
            window.close()
        }

        let smallViewport = smallScrollView.contentView.convert(smallScrollView.contentView.bounds, to: nil)
        let largeViewport = largeScrollView.contentView.convert(largeScrollView.contentView.bounds, to: nil)
        let overlappingPoint = CGPoint(x: smallViewport.midX, y: smallViewport.midY)

        XCTAssertTrue(largeViewport.contains(overlappingPoint))
        XCTAssertTrue(smallViewport.contains(overlappingPoint))
        XCTAssertTrue(
            registry.registeredScrollView(
                containingWindowPoint: overlappingPoint,
                in: window
            ) === smallScrollView
        )
    }

    func testAutoscrollRegistryAvoidsHighFrequencyAllocationPatterns() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sumi/Components/DragDrop/SidebarGlobalDragOverlay.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let registryRange = try XCTUnwrap(
            source.range(of: "final class SidebarTabListDragAutoscrollRegistry")
        )
        let registrySource = source[registryRange.lowerBound...]

        XCTAssertTrue(registrySource.contains("1.0 / 60.0"))
        XCTAssertFalse(registrySource.contains("1.0 / 120.0"))
        XCTAssertFalse(registrySource.contains("Task { @MainActor"))
        XCTAssertFalse(registrySource.contains(".sorted {"))
        XCTAssertFalse(registrySource.contains(".sorted("))
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

    private func makeScrollView(frame: NSRect) -> NSScrollView {
        let scrollView = NSScrollView(frame: frame)
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.documentView = NSView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: frame.width,
                height: frame.height
            )
        )
        return scrollView
    }
}
