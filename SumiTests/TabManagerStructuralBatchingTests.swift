import Combine
import SwiftData
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabManagerStructuralBatchingTests: XCTestCase {
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

    func testAdoptingGlanceTabInsertsAfterSourceAndPreservesWebView() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.createSpace(name: "Workspace")
        let source = tabManager.createNewTab(url: "https://example.com/source", in: space)
        let trailing = tabManager.createNewTab(url: "https://example.com/trailing", in: space, activate: false)
        let preview = Tab(
            url: URL(string: "https://destination.example/preview")!,
            name: "Preview",
            spaceId: space.id
        )
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        preview._webView = webView

        let adopted = tabManager.adoptGlanceTab(preview, sourceTab: source, in: space)

        XCTAssertTrue(adopted === preview)
        XCTAssertTrue(preview.existingWebView === webView)
        XCTAssertEqual(tabManager.tabsBySpace[space.id]?.map(\.id), [
            source.id,
            preview.id,
            trailing.id,
        ])
        XCTAssertEqual(tabManager.tabsBySpace[space.id]?.map(\.index), [0, 1, 2])
        XCTAssertEqual(tabManager.tab(for: preview.id)?.id, preview.id)
    }

    func testDuplicatingRegularTabPublishesOnlyFinalInsertionOrder() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.createSpace(name: "Workspace")
        let source = tabManager.createNewTab(url: "https://example.com/source", in: space)
        let trailing = tabManager.createNewTab(url: "https://example.com/trailing", in: space, activate: false)
        let recorder = TabsBySpaceRecorder(tabManager: tabManager, spaceId: space.id)
        recorder.reset()

        let duplicate = tabManager.duplicateAsRegularForSplit(from: source, anchor: source)

        let expectedOrder = [source.id, duplicate.id, trailing.id]
        XCTAssertEqual(tabManager.tabsBySpace[space.id]?.map(\.id), expectedOrder)
        XCTAssertEqual(recorder.snapshots, [expectedOrder])
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

    func testTogglingFolderOpenStatePublishesOnce() throws {
        let tabManager = try makeInMemoryTabManager()
        let recorder = StructuralEventRecorder(tabManager: tabManager)
        let space = tabManager.createSpace(name: "Workspace")
        let folder = tabManager.createFolder(for: space.id, name: "Folder")
        recorder.reset()

        tabManager.toggleFolderOpenState(folder.id)

        XCTAssertTrue(folder.isOpen)
        XCTAssertEqual(recorder.count, 1)
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

private final class TabsBySpaceRecorder {
    private var cancellable: AnyCancellable?
    private(set) var snapshots: [[UUID]] = []

    @MainActor
    init(tabManager: TabManager, spaceId: UUID) {
        cancellable = tabManager.$tabsBySpace.sink { [weak self] tabsBySpace in
            self?.snapshots.append(tabsBySpace[spaceId]?.map(\.id) ?? [])
        }
    }

    func reset() {
        snapshots.removeAll()
    }
}
