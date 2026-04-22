import Combine
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class TabManagerStructuralBatchingTests: XCTestCase {
    func testTopLevelPinnedReorderPublishesOnceForFolderAndPinUpdates() throws {
        let tabManager = try makeInMemoryTabManager()
        let recorder = StructuralEventRecorder(tabManager: tabManager)
        let space = tabManager.createSpace(name: "Workspace")
        let folder = tabManager.createFolder(for: space.id, name: "Folder")
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            launchURL: URL(string: "https://example.com/pinned")!,
            title: "Pinned"
        )
        folder.index = 1
        tabManager.setFolders([folder], for: space.id)
        tabManager.setSpacePinnedShortcuts([pin], for: space.id)
        recorder.reset()

        tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .folder(folder),
                fromContainer: .spacePinned(space.id),
                toContainer: .spacePinned(space.id),
                toIndex: 0,
                toSpaceId: space.id
            )
        )

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(tabManager.topLevelSpacePinnedItems(for: space.id).map(\.id), [folder.id, pin.id])
    }

    func testNestedRegularMutationsPublishOnceAndPreserveFinalOrder() throws {
        let tabManager = try makeInMemoryTabManager()
        let recorder = StructuralEventRecorder(tabManager: tabManager)
        let space = tabManager.createSpace(name: "Workspace")
        let first = tabManager.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.createNewTab(url: "https://example.com/two", in: space, activate: false)
        let third = tabManager.createNewTab(url: "https://example.com/three", in: space, activate: false)
        let batchFlushesBefore = tabManager.structuralLookupBatchFlushCount
        recorder.reset()

        tabManager.withStructuralUpdateTransaction {
            tabManager.reorderRegularTabs(first, in: space.id, to: 3)
            tabManager.reorderRegularTabs(second, in: space.id, to: 3)
        }

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(tabManager.structuralLookupBatchFlushCount, batchFlushesBefore + 1)
        XCTAssertEqual(tabManager.tabsBySpace[space.id]?.map(\.id), [third.id, first.id, second.id])
        XCTAssertEqual(tabManager.tabsBySpace[space.id]?.map(\.index), [0, 1, 2])
    }

    func testLookupBatchFlushesOncePerTransactionAndLookupIsCorrectAfterward() throws {
        let tabManager = try makeInMemoryTabManager()
        let recorder = StructuralEventRecorder(tabManager: tabManager)
        let space = tabManager.createSpace(name: "Workspace")
        let first = tabManager.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.createNewTab(url: "https://example.com/two", in: space, activate: false)
        let batchFlushesBefore = tabManager.structuralLookupBatchFlushCount
        let immediateFlushesBefore = tabManager.structuralLookupImmediateFlushCount
        recorder.reset()

        tabManager.withStructuralUpdateTransaction {
            tabManager.reorderRegularTabs(first, in: space.id, to: 2)
            tabManager.reorderRegularTabs(first, in: space.id, to: 0)
        }

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(tabManager.structuralLookupBatchFlushCount, batchFlushesBefore + 1)
        XCTAssertEqual(tabManager.structuralLookupImmediateFlushCount, immediateFlushesBefore)
        XCTAssertEqual(tabManager.tab(for: first.id)?.id, first.id)
        XCTAssertEqual(tabManager.tab(for: second.id)?.id, second.id)
    }

    func testRemovingSelectedTabPublishesOnceAndSelectsReplacement() throws {
        let tabManager = try makeInMemoryTabManager()
        let recorder = StructuralEventRecorder(tabManager: tabManager)
        let space = tabManager.createSpace(name: "Workspace")
        let first = tabManager.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.createNewTab(url: "https://example.com/two", in: space, activate: false)
        tabManager.setActiveTab(first)
        recorder.reset()

        tabManager.removeTab(first.id)

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(tabManager.currentTab?.id, second.id)
        XCTAssertEqual(tabManager.tabsBySpace[space.id]?.map(\.id), [second.id])
    }

    func testConvertingLiveFolderLauncherBackToRegularPublishesOnceAndClearsLiveBinding() throws {
        let tabManager = try makeInMemoryTabManager()
        let recorder = StructuralEventRecorder(tabManager: tabManager)
        let space = tabManager.createSpace(name: "Workspace")
        let folder = tabManager.createFolder(for: space.id, name: "Folder")
        let tab = tabManager.createNewTab(url: "https://example.com/folder", in: space)

        tabManager.moveTabToFolder(tab: tab, folderId: folder.id)
        let pin = try XCTUnwrap(tabManager.folderPinnedPins(for: folder.id, in: space.id).first)
        let windowId = UUID()
        let liveTab = tabManager.activateShortcutPin(pin, in: windowId, currentSpaceId: space.id)
        XCTAssertEqual(liveTab.shortcutPinId, pin.id)
        recorder.reset()

        tabManager.convertShortcutPinToRegularTab(pin, in: space.id, at: 0)

        XCTAssertEqual(recorder.count, 1)
        XCTAssertTrue(tabManager.spacePinnedPins(for: space.id).isEmpty)
        XCTAssertNil(tabManager.shortcutLiveTab(for: pin.id, in: windowId))
        let convertedTab = try XCTUnwrap(tabManager.tabsBySpace[space.id]?.first)
        XCTAssertEqual(convertedTab.url, pin.launchURL)
        XCTAssertEqual(convertedTab.spaceId, space.id)
        XCTAssertFalse(convertedTab.isShortcutLiveInstance)
        XCTAssertEqual(tabManager.tab(for: convertedTab.id)?.id, convertedTab.id)
    }

    private func makeInMemoryTabManager() throws -> TabManager {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return TabManager(context: container.mainContext, loadPersistedState: false)
    }
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
