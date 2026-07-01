import CoreGraphics
import XCTest

@testable import Sumi

@MainActor
final class SidebarDragGeometryRepositoryTests: XCTestCase {
    func testDeferredMutationsCoalesceByGeometryKeyBeforePublishing() {
        let repository = SidebarDragGeometryRepository()
        let spaceId = UUID()
        let key = SidebarSectionGeometryKey(spaceId: spaceId, section: .spaceRegular)
        let firstFrame = CGRect(x: 0, y: 10, width: 200, height: 40)
        let latestFrame = CGRect(x: 0, y: 20, width: 200, height: 44)

        repository.scheduleSectionFrame(
            spaceId: spaceId,
            section: .spaceRegular,
            frame: firstFrame,
            generation: repository.activeGeometryGeneration
        )
        repository.scheduleSectionFrame(
            spaceId: spaceId,
            section: .spaceRegular,
            frame: latestFrame,
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

        repository.scheduleSectionFrame(
            spaceId: spaceId,
            section: .spaceRegular,
            frame: frame,
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

        repository.scheduleSectionFrame(
            spaceId: spaceId,
            section: .spaceRegular,
            frame: CGRect(x: 0, y: 20, width: 200, height: 44),
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

        repository.scheduleSectionFrame(
            spaceId: spaceId,
            section: .spaceRegular,
            frame: firstFrame,
            generation: repository.activeGeometryGeneration
        )
        repository.scheduleSectionFrame(
            spaceId: spaceId,
            section: .spaceRegular,
            frame: latestFrame,
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
        repository.applySectionFrame(
            spaceId: spaceId,
            section: .essentials,
            frame: CGRect(x: 0, y: 0, width: 300, height: 140),
            generation: pendingGeneration
        )
        repository.applySectionFrame(
            spaceId: spaceId,
            section: .spacePinned,
            frame: CGRect(x: 0, y: 140, width: 300, height: 180),
            generation: pendingGeneration
        )
        repository.applySectionFrame(
            spaceId: spaceId,
            section: .spaceRegular,
            frame: CGRect(x: 0, y: 320, width: 300, height: 260),
            generation: pendingGeneration
        )
        repository.applyEssentialsLayoutMetrics(
            SidebarEssentialsLayoutUpdate(
                spaceId: spaceId,
                input: SidebarEssentialsLayoutMetricsInput(
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

        repository.applyRegularListHitTarget(
            spaceId: spaceId,
            frame: CGRect(x: 0, y: 320, width: 300, height: 260),
            itemCount: 6,
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
        XCTAssertEqual(repository.geometrySnapshot.regularListHitTargets[spaceId]?.itemCount, 6)
    }

    func testScrollDeltaMutatesActiveSnapshotAndRevisionImmediately() {
        let repository = SidebarDragGeometryRepository()
        let spaceId = UUID()
        let itemId = UUID()
        let generation = repository.activeGeometryGeneration

        repository.applyTopLevelPinnedItemTarget(
            SidebarTopLevelPinnedItemTargetUpdate(
                metrics: SidebarTopLevelPinnedItemMetrics(
                    itemId: itemId,
                    spaceId: spaceId,
                    topLevelIndex: 0,
                    frame: CGRect(x: 0, y: 50, width: 220, height: 36)
                )
            ),
            generation: generation
        )
        repository.applyRegularListHitTarget(
            spaceId: spaceId,
            frame: CGRect(x: 0, y: 120, width: 220, height: 200),
            itemCount: 3,
            generation: generation
        )
        repository.flushDeferredGeometryForDragStart()

        let revisionBeforeScroll = repository.geometryRevision
        repository.adjustGeometryStoreScrollDelta(deltaY: 12)

        XCTAssertEqual(repository.geometrySnapshot.topLevelPinnedItemTargets[itemId]?.frame.origin.y, 38)
        XCTAssertEqual(repository.geometrySnapshot.regularListHitTargets[spaceId]?.frame.origin.y, 108)
        XCTAssertEqual(repository.geometryRevision, revisionBeforeScroll + 1)
    }
}

private func drainMainQueue() async {
    await Task.yield()
    await Task.yield()
}
