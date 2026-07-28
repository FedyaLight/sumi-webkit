@testable import Sumi
import XCTest

final class PresentedSidebarLayoutTests: XCTestCase {
    func testNestedFolderGeometryUsesSemanticIndentAndPresentedSpan() throws {
        let spaceID = UUID()
        let rootFolderID = UUID()
        let nestedFolderID = UUID()
        let childID = UUID()
        let rootFrame = CGRect(x: 100, y: 200, width: 200, height: 200)

        let layout = PresentedSidebarLayout.resolve(
            spaceID: spaceID,
            rootFrame: rootFrame,
            items: [
                item(
                    extent: 36,
                    placement: .folderHeader(
                        folderID: rootFolderID,
                        parentFolderID: nil,
                        containerIndex: 0,
                        childCount: 1,
                        nestingDepth: 0,
                        isOpen: true,
                        acceptsDrop: true,
                        afterRegionHeight: 16.2
                    )
                ),
                item(
                    extent: 4,
                    placement: .folderBodyTop(folderID: rootFolderID)
                ),
                item(
                    extent: 36,
                    placement: .folderHeader(
                        folderID: nestedFolderID,
                        parentFolderID: rootFolderID,
                        containerIndex: 0,
                        childCount: 1,
                        nestingDepth: 1,
                        isOpen: true,
                        acceptsDrop: true,
                        afterRegionHeight: 16.2
                    )
                ),
                item(
                    extent: 4,
                    placement: .folderBodyTop(folderID: nestedFolderID)
                ),
                item(
                    extent: 36,
                    placement: .folderChild(
                        folderID: nestedFolderID,
                        childID: childID,
                        index: 0,
                        nestingDepth: 2,
                        splitPairingMemberIDs: []
                    )
                ),
                item(
                    extent: 4,
                    placement: .folderBodyBottom(folderID: nestedFolderID)
                ),
                item(
                    extent: 4,
                    placement: .folderBodyBottom(folderID: rootFolderID)
                ),
                item(extent: 12, placement: .boundary),
                item(extent: 0, placement: .regularRunStart),
                item(extent: 0, placement: .regularRunEnd),
            ]
        )

        let nested = try XCTUnwrap(
            layout.folderDropTargets[nestedFolderID]
        )
        XCTAssertEqual(
            try XCTUnwrap(nested.headerFrame).minX,
            114,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(nested.headerFrame).width,
            186,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(nested.bodyFrame).minX,
            114,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(nested.bodyFrame).width,
            186,
            accuracy: 0.001
        )

        let deepChild = try XCTUnwrap(
            layout.folderChildDropTargets[childID]
        )
        XCTAssertEqual(deepChild.frame.minX, 128, accuracy: 0.001)
        XCTAssertEqual(deepChild.frame.width, 172, accuracy: 0.001)

        let nestedAsChild = try XCTUnwrap(
            layout.folderChildDropTargets[nestedFolderID]
        )
        XCTAssertEqual(nestedAsChild.frame.minX, 114, accuracy: 0.001)
        XCTAssertEqual(nestedAsChild.frame.height, 80, accuracy: 0.001)

        var geometry = SidebarGeometrySnapshot.empty
        geometry.folderDropTargets = layout.folderDropTargets
        geometry.hitTestIndex = SidebarGeometryHitTestIndex(
            topLevelPinnedItemTargets:
                layout.topLevelPinnedItemTargets,
            folderDropTargets: layout.folderDropTargets,
            folderChildDropTargets: layout.folderChildDropTargets
        )
        let line = try XCTUnwrap(
            SidebarDropIndicatorGeometry.lineRect(
                slot: .folder(folderId: nestedFolderID, slot: 0),
                folderIntent: .insertIntoFolder(
                    folderId: nestedFolderID,
                    index: 0
                ),
                geometry: geometry
            )
        )
        XCTAssertEqual(line.minX, deepChild.frame.minX + 4, accuracy: 0.001)
        XCTAssertEqual(line.width, deepChild.frame.width - 8, accuracy: 0.001)
        XCTAssertEqual(line.midY, deepChild.frame.minY, accuracy: 0.001)
    }

    func testFolderAfterRegionIsCenteredOnPresentedCompositeBottom() throws {
        let folderID = UUID()
        let layout = PresentedSidebarLayout.resolve(
            spaceID: UUID(),
            rootFrame: CGRect(x: 20, y: 40, width: 180, height: 80),
            items: [
                item(
                    extent: 36,
                    placement: .folderHeader(
                        folderID: folderID,
                        parentFolderID: nil,
                        containerIndex: 0,
                        childCount: 0,
                        nestingDepth: 0,
                        isOpen: false,
                        acceptsDrop: true,
                        afterRegionHeight: 16.2
                    )
                ),
                item(extent: 10, placement: .boundary),
                item(extent: 0, placement: .regularRunStart),
                item(extent: 0, placement: .regularRunEnd),
            ]
        )

        let target = try XCTUnwrap(layout.folderDropTargets[folderID])
        let after = try XCTUnwrap(target.afterFrame)
        let composite = try XCTUnwrap(
            layout.topLevelPinnedItemTargets[folderID]
        ).frame

        XCTAssertEqual(after.midY, composite.maxY, accuracy: 0.001)
        XCTAssertEqual(after.minY, composite.maxY - 8.1, accuracy: 0.001)

        var geometry = SidebarGeometrySnapshot.empty
        geometry.folderDropTargets = layout.folderDropTargets
        geometry.hitTestIndex = SidebarGeometryHitTestIndex(
            topLevelPinnedItemTargets:
                layout.topLevelPinnedItemTargets,
            folderDropTargets: layout.folderDropTargets,
            folderChildDropTargets: layout.folderChildDropTargets
        )
        let line = try XCTUnwrap(
            SidebarDropIndicatorGeometry.lineRect(
                slot: .spacePinned(spaceId: layout.spaceID, slot: 1),
                folderIntent: .none,
                geometry: geometry
            )
        )
        XCTAssertEqual(line.midY, after.midY, accuracy: 0.001)
    }

    func testRegularGeometryUsesPresentedExtentDuringTransition() throws {
        let identity = SidebarVisualSceneProjection.RegularRow.Identity.tab(
            UUID()
        )
        let layout = PresentedSidebarLayout.resolve(
            spaceID: UUID(),
            rootFrame: CGRect(x: 30, y: 50, width: 240, height: 100),
            items: [
                item(extent: 14, placement: .boundary),
                item(extent: 0, placement: .regularRunStart),
                item(
                    extent: 18,
                    placement: .regularRow(
                        identity: identity,
                        splitPairingMemberIDs: []
                    ),
                    phase: .entering
                ),
                item(extent: 0, placement: .regularRunEnd),
            ]
        )

        let metrics = try XCTUnwrap(layout.regularListHitTarget)
        XCTAssertEqual(metrics.frame.minY, 64, accuracy: 0.001)
        XCTAssertEqual(metrics.frame.height, 18, accuracy: 0.001)
        XCTAssertEqual(
            try XCTUnwrap(metrics.rowFrame(at: 0)).height,
            18,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(layout.sectionFrames[.spaceRegular]).minY,
            50,
            accuracy: 0.001
        )
    }

    func testFolderTrailingGapAdvancesTrackWithoutExpandingDropTarget() throws {
        let folderID = UUID()
        let layout = PresentedSidebarLayout.resolve(
            spaceID: UUID(),
            rootFrame: CGRect(x: 0, y: 100, width: 200, height: 100),
            items: [
                item(
                    extent: SidebarRowLayout.rowHeight,
                    placement: .folderHeader(
                        folderID: folderID,
                        parentFolderID: nil,
                        containerIndex: 0,
                        childCount: 0,
                        nestingDepth: 0,
                        isOpen: true,
                        acceptsDrop: true,
                        afterRegionHeight: 16
                    )
                ),
                item(
                    extent: SidebarRowLayout.folderBodyPadding,
                    placement: .folderBodyTop(folderID: folderID)
                ),
                item(
                    extent: SidebarRowLayout.folderBodyPadding
                        + SidebarRowLayout.rowGap,
                    placement: .folderBodyBottom(folderID: folderID)
                ),
                item(extent: 0, placement: .boundary),
                item(extent: 0, placement: .regularRunStart),
                item(extent: 0, placement: .regularRunEnd),
            ]
        )

        let composite = try XCTUnwrap(
            layout.topLevelPinnedItemTargets[folderID]
        ).frame
        XCTAssertEqual(
            composite.height,
            SidebarRowLayout.rowHeight
                + (SidebarRowLayout.folderBodyPadding * 2),
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(layout.sectionFrames[.spacePinned]).height,
            composite.height + SidebarRowLayout.rowGap,
            accuracy: 0.001
        )
    }

    private func item(
        extent: CGFloat,
        placement: PresentedSidebarElementPlacement,
        phase: SidebarListElementPhase = .stable
    ) -> PresentedSidebarLayout.Item {
        PresentedSidebarLayout.Item(
            extent: extent,
            phase: phase,
            placement: placement
        )
    }
}
