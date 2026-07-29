import CoreGraphics
import Foundation
import XCTest

@testable import Sumi

final class EmptyPinnedDropIndicatorTests: XCTestCase {
    private let spaceID = UUID()

    func testEmptyPinnedSectionDrawsLineOnSeparator() throws {
        let sectionTop: CGFloat = 120
        let geometry = emptyPinnedGeometry(
            sectionTop: sectionTop,
            width: 240,
            regularRowCount: 3
        )

        let line = try XCTUnwrap(pinnedLine(geometry: geometry))
        XCTAssertEqual(
            line.midY,
            sectionTop + SpaceTabSectionBoundaryLayout.emptyPinnedTopPadding,
            accuracy: 0.001
        )
        XCTAssertEqual(
            line.height,
            SidebarDropIndicatorGeometry.Metrics.lineHeight
        )
        XCTAssertEqual(
            line.minX,
            12 + SidebarDropIndicatorGeometry.Metrics.horizontalInset
        )
        XCTAssertEqual(
            line.width,
            240 - (2 * SidebarDropIndicatorGeometry.Metrics.horizontalInset)
        )
    }

    func testEmptyPinnedSectionWithoutSeparatorHidesLine() {
        XCTAssertNil(
            pinnedLine(geometry: emptyPinnedGeometry(
                sectionTop: 120,
                width: 240,
                regularRowCount: 0
            ))
        )
    }

    func testEmptyPinnedSectionWithoutBoundaryExtentHidesLine() {
        let sectionTop: CGFloat = 120
        var geometry = emptyPinnedGeometry(
            sectionTop: sectionTop,
            width: 240,
            regularRowCount: 3
        )
        geometry.regularListHitTargets[spaceID] = regularMetrics(
            frame: CGRect(
                x: 12,
                y: sectionTop,
                width: 240,
                height: 3 * SidebarRowLayout.rowPitch
            ),
            rowCount: 3
        )

        XCTAssertNil(pinnedLine(geometry: geometry))
    }

    func testPopulatedPinnedSectionIgnoresSeparatorFallback() throws {
        let itemFrame = CGRect(x: 12, y: 60, width: 240, height: 36)
        let itemID = UUID()
        var geometry = SidebarGeometrySnapshot.empty
        geometry.hitTestIndex = SidebarGeometryHitTestIndex(
            topLevelPinnedItemTargets: [
                itemID: SidebarTopLevelPinnedItemMetrics(
                    itemId: itemID,
                    spaceId: spaceID,
                    topLevelIndex: 0,
                    frame: itemFrame
                ),
            ],
            folderDropTargets: [:],
            folderChildDropTargets: [:]
        )
        geometry.sectionFramesBySpace[
            SidebarSectionGeometryKey(spaceId: spaceID, section: .spacePinned)
        ] = itemFrame

        let line = try XCTUnwrap(pinnedLine(geometry: geometry))
        XCTAssertEqual(line.midY, itemFrame.minY, accuracy: 0.001)
    }

    private func emptyPinnedGeometry(
        sectionTop: CGFloat,
        width: CGFloat,
        regularRowCount: Int
    ) -> SidebarGeometrySnapshot {
        var geometry = SidebarGeometrySnapshot.empty
        let regularFrame = CGRect(
            x: 12,
            y: sectionTop
                + SpaceTabSectionBoundaryLayout.emptyPinnedTopPadding
                + SpaceTabSectionBoundaryLayout.hairlineHeight
                + SpaceTabSectionBoundaryLayout.separatorPadding,
            width: width,
            height: CGFloat(regularRowCount) * SidebarRowLayout.rowPitch
        )
        geometry.regularListHitTargets[spaceID] = regularMetrics(
            frame: regularFrame,
            rowCount: regularRowCount
        )
        geometry.sectionFramesBySpace[
            SidebarSectionGeometryKey(spaceId: spaceID, section: .spacePinned)
        ] = CGRect(x: 12, y: sectionTop, width: width, height: 0)
        return geometry
    }

    private func regularMetrics(
        frame: CGRect,
        rowCount: Int
    ) -> SidebarRegularListHitMetrics {
        SidebarRegularListHitMetrics(
            frame: frame,
            rowIdentities: (0..<rowCount).map { _ in .tab(UUID()) }
        )
    }

    private func pinnedLine(geometry: SidebarGeometrySnapshot) -> CGRect? {
        SidebarDropIndicatorGeometry.lineRect(
            slot: .spacePinned(spaceId: spaceID, slot: 0),
            folderIntent: .none,
            geometry: geometry
        )
    }
}
