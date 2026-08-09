import CoreGraphics
import XCTest

@testable import Sumi

@MainActor
final class SidebarDragGeometryRepositoryTests: XCTestCase {
    func testPublishedSnapshotDoesNotDuplicateIndexedItemMetrics() {
        let storedFieldNames = Set(
            Mirror(reflecting: SidebarGeometrySnapshot.empty).children.compactMap(\.label)
        )

        XCTAssertFalse(storedFieldNames.contains("topLevelPinnedItemTargets"))
        XCTAssertFalse(storedFieldNames.contains("folderChildDropTargets"))
    }

    func testRuntimeStoreKeepsOneAtomicListLayoutPerSpace() {
        let storedFieldNames = Set(
            Mirror(reflecting: SidebarRuntimeGeometryStore())
                .children.compactMap(\.label)
        )

        XCTAssertTrue(storedFieldNames.contains("spaceListLayoutsBySpace"))
        XCTAssertFalse(storedFieldNames.contains("topLevelPinnedItemTargets"))
        XCTAssertFalse(storedFieldNames.contains("folderDropTargets"))
        XCTAssertFalse(storedFieldNames.contains("folderChildDropTargets"))
        XCTAssertFalse(storedFieldNames.contains("pinnedListHitTargets"))
        XCTAssertFalse(storedFieldNames.contains("regularListHitTargets"))
    }

    func testDeferredMutationsCoalesceByGeometryKeyBeforePublishing() {
        let repository = SidebarDragGeometryRepository()
        let spaceId = UUID()
        let key = SidebarSectionGeometryKey(spaceId: spaceId, section: .spaceRegular)
        let firstFrame = CGRect(x: 0, y: 10, width: 200, height: 40)
        let latestFrame = CGRect(x: 0, y: 20, width: 200, height: 44)

        repository.schedulePresentedSpaceList(
            presentedLayout(
                spaceID: spaceId,
                pinnedFrame: .zero,
                regularFrame: firstFrame,
                regularRowCount: 0
            ),
            generation: repository.activeGeometryGeneration
        )
        repository.schedulePresentedSpaceList(
            presentedLayout(
                spaceID: spaceId,
                pinnedFrame: .zero,
                regularFrame: latestFrame,
                regularRowCount: 0
            ),
            generation: repository.activeGeometryGeneration
        )

        repository.flushDeferredGeometryForDragStart()

        XCTAssertEqual(repository.geometrySnapshot.sectionFramesBySpace[key], latestFrame)
    }

    func testDragStartFlushDrainsPendingRefreshAfterSnapshotPublish() {
        var events: [String] = []
        let repository = SidebarDragGeometryRepository(
            publishSnapshot: { snapshot in
                events.append("snapshot:\(!snapshot.sectionFramesBySpace.isEmpty)")
            },
            publishRevision: { revision in
                events.append("revision:\(revision)")
            }
        )
        let spaceId = UUID()
        let key = SidebarSectionGeometryKey(spaceId: spaceId, section: .spaceRegular)
        let frame = CGRect(x: 0, y: 20, width: 200, height: 44)

        repository.schedulePresentedSpaceList(
            presentedLayout(
                spaceID: spaceId,
                pinnedFrame: .zero,
                regularFrame: frame,
                regularRowCount: 0
            ),
            generation: repository.activeGeometryGeneration
        )
        repository.requestGeometryRefresh()

        repository.flushDeferredGeometryForDragStart()

        XCTAssertEqual(repository.geometrySnapshot.sectionFramesBySpace[key], frame)
        XCTAssertEqual(repository.geometryRevision, 1)
        XCTAssertEqual(events, ["snapshot:true", "revision:1"])
    }

    func testQueuedAsyncDrainDoesNotRepublishAfterSynchronousDragStartFlush() async {
        var snapshotPublishCount = 0
        var revisionPublishCount = 0
        let repository = SidebarDragGeometryRepository(
            publishSnapshot: { _ in snapshotPublishCount += 1 },
            publishRevision: { _ in revisionPublishCount += 1 }
        )
        let spaceId = UUID()

        repository.schedulePresentedSpaceList(
            presentedLayout(
                spaceID: spaceId,
                pinnedFrame: .zero,
                regularFrame: CGRect(
                    x: 0,
                    y: 20,
                    width: 200,
                    height: 44
                ),
                regularRowCount: 0
            ),
            generation: repository.activeGeometryGeneration
        )
        repository.requestGeometryRefresh()
        repository.flushDeferredGeometryForDragStart()

        await drainMainQueue()

        XCTAssertEqual(snapshotPublishCount, 1)
        XCTAssertEqual(revisionPublishCount, 1)
    }

    func testMutationSnapshotAndRefreshCoalesceIntoOneMainTurnDrain() async {
        var events: [String] = []
        let repository = SidebarDragGeometryRepository(
            publishSnapshot: { _ in events.append("snapshot") },
            publishRevision: { revision in events.append("revision:\(revision)") }
        )
        let spaceId = UUID()
        let key = SidebarSectionGeometryKey(spaceId: spaceId, section: .spaceRegular)
        let firstFrame = CGRect(x: 0, y: 10, width: 200, height: 40)
        let latestFrame = CGRect(x: 0, y: 20, width: 200, height: 44)

        repository.schedulePresentedSpaceList(
            presentedLayout(
                spaceID: spaceId,
                pinnedFrame: .zero,
                regularFrame: firstFrame,
                regularRowCount: 0
            ),
            generation: repository.activeGeometryGeneration
        )
        repository.schedulePresentedSpaceList(
            presentedLayout(
                spaceID: spaceId,
                pinnedFrame: .zero,
                regularFrame: latestFrame,
                regularRowCount: 0
            ),
            generation: repository.activeGeometryGeneration
        )
        repository.requestGeometryRefresh()

        await drainMainQueue()

        XCTAssertEqual(repository.geometrySnapshot.sectionFramesBySpace[key], latestFrame)
        XCTAssertEqual(repository.geometryRevision, 1)
        XCTAssertEqual(events, ["snapshot", "revision:1"])
    }

    func testPendingEpochPromotesOnlyAfterRequiredInteractiveGeometryArrives() throws {
        let repository = SidebarDragGeometryRepository()
        let spaceId = UUID()
        let profileId = UUID()

        repository.beginPendingGeometryEpoch(expectedSpaceId: spaceId, profileId: profileId)
        let pendingGeneration = try XCTUnwrap(repository.pendingGeometryGeneration)

        repository.applyPageGeometry(
            spaceId: spaceId,
            profileId: profileId,
            frame: CGRect(x: 0, y: 0, width: 300, height: 600),
            renderMode: .interactive,
            generation: pendingGeneration
        )
        repository.applyFavoriteLayoutMetrics(
            SidebarFavoriteLayoutUpdate(
                spaceId: spaceId,
                input: SidebarFavoriteLayoutMetricsInput(
                    profileId: profileId,
                    frame: CGRect(x: 0, y: 0, width: 300, height: 140),
                    dropFrame: CGRect(x: 0, y: 0, width: 300, height: 180),
                    itemCount: 4,
                    columnCount: 2,
                    rowCount: 2,
                    itemSize: CGSize(width: 96, height: 48),
                    gridSpacing: 8,
                    canAcceptDrop: true,
                    visibleItemCount: 4,
                    visibleRowCount: 2,
                    maxDropRowCount: 3
                )
            ),
            generation: pendingGeneration
        )

        XCTAssertEqual(repository.activeGeometryGeneration, 0)
        XCTAssertEqual(repository.pendingGeometryGeneration, pendingGeneration)

        repository.applyPresentedSpaceList(
            presentedLayout(
                spaceID: spaceId,
                pinnedFrame: CGRect(
                    x: 0,
                    y: 140,
                    width: 300,
                    height: 180
                ),
                regularFrame: CGRect(
                    x: 0,
                    y: 320,
                    width: 300,
                    height: 260
                ),
                regularRowCount: 6
            ),
            generation: pendingGeneration
        )
        repository.flushDeferredGeometryForDragStart()

        XCTAssertEqual(repository.activeGeometryGeneration, pendingGeneration)
        XCTAssertNil(repository.pendingGeometryGeneration)
        XCTAssertEqual(
            repository.geometrySnapshot.pageGeometryByKey[
                SidebarPageGeometryKey(spaceId: spaceId, profileId: profileId)
            ]?.renderMode,
            .interactive
        )
        XCTAssertEqual(repository.geometrySnapshot.regularListHitTargets[spaceId]?.rowCount, 6)
    }

    func testScrollDeltaKeepsBaseFramesAndPublishesOneSnapshotAndRevision() {
        var snapshotPublishCount = 0
        var revisionPublishCount = 0
        let repository = SidebarDragGeometryRepository(
            publishSnapshot: { _ in snapshotPublishCount += 1 },
            publishRevision: { _ in revisionPublishCount += 1 }
        )
        let spaceId = UUID()
        let itemId = UUID()
        let regularRowIdentities = (0..<3).map { _ in
            SidebarVisualSceneProjection.RegularRow.Identity.tab(UUID())
        }
        let generation = repository.activeGeometryGeneration

        repository.applyPresentedSpaceList(
            presentedLayout(
                spaceID: spaceId,
                pinnedFrame: CGRect(x: 0, y: 50, width: 220, height: 36),
                topLevelTargets: [
                    itemId: SidebarTopLevelPinnedItemMetrics(
                    itemId: itemId,
                    spaceId: spaceId,
                    topLevelIndex: 0,
                    frame: CGRect(x: 0, y: 50, width: 220, height: 36)
                    ),
                ],
                regularFrame: CGRect(x: 0, y: 120, width: 220, height: 200),
                regularRowIdentities: regularRowIdentities
            ),
            generation: generation
        )
        repository.flushDeferredGeometryForDragStart()

        let revisionBeforeScroll = repository.geometryRevision
        let structuralRevisionBeforeScroll = repository.geometrySnapshot.structuralRevision
        snapshotPublishCount = 0
        revisionPublishCount = 0
        repository.adjustGeometryStoreScrollDelta(deltaY: 12)

        XCTAssertEqual(
            repository.geometrySnapshot.hitTestIndex
                .topLevelPinnedItemsBySpace[spaceId]?.first(where: { $0.itemId == itemId })?
                .frame.origin.y,
            50
        )
        XCTAssertEqual(repository.geometrySnapshot.regularListHitTargets[spaceId]?.frame.origin.y, 120)
        XCTAssertEqual(repository.geometrySnapshot.cumulativeScrollDeltaY, 12)
        XCTAssertEqual(repository.geometrySnapshot.structuralRevision, structuralRevisionBeforeScroll)
        XCTAssertEqual(repository.geometrySnapshot.scrollRevision, 1)
        XCTAssertEqual(repository.geometryRevision, revisionBeforeScroll + 1)
        XCTAssertEqual(snapshotPublishCount, 1)
        XCTAssertEqual(revisionPublishCount, 1)

        repository.applyPresentedSpaceList(
            presentedLayout(
                spaceID: spaceId,
                pinnedFrame: CGRect(x: 0, y: 38, width: 220, height: 36),
                topLevelTargets: [
                    itemId: SidebarTopLevelPinnedItemMetrics(
                    itemId: itemId,
                    spaceId: spaceId,
                    topLevelIndex: 0,
                    frame: CGRect(x: 0, y: 38, width: 220, height: 36)
                    ),
                ],
                regularFrame: CGRect(x: 0, y: 108, width: 220, height: 200),
                regularRowIdentities: regularRowIdentities
            ),
            generation: generation
        )
        repository.flushDeferredGeometryForDragStart()
        XCTAssertEqual(
            repository.geometrySnapshot.hitTestIndex
                .topLevelPinnedItemsBySpace[spaceId]?.first(where: { $0.itemId == itemId })?
                .frame.origin.y,
            50
        )
        XCTAssertEqual(repository.geometrySnapshot.structuralRevision, structuralRevisionBeforeScroll)

        repository.adjustGeometryStoreScrollDelta(deltaY: -7)
        repository.adjustGeometryStoreScrollDelta(deltaY: -5)

        XCTAssertEqual(repository.geometrySnapshot.cumulativeScrollDeltaY, 0)
        XCTAssertEqual(repository.geometrySnapshot.structuralRevision, structuralRevisionBeforeScroll)
        XCTAssertEqual(repository.geometrySnapshot.scrollRevision, 3)
        XCTAssertEqual(
            repository.geometrySnapshot.hitTestIndex
                .topLevelPinnedItemsBySpace[spaceId]?.first(where: { $0.itemId == itemId })?
                .frame.origin.y,
            50
        )
        XCTAssertEqual(repository.geometrySnapshot.regularListHitTargets[spaceId]?.frame.origin.y, 120)
    }

    func testPresentedSpaceListAtomicallyReplacesStaleFolderGeometry() {
        var publishedSnapshots: [SidebarGeometrySnapshot] = []
        let repository = SidebarDragGeometryRepository(
            publishSnapshot: { publishedSnapshots.append($0) }
        )
        let spaceID = UUID()
        let folderID = UUID()
        let childID = UUID()
        let pinnedFrame = CGRect(x: 0, y: 20, width: 220, height: 80)
        let regularFrame = CGRect(x: 0, y: 100, width: 220, height: 120)
        let folderTarget = SidebarFolderDropTargetMetrics(
            folderId: folderID,
            spaceId: spaceID,
            parentFolderId: nil,
            topLevelIndex: 0,
            childCount: 1,
            isOpen: true,
            headerFrame: CGRect(x: 0, y: 20, width: 220, height: 36),
            bodyFrame: CGRect(x: 0, y: 56, width: 220, height: 44),
            afterFrame: nil
        )
        let childTarget = SidebarFolderChildDropTargetMetrics(
            childId: childID,
            spaceId: spaceID,
            folderId: folderID,
            index: 0,
            frame: CGRect(x: 14, y: 60, width: 206, height: 36)
        )

        let folderLayout = PresentedSidebarLayout(
            spaceID: spaceID,
            sectionFrames: [
                .spacePinned: pinnedFrame,
                .spaceRegular: regularFrame,
            ],
            topLevelPinnedItemTargets: [:],
            folderDropTargets: [folderID: folderTarget],
            folderChildDropTargets: [childID: childTarget],
            pinnedListHitTarget: nil,
            regularListHitTarget: SidebarRegularListHitMetrics(
                frame: regularFrame,
                rowIdentities: []
            )
        )
        repository.applyPresentedSpaceList(
            folderLayout,
            generation: repository.activeGeometryGeneration
        )
        repository.flushDeferredGeometryForDragStart()

        repository.applyPresentedSpaceList(
            presentedLayout(
                spaceID: spaceID,
                pinnedFrame: pinnedFrame,
                regularFrame: regularFrame,
                regularRowCount: 0
            ),
            generation: repository.activeGeometryGeneration
        )
        repository.flushDeferredGeometryForDragStart()

        XCTAssertEqual(publishedSnapshots.count, 2)
        XCTAssertNil(
            repository.geometrySnapshot.folderDropTargets[folderID]
        )
        XCTAssertNil(
            repository.geometrySnapshot.hitTestIndex
                .folderChildrenByFolder[folderID]
        )

        repository.applyPresentedSpaceList(
            folderLayout,
            generation: repository.activeGeometryGeneration
        )
        repository.flushDeferredGeometryForDragStart()
        repository.applyPresentedSpaceListRemoval(
            spaceID: spaceID,
            generation: repository.activeGeometryGeneration
        )
        repository.flushDeferredGeometryForDragStart()

        XCTAssertEqual(publishedSnapshots.count, 4)
        XCTAssertFalse(
            repository.geometrySnapshot.sectionFramesBySpace.keys.contains {
                $0.spaceId == spaceID
                    && ($0.section == .spacePinned || $0.section == .spaceRegular)
            }
        )
        XCTAssertNil(repository.geometrySnapshot.regularListHitTargets[spaceID])
        XCTAssertNil(
            repository.geometrySnapshot.hitTestIndex
                .folderChildrenByFolder[folderID]
        )
    }
}

private func presentedLayout(
    spaceID: UUID,
    pinnedFrame: CGRect,
    topLevelTargets: [UUID: SidebarTopLevelPinnedItemMetrics] = [:],
    regularFrame: CGRect,
    regularRowCount: Int? = nil,
    regularRowIdentities: [
        SidebarVisualSceneProjection.RegularRow.Identity
    ]? = nil
) -> PresentedSidebarLayout {
    let rowIdentities = regularRowIdentities
        ?? (0..<(regularRowCount ?? 0)).map { _ in .tab(UUID()) }
    return PresentedSidebarLayout(
        spaceID: spaceID,
        sectionFrames: [
            .spacePinned: pinnedFrame,
            .spaceRegular: regularFrame,
        ],
        topLevelPinnedItemTargets: topLevelTargets,
        folderDropTargets: [:],
        folderChildDropTargets: [:],
        pinnedListHitTarget: nil,
        regularListHitTarget: SidebarRegularListHitMetrics(
            frame: regularFrame,
            rowIdentities: rowIdentities
        )
    )
}

private func drainMainQueue() async {
    await Task.yield()
    await Task.yield()
}
