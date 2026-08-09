import Combine
import SumiDomain
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabManagerStructuralBatchingTests: XCTestCase {
    func testStructuralPublishOwnerCoalescesNestedTransactionsAndFlushesBeforePublish() {
        let eventBus = TabStructureEventBus()
        let owner = TabStructuralPublishOwner(eventBus: eventBus)
        var eventCount = 0
        var flushCount = 0
        var flushCountsAtPublish: [Int] = []
        let cancellable = eventBus.structureChangedPublisher.sink {
            eventCount += 1
            flushCountsAtPublish.append(flushCount)
        }

        withExtendedLifetime(cancellable) {
            owner.withTransaction(flushPendingLookupBatch: { flushCount += 1 }) {
                owner.requestPublish()
                owner.withTransaction(flushPendingLookupBatch: { flushCount += 1 }) {
                    owner.requestPublish()
                }

                XCTAssertTrue(owner.isBatching)
                XCTAssertEqual(eventCount, 0)
                XCTAssertEqual(flushCount, 0)
            }
        }

        XCTAssertEqual(flushCount, 1)
        XCTAssertEqual(eventCount, 1)
        XCTAssertEqual(flushCountsAtPublish, [1])
    }

    func testPrepublicationActionsDrainFIFOInsideBatchingSentinel() {
        let eventBus = TabStructureEventBus()
        let owner = TabStructuralPublishOwner(eventBus: eventBus)
        var events: [String] = []
        let cancellable = eventBus.structureChangedPublisher.sink {
            events.append("publish")
        }

        owner.withTransaction(flushPendingLookupBatch: {}) {
            owner.requestPublish()
            owner.runAfterCurrentBatch { events.append("after") }
            owner.runBeforeCurrentBatchPublication {
                XCTAssertTrue(owner.isBatching)
                events.append("before-1")
                owner.requestPublish()
                owner.runBeforeCurrentBatchPublication {
                    XCTAssertTrue(owner.isBatching)
                    events.append("before-2")
                }
            }
        }
        withExtendedLifetime(cancellable) {}

        XCTAssertEqual(events, ["before-1", "before-2", "publish", "after"])
    }

    func testNestedRegularMutationsPublishOnceAndPreserveFinalOrder() throws {
        let tabManager = makeBrowser()
        let recorder = StructuralEventRecorder(tabManager: tabManager)
        let space = makeSpace(
            in: tabManager,
            name: "Workspace",
            profileID: tabManager.profileManager.profiles.first?.id
        )
        let first = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/two", in: space, activate: false)
        let third = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/three", in: space, activate: false)
        let batchFlushesBefore = tabManager.structuralLookupCoordinator.batchFlushCount
        recorder.reset()

        tabManager.structuralLookupCoordinator.withTransaction {
            tabManager.regularTabCollectionOwner.reorderRegularTabs(first, in: space.id, to: 3)
            tabManager.regularTabCollectionOwner.reorderRegularTabs(second, in: space.id, to: 3)
        }

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(tabManager.structuralLookupCoordinator.batchFlushCount, batchFlushesBefore + 1)
        XCTAssertEqual(tabManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[space.id]?.map(\.id), [third.id, first.id, second.id])
        XCTAssertEqual(tabManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[space.id]?.map(\.index), [0, 1, 2])
    }

    func testLookupBatchFlushesOncePerTransactionAndLookupIsCorrectAfterward() throws {
        let tabManager = makeBrowser()
        let recorder = StructuralEventRecorder(tabManager: tabManager)
        let space = makeSpace(
            in: tabManager,
            name: "Workspace",
            profileID: tabManager.profileManager.profiles.first?.id
        )
        let first = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/two", in: space, activate: false)
        let batchFlushesBefore = tabManager.structuralLookupCoordinator.batchFlushCount
        let immediateFlushesBefore = tabManager.structuralLookupCoordinator.immediateFlushCount
        recorder.reset()

        tabManager.structuralLookupCoordinator.withTransaction {
            tabManager.regularTabCollectionOwner.reorderRegularTabs(first, in: space.id, to: 2)
            tabManager.regularTabCollectionOwner.reorderRegularTabs(first, in: space.id, to: 0)
        }

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(tabManager.structuralLookupCoordinator.batchFlushCount, batchFlushesBefore + 1)
        XCTAssertEqual(tabManager.structuralLookupCoordinator.immediateFlushCount, immediateFlushesBefore)
        XCTAssertEqual(tabManager.tabCollectionMembershipOwner.tab(for: first.id)?.id, first.id)
        XCTAssertEqual(tabManager.tabCollectionMembershipOwner.tab(for: second.id)?.id, second.id)
    }

    func testLookupReadInsideTransactionFlushesPendingRegularMutationsImmediately() throws {
        let tabManager = makeBrowser()
        let recorder = StructuralEventRecorder(tabManager: tabManager)
        let space = makeSpace(
            in: tabManager,
            name: "Workspace",
            profileID: tabManager.profileManager.profiles.first?.id
        )
        let first = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/two", in: space, activate: false)
        let batchFlushesBefore = tabManager.structuralLookupCoordinator.batchFlushCount
        let immediateFlushesBefore = tabManager.structuralLookupCoordinator.immediateFlushCount
        recorder.reset()

        tabManager.structuralLookupCoordinator.withTransaction {
            tabManager.regularTabCollectionOwner.reorderRegularTabs(first, in: space.id, to: 2)

            XCTAssertEqual(recorder.count, 0)
            XCTAssertEqual(tabManager.structuralLookupCoordinator.batchFlushCount, batchFlushesBefore)
            XCTAssertEqual(tabManager.tabCollectionMembershipOwner.tab(for: first.id)?.id, first.id)
            XCTAssertEqual(tabManager.tabCollectionMembershipOwner.tab(for: second.id)?.id, second.id)
            XCTAssertEqual(tabManager.structuralLookupCoordinator.immediateFlushCount, immediateFlushesBefore + 1)
        }

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(tabManager.structuralLookupCoordinator.batchFlushCount, batchFlushesBefore)
        XCTAssertEqual(tabManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[space.id]?.map(\.id), [second.id, first.id])
    }

    func testTabsSnapshotObserverReadsTerminalLookupOnFirstCallback() throws {
        let tabManager = makeBrowser()
        let space = makeSpace(
            in: tabManager,
            name: "Workspace",
            profileID: tabManager.profileManager.profiles.first?.id
        )
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/removed",
            in: space
        )
        var observedTabIDs: [[UUID]] = []
        var lookupWasTerminal: [Bool] = []
        var lookupFlushCounts: [(batch: Int, immediate: Int)] = []
        let batchFlushesBefore =
            tabManager.structuralLookupCoordinator.batchFlushCount
        let immediateFlushesBefore =
            tabManager.structuralLookupCoordinator.immediateFlushCount
        let cancellable = tabManager.tabStateStore.regularTabs
            .tabsBySpacePublisher.sink { tabsBySpace in
                observedTabIDs.append(tabsBySpace[space.id]?.map(\.id) ?? [])
                lookupWasTerminal.append(
                    tabManager.tabCollectionMembershipOwner.tab(for: tab.id)
                        == nil
                )
                lookupFlushCounts.append((
                    tabManager.structuralLookupCoordinator.batchFlushCount,
                    tabManager.structuralLookupCoordinator.immediateFlushCount
                ))
            }

        tabManager.structuralLookupCoordinator.withTransaction {
            tabManager.structuralCollectionMutationOwner.setTabs(
                [],
                for: space.id
            )
            XCTAssertTrue(observedTabIDs.isEmpty)
        }
        withExtendedLifetime(cancellable) {}

        XCTAssertEqual(observedTabIDs, [[]])
        XCTAssertEqual(lookupWasTerminal, [true])
        XCTAssertEqual(lookupFlushCounts.map(\.batch), [batchFlushesBefore + 1])
        XCTAssertEqual(
            lookupFlushCounts.map(\.immediate),
            [immediateFlushesBefore]
        )
    }

    func testTransientShortcutLookupRefreshFlushesImmediatelyInsideTransaction() throws {
        let retirement = DeferredSpaceProfileTransition()
        let windowState = BrowserWindowState()
        var runtimeProfile: Profile?
        let tabManager = BrowserManager(
            runtimePorts: TestRuntimePorts.make(
                currentProfileId: { runtimeProfile?.id },
                defaultProfileId: { runtimeProfile?.id },
                profile: { runtimeProfile?.id == $0 ? runtimeProfile : nil },
                windowState: { id in id == windowState.id ? windowState : nil },
                windows: { [(windowState.id, windowState)] },
                webViewLifecycle: retirement.makeLifecycle()
            ),
            automaticallyStartPersistedStateLoad: false
        )
        runtimeProfile = tabManager.profileManager.profiles.first
        tabManager.windowRegistry.register(windowState)
        let recorder = StructuralEventRecorder(tabManager: tabManager)
        let space = makeSpace(
            in: tabManager,
            name: "Workspace",
            profileID: runtimeProfile?.id
        )
        windowState.currentSpaceId = space.id
        let folder = makeFolder(in: tabManager, spaceID: space.id, name: "Folder")
        let regular = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/folder", in: space)
        tabManager.sidebarRegularTabPlacementCommands.moveTabToFolder(
            regular,
            folderID: folder.id
        )
        let pin = try XCTUnwrap(tabManager.shortcutPinCollectionStateOwner.folderPinnedPins(for: folder.id, in: space.id).first)
        let windowId = windowState.id
        let batchFlushesBefore = tabManager.structuralLookupCoordinator.batchFlushCount
        let immediateFlushesBefore = tabManager.structuralLookupCoordinator.immediateFlushCount
        recorder.reset()

        tabManager.structuralLookupCoordinator.withTransaction {
            let liveTab = tabManager.shortcutTabMaterializer.materialize(pin, in: windowId, currentSpaceId: space.id)!

            XCTAssertEqual(recorder.count, 0)
            XCTAssertEqual(tabManager.tabCollectionMembershipOwner.tab(for: liveTab.id)?.id, liveTab.id)
            XCTAssertEqual(tabManager.structuralLookupCoordinator.immediateFlushCount, immediateFlushesBefore + 1)

            _ = tabManager.shortcutLiveTabRetirement.retire(
                pinId: pin.id,
                in: windowId
            )

            XCTAssertNil(tabManager.tabCollectionMembershipOwner.tab(for: liveTab.id))
            XCTAssertEqual(tabManager.structuralLookupCoordinator.immediateFlushCount, immediateFlushesBefore + 2)
        }

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(tabManager.structuralLookupCoordinator.batchFlushCount, batchFlushesBefore)
    }

    func testRemoveSelectedShortcutPinClearsWindowShortcutSelection() throws {
        let windowState = BrowserWindowState()
        let validationRecorder = RuntimeValidationRecorder()
        let tabManager = makeBrowser(
            runtimePorts: makeRuntimeContext(
                windowStates: [windowState],
                validationRecorder: validationRecorder
            )
        )
        let space = makeSpace(in: tabManager, name: "Workspace")
        let pin = makeSpacePinnedShortcut(spaceId: space.id)
        tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([pin], for: space.id)
        windowState.currentSpaceId = space.id
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )!
        let regularHistoryId = UUID()
        windowState.currentTabId = liveTab.id
        windowState.currentShortcutPinId = pin.id
        windowState.currentShortcutPinRole = pin.role
        windowState.selectedShortcutPinForSpace[space.id] = pin.id
        windowState.selectionHistory.recentSelectionItemsBySpace[space.id] = [
            .shortcutPin(pin.id),
            .regularTab(regularHistoryId),
        ]

        XCTAssertTrue(tabManager.sidebarPinCommands.remove(pin))

        XCTAssertNil(tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id))
        XCTAssertNil(tabManager.tabCollectionMembershipOwner.tab(for: liveTab.id))
        XCTAssertNil(windowState.currentTabId)
        XCTAssertNil(windowState.currentShortcutPinId)
        XCTAssertNil(windowState.currentShortcutPinRole)
        XCTAssertNil(windowState.selectedShortcutPinForSpace[space.id])
        XCTAssertEqual(windowState.selectionHistory.recentSelectionItemsBySpace[space.id], [.regularTab(regularHistoryId)])
        XCTAssertEqual(validationRecorder.count, 1)
    }

    func testDeactivateSelectedShortcutLiveTabValidatesClearedCurrentSelection() throws {
        let windowState = BrowserWindowState()
        let validationRecorder = RuntimeValidationRecorder()
        let tabManager = makeBrowser(
            runtimePorts: makeRuntimeContext(
                windowStates: [windowState],
                validationRecorder: validationRecorder
            )
        )
        let space = makeSpace(in: tabManager, name: "Workspace")
        let pin = makeSpacePinnedShortcut(spaceId: space.id)
        tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([pin], for: space.id)
        windowState.currentSpaceId = space.id
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )!
        windowState.currentTabId = liveTab.id
        windowState.currentShortcutPinId = pin.id
        windowState.currentShortcutPinRole = pin.role

        let retirement = tabManager.shortcutLiveTabRetirement.retire(
            pinId: pin.id,
            in: windowState.id
        )

        XCTAssertTrue(retirement.didRetire)
        XCTAssertTrue(retirement.didClearCurrentSelection)
        XCTAssertNil(tabManager.tabCollectionMembershipOwner.tab(for: liveTab.id))
        XCTAssertNil(windowState.currentTabId)
        XCTAssertNil(windowState.currentShortcutPinId)
        XCTAssertNil(windowState.currentShortcutPinRole)
        XCTAssertEqual(validationRecorder.count, 1)
    }

    func testRemoveShortcutPinClearsProxySelectionWithoutLiveTab() throws {
        let windowState = BrowserWindowState()
        let validationRecorder = RuntimeValidationRecorder()
        let tabManager = makeBrowser(
            runtimePorts: makeRuntimeContext(
                windowStates: [windowState],
                validationRecorder: validationRecorder
            )
        )
        let space = makeSpace(in: tabManager, name: "Workspace")
        let pin = makeSpacePinnedShortcut(spaceId: space.id)
        tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([pin], for: space.id)
        windowState.currentSpaceId = space.id
        windowState.currentTabId = pin.id
        windowState.currentShortcutPinId = pin.id
        windowState.currentShortcutPinRole = pin.role
        windowState.selectedShortcutPinForSpace[space.id] = pin.id
        windowState.selectionHistory.recentSelectionItemsBySpace[space.id] = [.shortcutPin(pin.id)]

        XCTAssertTrue(tabManager.sidebarPinCommands.remove(pin))

        XCTAssertNil(tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id))
        XCTAssertNil(windowState.currentTabId)
        XCTAssertNil(windowState.currentShortcutPinId)
        XCTAssertNil(windowState.currentShortcutPinRole)
        XCTAssertNil(windowState.selectedShortcutPinForSpace[space.id])
        XCTAssertNil(windowState.selectionHistory.recentSelectionItemsBySpace[space.id])
        XCTAssertEqual(validationRecorder.count, 1)
    }

    func testRemoveBackgroundShortcutPinPreservesRegularSelection() throws {
        let windowState = BrowserWindowState()
        let validationRecorder = RuntimeValidationRecorder()
        let persistenceRecorder = RuntimeWindowSessionPersistenceRecorder()
        let tabManager = makeBrowser(
            runtimePorts: makeRuntimeContext(
                windowStates: [windowState],
                validationRecorder: validationRecorder,
                persistenceRecorder: persistenceRecorder
            )
        )
        let space = makeSpace(in: tabManager, name: "Workspace")
        let pin = makeSpacePinnedShortcut(spaceId: space.id)
        tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([pin], for: space.id)
        let regularTab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/regular", in: space)
        windowState.currentSpaceId = space.id
        windowState.currentTabId = regularTab.id
        windowState.selectedShortcutPinForSpace[space.id] = pin.id
        windowState.selectionHistory.recentSelectionItemsBySpace[space.id] = [
            .shortcutPin(pin.id),
            .regularTab(regularTab.id),
        ]
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )!

        XCTAssertTrue(tabManager.sidebarPinCommands.remove(pin))

        XCTAssertNil(tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id))
        XCTAssertNil(tabManager.tabCollectionMembershipOwner.tab(for: liveTab.id))
        XCTAssertEqual(windowState.currentTabId, regularTab.id)
        XCTAssertNil(windowState.currentShortcutPinId)
        XCTAssertNil(windowState.currentShortcutPinRole)
        XCTAssertNil(windowState.selectedShortcutPinForSpace[space.id])
        XCTAssertEqual(windowState.selectionHistory.recentSelectionItemsBySpace[space.id], [.regularTab(regularTab.id)])
        XCTAssertEqual(validationRecorder.count, 0)
        XCTAssertEqual(persistenceRecorder.windowIds, [windowState.id])
    }

    func testDeleteFolderClearsDeletedShortcutPinSelectionReferences() throws {
        let windowState = BrowserWindowState()
        let validationRecorder = RuntimeValidationRecorder()
        let tabManager = makeBrowser(
            runtimePorts: makeRuntimeContext(
                windowStates: [windowState],
                validationRecorder: validationRecorder
            )
        )
        let space = makeSpace(in: tabManager, name: "Workspace")
        let folder = makeFolder(in: tabManager, spaceID: space.id, name: "Pinned")
        let pin = makeSpacePinnedShortcut(spaceId: space.id, folderId: folder.id)
        tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([pin], for: space.id)
        windowState.currentSpaceId = space.id
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )!
        windowState.currentTabId = liveTab.id
        windowState.currentShortcutPinId = pin.id
        windowState.currentShortcutPinRole = pin.role
        windowState.selectedShortcutPinForSpace[space.id] = pin.id
        windowState.selectionHistory.recentSelectionItemsBySpace[space.id] = [.shortcutPin(pin.id)]

        XCTAssertTrue(tabManager.sidebarFolderCommands.deleteFolder(folder.id))

        XCTAssertNil(tabManager.folderCollectionStateOwner.folder(by: folder.id))
        XCTAssertNil(tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id))
        XCTAssertNil(tabManager.tabCollectionMembershipOwner.tab(for: liveTab.id))
        XCTAssertNil(windowState.currentTabId)
        XCTAssertNil(windowState.currentShortcutPinId)
        XCTAssertNil(windowState.currentShortcutPinRole)
        XCTAssertNil(windowState.selectedShortcutPinForSpace[space.id])
        XCTAssertNil(windowState.selectionHistory.recentSelectionItemsBySpace[space.id])
        XCTAssertEqual(validationRecorder.count, 1)
    }

    func testFolderRemovalTouchesProviderStateOnlyForDurableLiveFolders() {
        var deletedLiveFolderIDs: [Set<UUID>] = []
        let tabManager = makeBrowser(runtimePorts: TestRuntimePorts.make(
            deleteLiveFolderState: { deletedLiveFolderIDs.append($0) }
        ))
        let space = makeSpace(in: tabManager, name: "Workspace")
        let ordinary = makeFolder(
            in: tabManager,
            spaceID: space.id,
            name: "Ordinary"
        )
        let live = makeFolder(
            in: tabManager,
            spaceID: space.id,
            name: "Live"
        )
        live.isLiveFolder = true

        XCTAssertTrue(tabManager.sidebarFolderCommands.deleteFolder(ordinary.id))
        XCTAssertTrue(deletedLiveFolderIDs.isEmpty)

        XCTAssertTrue(tabManager.sidebarFolderCommands.ungroupFolder(live.id))
        XCTAssertEqual(deletedLiveFolderIDs, [[live.id]])
    }

    func testLookupIncludesTransientExtensionAndAuxiliaryTabs() throws {
        let tabManager = BrowserManager()
        let space = makeSpace(in: tabManager, name: "Workspace")
        let opener = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/opener", in: space)

        let transientExtension = tabManager.extensionTabCommands.createTransient(
            url: URL(string: "https://example.com/transient")!,
            in: space,
            webExtensionContextOverride: nil
        )
        let auxiliary = try XCTUnwrap(
            tabManager.auxiliaryMiniWindowTabs.create(
                openerTab: opener,
                profileID: nil,
                urlString: nil,
                webExtensionContextOverride: nil
            )
        )

        XCTAssertIdentical(tabManager.tabCollectionMembershipOwner.tab(for: transientExtension.id), transientExtension)
        XCTAssertIdentical(tabManager.tabCollectionMembershipOwner.tab(for: auxiliary.id), auxiliary)

        tabManager.auxiliaryMiniWindowTabs.remove(auxiliary)
        tabManager.tabClosureService.removeTab(transientExtension.id)

        XCTAssertNil(tabManager.tabCollectionMembershipOwner.tab(for: auxiliary.id))
        XCTAssertNil(tabManager.tabCollectionMembershipOwner.tab(for: transientExtension.id))
    }

    func testAddTabWithoutSpaceDoesNotFallbackToCurrentSpaceOrAttachOrphan() throws {
        let tabManager = BrowserManager()
        let primarySpace = makeSpace(in: tabManager, name: "Primary")
        let currentSpace = makeSpace(in: tabManager, name: "Current")
        tabManager.spaceStateOwner.replaceCurrentSpace(currentSpace)
        let tab = Tab(
            url: URL(string: "https://example.com/orphan")!,
            name: "Orphan",
            spaceId: nil
        )

        tabManager.regularTabLifecycleOwner.addTab(tab)

        XCTAssertNil(tab.spaceId)
        XCTAssertTrue(tabManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[primarySpace.id]?.isEmpty ?? true)
        XCTAssertTrue(tabManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[currentSpace.id]?.isEmpty ?? true)
        XCTAssertNil(tabManager.tabCollectionMembershipOwner.tab(for: tab.id))
    }

    func testPromotingTransientExtensionWithoutTargetSpaceDoesNotFallbackToCurrentSpace() throws {
        let tabManager = BrowserManager()
        let sourceSpace = makeSpace(in: tabManager, name: "Source")
        let currentSpace = makeSpace(in: tabManager, name: "Current")
        tabManager.spaceStateOwner.replaceCurrentSpace(currentSpace)
        let transientExtension = tabManager.extensionTabCommands.createTransient(
            url: URL(string: "https://example.com/transient")!,
            in: sourceSpace,
            webExtensionContextOverride: nil
        )
        transientExtension.spaceId = nil

        let promoted = tabManager.extensionTabCommands.promoteTransient(
            transientExtension
        )

        XCTAssertFalse(promoted)
        XCTAssertTrue(tabManager.extensionTabCommands.containsTransient(transientExtension))
        XCTAssertTrue(tabManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[currentSpace.id]?.isEmpty ?? true)
        XCTAssertNil(tabManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[sourceSpace.id]?.first { $0.id == transientExtension.id })
    }

    func testTabCreationWithoutTargetSpaceUsesDefaultSpaceInsteadOfCurrentSpace() throws {
        let tabManager = BrowserManager()
        let defaultSpace = makeSpace(in: tabManager, name: "Default")
        let currentSpace = makeSpace(in: tabManager, name: "Current")

        tabManager.spaceStateOwner.replaceCurrentSpace(currentSpace)
        let regular = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/regular",
            in: nil,
            activate: false
        )

        tabManager.spaceStateOwner.replaceCurrentSpace(currentSpace)
        let transientExtension = tabManager.extensionTabCommands.createTransient(
            url: URL(string: "https://example.com/transient")!,
            in: nil,
            webExtensionContextOverride: nil
        )

        tabManager.spaceStateOwner.replaceCurrentSpace(currentSpace)
        let secondRegular = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/second",
            in: nil,
            activate: false
        )

        tabManager.spaceStateOwner.replaceCurrentSpace(currentSpace)
        let popup = tabManager.regularTabLifecycleOwner.createPopupTab(in: nil, activate: false)

        XCTAssertEqual(regular.spaceId, defaultSpace.id)
        XCTAssertEqual(transientExtension.spaceId, defaultSpace.id)
        XCTAssertEqual(secondRegular.spaceId, defaultSpace.id)
        XCTAssertEqual(popup.spaceId, defaultSpace.id)
        XCTAssertTrue(tabManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[currentSpace.id]?.isEmpty ?? true)
    }

    func testTabCreationWithoutTargetSpaceUsesCurrentProfileSpaceBeforeFirstSpace() throws {
        let firstProfileId = UUID()
        let currentProfileId = UUID()
        let tabManager = makeBrowser(
            runtimePorts: TestRuntimePorts.make(
                currentProfileId: { currentProfileId },
                defaultProfileId: { firstProfileId }
            )
        )
        let firstProfileSpace = makeSpace(in: tabManager, name: "First", profileID: firstProfileId)
        let currentProfileSpace = makeSpace(in: tabManager, name: "Current Profile", profileID: currentProfileId)
        tabManager.spaceStateOwner.replaceCurrentSpace(firstProfileSpace)
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/profile",
            in: nil,
            activate: false
        )

        XCTAssertEqual(tab.spaceId, currentProfileSpace.id)
        XCTAssertNil(tab.profileId)
        XCTAssertTrue(tabManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[firstProfileSpace.id]?.isEmpty ?? true)
    }

    func testTransientExtensionTabWithoutTargetSpaceUsesCurrentProfileSpaceBeforeFirstSpace() throws {
        let defaultProfileId = UUID()
        let currentProfileId = UUID()
        let tabManager = makeBrowser(
            runtimePorts: TestRuntimePorts.make(
                currentProfileId: { currentProfileId },
                defaultProfileId: { defaultProfileId }
            )
        )
        let defaultProfileSpace = makeSpace(in: tabManager, name: "Default Profile", profileID: defaultProfileId)
        let currentProfileSpace = makeSpace(in: tabManager, name: "Current Profile", profileID: currentProfileId)
        tabManager.spaceStateOwner.replaceCurrentSpace(defaultProfileSpace)
        let transientExtension = tabManager.extensionTabCommands.createTransient(
            url: URL(string: "https://example.com/transient")!,
            in: nil,
            webExtensionContextOverride: nil
        )

        XCTAssertNil(transientExtension.profileId)
        XCTAssertEqual(transientExtension.spaceId, currentProfileSpace.id)
        XCTAssertTrue(tabManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[defaultProfileSpace.id]?.isEmpty ?? true)
    }

    func testSelectionTabsForWindowContextUsesWindowSpaceInsteadOfCurrentSpace() throws {
        let windowProfileId = UUID()
        let globalProfileId = UUID()
        let windowState = BrowserWindowState()
        let tabManager = makeBrowser(
            runtimePorts: TestRuntimePorts.make(
                currentProfileId: { globalProfileId },
                windowState: { id in
                    id == windowState.id ? windowState : nil
                }
            )
        )
        let windowSpace = makeSpace(in: tabManager, name: "Window", profileID: windowProfileId)
        let globalSpace = makeSpace(in: tabManager, name: "Global", profileID: globalProfileId)
        let windowRegular = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://window.example/regular",
            in: windowSpace,
            activate: false
        )
        let globalRegular = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://global.example/regular",
            in: globalSpace,
            activate: false
        )
        windowState.currentSpaceId = windowSpace.id
        windowState.currentProfileId = windowProfileId

        let windowFavoritePin = ShortcutPin(
            id: UUID(),
            role: .favorite,
            profileId: windowProfileId,
            spaceId: nil,
            index: 0,
            folderId: nil,
            launchURL: URL(string: "https://window.example/favorite")!,
            title: "Window Favorite",
            iconAsset: nil
        )
        let globalFavoritePin = ShortcutPin(
            id: UUID(),
            role: .favorite,
            profileId: globalProfileId,
            spaceId: nil,
            index: 0,
            folderId: nil,
            launchURL: URL(string: "https://global.example/favorite")!,
            title: "Global Favorite",
            iconAsset: nil
        )
        let windowSpacePin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            profileId: nil,
            spaceId: windowSpace.id,
            index: 0,
            folderId: nil,
            launchURL: URL(string: "https://window.example/pinned")!,
            title: "Window Pin",
            iconAsset: nil
        )
        tabManager.structuralCollectionMutationOwner.setPinnedTabs([windowFavoritePin], for: windowProfileId)
        tabManager.structuralCollectionMutationOwner.setPinnedTabs([globalFavoritePin], for: globalProfileId)
        tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([windowSpacePin], for: windowSpace.id)
        tabManager.spaceStateOwner.replaceCurrentSpace(globalSpace)
        let windowFavorite = tabManager.shortcutTabMaterializer.materialize(
            windowFavoritePin,
            in: windowState.id,
            currentSpaceId: windowSpace.id
        )!
        let globalFavorite = tabManager.shortcutTabMaterializer.materialize(
            globalFavoritePin,
            in: UUID(),
            currentSpaceId: globalSpace.id
        )!
        let windowLauncher = tabManager.shortcutTabMaterializer.materialize(
            windowSpacePin,
            in: windowState.id,
            currentSpaceId: windowSpace.id
        )!
        windowState.currentShortcutPinId = windowSpacePin.id

        let selection = TabSelectionContextProjection(
            runtimeConnection: tabManager.runtimePortConnection,
            spaces: tabManager.spaceStateOwner,
            regularTabs: tabManager.regularTabCollectionOwner,
            shortcutPresentation: tabManager.shortcutPresentationOwner
        ).tabs(in: windowState.id)
        let selectionIds = selection.map(\.id)

        XCTAssertTrue(selectionIds.contains(windowFavorite.id))
        XCTAssertTrue(selectionIds.contains(windowLauncher.id))
        XCTAssertTrue(selectionIds.contains(windowRegular.id))
        XCTAssertFalse(selectionIds.contains(globalFavorite.id))
        XCTAssertFalse(selectionIds.contains(globalRegular.id))
    }

    func testSplitGroupLookupsFollowStructuralMutations() throws {
        let tabManager = BrowserManager()
        let space = makeSpace(in: tabManager, name: "Workspace")
        let first = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/two", in: space, activate: false)
        let third = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/three", in: space, activate: false)
        let fourth = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/four", in: space, activate: false)
        let initial = try XCTUnwrap(
            SplitGroup.make(
                members: [.regularTab(first.id), .regularTab(second.id)],
                layoutKind: .vertical,
                container: .regularTabs(spaceId: space.id)
            )
        )

        XCTAssertTrue(tabManager.splitGroupMutations.insert(initial))

        XCTAssertEqual(tabManager.splitGroupStore.group(id: initial.id), initial)
        XCTAssertEqual(
            tabManager.splitGroupStore.group(containing: .regularTab(first.id)),
            initial
        )
        XCTAssertEqual(
            tabManager.splitGroupStore.groupID(containing: .regularTab(second.id)),
            initial.id
        )

        let replacement = try XCTUnwrap(
            SplitGroup.make(
                id: initial.id,
                members: [
                    .regularTab(second.id),
                    .regularTab(third.id),
                    .regularTab(fourth.id),
                ],
                layoutKind: .horizontal,
                container: initial.container
            )
        )
        XCTAssertTrue(
            tabManager.splitGroupMutations.replace(initial, with: replacement)
        )

        XCTAssertEqual(tabManager.splitGroupStore.group(id: initial.id), replacement)
        XCTAssertNil(
            tabManager.splitGroupStore.group(containing: .regularTab(first.id))
        )
        XCTAssertEqual(
            tabManager.splitGroupStore.group(containing: .regularTab(second.id)),
            replacement
        )
        XCTAssertEqual(
            tabManager.splitGroupStore.group(containing: .regularTab(fourth.id)),
            replacement
        )

        let trimmed = try XCTUnwrap(
            replacement.removingMember(.regularTab(second.id))
        )
        XCTAssertTrue(
            tabManager.splitGroupMutations.replace(replacement, with: trimmed)
        )

        XCTAssertEqual(
            tabManager.splitGroupStore.group(id: replacement.id)?.memberIDs,
            [.regularTab(third.id), .regularTab(fourth.id)]
        )
        XCTAssertNil(
            tabManager.splitGroupStore.group(containing: .regularTab(second.id))
        )
        XCTAssertEqual(
            tabManager.splitGroupStore.group(containing: .regularTab(third.id)),
            trimmed
        )

        let final = try XCTUnwrap(
            SplitGroup.make(
                members: [.regularTab(first.id), .regularTab(fourth.id)],
                layoutKind: .vertical,
                container: .regularTabs(spaceId: space.id)
            )
        )
        XCTAssertTrue(
            tabManager.splitGroupMutations.replaceAll(
                expected: [trimmed],
                with: [final]
            )
        )

        XCTAssertEqual(tabManager.splitGroupStore.group(id: final.id), final)
        XCTAssertNil(tabManager.splitGroupStore.group(id: replacement.id))
        XCTAssertNil(
            tabManager.splitGroupStore.group(containing: .regularTab(third.id))
        )
        XCTAssertEqual(
            tabManager.splitGroupStore.group(containing: .regularTab(first.id)),
            final
        )

        XCTAssertTrue(tabManager.splitGroupMutations.remove(final))

        XCTAssertNil(tabManager.splitGroupStore.group(id: final.id))
        XCTAssertNil(
            tabManager.splitGroupStore.group(containing: .regularTab(first.id))
        )
    }

    func testSplitGroupReplacementRefreshesLookups() throws {
        let tabManager = BrowserManager()
        let space = makeSpace(in: tabManager, name: "Workspace")
        let first = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/two", in: space, activate: false)
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: [.regularTab(first.id), .regularTab(second.id)],
                layoutKind: .vertical,
                container: .regularTabs(spaceId: space.id)
            )
        )

        XCTAssertTrue(
            tabManager.splitGroupMutations.replaceAll(
                expected: [],
                with: [group]
            )
        )

        XCTAssertEqual(tabManager.splitGroupStore.group(id: group.id), group)
        XCTAssertEqual(
            tabManager.splitGroupStore.group(containing: .regularTab(first.id)),
            group
        )

        XCTAssertTrue(
            tabManager.splitGroupMutations.replaceAll(
                expected: [group],
                with: []
            )
        )

        XCTAssertNil(tabManager.splitGroupStore.group(id: group.id))
        XCTAssertNil(
            tabManager.splitGroupStore.group(containing: .regularTab(first.id))
        )
    }

    func testSplitGroupMutationsPublishOnceAndLookupUpdatesDuringTransaction() throws {
        let tabManager = BrowserManager()
        let recorder = StructuralEventRecorder(tabManager: tabManager)
        let space = makeSpace(in: tabManager, name: "Workspace")
        let first = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/two", in: space, activate: false)
        let third = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/three", in: space, activate: false)
        let initial = try XCTUnwrap(
            SplitGroup.make(
                members: [.regularTab(first.id), .regularTab(second.id)],
                layoutKind: .vertical,
                container: .regularTabs(spaceId: space.id)
            )
        )
        let replacement = try XCTUnwrap(
            SplitGroup.make(
                id: initial.id,
                members: [.regularTab(second.id), .regularTab(third.id)],
                layoutKind: .horizontal,
                container: initial.container
            )
        )
        recorder.reset()

        tabManager.structuralLookupCoordinator.withTransaction {
            XCTAssertTrue(
                tabManager.splitGroupMutations.insert(initial, persist: false)
            )
            XCTAssertEqual(recorder.count, 0)
            XCTAssertEqual(
                tabManager.splitGroupStore.group(containing: .regularTab(first.id)),
                initial
            )

            XCTAssertTrue(
                tabManager.splitGroupMutations.replace(
                    initial,
                    with: replacement,
                    persist: false
                )
            )
            XCTAssertEqual(recorder.count, 0)
            XCTAssertNil(
                tabManager.splitGroupStore.group(
                    containing: .regularTab(first.id)
                )
            )
            XCTAssertEqual(
                tabManager.splitGroupStore.group(
                    containing: .regularTab(third.id)
                ),
                replacement
            )
        }

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(tabManager.splitGroupStore.group(id: initial.id), replacement)
        XCTAssertEqual(
            tabManager.splitGroupStore.group(containing: .regularTab(second.id)),
            replacement
        )
    }

    func testAdoptingGlanceTabInsertsAfterSourceAndPreservesWebView() throws {
        let tabManager = BrowserManager()
        let space = makeSpace(in: tabManager, name: "Workspace")
        let source = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/source", in: space)
        let trailing = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/trailing", in: space, activate: false)
        let preview = tabManager.tabFactory.makeTab(
            url: URL(string: "https://destination.example/preview")!,
            name: "Preview",
            spaceId: space.id
        )
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        preview.replaceUntrackedWebView(webView)

        let adopted = tabManager.regularTabLifecycleOwner.adoptGlanceTab(preview, sourceTab: source, in: space)

        XCTAssertIdentical(adopted, preview)
        XCTAssertIdentical(preview.resolvedCurrentWebView(), webView)
        XCTAssertEqual(tabManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[space.id]?.map(\.id), [
            source.id,
            preview.id,
            trailing.id,
        ])
        XCTAssertEqual(tabManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[space.id]?.map(\.index), [0, 1, 2])
        XCTAssertEqual(tabManager.tabCollectionMembershipOwner.tab(for: preview.id)?.id, preview.id)
    }

    func testGlanceAdoptionRejectsStaleSameIDPreview() throws {
        let tabManager = BrowserManager()
        let space = makeSpace(in: tabManager, name: "Workspace")
        let canonical = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://canonical.example",
            in: space,
            activate: false
        )
        let stale = tabManager.tabFactory.makeTab(id: canonical.id)

        let adopted = tabManager.regularTabLifecycleOwner.adoptGlanceTab(
            stale,
            sourceTab: canonical,
            in: space
        )

        XCTAssertNil(adopted)
        XCTAssertNil(stale.spaceId)
        XCTAssertIdentical(
            tabManager.tabCollectionMembershipOwner.tab(for: canonical.id),
            canonical
        )
        XCTAssertEqual(
            tabManager.regularTabCollectionOwner.tabs(in: space).count,
            1
        )
    }

    func testTabCreationPathsInheritTargetProfileAndPreserveCollectionRoles() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = makeSpace(in: tabManager, name: "Workspace", profileID: profileId)

        let regular = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/regular",
            in: space,
            activate: false
        )
        let transientExtension = tabManager.extensionTabCommands.createTransient(
            url: URL(string: "https://example.com/transient")!,
            in: space,
            webExtensionContextOverride: nil
        )
        let secondRegular = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/second",
            in: space,
            activate: false
        )
        let popup = tabManager.regularTabLifecycleOwner.createPopupTab(in: space, activate: false)

        XCTAssertEqual(regular.spaceId, space.id)
        XCTAssertNil(regular.profileId)
        XCTAssertEqual(transientExtension.spaceId, space.id)
        XCTAssertNil(transientExtension.profileId)
        XCTAssertTrue(tabManager.extensionTabCommands.containsTransient(transientExtension))

        XCTAssertEqual(secondRegular.spaceId, space.id)
        XCTAssertNil(secondRegular.profileId)
        XCTAssertEqual(popup.spaceId, space.id)
        XCTAssertNil(popup.profileId)
        XCTAssertTrue(popup.isPopupHost)

        XCTAssertEqual(tabManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[space.id]?.map(\.id), [
            regular.id,
            secondRegular.id,
            popup.id,
        ])
        XCTAssertFalse((tabManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[space.id] ?? []).contains { $0.id == transientExtension.id })
    }

    func testGlanceAdoptionTargetsSourceSpaceAndBackfillsFromPreviewProfile() throws {
        var previewProfile: Profile?
        let tabManager = BrowserManager(
            runtimePorts: TestRuntimePorts.make(
                currentProfileId: { previewProfile?.id },
                defaultProfileId: { previewProfile?.id },
                profile: { profileId in
                    profileId == previewProfile?.id ? previewProfile : nil
                }
            ),
            automaticallyStartPersistedStateLoad: false
        )
        previewProfile = tabManager.profileManager.profiles.first
        let previewProfileId = try XCTUnwrap(previewProfile?.id)
        let sourceSpace = makeSpace(in: tabManager, name: "Source")
        let currentSpace = makeSpace(in: tabManager, name: "Current")
        let source = tabManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/source")!,
            spaceId: sourceSpace.id
        )
        tabManager.structuralCollectionMutationOwner.setTabs(
            [source],
            for: sourceSpace.id
        )
        let preview = tabManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/preview")!,
            name: "Preview",
            spaceId: nil
        )
        preview.profileId = previewProfileId

        let adopted = tabManager.regularTabLifecycleOwner.adoptGlanceTab(preview, sourceTab: source)

        XCTAssertIdentical(adopted, preview)
        XCTAssertEqual(preview.spaceId, sourceSpace.id)
        XCTAssertEqual(preview.profileId, previewProfileId)
        XCTAssertEqual(sourceSpace.profileId, previewProfileId)
        XCTAssertNil(currentSpace.profileId)
        XCTAssertEqual(tabManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[sourceSpace.id]?.map(\.id), [
            source.id,
            preview.id,
        ])
    }

    func testGlanceAdoptionPreservesExplicitProfileOverrideInAssignedSpace() throws {
        var profiles: [UUID: Profile] = [:]
        let tabManager = BrowserManager(
            runtimePorts: TestRuntimePorts.make(
                profile: { profiles[$0] }
            ),
            automaticallyStartPersistedStateLoad: false
        )
        let spaceProfile = try XCTUnwrap(
            tabManager.profileManager.profiles.first
        )
        let previewProfile = try tabManager.profileManager.createProfile(
            name: "Preview"
        )
        profiles = [
            spaceProfile.id: spaceProfile,
            previewProfile.id: previewProfile,
        ]
        let space = makeSpace(
            in: tabManager,
            name: "Workspace",
            profileID: spaceProfile.id
        )
        let source = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://source.example",
            in: space,
            activate: false
        )
        let preview = tabManager.tabFactory.makeTab(
            url: URL(string: "https://preview.example")!,
            name: "Preview",
            spaceId: nil
        )
        preview.profileId = previewProfile.id
        let webView = WKWebView()
        preview.replaceUntrackedWebView(webView)

        _ = tabManager.regularTabLifecycleOwner.adoptGlanceTab(
            preview,
            sourceTab: source,
            in: space
        )

        XCTAssertEqual(space.profileId, spaceProfile.id)
        XCTAssertEqual(preview.profileId, previewProfile.id)
        XCTAssertIdentical(preview.resolvedCurrentWebView(), webView)
    }

    func testRemovingSelectedTabPublishesOnceAndSelectsReplacement() throws {
        let tabManager = BrowserManager()
        let recorder = StructuralEventRecorder(tabManager: tabManager)
        let space = makeSpace(in: tabManager, name: "Workspace")
        let first = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/two", in: space, activate: false)
        tabManager.activeSelectionOwner.setActiveTab(first)
        recorder.reset()

        tabManager.tabClosureService.removeTab(first.id)

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(tabManager.tabStateStore.selection.currentTab?.id, second.id)
        XCTAssertEqual(tabManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[space.id]?.map(\.id), [second.id])
    }

    func testConvertingLiveFolderLauncherBackToRegularPublishesOnceAndClearsLiveBinding() throws {
        let retirement = DeferredSpaceProfileTransition()
        let windowState = BrowserWindowState()
        var runtimeProfile: Profile?
        let tabManager = BrowserManager(
            runtimePorts: TestRuntimePorts.make(
                currentProfileId: { runtimeProfile?.id },
                defaultProfileId: { runtimeProfile?.id },
                profile: { runtimeProfile?.id == $0 ? runtimeProfile : nil },
                windowState: { $0 == windowState.id ? windowState : nil },
                windows: { [(windowState.id, windowState)] },
                webViewLifecycle: retirement.makeLifecycle()
            ),
            automaticallyStartPersistedStateLoad: false
        )
        runtimeProfile = tabManager.profileManager.profiles.first
        tabManager.windowRegistry.register(windowState)
        let recorder = StructuralEventRecorder(tabManager: tabManager)
        let space = makeSpace(
            in: tabManager,
            name: "Workspace",
            profileID: runtimeProfile?.id
        )
        let folder = makeFolder(in: tabManager, spaceID: space.id, name: "Folder")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/folder", in: space)

        tabManager.sidebarRegularTabPlacementCommands.moveTabToFolder(
            tab,
            folderID: folder.id
        )
        let pin = try XCTUnwrap(tabManager.shortcutPinCollectionStateOwner.folderPinnedPins(for: folder.id, in: space.id).first)
        let windowId = windowState.id
        windowState.currentSpaceId = space.id
        let liveTab = tabManager.shortcutTabMaterializer.materialize(pin, in: windowId, currentSpaceId: space.id)!
        XCTAssertEqual(liveTab.shortcutPinId, pin.id)
        recorder.reset()

        let dragItem = SumiDragItem.shortcutPin(
            pin.id,
            title: pin.title,
            urlString: pin.launchURL.absoluteString
        )
        let scope = try XCTUnwrap(SidebarDragScope(
            windowState: windowState,
            sourceZone: .folder(folder.id),
            item: dragItem
        ))
        XCTAssertTrue(tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: .folder(folder.id),
                toContainer: .spaceRegular(space.id),
                toIndex: 0
            )
        ))

        XCTAssertEqual(recorder.count, 1)
        XCTAssertTrue(tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: space.id).isEmpty)
        XCTAssertNil(tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: windowId))
        let convertedTab = try XCTUnwrap(tabManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()[space.id]?.first)
        XCTAssertEqual(convertedTab.url, pin.launchURL)
        XCTAssertEqual(convertedTab.spaceId, space.id)
        XCTAssertFalse(convertedTab.isShortcutLiveInstance)
        XCTAssertEqual(tabManager.tabCollectionMembershipOwner.tab(for: convertedTab.id)?.id, convertedTab.id)
    }

    func testTogglingFolderOpenStatePublishesOnlyExpansionRevision() throws {
        let tabManager = BrowserManager()
        let recorder = StructuralEventRecorder(tabManager: tabManager)
        let space = makeSpace(in: tabManager, name: "Workspace")
        let folder = makeFolder(in: tabManager, spaceID: space.id, name: "Folder")
        var expansionChanges: [TabFolderExpansionChange] = []
        let expansionCancellable = tabManager.tabStructureEventBus
            .folderExpansionChangesPublisher
            .sink { expansionChanges.append($0) }
        recorder.reset()

        tabManager.folderOpenState.toggleFolderOpenState(folder.id)

        XCTAssertTrue(folder.isOpen)
        XCTAssertEqual(recorder.count, 0)
        XCTAssertEqual(expansionChanges.count, 1)
        XCTAssertEqual(expansionChanges.first?.spaceID, space.id)
        XCTAssertEqual(expansionChanges.first?.expansionByFolderID, [folder.id: true])
        withExtendedLifetime(expansionCancellable) {}
    }

    func testDraggingLiveFolderItemToPinnedDetachesProviderStateAfterMove() throws {
        var liveFolderID: UUID?
        var placements: [(pinID: UUID, folderID: UUID, targetFolderID: UUID?, index: Int?)] = []
        let browser = makeBrowser(runtimePorts: TestRuntimePorts.make(
            isLiveFolder: { $0 == liveFolderID },
            reconcileLiveFolderItemMove: { placements.append(($0, $1, $2, $3)) }
        ))
        let space = makeSpace(in: browser, name: "Workspace")
        let folder = try XCTUnwrap(browser.sidebarFolderCommands.createFolder(
            in: space.id,
            name: "Feed",
            isLiveFolder: true
        ))
        liveFolderID = folder.id
        let pin = try XCTUnwrap(browser.shortcutPinStoreOwner.insert(
            ShortcutPin(
                id: UUID(),
                role: .spacePinned,
                spaceId: space.id,
                index: 0,
                folderId: folder.id,
                launchURL: URL(string: "https://example.test/item")!,
                title: "Live item"
            ),
            at: 0,
            openTargetFolder: false
        ))
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        browser.windowRegistry.register(windowState)
        let scope = try XCTUnwrap(SidebarDragScope(
            windowState: windowState,
            sourceZone: .folder(folder.id),
            item: .shortcutPin(pin.id, title: pin.title)
        ))

        XCTAssertTrue(browser.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: .folder(folder.id),
                toContainer: .spacePinned(space.id),
                toIndex: 0
            )
        ))

        XCTAssertNil(browser.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id)?.folderId)
        XCTAssertEqual(placements.map(\.pinID), [pin.id])
        XCTAssertEqual(placements.map(\.folderID), [folder.id])
        XCTAssertNil(placements.first?.targetFolderID)
    }

    func testDraggingLiveFolderItemWithinFolderCommitsProviderOrder() throws {
        var liveFolderID: UUID?
        var placements: [(pinID: UUID, folderID: UUID, targetFolderID: UUID?, index: Int?)] = []
        let browser = makeBrowser(runtimePorts: TestRuntimePorts.make(
            isLiveFolder: { $0 == liveFolderID },
            reconcileLiveFolderItemMove: { placements.append(($0, $1, $2, $3)) }
        ))
        let space = makeSpace(in: browser, name: "Workspace")
        let folder = try XCTUnwrap(browser.sidebarFolderCommands.createFolder(
            in: space.id,
            name: "Feed",
            isLiveFolder: true
        ))
        liveFolderID = folder.id
        let first = try XCTUnwrap(browser.shortcutPinStoreOwner.insert(
            ShortcutPin(
                id: UUID(),
                role: .spacePinned,
                spaceId: space.id,
                index: 0,
                folderId: folder.id,
                launchURL: URL(string: "https://example.test/first")!,
                title: "First"
            ),
            at: 0,
            openTargetFolder: false
        ))
        let second = try XCTUnwrap(browser.shortcutPinStoreOwner.insert(
            ShortcutPin(
                id: UUID(),
                role: .spacePinned,
                spaceId: space.id,
                index: 1,
                folderId: folder.id,
                launchURL: URL(string: "https://example.test/second")!,
                title: "Second"
            ),
            at: 1,
            openTargetFolder: false
        ))
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        browser.windowRegistry.register(windowState)
        let scope = try XCTUnwrap(SidebarDragScope(
            windowState: windowState,
            sourceZone: .folder(folder.id),
            item: .shortcutPin(second.id, title: second.title)
        ))

        XCTAssertTrue(browser.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .pin(second),
                scope: scope,
                fromContainer: .folder(folder.id),
                toContainer: .folder(folder.id),
                toIndex: 0
            )
        ))

        XCTAssertEqual(
            browser.shortcutPinCollectionStateOwner.folderPinnedPins(
                for: folder.id,
                in: space.id
            ).map(\.id),
            [second.id, first.id]
        )
        XCTAssertEqual(placements.map(\.pinID), [second.id])
        XCTAssertEqual(placements.first?.targetFolderID, folder.id)
        XCTAssertEqual(placements.first?.index, 0)
    }

    func testDraggingLiveFolderItemToRegularDetachesOnlyAfterConversion() throws {
        var liveFolderID: UUID?
        var placements: [(pinID: UUID, folderID: UUID, targetFolderID: UUID?, index: Int?)] = []
        var runtimeProfile: Profile?
        let windowState = BrowserWindowState()
        let browser = makeBrowser(runtimePorts: TestRuntimePorts.make(
            currentProfileId: { runtimeProfile?.id },
            defaultProfileId: { runtimeProfile?.id },
            profile: { runtimeProfile?.id == $0 ? runtimeProfile : nil },
            windowState: { $0 == windowState.id ? windowState : nil },
            windows: { [(windowState.id, windowState)] },
            isLiveFolder: { $0 == liveFolderID },
            reconcileLiveFolderItemMove: { placements.append(($0, $1, $2, $3)) }
        ))
        runtimeProfile = browser.profileManager.profiles.first
        let space = makeSpace(
            in: browser,
            name: "Workspace",
            profileID: runtimeProfile?.id
        )
        let folder = try XCTUnwrap(browser.sidebarFolderCommands.createFolder(
            in: space.id,
            name: "Feed",
            isLiveFolder: true
        ))
        liveFolderID = folder.id
        let pin = try XCTUnwrap(browser.shortcutPinStoreOwner.insert(
            ShortcutPin(
                id: UUID(),
                role: .spacePinned,
                spaceId: space.id,
                index: 0,
                folderId: folder.id,
                launchURL: URL(string: "https://example.test/item")!,
                title: "Live item"
            ),
            at: 0,
            openTargetFolder: false
        ))
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = runtimeProfile?.id
        browser.windowRegistry.register(windowState)
        let scope = try XCTUnwrap(SidebarDragScope(
            windowState: windowState,
            sourceZone: .folder(folder.id),
            item: .shortcutPin(pin.id, title: pin.title)
        ))

        XCTAssertTrue(browser.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: .folder(folder.id),
                toContainer: .spaceRegular(space.id),
                toIndex: 0
            )
        ))

        XCTAssertNil(browser.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id))
        XCTAssertEqual(
            browser.regularTabCollectionOwner.tabs(in: space.id).map(\.url),
            [pin.launchURL]
        )
        XCTAssertEqual(placements.map(\.pinID), [pin.id])
        XCTAssertEqual(placements.map(\.folderID), [folder.id])
        XCTAssertNil(placements.first?.targetFolderID)
    }

    func testLiveFolderRejectsInboundDragWhenOptionalModuleHasNoRuntimeState() throws {
        let browser = BrowserManager()
        let space = makeSpace(
            in: browser,
            name: "Workspace",
            profileID: browser.profileManager.profiles.first?.id
        )
        let folder = try XCTUnwrap(browser.sidebarFolderCommands.createFolder(
            in: space.id,
            name: "Feed",
            isLiveFolder: true
        ))
        XCTAssertNil(browser.liveFolderManager.source(for: folder.id))
        let pin = try XCTUnwrap(browser.shortcutPinStoreOwner.insert(
            ShortcutPin(
                id: UUID(),
                role: .spacePinned,
                spaceId: space.id,
                index: 0,
                launchURL: URL(string: "https://example.test/ordinary")!,
                title: "Ordinary item"
            ),
            at: 0
        ))
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = space.profileId
        browser.windowRegistry.register(windowState)
        let scope = try XCTUnwrap(SidebarDragScope(
            windowState: windowState,
            sourceZone: .spacePinned(space.id),
            item: .shortcutPin(pin.id, title: pin.title)
        ))

        XCTAssertFalse(browser.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: .spacePinned(space.id),
                toContainer: .folder(folder.id),
                toIndex: 0
            )
        ))
        XCTAssertNil(browser.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id)?.folderId)
    }

    func testFolderShortcutPlacementTargetUsesCanonicalPinAndAppendIndex() throws {
        let tabManager = BrowserManager()
        let space = makeSpace(in: tabManager, name: "Workspace")
        let folder = makeFolder(in: tabManager, spaceID: space.id, name: "Folder")
        let existing = makeSpacePinnedShortcut(
            spaceId: space.id,
            folderId: folder.id,
            index: 0
        )
        let source = makeSpacePinnedShortcut(
            spaceId: space.id,
            index: 1
        )
        tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts(
            [existing, source],
            for: space.id
        )
        let tab = Tab(
            id: source.id,
            url: source.launchURL,
            name: source.title,
            spaceId: space.id,
            loadsCachedFaviconOnInit: false
        )
        tab.bindToShortcutPin(source)
        let query = TabFolderShortcutPlacementTargetQuery(
            folders: tabManager.folderCollectionStateOwner,
            pins: tabManager.shortcutPinCollectionStateOwner,
            runtimeConnection: tabManager.runtimePortConnection
        )

        let target = try XCTUnwrap(query.target(for: folder.id, moving: tab))

        XCTAssertEqual(target.folderID, folder.id)
        XCTAssertEqual(target.spaceID, space.id)
        XCTAssertEqual(target.insertionIndex, 1)
        XCTAssertIdentical(target.sourcePin, source)
    }

    private func makeSpacePinnedShortcut(
        id: UUID = UUID(),
        spaceId: UUID,
        folderId: UUID? = nil,
        index: Int = 0,
        urlString: String = "https://shortcut.example"
    ) -> ShortcutPin {
        ShortcutPin(
            id: id,
            role: .spacePinned,
            spaceId: spaceId,
            index: index,
            folderId: folderId,
            launchURL: URL(string: urlString)!,
            title: "Shortcut"
        )
    }

    private func makeRuntimeContext(
        windowStates: [BrowserWindowState],
        validationRecorder: RuntimeValidationRecorder,
        persistenceRecorder: RuntimeWindowSessionPersistenceRecorder? = nil
    ) -> RuntimePortRegistry {
        let statesById = Dictionary(uniqueKeysWithValues: windowStates.map { ($0.id, $0) })
        return TestRuntimePorts.make(
            windowState: { statesById[$0] },
            windows: { windowStates.map { ($0.id, $0) } },
            windowStates: { windowStates },
            validateWindowStates: {
                validationRecorder.count += 1
                return []
            },
            persistWindowSession: { windowState in
                persistenceRecorder?.windowIds.append(windowState.id)
            }
        )
    }

    private func makeBrowser(
        runtimePorts: RuntimePortRegistry? = nil
    ) -> BrowserManager {
        BrowserManager(
            runtimePorts: runtimePorts ?? TestRuntimePorts.inactive,
            automaticallyStartPersistedStateLoad: false
        )
    }

    private func makeSpace(
        in browser: BrowserManager,
        name: String,
        profileID: UUID? = nil
    ) -> Space {
        let space = Space(name: name, profileId: profileID)
        browser.spaceStateOwner.append(space)
        return space
    }

    private func makeFolder(
        in browser: BrowserManager,
        spaceID: UUID,
        name: String
    ) -> TabFolder {
        let folder = TabFolder(name: name, spaceId: spaceID)
        let existing = browser.folderCollectionStateOwner.folders(for: spaceID)
        browser.structuralCollectionMutationOwner.setFolders(
            existing + [folder],
            for: spaceID
        )
        return folder
    }
}

@MainActor
private final class RuntimeValidationRecorder {
    var count = 0
}

@MainActor
private final class RuntimeWindowSessionPersistenceRecorder {
    var windowIds: [UUID] = []
}

@MainActor
private final class StructuralEventRecorder {
    private var cancellable: AnyCancellable?
    private(set) var count = 0

    init(tabManager: BrowserManager) {
        cancellable = tabManager.tabStructureEventBus.structureChangedPublisher.sink { [weak self] _ in
            self?.count += 1
        }
    }

    func reset() {
        count = 0
    }
}

private final class TabsBySpaceRecorder {
    private var cancellable: AnyCancellable?
    private(set) var snapshots: [[UUID]] = []

    @MainActor
    init(tabManager: BrowserManager, spaceId: UUID) {
        cancellable = tabManager.tabStateStore.regularTabs.tabsBySpacePublisher.sink { [weak self] tabsBySpace in
            self?.snapshots.append(tabsBySpace[spaceId]?.map(\.id) ?? [])
        }
    }

    func reset() {
        snapshots.removeAll()
    }
}
