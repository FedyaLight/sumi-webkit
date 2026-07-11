import Combine
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class SplitLayoutWeightMutationServiceTests: XCTestCase {
    func testWeightUpdateUsesLayoutOnlyStoreAndPresentationChannels() throws {
        let tabManager = try makeInMemoryTabManager()
        let original = try makeGroup()
        tabManager.splitGroupStore.replaceAll(with: [original])
        tabManager.structuralPersistence.resetDirtySet()
        tabManager.structuralPersistence.cancelPendingPersistence()

        let firstWindow = selectedWindow(original)
        let secondWindow = selectedWindow(original)
        let unrelatedWindow = BrowserWindowState()
        unrelatedWindow.splitSelection = WindowSplitSelection(
            groupID: UUID(),
            activeMemberID: .regularTab(UUID())
        )
        let windows = [firstWindow, secondWindow, unrelatedWindow]
        let probe = LayoutChannelProbe()
        let service = makeLayoutService(
            tabManager: tabManager,
            windows: windows,
            probe: probe
        )
        let eventObservation = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink {
                probe.structureEvents += 1
            }

        service.updateWeights(
            expectedGroup: original,
            path: [],
            weights: [0.25, 0.75],
            in: firstWindow.id
        )

        let expectedTree = SplitLayoutSizing.updatingChildWeights(
            in: original.layoutTree,
            at: [],
            weights: [0.25, 0.75]
        )
        let replacement = try XCTUnwrap(
            original.replacingLayoutTree(with: expectedTree)
        )
        XCTAssertEqual(tabManager.splitGroupStore.groups, [replacement])
        XCTAssertEqual(tabManager.splitGroupStore.index(of: original.id), 0)
        for memberID in original.memberIDs {
            XCTAssertEqual(
                tabManager.splitGroupStore.group(containing: memberID),
                replacement
            )
        }
        XCTAssertEqual(probe.structureEvents, 0)
        XCTAssertEqual(probe.windowSessionWrites, 0)
        XCTAssertEqual(probe.selectionWrites, 0)
        XCTAssertEqual(
            Set(probe.publishedWindowIDs),
            Set([firstWindow.id, secondWindow.id])
        )
        XCTAssertEqual(
            Set(probe.refreshedWindowIDs),
            Set([firstWindow.id, secondWindow.id])
        )
        XCTAssertTrue(
            tabManager.structuralPersistence.dirtySet.splitGroupsDirty
        )
        XCTAssertNotNil(
            tabManager.structuralPersistence.scheduledPersistTask
        )
        XCTAssertEqual(firstWindow.splitSelection?.groupID, original.id)
        XCTAssertEqual(secondWindow.splitSelection?.groupID, original.id)
        tabManager.structuralPersistence.cancelPendingPersistence()
        _ = eventObservation
    }

    func testStaleWeightSnapshotIsRejectedWithoutDirtyingOrRefreshing() throws {
        let tabManager = try makeInMemoryTabManager()
        let original = try makeGroup()
        tabManager.splitGroupStore.replaceAll(with: [original])
        let mutation = SplitLayoutWeightMutationService(
            tabManager: { tabManager }
        )
        XCTAssertTrue(mutation.update(
            expectedGroup: original,
            path: [],
            weights: [0.3, 0.7]
        ))
        let committed = try XCTUnwrap(
            tabManager.splitGroupStore.group(id: original.id)
        )
        tabManager.structuralPersistence.cancelPendingPersistence()
        tabManager.structuralPersistence.resetDirtySet()

        XCTAssertFalse(mutation.update(
            expectedGroup: original,
            path: [],
            weights: [0.4, 0.6]
        ))

        XCTAssertEqual(
            tabManager.splitGroupStore.group(id: original.id),
            committed
        )
        XCTAssertTrue(tabManager.structuralPersistence.dirtySet.isEmpty)
        XCTAssertNil(tabManager.structuralPersistence.scheduledPersistTask)
    }

    private func makeGroup() throws -> SumiDomain.SplitGroup {
        try XCTUnwrap(SumiDomain.SplitGroup.make(
            members: [
                .regularTab(UUID()),
                .regularTab(UUID()),
            ],
            layoutKind: .vertical
        ))
    }

    private func selectedWindow(
        _ group: SumiDomain.SplitGroup
    ) -> BrowserWindowState {
        let windowState = BrowserWindowState()
        windowState.splitSelection = WindowSplitSelection(
            groupID: group.id,
            activeMemberID: group.memberIDs[0]
        )
        return windowState
    }

    private func makeLayoutService(
        tabManager: TabManager,
        windows: [BrowserWindowState],
        probe: LayoutChannelProbe
    ) -> SplitLayoutService {
        let windowsByID = Dictionary(
            uniqueKeysWithValues: windows.map { ($0.id, $0) }
        )
        let presentations = WindowSplitPresentationSynchronizer(
            tabManager: { tabManager },
            windows: { windows },
            selectTabWithoutPersistence: { _, _ in
                probe.selectionWrites += 1
            },
            publishWindowChange: {
                probe.publishedWindowIDs.append($0)
            },
            refreshCompositor: {
                probe.refreshedWindowIDs.append($0.id)
            },
            scheduleWindowSession: { _ in
                probe.windowSessionWrites += 1
            },
            persistWindowSession: { _ in
                probe.windowSessionWrites += 1
            }
        )
        let launcherPlacement = ShortcutSplitLauncherPlacementService(
            tabManager: { tabManager }
        )
        return SplitLayoutService(
            tabManager: { tabManager },
            query: WindowSplitQuery(
                tabManager: { tabManager },
                windowState: { windowsByID[$0] },
                previewIsActive: { _ in false }
            ),
            weightMutations: SplitLayoutWeightMutationService(
                tabManager: { tabManager }
            ),
            presentations: presentations,
            dissolution: SplitGroupDissolutionService(
                tabManager: { tabManager },
                launcherPlacement: launcherPlacement,
                presentations: presentations
            ),
            launcherPlacement: launcherPlacement,
            restoreShortcutMember: { _, _, _ in false }
        )
    }
}

@MainActor
private final class LayoutChannelProbe {
    var structureEvents = 0
    var selectionWrites = 0
    var windowSessionWrites = 0
    var publishedWindowIDs: [UUID] = []
    var refreshedWindowIDs: [UUID] = []
}
