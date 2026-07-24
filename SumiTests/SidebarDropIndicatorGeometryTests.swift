import CoreGraphics
import Foundation
import XCTest

@testable import Sumi

final class SidebarDropIndicatorGeometryTests: XCTestCase {
    private let spaceId = UUID()
    private let folderId = UUID()

    private let inset = SidebarDropIndicatorGeometry.Metrics.horizontalInset
    private let lineHeight = SidebarDropIndicatorGeometry.Metrics.lineHeight

    // MARK: - Hidden states

    func testLineHiddenForEmptyAndEssentialsSlots() {
        XCTAssertNil(
            SidebarDropIndicatorGeometry.lineRect(
                slot: .empty,
                folderIntent: .none,
                geometry: .empty
            )
        )
        XCTAssertNil(
            SidebarDropIndicatorGeometry.lineRect(
                slot: .essentials(slot: 2),
                folderIntent: .none,
                geometry: .empty
            )
        )
    }

    func testLineHiddenForFolderContainIntent() {
        let geometry = folderGeometry(childFrames: [
            CGRect(x: 20, y: 100, width: 200, height: 36),
        ])
        XCTAssertNil(
            SidebarDropIndicatorGeometry.lineRect(
                slot: .folder(folderId: folderId, slot: 0),
                folderIntent: .contain(folderId: folderId),
                geometry: geometry
            )
        )
    }

    func testLineHiddenForEmptyPinnedSection() {
        XCTAssertNil(
            SidebarDropIndicatorGeometry.lineRect(
                slot: .spacePinned(spaceId: spaceId, slot: 0),
                folderIntent: .none,
                geometry: .empty
            )
        )
    }

    // MARK: - Regular list

    func testRegularBoundariesUseSharedRowPitch() {
        // 3 rows of 36 with the shared 4pt gap -> frame height 116, pitch 40.
        let frame = CGRect(x: 12, y: 200, width: 240, height: 116)
        let geometry = regularGeometry(frame: frame, itemCount: 3)

        let top = SidebarDropIndicatorGeometry.lineRect(
            slot: .spaceRegular(spaceId: spaceId, slot: 0),
            folderIntent: .none,
            geometry: geometry
        )
        XCTAssertEqual(top?.midY, frame.minY)

        let interior = SidebarDropIndicatorGeometry.lineRect(
            slot: .spaceRegular(spaceId: spaceId, slot: 1),
            folderIntent: .none,
            geometry: geometry
        )
        XCTAssertEqual(interior?.midY, 238)

        let bottom = SidebarDropIndicatorGeometry.lineRect(
            slot: .spaceRegular(spaceId: spaceId, slot: 3),
            folderIntent: .none,
            geometry: geometry
        )
        XCTAssertEqual(bottom?.midY, frame.maxY)
    }

    func testRegularAndPinnedInsertionLinesUseTheSameRowRhythm() throws {
        // A transiently stale frame must not change the canonical row pitch.
        let regularFrame = CGRect(x: 12, y: 200, width: 240, height: 112)
        let regularGeometry = regularGeometry(
            frame: regularFrame,
            itemCount: 3
        )
        let regularLine = try XCTUnwrap(
            SidebarDropIndicatorGeometry.lineRect(
                slot: .spaceRegular(spaceId: spaceId, slot: 1),
                folderIntent: .none,
                geometry: regularGeometry
            )
        )

        let pinnedMetrics = SidebarPinnedListHitMetrics(
            frame: CGRect(x: 12, y: 80, width: 240, height: 134),
            rowCount: 3,
            leadingInset: 18
        )
        let regularBoundaryOffset = regularLine.midY - regularFrame.minY
        let pinnedBoundaryOffset = pinnedMetrics.boundaryY(for: 1)
            - pinnedMetrics.rowsFrame.minY

        XCTAssertEqual(
            regularBoundaryOffset,
            pinnedBoundaryOffset,
            accuracy: 0.001
        )
    }

    func testRegularSentinelAndOvershootClampToLastBoundary() {
        let frame = CGRect(x: 12, y: 200, width: 240, height: 116)
        let geometry = regularGeometry(frame: frame, itemCount: 3)

        let sentinel = SidebarDropIndicatorGeometry.lineRect(
            slot: .spaceRegular(spaceId: spaceId, slot: 9999),
            folderIntent: .none,
            geometry: geometry
        )
        XCTAssertEqual(sentinel?.midY, frame.maxY)

        let negative = SidebarDropIndicatorGeometry.lineRect(
            slot: .spaceRegular(spaceId: spaceId, slot: -2),
            folderIntent: .none,
            geometry: geometry
        )
        XCTAssertEqual(negative?.midY, frame.minY)
    }

    func testRegularEmptyListPointsAtFrameTop() {
        let frame = CGRect(x: 12, y: 200, width: 240, height: 0)
        let geometry = regularGeometry(frame: frame, itemCount: 0)

        let rect = SidebarDropIndicatorGeometry.lineRect(
            slot: .spaceRegular(spaceId: spaceId, slot: 0),
            folderIntent: .none,
            geometry: geometry
        )
        XCTAssertEqual(rect?.midY, frame.minY)
    }

    func testRegularLineRectAppliesHorizontalInsetAndHeight() {
        let frame = CGRect(x: 12, y: 200, width: 240, height: 116)
        let geometry = regularGeometry(frame: frame, itemCount: 3)

        let rect = SidebarDropIndicatorGeometry.lineRect(
            slot: .spaceRegular(spaceId: spaceId, slot: 0),
            folderIntent: .none,
            geometry: geometry
        )
        XCTAssertEqual(rect?.minX, frame.minX + inset)
        XCTAssertEqual(rect?.width, frame.width - inset * 2)
        XCTAssertEqual(rect?.height, lineHeight)
    }

    func testPresentedResolutionKeepsTheAnchorChosenWithItsSlot() {
        let originalFrame = CGRect(x: 12, y: 200, width: 240, height: 116)
        let resolution = SidebarDropResolution(
            slot: .spaceRegular(spaceId: spaceId, slot: 1),
            folderIntent: .none,
            activeHoveredFolderId: nil
        ).anchored(in: regularGeometry(frame: originalFrame, rowCount: 3))

        XCTAssertEqual(resolution.indicatorLineRect?.midY, 238)

        let movedGeometry = regularGeometry(
            frame: originalFrame.offsetBy(dx: 0, dy: 100),
            rowCount: 3
        )
        XCTAssertNotEqual(
            resolution.indicatorLineRect,
            SidebarDropIndicatorGeometry.lineRect(
                slot: resolution.slot,
                folderIntent: resolution.folderIntent,
                geometry: movedGeometry
            )
        )
    }

    func testSplitGroupRowKeepsLineOnVisualBoundaries() {
        // 4 tabs render as 3 visual rows: [a], [g1, g2] split row, [b]
        // -> row boundaries [0, 1, 2, 3]. Rows 36pt, spacing 4 -> pitch 40.
        let frame = CGRect(x: 12, y: 200, width: 240, height: 116)
        let geometry = regularGeometry(
            frame: frame,
            rowCount: 3
        )

        // Visual slot 2 is the boundary after the whole split row.
        let belowGroup = SidebarDropIndicatorGeometry.lineRect(
            slot: .spaceRegular(spaceId: spaceId, slot: 2),
            folderIntent: .none,
            geometry: geometry
        )
        XCTAssertEqual(belowGroup?.midY, 200 + 2 * 40 - 2)

        // Visual slot 1 is the boundary before the split row.
        let aboveGroup = SidebarDropIndicatorGeometry.lineRect(
            slot: .spaceRegular(spaceId: spaceId, slot: 1),
            folderIntent: .none,
            geometry: geometry
        )
        XCTAssertEqual(aboveGroup?.midY, 200 + 1 * 40 - 2)

        // Visual slot 3 (after every row) is the frame bottom.
        let after = SidebarDropIndicatorGeometry.lineRect(
            slot: .spaceRegular(spaceId: spaceId, slot: 3),
            folderIntent: .none,
            geometry: geometry
        )
        XCTAssertEqual(after?.midY, frame.maxY)
    }

    func testRegularHitMetricsMapPointerAndSlotsThroughSplitGroupBoundaries() {
        let metrics = SidebarRegularListHitMetrics(
            frame: CGRect(x: 0, y: 0, width: 240, height: 116),
            rowIdentities: (0..<3).map { _ in .tab(UUID()) }
        )

        XCTAssertEqual(metrics.rowCount, 3)

        XCTAssertEqual(metrics.rowBoundaryIndex(forLocalY: 40), 1)
        XCTAssertEqual(metrics.rowBoundaryIndex(forLocalY: 70), 2)
        XCTAssertEqual(metrics.rowBoundaryIndex(forLocalY: 500), 3)
    }

    func testRegularHitBoundaryChangesAtTheVisualRowMidpoint() {
        let metrics = SidebarRegularListHitMetrics(
            frame: CGRect(x: 0, y: 0, width: 240, height: 116),
            rowIdentities: (0..<3).map { _ in .tab(UUID()) }
        )
        let firstRowMidpoint = SidebarRowLayout.rowHeight / 2

        XCTAssertEqual(metrics.rowBoundaryIndex(forLocalY: firstRowMidpoint - 0.25), 0)
        XCTAssertEqual(metrics.rowBoundaryIndex(forLocalY: firstRowMidpoint + 0.25), 1)
    }

    func testRegularHitMetricsDoNotAccumulateSplitMemberOffsetNearListBottom() {
        let leadingIDs = (0..<7).map { _ in UUID() }
        let splitID = UUID()
        let trailingIDs = (0..<2).map { _ in UUID() }
        let identities: [SidebarVisualSceneProjection.RegularRow.Identity] =
            leadingIDs.map { .tab($0) }
            + [.splitGroup(splitID)]
            + trailingIDs.map { .tab($0) }
        let metrics = SidebarRegularListHitMetrics(
            frame: CGRect(x: 0, y: 0, width: 240, height: 396),
            rowIdentities: identities
        )

        let boundaryIndex = metrics.rowBoundaryIndex(forLocalY: 8 * 40)

        XCTAssertEqual(boundaryIndex, 8)
        XCTAssertEqual(
            metrics.presentedBoundary(at: boundaryIndex),
            SidebarVisualSceneProjection.RegularBoundary(
                before: .splitGroup(splitID),
                after: .tab(trailingIDs[0])
            )
        )
    }

    func testMissingRegularMetricsHideLine() {
        XCTAssertNil(
            SidebarDropIndicatorGeometry.lineRect(
                slot: .spaceRegular(spaceId: spaceId, slot: 0),
                folderIntent: .none,
                geometry: .empty
            )
        )
    }

    // MARK: - Pinned list (variable-height rows)

    func testPinnedBoundariesFollowItemFrames() {
        // Middle row is a tall open folder — boundaries must track real frames.
        let frames = [
            CGRect(x: 12, y: 100, width: 240, height: 36),
            CGRect(x: 12, y: 140, width: 240, height: 110),
            CGRect(x: 12, y: 254, width: 240, height: 36),
        ]
        let geometry = pinnedGeometry(itemFrames: frames)

        let top = pinnedLine(slot: 0, geometry: geometry)
        XCTAssertEqual(top?.midY, frames[0].minY)

        let betweenFirstAndSecond = pinnedLine(slot: 1, geometry: geometry)
        XCTAssertEqual(
            betweenFirstAndSecond?.midY,
            (frames[0].maxY + frames[1].minY) / 2
        )

        let afterLast = pinnedLine(slot: 3, geometry: geometry)
        XCTAssertEqual(afterLast?.midY, frames[2].maxY)

        let overshoot = pinnedLine(slot: 42, geometry: geometry)
        XCTAssertEqual(overshoot?.midY, frames[2].maxY)
    }

    func testUniformPinnedBoundariesUseOneListMetric() {
        var geometry = SidebarGeometrySnapshot.empty
        geometry.pinnedListHitTargets = [
            spaceId: SidebarPinnedListHitMetrics(
                frame: CGRect(x: 12, y: 80, width: 240, height: 134),
                rowCount: 3,
                leadingInset: 18
            ),
        ]

        // Frame height 134 with leadingInset 18 encodes 3 rows + two 4px gaps
        // (116 = 3·36 + 2·4). Interior boundaries center in the 4px gap.
        XCTAssertEqual(pinnedLine(slot: 0, geometry: geometry)?.midY, 98)
        XCTAssertEqual(pinnedLine(slot: 1, geometry: geometry)?.midY, 136)
        XCTAssertEqual(pinnedLine(slot: 3, geometry: geometry)?.midY, 214)
    }

    func testPinnedHitMetricsUsesSharedRowRhythm() {
        let leadingInset = SidebarInsertionGuide.visualCenterY
        let rowCount = 3
        let gap = SidebarRowLayout.rowGap
        let height = leadingInset
            + CGFloat(rowCount) * SidebarRowLayout.rowHeight
            + CGFloat(rowCount - 1) * gap
        let metrics = SidebarPinnedListHitMetrics(
            frame: CGRect(x: 0, y: 100, width: 240, height: height),
            rowCount: rowCount,
            leadingInset: leadingInset
        )

        XCTAssertEqual(metrics.rowsFrame.height, 116, accuracy: 0.01)
        XCTAssertEqual(metrics.boundaryY(for: 0), 100 + leadingInset, accuracy: 0.01)
        XCTAssertEqual(
            metrics.boundaryY(for: 1),
            100 + leadingInset + SidebarRowLayout.rowHeight + gap / 2,
            accuracy: 0.01
        )

        let midSecondRow = 100 + leadingInset + SidebarRowLayout.rowHeight + gap + 2
        XCTAssertEqual(metrics.rowBoundaryIndex(forGlobalY: midSecondRow), 1)
    }

    func testPinnedHitBoundaryChangesAtTheVisualRowMidpoint() {
        let metrics = SidebarPinnedListHitMetrics(
            frame: CGRect(x: 0, y: 100, width: 240, height: 116),
            rowCount: 3,
            leadingInset: 0
        )
        let firstRowMidpoint = metrics.rowsFrame.minY + SidebarRowLayout.rowHeight / 2

        XCTAssertEqual(metrics.rowBoundaryIndex(forGlobalY: firstRowMidpoint - 0.25), 0)
        XCTAssertEqual(metrics.rowBoundaryIndex(forGlobalY: firstRowMidpoint + 0.25), 1)
    }

    // MARK: - Folder children

    func testFolderChildBoundariesFollowChildFrames() {
        let frames = [
            CGRect(x: 28, y: 300, width: 224, height: 36),
            CGRect(x: 28, y: 338, width: 224, height: 36),
        ]
        let geometry = folderGeometry(childFrames: frames)

        let first = folderLine(slot: 0, geometry: geometry)
        XCTAssertEqual(first?.midY, frames[0].minY)
        XCTAssertEqual(first?.minX, frames[0].minX + inset)

        let between = folderLine(slot: 1, geometry: geometry)
        XCTAssertEqual(between?.midY, (frames[0].maxY + frames[1].minY) / 2)

        let after = folderLine(slot: 2, geometry: geometry)
        XCTAssertEqual(after?.midY, frames[1].maxY)
    }

    func testEmptyOpenFolderPointsAtBodyTop() {
        let bodyFrame = CGRect(x: 28, y: 300, width: 224, height: 0)
        let geometry = folderGeometry(childFrames: [], bodyFrame: bodyFrame)

        let rect = folderLine(slot: 0, geometry: geometry)
        XCTAssertEqual(rect?.midY, bodyFrame.minY)
    }

    func testFolderWithoutGeometryHidesLine() {
        XCTAssertNil(
            SidebarDropIndicatorGeometry.lineRect(
                slot: .folder(folderId: folderId, slot: 0),
                folderIntent: .insertIntoFolder(folderId: folderId, index: 0),
                geometry: .empty
            )
        )
    }

    // MARK: - Coordinate inversion (SidebarDragLocationMapper)

    func testWindowRectInvertsSwiftUITopLeftRect() {
        let swiftUIRect = CGRect(x: 10, y: 100, width: 200, height: 2)
        let windowRect = SidebarDragLocationMapper.windowRect(
            fromSwiftUITopLeftRect: swiftUIRect,
            topBoundaryY: 600
        )
        XCTAssertEqual(windowRect, CGRect(x: 10, y: 498, width: 200, height: 2))

        // Round trip: the rect's top-left corner maps back to the original point.
        let roundTrip = SidebarDragLocationMapper.swiftUITopLeftPoint(
            windowPoint: CGPoint(x: windowRect.minX, y: windowRect.maxY),
            topBoundaryY: 600
        )
        XCTAssertEqual(roundTrip, CGPoint(x: swiftUIRect.minX, y: swiftUIRect.minY))
    }

    // MARK: - Fixtures

    private func regularGeometry(frame: CGRect, itemCount: Int) -> SidebarGeometrySnapshot {
        regularGeometry(
            frame: frame,
            rowCount: max(0, itemCount)
        )
    }

    private func regularGeometry(
        frame: CGRect,
        rowCount: Int
    ) -> SidebarGeometrySnapshot {
        var geometry = SidebarGeometrySnapshot.empty
        geometry.regularListHitTargets = [
            spaceId: SidebarRegularListHitMetrics(
                frame: frame,
                rowIdentities: (0..<rowCount).map { _ in .tab(UUID()) }
            ),
        ]
        return geometry
    }

    private func pinnedGeometry(itemFrames: [CGRect]) -> SidebarGeometrySnapshot {
        var geometry = SidebarGeometrySnapshot.empty
        let targets = Dictionary(
            uniqueKeysWithValues: itemFrames.enumerated().map { index, frame in
                let itemId = UUID()
                return (
                    itemId,
                    SidebarTopLevelPinnedItemMetrics(
                        itemId: itemId,
                        spaceId: spaceId,
                        topLevelIndex: index,
                        frame: frame
                    )
                )
            }
        )
        geometry.hitTestIndex = SidebarGeometryHitTestIndex(
            topLevelPinnedItemTargets: targets,
            folderDropTargets: [:],
            folderChildDropTargets: [:]
        )
        return geometry
    }

    private func folderGeometry(
        childFrames: [CGRect],
        bodyFrame: CGRect? = nil
    ) -> SidebarGeometrySnapshot {
        var geometry = SidebarGeometrySnapshot.empty
        let childTargets = Dictionary(
            uniqueKeysWithValues: childFrames.enumerated().map { index, frame in
                let childId = UUID()
                return (
                    childId,
                    SidebarFolderChildDropTargetMetrics(
                        childId: childId,
                        folderId: folderId,
                        index: index,
                        frame: frame
                    )
                )
            }
        )
        let folderTargets = [
            folderId: SidebarFolderDropTargetMetrics(
                folderId: folderId,
                spaceId: spaceId,
                parentFolderId: nil,
                topLevelIndex: 0,
                childCount: childFrames.count,
                isOpen: true,
                headerFrame: nil,
                bodyFrame: bodyFrame,
                afterFrame: nil
            ),
        ]
        geometry.folderDropTargets = folderTargets
        geometry.hitTestIndex = SidebarGeometryHitTestIndex(
            topLevelPinnedItemTargets: [:],
            folderDropTargets: folderTargets,
            folderChildDropTargets: childTargets
        )
        return geometry
    }

    private func pinnedLine(slot: Int, geometry: SidebarGeometrySnapshot) -> CGRect? {
        SidebarDropIndicatorGeometry.lineRect(
            slot: .spacePinned(spaceId: spaceId, slot: slot),
            folderIntent: .none,
            geometry: geometry
        )
    }

    private func folderLine(slot: Int, geometry: SidebarGeometrySnapshot) -> CGRect? {
        SidebarDropIndicatorGeometry.lineRect(
            slot: .folder(folderId: folderId, slot: slot),
            folderIntent: .insertIntoFolder(folderId: folderId, index: slot),
            geometry: geometry
        )
    }
}
