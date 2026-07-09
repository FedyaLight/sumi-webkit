import Combine
import SwiftData
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabManagerStructuralBatchingTests: XCTestCase {
    func testStructuralPublishOwnerCoalescesNestedTransactionsAndFlushesBeforePublish() {
        let changes = PassthroughSubject<Void, Never>()
        let owner = TabStructuralPublishOwner(structuralChanges: changes)
        var eventCount = 0
        var flushCount = 0
        var flushCountsAtPublish: [Int] = []
        let cancellable = changes.sink {
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

    func testNestedRegularMutationsPublishOnceAndPreserveFinalOrder() throws {
        let tabManager = try makeInMemoryTabManager()
        let recorder = StructuralEventRecorder(tabManager: tabManager)
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Workspace")
        let first = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/two", in: space, activate: false)
        let third = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/three", in: space, activate: false)
        let batchFlushesBefore = tabManager.structuralLookupBatchFlushCount
        recorder.reset()

        tabManager.withStructuralUpdateTransaction {
            tabManager.regularTabCollectionOwner.reorderRegularTabs(first, in: space.id, to: 3)
            tabManager.regularTabCollectionOwner.reorderRegularTabs(second, in: space.id, to: 3)
        }

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(tabManager.structuralLookupBatchFlushCount, batchFlushesBefore + 1)
        XCTAssertEqual(tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[space.id]?.map(\.id), [third.id, first.id, second.id])
        XCTAssertEqual(tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[space.id]?.map(\.index), [0, 1, 2])
    }

    func testLookupBatchFlushesOncePerTransactionAndLookupIsCorrectAfterward() throws {
        let tabManager = try makeInMemoryTabManager()
        let recorder = StructuralEventRecorder(tabManager: tabManager)
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Workspace")
        let first = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/two", in: space, activate: false)
        let batchFlushesBefore = tabManager.structuralLookupBatchFlushCount
        let immediateFlushesBefore = tabManager.structuralLookupImmediateFlushCount
        recorder.reset()

        tabManager.withStructuralUpdateTransaction {
            tabManager.regularTabCollectionOwner.reorderRegularTabs(first, in: space.id, to: 2)
            tabManager.regularTabCollectionOwner.reorderRegularTabs(first, in: space.id, to: 0)
        }

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(tabManager.structuralLookupBatchFlushCount, batchFlushesBefore + 1)
        XCTAssertEqual(tabManager.structuralLookupImmediateFlushCount, immediateFlushesBefore)
        XCTAssertEqual(tabManager.tabCollectionMembershipOwner.tab(for: first.id)?.id, first.id)
        XCTAssertEqual(tabManager.tabCollectionMembershipOwner.tab(for: second.id)?.id, second.id)
    }

    func testLookupReadInsideTransactionFlushesPendingRegularMutationsImmediately() throws {
        let tabManager = try makeInMemoryTabManager()
        let recorder = StructuralEventRecorder(tabManager: tabManager)
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Workspace")
        let first = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/two", in: space, activate: false)
        let batchFlushesBefore = tabManager.structuralLookupBatchFlushCount
        let immediateFlushesBefore = tabManager.structuralLookupImmediateFlushCount
        recorder.reset()

        tabManager.withStructuralUpdateTransaction {
            tabManager.regularTabCollectionOwner.reorderRegularTabs(first, in: space.id, to: 2)

            XCTAssertEqual(recorder.count, 0)
            XCTAssertEqual(tabManager.structuralLookupBatchFlushCount, batchFlushesBefore)
            XCTAssertEqual(tabManager.tabCollectionMembershipOwner.tab(for: first.id)?.id, first.id)
            XCTAssertEqual(tabManager.tabCollectionMembershipOwner.tab(for: second.id)?.id, second.id)
            XCTAssertEqual(tabManager.structuralLookupImmediateFlushCount, immediateFlushesBefore + 1)
        }

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(tabManager.structuralLookupBatchFlushCount, batchFlushesBefore)
        XCTAssertEqual(tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[space.id]?.map(\.id), [second.id, first.id])
    }

    func testTransientShortcutLookupRefreshFlushesImmediatelyInsideTransaction() throws {
        let tabManager = try makeInMemoryTabManager()
        let recorder = StructuralEventRecorder(tabManager: tabManager)
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Workspace")
        let folder = tabManager.folderMutationOwner.createFolder(for: space.id, name: "Folder")
        let regular = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/folder", in: space)
        tabManager.folderMutationOwner.moveTabToFolder(tab: regular, folderId: folder.id)
        let pin = try XCTUnwrap(tabManager.shortcutPinCollectionStateOwner.folderPinnedPins(for: folder.id, in: space.id).first)
        let windowId = UUID()
        let batchFlushesBefore = tabManager.structuralLookupBatchFlushCount
        let immediateFlushesBefore = tabManager.structuralLookupImmediateFlushCount
        recorder.reset()

        tabManager.withStructuralUpdateTransaction {
            let liveTab = tabManager.shortcutLiveTabOwner.activateShortcutPin(pin, in: windowId, currentSpaceId: space.id)

            XCTAssertEqual(recorder.count, 0)
            XCTAssertEqual(tabManager.tabCollectionMembershipOwner.tab(for: liveTab.id)?.id, liveTab.id)
            XCTAssertEqual(tabManager.structuralLookupImmediateFlushCount, immediateFlushesBefore + 1)

            tabManager.shortcutLiveTabOwner.deactivateShortcutLiveTab(pinId: pin.id, in: windowId)

            XCTAssertNil(tabManager.tabCollectionMembershipOwner.tab(for: liveTab.id))
            XCTAssertEqual(tabManager.structuralLookupImmediateFlushCount, immediateFlushesBefore + 2)
        }

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(tabManager.structuralLookupBatchFlushCount, batchFlushesBefore)
    }

    func testRemoveSelectedShortcutPinClearsWindowShortcutSelection() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Workspace")
        let pin = makeSpacePinnedShortcut(spaceId: space.id)
        tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([pin], for: space.id)
        let windowState = BrowserWindowState()
        windowState.tabManager = tabManager
        windowState.currentSpaceId = space.id
        let validationRecorder = RuntimeValidationRecorder()
        attachRuntimeContext(tabManager, windowStates: [windowState], validationRecorder: validationRecorder)
        let liveTab = tabManager.shortcutLiveTabOwner.activateShortcutPin(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )
        let regularHistoryId = UUID()
        windowState.currentTabId = liveTab.id
        windowState.currentShortcutPinId = pin.id
        windowState.currentShortcutPinRole = pin.role
        windowState.selectedShortcutPinForSpace[space.id] = pin.id
        windowState.selectionHistory.recentSelectionItemsBySpace[space.id] = [
            .shortcutPin(pin.id),
            .regularTab(regularHistoryId),
        ]

        tabManager.shortcutPinCommandOwner.removeShortcutPin(pin)

        XCTAssertNil(tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id))
        XCTAssertNil(tabManager.tabCollectionMembershipOwner.tab(for: liveTab.id))
        XCTAssertNil(windowState.currentTabId)
        XCTAssertNil(windowState.currentShortcutPinId)
        XCTAssertNil(windowState.currentShortcutPinRole)
        XCTAssertNil(windowState.selectedShortcutPinForSpace[space.id])
        XCTAssertEqual(windowState.selectionHistory.recentSelectionItemsBySpace[space.id], [.regularTab(regularHistoryId)])
        XCTAssertEqual(validationRecorder.count, 1)
    }

    func testDeactivateSelectedShortcutLiveTabClearsCurrentSelectionWithoutValidation() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Workspace")
        let pin = makeSpacePinnedShortcut(spaceId: space.id)
        tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([pin], for: space.id)
        let windowState = BrowserWindowState()
        windowState.tabManager = tabManager
        windowState.currentSpaceId = space.id
        let validationRecorder = RuntimeValidationRecorder()
        attachRuntimeContext(tabManager, windowStates: [windowState], validationRecorder: validationRecorder)
        let liveTab = tabManager.shortcutLiveTabOwner.activateShortcutPin(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )
        windowState.currentTabId = liveTab.id
        windowState.currentShortcutPinId = pin.id
        windowState.currentShortcutPinRole = pin.role

        let didClearSelection = tabManager.shortcutLiveTabOwner.deactivateShortcutLiveTab(pinId: pin.id, in: windowState.id)

        XCTAssertTrue(didClearSelection)
        XCTAssertNil(tabManager.tabCollectionMembershipOwner.tab(for: liveTab.id))
        XCTAssertNil(windowState.currentTabId)
        XCTAssertNil(windowState.currentShortcutPinId)
        XCTAssertNil(windowState.currentShortcutPinRole)
        XCTAssertEqual(validationRecorder.count, 0)
    }

    func testRemoveShortcutPinClearsProxySelectionWithoutLiveTab() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Workspace")
        let pin = makeSpacePinnedShortcut(spaceId: space.id)
        tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([pin], for: space.id)
        let windowState = BrowserWindowState()
        windowState.tabManager = tabManager
        windowState.currentSpaceId = space.id
        let validationRecorder = RuntimeValidationRecorder()
        attachRuntimeContext(tabManager, windowStates: [windowState], validationRecorder: validationRecorder)
        windowState.currentTabId = pin.id
        windowState.currentShortcutPinId = pin.id
        windowState.currentShortcutPinRole = pin.role
        windowState.selectedShortcutPinForSpace[space.id] = pin.id
        windowState.selectionHistory.recentSelectionItemsBySpace[space.id] = [.shortcutPin(pin.id)]

        tabManager.shortcutPinCommandOwner.removeShortcutPin(pin)

        XCTAssertNil(tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id))
        XCTAssertNil(windowState.currentTabId)
        XCTAssertNil(windowState.currentShortcutPinId)
        XCTAssertNil(windowState.currentShortcutPinRole)
        XCTAssertNil(windowState.selectedShortcutPinForSpace[space.id])
        XCTAssertNil(windowState.selectionHistory.recentSelectionItemsBySpace[space.id])
        XCTAssertEqual(validationRecorder.count, 1)
    }

    func testRemoveBackgroundShortcutPinPreservesRegularSelection() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Workspace")
        let pin = makeSpacePinnedShortcut(spaceId: space.id)
        tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([pin], for: space.id)
        let regularTab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/regular", in: space)
        let windowState = BrowserWindowState()
        windowState.tabManager = tabManager
        windowState.currentSpaceId = space.id
        windowState.currentTabId = regularTab.id
        windowState.selectedShortcutPinForSpace[space.id] = pin.id
        windowState.selectionHistory.recentSelectionItemsBySpace[space.id] = [
            .shortcutPin(pin.id),
            .regularTab(regularTab.id),
        ]
        let validationRecorder = RuntimeValidationRecorder()
        let persistenceRecorder = RuntimeWindowSessionPersistenceRecorder()
        attachRuntimeContext(
            tabManager,
            windowStates: [windowState],
            validationRecorder: validationRecorder,
            persistenceRecorder: persistenceRecorder
        )
        let liveTab = tabManager.shortcutLiveTabOwner.activateShortcutPin(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )

        tabManager.shortcutPinCommandOwner.removeShortcutPin(pin)

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
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Workspace")
        let folder = tabManager.folderMutationOwner.createFolder(for: space.id, name: "Pinned")
        let pin = makeSpacePinnedShortcut(spaceId: space.id, folderId: folder.id)
        tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([pin], for: space.id)
        let windowState = BrowserWindowState()
        windowState.tabManager = tabManager
        windowState.currentSpaceId = space.id
        let validationRecorder = RuntimeValidationRecorder()
        attachRuntimeContext(tabManager, windowStates: [windowState], validationRecorder: validationRecorder)
        let liveTab = tabManager.shortcutLiveTabOwner.activateShortcutPin(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )
        windowState.currentTabId = liveTab.id
        windowState.currentShortcutPinId = pin.id
        windowState.currentShortcutPinRole = pin.role
        windowState.selectedShortcutPinForSpace[space.id] = pin.id
        windowState.selectionHistory.recentSelectionItemsBySpace[space.id] = [.shortcutPin(pin.id)]

        tabManager.folderMutationOwner.deleteFolder(folder.id)

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

    func testLookupIncludesTransientExtensionAndAuxiliaryTabs() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Workspace")
        let opener = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/opener", in: space)

        let transientExtension = tabManager.transientWebKitTabLifecycleOwner.createTransientExtensionTab(
            url: "https://example.com/transient",
            in: space,
            webExtensionContextOverride: nil
        )
        let auxiliary = tabManager.transientWebKitTabLifecycleOwner.createAuxiliaryMiniWindowTab(
            openerTab: opener,
            profileId: nil,
            urlString: nil,
            webExtensionContextOverride: nil
        )

        XCTAssertIdentical(tabManager.tabCollectionMembershipOwner.tab(for: transientExtension.id), transientExtension)
        XCTAssertIdentical(tabManager.tabCollectionMembershipOwner.tab(for: auxiliary.id), auxiliary)

        tabManager.transientWebKitTabLifecycleOwner.removeAuxiliaryMiniWindowTab(auxiliary)
        tabManager.tabRemovalOwner.removeTab(transientExtension.id)

        XCTAssertNil(tabManager.tabCollectionMembershipOwner.tab(for: auxiliary.id))
        XCTAssertNil(tabManager.tabCollectionMembershipOwner.tab(for: transientExtension.id))
    }

    func testAddTabWithoutSpaceDoesNotFallbackToCurrentSpaceOrAttachOrphan() throws {
        let tabManager = try makeInMemoryTabManager()
        let primarySpace = tabManager.spaceLifecycleOwner.createSpace(name: "Primary")
        let currentSpace = tabManager.spaceLifecycleOwner.createSpace(name: "Current")
        tabManager.spaceStateOwner.replaceCurrentSpace(currentSpace)
        let tab = Tab(
            url: URL(string: "https://example.com/orphan")!,
            name: "Orphan",
            spaceId: nil
        )

        tabManager.regularTabLifecycleOwner.addTab(tab)

        XCTAssertNil(tab.spaceId)
        XCTAssertTrue(tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[primarySpace.id]?.isEmpty ?? true)
        XCTAssertTrue(tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[currentSpace.id]?.isEmpty ?? true)
        XCTAssertNil(tabManager.tabCollectionMembershipOwner.tab(for: tab.id))
    }

    func testPromotingTransientExtensionWithoutTargetSpaceDoesNotFallbackToCurrentSpace() throws {
        let tabManager = try makeInMemoryTabManager()
        let sourceSpace = tabManager.spaceLifecycleOwner.createSpace(name: "Source")
        let currentSpace = tabManager.spaceLifecycleOwner.createSpace(name: "Current")
        tabManager.spaceStateOwner.replaceCurrentSpace(currentSpace)
        let transientExtension = tabManager.transientWebKitTabLifecycleOwner.createTransientExtensionTab(
            url: "https://example.com/transient",
            in: sourceSpace,
            webExtensionContextOverride: nil
        )
        transientExtension.spaceId = nil

        let promoted = tabManager.transientWebKitTabLifecycleOwner.promoteTransientExtensionTab(
            transientExtension,
            in: nil,
            activate: false
        )

        XCTAssertFalse(promoted)
        XCTAssertTrue(tabManager.transientWebKitTabLifecycleOwner.isTransientExtensionTab(transientExtension))
        XCTAssertTrue(tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[currentSpace.id]?.isEmpty ?? true)
        XCTAssertNil(tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[sourceSpace.id]?.first { $0.id == transientExtension.id })
    }

    func testTabCreationWithoutTargetSpaceUsesDefaultSpaceInsteadOfCurrentSpace() throws {
        let tabManager = try makeInMemoryTabManager()
        let defaultSpace = tabManager.spaceLifecycleOwner.createSpace(name: "Default")
        let currentSpace = tabManager.spaceLifecycleOwner.createSpace(name: "Current")

        tabManager.spaceStateOwner.replaceCurrentSpace(currentSpace)
        let regular = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/regular",
            in: nil,
            activate: false
        )

        tabManager.spaceStateOwner.replaceCurrentSpace(currentSpace)
        let transientExtension = tabManager.transientWebKitTabLifecycleOwner.createTransientExtensionTab(
            url: "https://example.com/transient",
            in: nil,
            webExtensionContextOverride: nil
        )

        tabManager.spaceStateOwner.replaceCurrentSpace(currentSpace)
        let webViewBacked = tabManager.regularTabLifecycleOwner.createNewTabWithWebView(
            url: "https://example.com/webview",
            in: nil
        )

        tabManager.spaceStateOwner.replaceCurrentSpace(currentSpace)
        let popup = tabManager.regularTabLifecycleOwner.createPopupTab(in: nil, activate: false)

        XCTAssertEqual(regular.spaceId, defaultSpace.id)
        XCTAssertEqual(transientExtension.spaceId, defaultSpace.id)
        XCTAssertEqual(webViewBacked.spaceId, defaultSpace.id)
        XCTAssertEqual(popup.spaceId, defaultSpace.id)
        XCTAssertTrue(tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[currentSpace.id]?.isEmpty ?? true)
    }

    func testTabCreationWithoutTargetSpaceUsesCurrentProfileSpaceBeforeFirstSpace() throws {
        let tabManager = try makeInMemoryTabManager()
        let firstProfileId = UUID()
        let currentProfileId = UUID()
        let firstProfileSpace = tabManager.spaceLifecycleOwner.createSpace(name: "First", profileId: firstProfileId)
        let currentProfileSpace = tabManager.spaceLifecycleOwner.createSpace(name: "Current Profile", profileId: currentProfileId)
        tabManager.spaceStateOwner.replaceCurrentSpace(firstProfileSpace)
        tabManager.runtimeContextAttachmentOwner.attach(
            TabManagerRuntimeContext(
                currentProfileId: { currentProfileId },
                defaultProfileId: { firstProfileId }
            )
        )

        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/profile",
            in: nil,
            activate: false
        )

        XCTAssertEqual(tab.spaceId, currentProfileSpace.id)
        XCTAssertEqual(tab.profileId, currentProfileId)
        XCTAssertTrue(tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[firstProfileSpace.id]?.isEmpty ?? true)
    }

    func testTransientExtensionTabWithoutTargetSpaceUsesCurrentProfileSpaceBeforeFirstSpace() throws {
        let tabManager = try makeInMemoryTabManager()
        let defaultProfileId = UUID()
        let currentProfileId = UUID()
        let defaultProfileSpace = tabManager.spaceLifecycleOwner.createSpace(name: "Default Profile", profileId: defaultProfileId)
        let currentProfileSpace = tabManager.spaceLifecycleOwner.createSpace(name: "Current Profile", profileId: currentProfileId)
        tabManager.spaceStateOwner.replaceCurrentSpace(defaultProfileSpace)
        tabManager.runtimeContextAttachmentOwner.attach(
            TabManagerRuntimeContext(
                currentProfileId: { currentProfileId },
                defaultProfileId: { defaultProfileId }
            )
        )

        let transientExtension = tabManager.transientWebKitTabLifecycleOwner.createTransientExtensionTab(
            url: "https://example.com/transient",
            in: nil,
            webExtensionContextOverride: nil
        )

        XCTAssertEqual(transientExtension.profileId, currentProfileId)
        XCTAssertEqual(transientExtension.spaceId, currentProfileSpace.id)
        XCTAssertTrue(tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[defaultProfileSpace.id]?.isEmpty ?? true)
    }

    func testSelectionTabsForWindowContextUsesWindowSpaceInsteadOfCurrentSpace() throws {
        let tabManager = try makeInMemoryTabManager()
        let windowProfileId = UUID()
        let globalProfileId = UUID()
        let windowSpace = tabManager.spaceLifecycleOwner.createSpace(name: "Window", profileId: windowProfileId)
        let globalSpace = tabManager.spaceLifecycleOwner.createSpace(name: "Global", profileId: globalProfileId)
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
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = windowSpace.id
        windowState.currentProfileId = windowProfileId

        let windowEssentialPin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: windowProfileId,
            spaceId: nil,
            index: 0,
            folderId: nil,
            launchURL: URL(string: "https://window.example/essential")!,
            title: "Window Essential",
            iconAsset: nil
        )
        let globalEssentialPin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: globalProfileId,
            spaceId: nil,
            index: 0,
            folderId: nil,
            launchURL: URL(string: "https://global.example/essential")!,
            title: "Global Essential",
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
        tabManager.structuralCollectionMutationOwner.setPinnedTabs([windowEssentialPin], for: windowProfileId)
        tabManager.structuralCollectionMutationOwner.setPinnedTabs([globalEssentialPin], for: globalProfileId)
        tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([windowSpacePin], for: windowSpace.id)
        tabManager.spaceStateOwner.replaceCurrentSpace(globalSpace)
        tabManager.runtimeContextAttachmentOwner.attach(
            TabManagerRuntimeContext(
                currentProfileId: { globalProfileId },
                windowState: { id in
                    id == windowState.id ? windowState : nil
                }
            )
        )

        let windowEssential = tabManager.shortcutLiveTabOwner.activateShortcutPin(
            windowEssentialPin,
            in: windowState.id,
            currentSpaceId: windowSpace.id
        )
        let globalEssential = tabManager.shortcutLiveTabOwner.activateShortcutPin(
            globalEssentialPin,
            in: UUID(),
            currentSpaceId: globalSpace.id
        )
        let windowLauncher = tabManager.shortcutLiveTabOwner.activateShortcutPin(
            windowSpacePin,
            in: windowState.id,
            currentSpaceId: windowSpace.id
        )
        windowState.currentShortcutPinId = windowSpacePin.id

        let selection = tabManager.activeSelectionOwner.selectionTabsForCurrentContext(in: windowState.id)
        let selectionIds = selection.map(\.id)

        XCTAssertTrue(selectionIds.contains(windowEssential.id))
        XCTAssertTrue(selectionIds.contains(windowLauncher.id))
        XCTAssertTrue(selectionIds.contains(windowRegular.id))
        XCTAssertFalse(selectionIds.contains(globalEssential.id))
        XCTAssertFalse(selectionIds.contains(globalRegular.id))
    }

    func testSplitGroupLookupsFollowStructuralMutations() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Workspace")
        let first = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/two", in: space, activate: false)
        let third = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/three", in: space, activate: false)
        let fourth = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/four", in: space, activate: false)
        let initial = try XCTUnwrap(
            SplitGroup.make(tabIds: [first.id, second.id], layoutKind: .vertical, activeTabId: first.id)
        )

        tabManager.splitGroupStructureOwner.upsertSplitGroup(initial)

        XCTAssertEqual(tabManager.splitGroupCollectionStateOwner.group(with: initial.id)?.id, initial.id)
        XCTAssertEqual(tabManager.splitGroupStructureOwner.splitGroup(containing: first.id)?.id, initial.id)
        XCTAssertEqual(tabManager.splitGroupStructureOwner.splitGroupIds(containing: second.id), [initial.id])

        let replacement = try XCTUnwrap(
            SplitGroup.make(tabIds: [second.id, third.id, fourth.id], layoutKind: .horizontal, activeTabId: third.id)
        )
        tabManager.splitGroupStructureOwner.upsertSplitGroup(replacement)

        XCTAssertNil(tabManager.splitGroupCollectionStateOwner.group(with: initial.id))
        XCTAssertNil(tabManager.splitGroupStructureOwner.splitGroup(containing: first.id))
        XCTAssertEqual(tabManager.splitGroupStructureOwner.splitGroup(containing: second.id)?.id, replacement.id)
        XCTAssertEqual(tabManager.splitGroupStructureOwner.splitGroup(containing: fourth.id)?.id, replacement.id)

        tabManager.splitGroupStructureOwner.removeSplitGroups(containing: second.id)

        let trimmed = try XCTUnwrap(tabManager.splitGroupCollectionStateOwner.group(with: replacement.id))
        XCTAssertEqual(trimmed.tabIds, [third.id, fourth.id])
        XCTAssertNil(tabManager.splitGroupStructureOwner.splitGroup(containing: second.id))
        XCTAssertEqual(tabManager.splitGroupStructureOwner.splitGroup(containing: third.id)?.id, replacement.id)

        let final = try XCTUnwrap(
            SplitGroup.make(tabIds: [first.id, fourth.id], layoutKind: .vertical, activeTabId: fourth.id)
        )
        tabManager.splitGroupStructureOwner.replaceSplitGroups([final])

        XCTAssertEqual(tabManager.splitGroupCollectionStateOwner.group(with: final.id)?.id, final.id)
        XCTAssertNil(tabManager.splitGroupCollectionStateOwner.group(with: replacement.id))
        XCTAssertNil(tabManager.splitGroupStructureOwner.splitGroup(containing: third.id))
        XCTAssertEqual(tabManager.splitGroupStructureOwner.splitGroup(containing: first.id)?.id, final.id)

        tabManager.splitGroupStructureOwner.removeSplitGroup(id: final.id)

        XCTAssertNil(tabManager.splitGroupCollectionStateOwner.group(with: final.id))
        XCTAssertNil(tabManager.splitGroupStructureOwner.splitGroup(containing: first.id))
    }

    func testSplitGroupReplacementRefreshesLookups() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Workspace")
        let first = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/two", in: space, activate: false)
        let group = try XCTUnwrap(
            SplitGroup.make(tabIds: [first.id, second.id], layoutKind: .vertical, activeTabId: first.id)
        )

        tabManager.splitGroupStructureOwner.replaceSplitGroups([group])

        XCTAssertEqual(tabManager.splitGroupCollectionStateOwner.group(with: group.id)?.id, group.id)
        XCTAssertEqual(tabManager.splitGroupStructureOwner.splitGroup(containing: first.id)?.id, group.id)

        tabManager.splitGroupStructureOwner.replaceSplitGroups([])

        XCTAssertNil(tabManager.splitGroupCollectionStateOwner.group(with: group.id))
        XCTAssertNil(tabManager.splitGroupStructureOwner.splitGroup(containing: first.id))
    }

    func testSplitGroupMutationsPublishOnceAndLookupUpdatesDuringTransaction() throws {
        let tabManager = try makeInMemoryTabManager()
        let recorder = StructuralEventRecorder(tabManager: tabManager)
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Workspace")
        let first = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/two", in: space, activate: false)
        let third = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/three", in: space, activate: false)
        let initial = try XCTUnwrap(
            SplitGroup.make(tabIds: [first.id, second.id], layoutKind: .vertical, activeTabId: first.id)
        )
        let replacement = try XCTUnwrap(
            SplitGroup.make(tabIds: [second.id, third.id], layoutKind: .horizontal, activeTabId: third.id)
        )
        recorder.reset()

        tabManager.withStructuralUpdateTransaction {
            tabManager.splitGroupStructureOwner.upsertSplitGroup(initial)
            XCTAssertEqual(recorder.count, 0)
            XCTAssertEqual(tabManager.splitGroupStructureOwner.splitGroup(containing: first.id)?.id, initial.id)

            tabManager.splitGroupStructureOwner.upsertSplitGroup(replacement)
            XCTAssertEqual(recorder.count, 0)
            XCTAssertNil(tabManager.splitGroupStructureOwner.splitGroup(containing: first.id))
            XCTAssertEqual(tabManager.splitGroupStructureOwner.splitGroup(containing: third.id)?.id, replacement.id)
        }

        XCTAssertEqual(recorder.count, 1)
        XCTAssertNil(tabManager.splitGroupCollectionStateOwner.group(with: initial.id))
        XCTAssertEqual(tabManager.splitGroupStructureOwner.splitGroup(containing: second.id)?.id, replacement.id)
    }

    func testAdoptingGlanceTabInsertsAfterSourceAndPreservesWebView() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Workspace")
        let source = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/source", in: space)
        let trailing = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/trailing", in: space, activate: false)
        let preview = Tab(
            url: URL(string: "https://destination.example/preview")!,
            name: "Preview",
            spaceId: space.id
        )
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        preview.replaceUntrackedWebView(webView)

        let adopted = tabManager.regularTabLifecycleOwner.adoptGlanceTab(preview, sourceTab: source, in: space)

        XCTAssertIdentical(adopted, preview)
        XCTAssertIdentical(preview.resolvedCurrentWebView(), webView)
        XCTAssertEqual(tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[space.id]?.map(\.id), [
            source.id,
            preview.id,
            trailing.id,
        ])
        XCTAssertEqual(tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[space.id]?.map(\.index), [0, 1, 2])
        XCTAssertEqual(tabManager.tabCollectionMembershipOwner.tab(for: preview.id)?.id, preview.id)
    }

    func testTabCreationPathsKeepDistinctProfileAndPersistenceBehavior() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Workspace", profileId: profileId)

        let regular = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/regular",
            in: space,
            activate: false
        )
        let transientExtension = tabManager.transientWebKitTabLifecycleOwner.createTransientExtensionTab(
            url: "https://example.com/transient",
            in: space,
            webExtensionContextOverride: nil
        )
        let webViewBacked = tabManager.regularTabLifecycleOwner.createNewTabWithWebView(
            url: "https://example.com/webview",
            in: space
        )
        let popup = tabManager.regularTabLifecycleOwner.createPopupTab(in: space, activate: false)

        XCTAssertEqual(regular.spaceId, space.id)
        XCTAssertEqual(regular.profileId, profileId)
        XCTAssertEqual(transientExtension.spaceId, space.id)
        XCTAssertEqual(transientExtension.profileId, profileId)
        XCTAssertTrue(tabManager.transientWebKitTabLifecycleOwner.isTransientExtensionTab(transientExtension))

        XCTAssertEqual(webViewBacked.spaceId, space.id)
        XCTAssertNil(webViewBacked.profileId)
        XCTAssertEqual(popup.spaceId, space.id)
        XCTAssertNil(popup.profileId)
        XCTAssertTrue(popup.isPopupHost)

        XCTAssertEqual(tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[space.id]?.map(\.id), [
            regular.id,
            webViewBacked.id,
            popup.id,
        ])
        XCTAssertFalse((tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[space.id] ?? []).contains { $0.id == transientExtension.id })
    }

    func testGlanceAdoptionTargetsSourceSpaceAndBackfillsFromPreviewProfile() throws {
        let tabManager = try makeInMemoryTabManager()
        let sourceSpace = tabManager.spaceLifecycleOwner.createSpace(name: "Source")
        let currentSpace = tabManager.spaceLifecycleOwner.createSpace(name: "Current")
        let source = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/source",
            in: sourceSpace,
            activate: false
        )
        let previewProfileId = UUID()
        let preview = Tab(
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
        XCTAssertEqual(tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[sourceSpace.id]?.map(\.id), [
            source.id,
            preview.id,
        ])
    }

    func testDuplicatingRegularTabPublishesOnlyFinalInsertionOrder() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Workspace")
        let source = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/source", in: space)
        let trailing = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/trailing", in: space, activate: false)
        let recorder = TabsBySpaceRecorder(tabManager: tabManager, spaceId: space.id)
        recorder.reset()

        let duplicate = tabManager.regularTabLifecycleOwner.duplicateAsRegularForSplit(from: source, anchor: source)

        let expectedOrder = [source.id, duplicate.id, trailing.id]
        XCTAssertEqual(tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[space.id]?.map(\.id), expectedOrder)
        XCTAssertEqual(recorder.snapshots, [expectedOrder])
    }

    func testRemovingSelectedTabPublishesOnceAndSelectsReplacement() throws {
        let tabManager = try makeInMemoryTabManager()
        let recorder = StructuralEventRecorder(tabManager: tabManager)
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Workspace")
        let first = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/two", in: space, activate: false)
        tabManager.activeSelectionOwner.setActiveTab(first)
        recorder.reset()

        tabManager.tabRemovalOwner.removeTab(first.id)

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(tabManager.selectionStateOwner.currentTab?.id, second.id)
        XCTAssertEqual(tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[space.id]?.map(\.id), [second.id])
    }

    func testConvertingLiveFolderLauncherBackToRegularPublishesOnceAndClearsLiveBinding() throws {
        let tabManager = try makeInMemoryTabManager()
        let recorder = StructuralEventRecorder(tabManager: tabManager)
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Workspace")
        let folder = tabManager.folderMutationOwner.createFolder(for: space.id, name: "Folder")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/folder", in: space)

        tabManager.folderMutationOwner.moveTabToFolder(tab: tab, folderId: folder.id)
        let pin = try XCTUnwrap(tabManager.shortcutPinCollectionStateOwner.folderPinnedPins(for: folder.id, in: space.id).first)
        let windowId = UUID()
        let liveTab = tabManager.shortcutLiveTabOwner.activateShortcutPin(pin, in: windowId, currentSpaceId: space.id)
        XCTAssertEqual(liveTab.shortcutPinId, pin.id)
        recorder.reset()

        tabManager.shortcutPinCommandOwner.convertShortcutPinToRegularTab(pin, in: space.id, at: 0)

        XCTAssertEqual(recorder.count, 1)
        XCTAssertTrue(tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: space.id).isEmpty)
        XCTAssertNil(tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: windowId))
        let convertedTab = try XCTUnwrap(tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[space.id]?.first)
        XCTAssertEqual(convertedTab.url, pin.launchURL)
        XCTAssertEqual(convertedTab.spaceId, space.id)
        XCTAssertFalse(convertedTab.isShortcutLiveInstance)
        XCTAssertEqual(tabManager.tabCollectionMembershipOwner.tab(for: convertedTab.id)?.id, convertedTab.id)
    }

    func testTogglingFolderOpenStatePublishesOnce() throws {
        let tabManager = try makeInMemoryTabManager()
        let recorder = StructuralEventRecorder(tabManager: tabManager)
        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Workspace")
        let folder = tabManager.folderMutationOwner.createFolder(for: space.id, name: "Folder")
        recorder.reset()

        tabManager.folderMutationOwner.toggleFolderOpenState(folder.id)

        XCTAssertTrue(folder.isOpen)
        XCTAssertEqual(recorder.count, 1)
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

    private func attachRuntimeContext(
        _ tabManager: TabManager,
        windowStates: [BrowserWindowState],
        validationRecorder: RuntimeValidationRecorder,
        persistenceRecorder: RuntimeWindowSessionPersistenceRecorder? = nil
    ) {
        let statesById = Dictionary(uniqueKeysWithValues: windowStates.map { ($0.id, $0) })
        tabManager.runtimeContextAttachmentOwner.attach(
            TabManagerRuntimeContext(
                windowState: { statesById[$0] },
                windows: { windowStates.map { ($0.id, $0) } },
                windowStates: { windowStates },
                validateWindowStates: {
                    validationRecorder.count += 1
                },
                persistWindowSession: { windowState in
                    persistenceRecorder?.windowIds.append(windowState.id)
                }
            )
        )
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

    init(tabManager: TabManager) {
        cancellable = tabManager.structuralChanges.sink { [weak self] _ in
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
    init(tabManager: TabManager, spaceId: UUID) {
        cancellable = tabManager.regularTabCollectionStateOwner.tabsBySpacePublisher.sink { [weak self] tabsBySpace in
            self?.snapshots.append(tabsBySpace[spaceId]?.map(\.id) ?? [])
        }
    }

    func reset() {
        snapshots.removeAll()
    }
}
