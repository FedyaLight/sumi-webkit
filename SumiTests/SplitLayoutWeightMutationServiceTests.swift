import Combine
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class SplitLayoutWeightMutationServiceTests: XCTestCase {
    func testWeightUpdateUsesLayoutOnlyStoreAndPresentationChannels() throws {
        let tabManager = BrowserManager()
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
        windows.forEach { tabManager.windowRegistry.register($0) }
        let firstCompositorVersion = firstWindow.compositorInvalidation.compositorVersion
        let secondCompositorVersion = secondWindow.compositorInvalidation.compositorVersion
        let unrelatedCompositorVersion = unrelatedWindow.compositorInvalidation.compositorVersion
        let firstUpdate = tabManager.splitUpdateChannel.stream
            .updates(for: firstWindow.id).sink { probe.publishedWindowIDs.append(firstWindow.id) }
        let secondUpdate = tabManager.splitUpdateChannel.stream
            .updates(for: secondWindow.id).sink { probe.publishedWindowIDs.append(secondWindow.id) }
        let unrelatedUpdate = tabManager.splitUpdateChannel.stream
            .updates(for: unrelatedWindow.id).sink { probe.publishedWindowIDs.append(unrelatedWindow.id) }
        let service = makeLayoutService(tabManager: tabManager)
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
        XCTAssertEqual(tabManager.windowSessionPersistenceCoordinator.flush(), 0)
        XCTAssertEqual(
            Set(probe.publishedWindowIDs),
            Set([firstWindow.id, secondWindow.id])
        )
        XCTAssertEqual(firstWindow.compositorInvalidation.compositorVersion, firstCompositorVersion + 1)
        XCTAssertEqual(secondWindow.compositorInvalidation.compositorVersion, secondCompositorVersion + 1)
        XCTAssertEqual(unrelatedWindow.compositorInvalidation.compositorVersion, unrelatedCompositorVersion)
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
        _ = [firstUpdate, secondUpdate, unrelatedUpdate]
    }

    func testStaleWeightSnapshotIsRejectedWithoutDirtyingOrRefreshing() throws {
        let tabManager = BrowserManager()
        let original = try makeGroup()
        tabManager.splitGroupStore.replaceAll(with: [original])
        let mutation = SplitLayoutWeightMutationService(
            splitGroups: tabManager.splitGroupStore,
            persistence: tabManager.structuralPersistence
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
        tabManager: BrowserManager
    ) -> SplitLayoutService {
        return SplitLayoutService(
            topology: SplitLayoutTopologyTransaction(
                splitGroups: tabManager.splitGroupStore,
                mutations: tabManager.splitGroupMutations,
                regularTabs: tabManager.regularTabCollectionOwner
            ),
            query: WindowSplitQuery(
                splitGroups: tabManager.splitGroupStore,
                regularTabs: tabManager.regularTabCollectionOwner,
                pins: tabManager.shortcutPinCollectionStateOwner,
                liveShortcuts: tabManager.liveShortcutTabs,
                windows: tabManager.windowRegistry,
                previewIsActive: { _ in false }
            ),
            weightMutations: SplitLayoutWeightMutationService(
                splitGroups: tabManager.splitGroupStore,
                persistence: tabManager.structuralPersistence
            ),
            presentations: tabManager.splitPresentations,
            dissolution: SplitGroupDissolutionService(
                splitGroups: tabManager.splitGroupStore,
                mutations: tabManager.splitGroupMutations,
                presentations: tabManager.splitPresentations
            )
        )
    }
}

@MainActor
private final class LayoutChannelProbe {
    var structureEvents = 0
    var publishedWindowIDs: [UUID] = []
}
