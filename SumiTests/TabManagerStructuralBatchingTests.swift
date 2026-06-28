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

    func testLookupReadInsideTransactionFlushesPendingRegularMutationsImmediately() throws {
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

            XCTAssertEqual(recorder.count, 0)
            XCTAssertEqual(tabManager.structuralLookupBatchFlushCount, batchFlushesBefore)
            XCTAssertEqual(tabManager.tab(for: first.id)?.id, first.id)
            XCTAssertEqual(tabManager.tab(for: second.id)?.id, second.id)
            XCTAssertEqual(tabManager.structuralLookupImmediateFlushCount, immediateFlushesBefore + 1)
        }

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(tabManager.structuralLookupBatchFlushCount, batchFlushesBefore)
        XCTAssertEqual(tabManager.tabsBySpace[space.id]?.map(\.id), [second.id, first.id])
    }

    func testTransientShortcutLookupRefreshFlushesImmediatelyInsideTransaction() throws {
        let tabManager = try makeInMemoryTabManager()
        let recorder = StructuralEventRecorder(tabManager: tabManager)
        let space = tabManager.createSpace(name: "Workspace")
        let folder = tabManager.createFolder(for: space.id, name: "Folder")
        let regular = tabManager.createNewTab(url: "https://example.com/folder", in: space)
        tabManager.moveTabToFolder(tab: regular, folderId: folder.id)
        let pin = try XCTUnwrap(tabManager.folderPinnedPins(for: folder.id, in: space.id).first)
        let windowId = UUID()
        let batchFlushesBefore = tabManager.structuralLookupBatchFlushCount
        let immediateFlushesBefore = tabManager.structuralLookupImmediateFlushCount
        recorder.reset()

        tabManager.withStructuralUpdateTransaction {
            let liveTab = tabManager.activateShortcutPin(pin, in: windowId, currentSpaceId: space.id)

            XCTAssertEqual(recorder.count, 0)
            XCTAssertEqual(tabManager.tab(for: liveTab.id)?.id, liveTab.id)
            XCTAssertEqual(tabManager.structuralLookupImmediateFlushCount, immediateFlushesBefore + 1)

            tabManager.deactivateShortcutLiveTab(pinId: pin.id, in: windowId)

            XCTAssertNil(tabManager.tab(for: liveTab.id))
            XCTAssertEqual(tabManager.structuralLookupImmediateFlushCount, immediateFlushesBefore + 2)
        }

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(tabManager.structuralLookupBatchFlushCount, batchFlushesBefore)
    }

    func testLookupIncludesTransientExtensionAndAuxiliaryTabs() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.createSpace(name: "Workspace")
        let opener = tabManager.createNewTab(url: "https://example.com/opener", in: space)

        let transientExtension = tabManager.createTransientExtensionTab(
            url: "https://example.com/transient",
            in: space,
            webExtensionContextOverride: nil
        )
        let auxiliary = tabManager.createAuxiliaryMiniWindowTab(openerTab: opener)

        XCTAssertIdentical(tabManager.tab(for: transientExtension.id), transientExtension)
        XCTAssertIdentical(tabManager.tab(for: auxiliary.id), auxiliary)

        tabManager.removeAuxiliaryMiniWindowTab(auxiliary)
        tabManager.removeTab(transientExtension.id)

        XCTAssertNil(tabManager.tab(for: auxiliary.id))
        XCTAssertNil(tabManager.tab(for: transientExtension.id))
    }

    func testSplitGroupLookupsFollowStructuralMutations() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.createSpace(name: "Workspace")
        let first = tabManager.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.createNewTab(url: "https://example.com/two", in: space, activate: false)
        let third = tabManager.createNewTab(url: "https://example.com/three", in: space, activate: false)
        let fourth = tabManager.createNewTab(url: "https://example.com/four", in: space, activate: false)
        let initial = try XCTUnwrap(
            SplitGroup.make(tabIds: [first.id, second.id], layoutKind: .vertical, activeTabId: first.id)
        )

        tabManager.upsertSplitGroup(initial)

        XCTAssertEqual(tabManager.splitGroup(with: initial.id)?.id, initial.id)
        XCTAssertEqual(tabManager.splitGroup(containing: first.id)?.id, initial.id)
        XCTAssertEqual(tabManager.splitGroupIds(containing: second.id), [initial.id])

        let replacement = try XCTUnwrap(
            SplitGroup.make(tabIds: [second.id, third.id, fourth.id], layoutKind: .horizontal, activeTabId: third.id)
        )
        tabManager.upsertSplitGroup(replacement)

        XCTAssertNil(tabManager.splitGroup(with: initial.id))
        XCTAssertNil(tabManager.splitGroup(containing: first.id))
        XCTAssertEqual(tabManager.splitGroup(containing: second.id)?.id, replacement.id)
        XCTAssertEqual(tabManager.splitGroup(containing: fourth.id)?.id, replacement.id)

        tabManager.removeSplitGroups(containing: second.id)

        let trimmed = try XCTUnwrap(tabManager.splitGroup(with: replacement.id))
        XCTAssertEqual(trimmed.tabIds, [third.id, fourth.id])
        XCTAssertNil(tabManager.splitGroup(containing: second.id))
        XCTAssertEqual(tabManager.splitGroup(containing: third.id)?.id, replacement.id)

        let final = try XCTUnwrap(
            SplitGroup.make(tabIds: [first.id, fourth.id], layoutKind: .vertical, activeTabId: fourth.id)
        )
        tabManager.replaceSplitGroups([final])

        XCTAssertEqual(tabManager.splitGroup(with: final.id)?.id, final.id)
        XCTAssertNil(tabManager.splitGroup(with: replacement.id))
        XCTAssertNil(tabManager.splitGroup(containing: third.id))
        XCTAssertEqual(tabManager.splitGroup(containing: first.id)?.id, final.id)

        tabManager.removeSplitGroup(id: final.id)

        XCTAssertNil(tabManager.splitGroup(with: final.id))
        XCTAssertNil(tabManager.splitGroup(containing: first.id))
    }

    func testDirectSplitGroupsAssignmentRefreshesLookups() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.createSpace(name: "Workspace")
        let first = tabManager.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.createNewTab(url: "https://example.com/two", in: space, activate: false)
        let group = try XCTUnwrap(
            SplitGroup.make(tabIds: [first.id, second.id], layoutKind: .vertical, activeTabId: first.id)
        )

        tabManager.splitGroups = [group]

        XCTAssertEqual(tabManager.splitGroup(with: group.id)?.id, group.id)
        XCTAssertEqual(tabManager.splitGroup(containing: first.id)?.id, group.id)

        tabManager.splitGroups.removeAll()

        XCTAssertNil(tabManager.splitGroup(with: group.id))
        XCTAssertNil(tabManager.splitGroup(containing: first.id))
    }

    func testSplitGroupMutationsPublishOnceAndLookupUpdatesDuringTransaction() throws {
        let tabManager = try makeInMemoryTabManager()
        let recorder = StructuralEventRecorder(tabManager: tabManager)
        let space = tabManager.createSpace(name: "Workspace")
        let first = tabManager.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.createNewTab(url: "https://example.com/two", in: space, activate: false)
        let third = tabManager.createNewTab(url: "https://example.com/three", in: space, activate: false)
        let initial = try XCTUnwrap(
            SplitGroup.make(tabIds: [first.id, second.id], layoutKind: .vertical, activeTabId: first.id)
        )
        let replacement = try XCTUnwrap(
            SplitGroup.make(tabIds: [second.id, third.id], layoutKind: .horizontal, activeTabId: third.id)
        )
        recorder.reset()

        tabManager.withStructuralUpdateTransaction {
            tabManager.upsertSplitGroup(initial)
            XCTAssertEqual(recorder.count, 0)
            XCTAssertEqual(tabManager.splitGroup(containing: first.id)?.id, initial.id)

            tabManager.upsertSplitGroup(replacement)
            XCTAssertEqual(recorder.count, 0)
            XCTAssertNil(tabManager.splitGroup(containing: first.id))
            XCTAssertEqual(tabManager.splitGroup(containing: third.id)?.id, replacement.id)
        }

        XCTAssertEqual(recorder.count, 1)
        XCTAssertNil(tabManager.splitGroup(with: initial.id))
        XCTAssertEqual(tabManager.splitGroup(containing: second.id)?.id, replacement.id)
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

        XCTAssertIdentical(adopted, preview)
        XCTAssertIdentical(preview.existingWebView, webView)
        XCTAssertEqual(tabManager.tabsBySpace[space.id]?.map(\.id), [
            source.id,
            preview.id,
            trailing.id,
        ])
        XCTAssertEqual(tabManager.tabsBySpace[space.id]?.map(\.index), [0, 1, 2])
        XCTAssertEqual(tabManager.tab(for: preview.id)?.id, preview.id)
    }

    func testTabCreationPathsKeepDistinctProfileAndPersistenceBehavior() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Workspace", profileId: profileId)

        let regular = tabManager.createNewTab(
            url: "https://example.com/regular",
            in: space,
            activate: false
        )
        let transientExtension = tabManager.createTransientExtensionTab(
            url: "https://example.com/transient",
            in: space,
            webExtensionContextOverride: nil
        )
        let webViewBacked = tabManager.createNewTabWithWebView(
            url: "https://example.com/webview",
            in: space
        )
        let popup = tabManager.createPopupTab(in: space, activate: false)

        XCTAssertEqual(regular.spaceId, space.id)
        XCTAssertEqual(regular.profileId, profileId)
        XCTAssertEqual(transientExtension.spaceId, space.id)
        XCTAssertEqual(transientExtension.profileId, profileId)
        XCTAssertTrue(tabManager.isTransientExtensionTab(transientExtension))

        XCTAssertEqual(webViewBacked.spaceId, space.id)
        XCTAssertNil(webViewBacked.profileId)
        XCTAssertEqual(popup.spaceId, space.id)
        XCTAssertNil(popup.profileId)
        XCTAssertTrue(popup.isPopupHost)

        XCTAssertEqual(tabManager.tabsBySpace[space.id]?.map(\.id), [
            regular.id,
            webViewBacked.id,
            popup.id,
        ])
        XCTAssertFalse((tabManager.tabsBySpace[space.id] ?? []).contains { $0.id == transientExtension.id })
    }

    func testGlanceAdoptionTargetsSourceSpaceAndBackfillsFromPreviewProfile() throws {
        let tabManager = try makeInMemoryTabManager()
        let sourceSpace = tabManager.createSpace(name: "Source")
        let currentSpace = tabManager.createSpace(name: "Current")
        let source = tabManager.createNewTab(
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

        let adopted = tabManager.adoptGlanceTab(preview, sourceTab: source)

        XCTAssertIdentical(adopted, preview)
        XCTAssertEqual(preview.spaceId, sourceSpace.id)
        XCTAssertEqual(preview.profileId, previewProfileId)
        XCTAssertEqual(sourceSpace.profileId, previewProfileId)
        XCTAssertNil(currentSpace.profileId)
        XCTAssertEqual(tabManager.tabsBySpace[sourceSpace.id]?.map(\.id), [
            source.id,
            preview.id,
        ])
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
