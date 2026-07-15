import Combine
import XCTest

@testable import Sumi

@MainActor
final class ShortcutTabBindingSynchronizerTests: XCTestCase {
    func testRefreshMovesRuntimeBindingWithoutSwitchingBackgroundWindowSpace() throws {
        let window = BrowserWindowState()
        let tabManager = try makeInMemoryTabManager(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] }
        )
        window.tabManager = tabManager
        let sourceSpace = tabManager.spaceServices.catalog.createSpace(name: "Source")
        let visibleSpace = tabManager.spaceServices.catalog.createSpace(name: "Visible")
        let targetSpace = tabManager.spaceServices.catalog.createSpace(name: "Target")
        let source = makePin(spaceId: sourceSpace.id)
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            source,
            in: window.id,
            currentSpaceId: sourceSpace.id
        )!
        window.currentSpaceId = visibleSpace.id
        window.currentTabId = UUID()
        window.currentShortcutPinId = source.id
        window.currentShortcutPinRole = source.role
        let moved = source.moved(to: targetSpace.id)

        tabManager.shortcutTabBindings.refreshInstances(for: moved)

        XCTAssertEqual(liveTab.spaceId, targetSpace.id)
        XCTAssertEqual(window.currentSpaceId, visibleSpace.id)
        XCTAssertEqual(liveTab.shortcutPinId, moved.id)
        XCTAssertEqual(liveTab.shortcutPinRole, .spacePinned)
    }

    func testRebindDoesNotTreatStaleShortcutMetadataAsSelection() throws {
        let window = BrowserWindowState()
        let tabManager = try makeInMemoryTabManager(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] }
        )
        window.tabManager = tabManager
        let sourceSpace = tabManager.spaceServices.catalog.createSpace(name: "Source")
        let visibleSpace = tabManager.spaceServices.catalog.createSpace(name: "Visible")
        let targetSpace = tabManager.spaceServices.catalog.createSpace(name: "Target")
        let source = makePin(spaceId: sourceSpace.id)
        let target = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: targetSpace.id,
            index: 0,
            launchURL: source.launchURL,
            title: source.title
        )
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            source,
            in: window.id,
            currentSpaceId: sourceSpace.id
        )!
        let selectedTabId = UUID()
        window.currentSpaceId = visibleSpace.id
        window.currentTabId = selectedTabId
        window.currentShortcutPinId = source.id
        window.currentShortcutPinRole = source.role

        XCTAssertTrue(
            tabManager.shortcutTabBindings.rebind(
                liveTab,
                from: source,
                to: target
            )
        )

        XCTAssertEqual(window.currentSpaceId, visibleSpace.id)
        XCTAssertEqual(window.currentTabId, selectedTabId)
        XCTAssertNil(window.currentShortcutPinId)
        XCTAssertNil(window.currentShortcutPinRole)
        XCTAssertIdentical(
            tabManager.liveShortcutTabs.tab(for: target.id, in: window.id),
            liveTab
        )
    }

    func testRefreshSwitchesSpaceOnlyForSelectedLiveInstance() throws {
        let window = BrowserWindowState()
        let tabManager = try makeInMemoryTabManager(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] }
        )
        window.tabManager = tabManager
        let sourceSpace = tabManager.spaceServices.catalog.createSpace(name: "Source")
        let targetSpace = tabManager.spaceServices.catalog.createSpace(name: "Target")
        let source = makePin(spaceId: sourceSpace.id)
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            source,
            in: window.id,
            currentSpaceId: sourceSpace.id
        )!
        window.currentSpaceId = sourceSpace.id
        window.currentTabId = liveTab.id
        window.currentShortcutPinId = source.id
        window.currentShortcutPinRole = source.role
        let moved = source.moved(to: targetSpace.id)

        tabManager.shortcutTabBindings.refreshInstances(for: moved)

        XCTAssertEqual(window.currentSpaceId, targetSpace.id)
        XCTAssertEqual(window.currentShortcutPinRole, .spacePinned)
    }

    func testRebindRekeysExactInstanceAndRepairsSelectionMetadata() throws {
        let window = BrowserWindowState()
        let tabManager = try makeInMemoryTabManager(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] }
        )
        window.tabManager = tabManager
        let profileID = UUID()
        let space = tabManager.spaceServices.catalog.createSpace(
            name: "Space",
            profileId: profileID
        )
        let source = makePin(spaceId: space.id)
        let target = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileID,
            index: 0,
            launchURL: source.launchURL,
            title: source.title
        )
        tabManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([source], for: space.id)
        tabManager.structuralCollectionMutationOwner.setPinnedTabs(
            [target],
            for: profileID
        )
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            source,
            in: window.id,
            currentSpaceId: space.id
        )!
        window.currentSpaceId = space.id
        window.currentTabId = liveTab.id
        window.currentShortcutPinId = source.id
        window.currentShortcutPinRole = source.role
        window.selectionHistory.recentSelectionItemsBySpace[space.id] = [
            .shortcutPin(source.id),
        ]

        XCTAssertTrue(
            tabManager.shortcutTabBindings.rebind(
                liveTab,
                from: source,
                to: target
            )
        )

        XCTAssertNil(tabManager.liveShortcutTabs.tab(for: source.id, in: window.id))
        XCTAssertIdentical(
            tabManager.liveShortcutTabs.tab(for: target.id, in: window.id),
            liveTab
        )
        XCTAssertEqual(window.currentShortcutPinId, target.id)
        XCTAssertEqual(window.currentShortcutPinRole, .essential)
        XCTAssertNil(liveTab.spaceId)
        XCTAssertNil(liveTab.folderId)
        XCTAssertEqual(
            window.selectionHistory.recentSelectionItemsBySpace[space.id],
            [.shortcutPin(target.id)]
        )
    }

    func testHistoryOnlyRefreshDoesNotPersistWindowSession() throws {
        let window = BrowserWindowState()
        var persistedWindowIds: [UUID] = []
        let tabManager = try makeInMemoryTabManager(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            persistWindowSession: { persistedWindowIds.append($0.id) }
        )
        window.tabManager = tabManager
        let sourceSpace = tabManager.spaceServices.catalog.createSpace(
            name: "Source"
        )
        let targetSpace = tabManager.spaceServices.catalog.createSpace(
            name: "Target"
        )
        let source = makePin(spaceId: sourceSpace.id)
        _ = tabManager.shortcutTabMaterializer.materialize(
            source,
            in: window.id,
            currentSpaceId: sourceSpace.id
        )!
        window.currentSpaceId = sourceSpace.id
        window.currentTabId = UUID()
        window.selectionHistory.recentSelectionItemsBySpace[sourceSpace.id] = [
            .shortcutPin(source.id),
        ]

        tabManager.shortcutTabBindings.refreshInstances(
            for: source.moved(to: targetSpace.id)
        )

        XCTAssertTrue(persistedWindowIds.isEmpty)
        XCTAssertNil(
            window.selectionHistory.recentSelectionItemsBySpace[sourceSpace.id]
        )
        XCTAssertEqual(
            window.selectionHistory.recentSelectionItemsBySpace[targetSpace.id],
            [.shortcutPin(source.id)]
        )
    }

    func testStagedRefreshRejectsWindowDriftAndRollsBackResidenceWithoutEffects() throws {
        let window = BrowserWindowState()
        var persistedWindowIDs: [UUID] = []
        let tabManager = try makeInMemoryTabManager(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            persistWindowSession: { persistedWindowIDs.append($0.id) }
        )
        window.tabManager = tabManager
        let sourceSpace = tabManager.spaceServices.catalog.createSpace(
            name: "Source"
        )
        let targetSpace = tabManager.spaceServices.catalog.createSpace(
            name: "Target"
        )
        let source = makePin(spaceId: sourceSpace.id)
        let liveTab = try XCTUnwrap(
            tabManager.shortcutTabMaterializer.materialize(
                source,
                in: window.id,
                currentSpaceId: sourceSpace.id
            )
        )
        window.currentSpaceId = sourceSpace.id
        window.currentTabId = liveTab.id
        window.currentShortcutPinId = source.id
        window.currentShortcutPinRole = source.role
        let moved = source.moved(to: targetSpace.id)
        let staging = ShortcutSplitLauncherBindingStaging(
            tabManager: tabManager
        )
        let admission = try XCTUnwrap(
            staging.admission(for: moved)
        )
        var structuralEvents = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0
        let profileRevision = liveTab.profileAssignment.changeRevision

        let receipt = try XCTUnwrap(
            staging.stage(
                pin: moved,
                admission: admission
            )
        )

        XCTAssertEqual(
            tabManager.liveShortcutTabs.entry(containing: liveTab)?
                .presentationPage.page.spaceID,
            targetSpace.id
        )
        XCTAssertEqual(liveTab.spaceId, sourceSpace.id)
        XCTAssertEqual(window.currentSpaceId, sourceSpace.id)
        XCTAssertEqual(liveTab.profileAssignment.changeRevision, profileRevision)
        XCTAssertEqual(structuralEvents, 0)
        XCTAssertTrue(persistedWindowIDs.isEmpty)

        let foreignTabID = UUID()
        window.currentTabId = foreignTabID

        XCTAssertFalse(receipt.isCurrent())
        XCTAssertTrue(receipt.canRollback())
        XCTAssertTrue(receipt.rollback())
        XCTAssertEqual(
            tabManager.liveShortcutTabs.entry(containing: liveTab)?
                .presentationPage.page.spaceID,
            sourceSpace.id
        )
        XCTAssertEqual(window.currentTabId, foreignTabID)
        XCTAssertEqual(liveTab.spaceId, sourceSpace.id)
        XCTAssertEqual(liveTab.profileAssignment.changeRevision, profileRevision)
        XCTAssertEqual(structuralEvents, 0)
        XCTAssertTrue(persistedWindowIDs.isEmpty)
        _ = cancellable
    }

    func testLauncherBatchCapacityRaceRestoresRawCatalogAndResidences() throws {
        let window = BrowserWindowState()
        var persistedWindowIDs: [UUID] = []
        let tabManager = try makeInMemoryTabManager(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            persistWindowSession: { persistedWindowIDs.append($0.id) }
        )
        window.tabManager = tabManager
        let profileID = UUID()
        let space = tabManager.spaceServices.catalog.createSpace(
            name: "Source",
            profileId: profileID
        )
        let firstID = UUID()
        let secondID = UUID()
        for (id, index) in [(firstID, 0), (secondID, 1)] {
            _ = try XCTUnwrap(tabManager.shortcutPinStoreOwner.insert(
                ShortcutPin(
                    id: id,
                    role: .spacePinned,
                    spaceId: space.id,
                    index: index,
                    launchURL: URL(string: "https://batch-\(index).example")!,
                    title: "Batch \(index)"
                ),
                at: index
            ))
        }
        let first = try XCTUnwrap(
            tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: firstID)
        )
        let second = try XCTUnwrap(
            tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: secondID)
        )
        let firstTab = try XCTUnwrap(
            tabManager.shortcutTabMaterializer.materialize(
                first,
                in: window.id,
                currentSpaceId: space.id
            )
        )
        let secondTab = try XCTUnwrap(
            tabManager.shortcutTabMaterializer.materialize(
                second,
                in: window.id,
                currentSpaceId: space.id
            )
        )
        let sourceWindow = window.unpublishedShortcutMutationState
        let sourceFirstRevision = firstTab.profileAssignment.changeRevision
        let sourceSecondRevision = secondTab.profileAssignment.changeRevision
        let essentials = (0..<(EssentialsShortcutPlacementOwner.CapacityPolicy.maxItems - 1))
            .map { index in
                ShortcutPin(
                    id: UUID(),
                    role: .essential,
                    profileId: profileID,
                    index: index,
                    launchURL: URL(string: "https://full-\(index).example")!,
                    title: "Full \(index)"
                )
            }
        tabManager.structuralCollectionMutationOwner.setPinnedTabs(
            essentials,
            for: profileID
        )
        let batches = ShortcutSplitLauncherMoveBatchStaging(
            catalog: ShortcutSplitLauncherCatalogTransaction(
                pinStore: tabManager.shortcutPinStoreOwner,
                pins: tabManager.shortcutPinCollectionStateOwner
            ),
            bindingStaging: ShortcutSplitLauncherBindingStaging(
                tabManager: tabManager
            ),
            residenceMutations: tabManager.liveShortcutTabs.staging,
            folderOpenState: tabManager.folderOpenState
        )
        let transaction = ShortcutSplitLauncherMoveTransaction(
            batches: batches,
            windowMutations: tabManager.shortcutWindowMutationOwner
        )
        let destination = ShortcutSplitLauncherDestination(
            role: .essential,
            profileId: profileID,
            spaceId: nil,
            folderId: nil,
            index: essentials.count
        )
        var structuralEvents = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0
        var restoredBeforeOuterRollback = false

        let committed = tabManager.structuralCollectionMutationOwner
            .withReversibleSideEffects {
                let result = transaction.stage([
                    PreparedShortcutSplitLauncherRestoration(
                        pin: first,
                        destination: destination
                    ),
                    PreparedShortcutSplitLauncherRestoration(
                        pin: second,
                        destination: destination
                    ),
                ])
                restoredBeforeOuterRollback =
                    tabManager.shortcutPinCollectionStateOwner
                        .shortcutPin(by: firstID) === first
                    && tabManager.shortcutPinCollectionStateOwner
                        .shortcutPin(by: secondID) === second
                    && tabManager.liveShortcutTabs
                        .entry(containing: firstTab)?.pinId == firstID
                    && tabManager.liveShortcutTabs
                        .entry(containing: secondTab)?.pinId == secondID
                return result != nil
            }

        XCTAssertFalse(committed)
        XCTAssertTrue(restoredBeforeOuterRollback)
        XCTAssertIdentical(
            tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: firstID),
            first
        )
        XCTAssertIdentical(
            tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: secondID),
            second
        )
        XCTAssertIdentical(
            tabManager.liveShortcutTabs.tab(for: firstID, in: window.id),
            firstTab
        )
        XCTAssertIdentical(
            tabManager.liveShortcutTabs.tab(for: secondID, in: window.id),
            secondTab
        )
        XCTAssertEqual(window.unpublishedShortcutMutationState, sourceWindow)
        XCTAssertEqual(
            firstTab.profileAssignment.changeRevision,
            sourceFirstRevision
        )
        XCTAssertEqual(
            secondTab.profileAssignment.changeRevision,
            sourceSecondRevision
        )
        XCTAssertEqual(structuralEvents, 0)
        XCTAssertTrue(persistedWindowIDs.isEmpty)
        _ = cancellable
    }

    private func makePin(spaceId: UUID) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: spaceId,
            index: 0,
            launchURL: URL(string: "https://binding.example")!,
            title: "Binding"
        )
    }
}

private extension ShortcutPin {
    func moved(to spaceId: UUID) -> ShortcutPin {
        ShortcutPin(
            id: id,
            role: .spacePinned,
            executionProfileId: executionProfileId,
            spaceId: spaceId,
            index: index,
            folderId: folderId,
            launchURL: launchURL,
            title: title,
            iconAsset: iconAsset
        )
    }
}
