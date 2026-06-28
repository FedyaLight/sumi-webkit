import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class TabManagerStructuralPersistenceTests: XCTestCase {
    func testIncrementalAddAndRemoveRegularTabPersistence() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let space = tabManager.createSpace(name: "Work", profileId: UUID())
        let tab = tabManager.createNewTab(in: space, activate: true)

        try await waitForStore(in: container) { context in
            guard let storedTab = try fetchTab(tab.id, in: context) else { return false }
            return storedTab.spaceId == space.id
                && storedTab.isPinned == false
                && storedTab.isSpacePinned == false
        }

        var context = ModelContext(container)
        let storedTab = try XCTUnwrap(fetchTab(tab.id, in: context))
        XCTAssertEqual(storedTab.spaceId, space.id)
        XCTAssertFalse(storedTab.isPinned)
        XCTAssertFalse(storedTab.isSpacePinned)

        tabManager.removeTab(tab.id)
        try await waitForStore(in: container) { context in
            try fetchTab(tab.id, in: context) == nil
        }

        context = ModelContext(container)
        XCTAssertNil(try fetchTab(tab.id, in: context))
    }

    func testFullReconcileDoesNotPersistExtensionOwnedRegularTabs() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let space = tabManager.createSpace(name: "Work", profileId: UUID())
        let normalTab = tabManager.createNewTab(
            url: "https://example.com/keep",
            in: space,
            activate: false
        )
        let extensionTab = tabManager.createNewTab(
            url: "webkit-extension://extension-id/app/app.html#/page/welcome",
            in: space,
            activate: true
        )

        XCTAssertEqual(tabManager.currentTab?.id, extensionTab.id)

        let didPersist = await tabManager.persistFullReconcileAwaitingResult(
            reason: "extension-owned tabs are runtime-owned"
        )

        XCTAssertTrue(didPersist)
        let context = ModelContext(container)
        XCTAssertNotNil(try fetchTab(normalTab.id, in: context))
        XCTAssertNil(try fetchTab(extensionTab.id, in: context))
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<TabsStateEntity>()).first)
        XCTAssertNil(state.currentTabID)
        XCTAssertEqual(state.currentSpaceID, space.id)
    }

    func testIncrementalPersistenceDeletesRegularTabThatBecomesExtensionOwned() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let space = tabManager.createSpace(name: "Work", profileId: UUID())
        let tab = tabManager.createNewTab(
            url: "https://example.com/start",
            in: space,
            activate: true
        )

        try await waitForStore(in: container) { context in
            guard let storedTab = try fetchTab(tab.id, in: context),
                  let state = try context.fetch(FetchDescriptor<TabsStateEntity>()).first
            else {
                return false
            }
            return storedTab.urlString == "https://example.com/start"
                && state.currentTabID == tab.id
                && state.currentSpaceID == space.id
        }

        tab.url = try XCTUnwrap(
            URL(string: "webkit-extension://extension-id/app/app.html#/page/migration")
        )
        tab.name = "Migration"

        tabManager.scheduleRuntimeStatePersistence(for: tab)
        let flushedCount = await tabManager.flushRuntimeStatePersistenceAwaitingResult()

        XCTAssertEqual(flushedCount, 0)
        var context = ModelContext(container)
        XCTAssertEqual(try fetchTab(tab.id, in: context)?.urlString, "https://example.com/start")

        tabManager.markRegularTabsStructurallyDirty(for: space.id)
        tabManager.scheduleStructuralPersistence()

        try await waitForStore(in: container) { context in
            let state = try context.fetch(FetchDescriptor<TabsStateEntity>()).first
            return try fetchTab(tab.id, in: context) == nil
                && state?.currentTabID == nil
                && state?.currentSpaceID == space.id
        }

        context = ModelContext(container)
        XCTAssertNil(try fetchTab(tab.id, in: context))
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<TabsStateEntity>()).first)
        XCTAssertNil(state.currentTabID)
        XCTAssertEqual(state.currentSpaceID, space.id)
    }

    func testStartupRestoreRemovesPersistedExtensionOwnedRegularTabs() async throws {
        let container = try makeInMemoryContainer()
        let profileId = UUID()
        let spaceId = UUID()
        let normalTabId = UUID()
        let webKitExtensionTabId = UUID()
        let safariExtensionTabId = UUID()

        let mutationContext = ModelContext(container)
        mutationContext.insert(
            SpaceEntity(
                id: spaceId,
                name: "Work",
                icon: "square.grid.2x2",
                index: 0,
                profileId: profileId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: webKitExtensionTabId,
                urlString: "webkit-extension://extension-id/app/app.html#/page/migration",
                name: "Migration",
                isPinned: false,
                index: 0,
                spaceId: spaceId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: normalTabId,
                urlString: "https://example.com/keep",
                name: "Keep",
                isPinned: false,
                index: 1,
                spaceId: spaceId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: safariExtensionTabId,
                urlString: "safari-web-extension://extension-id/app/app.html#/page/welcome",
                name: "Welcome",
                isPinned: false,
                index: 2,
                spaceId: spaceId
            )
        )
        mutationContext.insert(
            TabsStateEntity(
                currentTabID: safariExtensionTabId,
                currentSpaceID: spaceId
            )
        )
        try mutationContext.save()

        let tabManager = TabManager(context: ModelContext(container), loadPersistedState: false)
        let didLoad = await tabManager.loadFromStoreAwaitingResult()

        XCTAssertTrue(didLoad)
        XCTAssertEqual(tabManager.tabsBySpace[spaceId]?.map(\.id), [normalTabId])
        XCTAssertEqual(tabManager.currentSpace?.id, spaceId)
        XCTAssertEqual(tabManager.currentTab?.id, normalTabId)

        try await waitForStore(in: container) { context in
            let state = try context.fetch(FetchDescriptor<TabsStateEntity>()).first
            return try fetchTab(webKitExtensionTabId, in: context) == nil
                && fetchTab(safariExtensionTabId, in: context) == nil
                && fetchTab(normalTabId, in: context) != nil
                && state?.currentTabID == normalTabId
                && state?.currentSpaceID == spaceId
        }
    }

    func testIncrementalFolderRelationshipPersistence() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let space = tabManager.createSpace(name: "Pinned", profileId: UUID())
        let folder = tabManager.createFolder(for: space.id, name: "Docs")
        let tab = tabManager.createNewTab(url: "https://example.com/docs", in: space, activate: true)

        tabManager.moveTabToFolder(tab: tab, folderId: folder.id)
        let pin = try XCTUnwrap(tabManager.spacePinnedPins(for: space.id).first)

        try await waitForStore(in: container) { context in
            guard let storedFolder = try fetchFolder(folder.id, in: context),
                  let storedPin = try fetchTab(pin.id, in: context)
            else {
                return false
            }
            return storedFolder.spaceId == space.id
                && storedPin.isSpacePinned
                && storedPin.folderId == folder.id
        }

        var context = ModelContext(container)
        let storedFolder = try XCTUnwrap(fetchFolder(folder.id, in: context))
        XCTAssertEqual(storedFolder.spaceId, space.id)

        var storedPin = try XCTUnwrap(fetchTab(pin.id, in: context))
        XCTAssertTrue(storedPin.isSpacePinned)
        XCTAssertEqual(storedPin.folderId, folder.id)

        tabManager.ungroupFolder(folder.id)
        try await waitForStore(in: container) { context in
            guard let storedPin = try fetchTab(pin.id, in: context) else { return false }
            return try fetchFolder(folder.id, in: context) == nil
                && storedPin.folderId == nil
                && storedPin.isSpacePinned
        }

        context = ModelContext(container)
        XCTAssertNil(try fetchFolder(folder.id, in: context))
        storedPin = try XCTUnwrap(fetchTab(pin.id, in: context))
        XCTAssertNil(storedPin.folderId)
        XCTAssertTrue(storedPin.isSpacePinned)
    }

    func testDeleteFolderRemovesFolderChildrenPersistence() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let space = tabManager.createSpace(name: "Pinned", profileId: UUID())
        let folder = tabManager.createFolder(for: space.id, name: "Docs")
        let nested = try XCTUnwrap(tabManager.createFolder(for: space.id, parentFolderId: folder.id, name: "Nested"))
        let tab = tabManager.createNewTab(url: "https://example.com/docs", in: space, activate: true)
        let nestedTab = tabManager.createNewTab(url: "https://example.com/nested", in: space, activate: false)

        tabManager.moveTabToFolder(tab: tab, folderId: folder.id)
        tabManager.moveTabToFolder(tab: nestedTab, folderId: nested.id)
        let pins = tabManager.spacePinnedPins(for: space.id)
        let pinIds = Set(pins.map(\.id))
        XCTAssertEqual(pins.count, 2)

        try await waitForStore(in: container) { context in
            try fetchFolder(folder.id, in: context) != nil
                && fetchFolder(nested.id, in: context) != nil
                && pins.allSatisfy { pin in
                    (try? fetchTab(pin.id, in: context)) != nil
                }
        }

        tabManager.deleteFolder(folder.id)
        try await waitForStore(in: container) { context in
            guard try fetchFolder(folder.id, in: context) == nil,
                  try fetchFolder(nested.id, in: context) == nil else {
                return false
            }
            for pinId in pinIds {
                if try fetchTab(pinId, in: context) != nil {
                    return false
                }
            }
            return true
        }
    }

    func testFolderOpenStatePersistence() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let space = tabManager.createSpace(name: "Pinned", profileId: UUID())
        let folder = tabManager.createFolder(for: space.id, name: "Docs")

        tabManager.setFolder(folder.id, open: true)
        try await waitForStore(in: container) { context in
            try fetchFolder(folder.id, in: context)?.isOpen == true
        }

        tabManager.setFolder(folder.id, open: false)
        try await waitForStore(in: container) { context in
            try fetchFolder(folder.id, in: context)?.isOpen == false
        }
    }

    func testFolderLifecycleAndMembershipMutationsAreOwnedByFolderMutationOwner() throws {
        let tabManagerSource = try Self.source(named: "Sumi/Managers/TabManager/TabManager.swift")
        let folderFacadeSource = try Self.sourceRange(
            in: tabManagerSource,
            from: "// MARK: - Folder Management",
            to: "// MARK: - Tab Management"
        )
        let ownerSource = try Self.source(named: "Sumi/Managers/TabManager/TabFolderMutationOwner.swift")

        XCTAssertTrue(tabManagerSource.contains("lazy var folderMutationOwner = TabFolderMutationOwner(tabManager: self)"))
        XCTAssertFalse(tabManagerSource.contains("TabFolderService"))
        XCTAssertTrue(ownerSource.contains("final class TabFolderMutationOwner"))
        XCTAssertTrue(ownerSource.contains("private enum FolderContainerItem"))
        XCTAssertTrue(ownerSource.contains("private func descendantFolderIds"))

        for method in [
            "createFolder(for: spaceId",
            "createFolder(for: spaceId, parentFolderId:",
            "renameFolder(folderId",
            "updateFolderIcon(folderId",
            "setFolder(folderId",
            "toggleFolderOpenState(folderId",
            "deleteFolder(folderId",
            "ungroupFolder(folderId",
            "folders(for: spaceId",
            "openFolderIfNeeded(folderId",
            "setAllFolders(open: isOpen",
            "moveTabToFolder(tab: tab"
        ] {
            XCTAssertTrue(folderFacadeSource.contains("folderMutationOwner.\(method)"))
        }

        for forbidden in [
            "withStructuralUpdateTransaction",
            "foldersBySpace",
            "spacePinnedShortcuts",
            "convertTabToShortcutPin",
            "deleteLiveFolderState"
        ] {
            XCTAssertFalse(folderFacadeSource.contains(forbidden), "TabManager folder facade should not own \(forbidden)")
        }
    }

    func testTopLevelFolderPositionPersistsAfterSpacePinnedShortcuts() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let space = tabManager.createSpace(name: "Pinned", profileId: UUID())
        let firstTab = tabManager.createNewTab(url: "https://example.com/first", in: space, activate: true)
        let secondTab = tabManager.createNewTab(url: "https://example.com/second", in: space, activate: false)
        let firstPin = try XCTUnwrap(
            tabManager.convertTabToShortcutPin(
                firstTab,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                at: 0
            )
        )
        let secondPin = try XCTUnwrap(
            tabManager.convertTabToShortcutPin(
                secondTab,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                at: 1
            )
        )
        let folder = tabManager.createFolder(for: space.id, name: "Bottom")

        XCTAssertEqual(
            tabManager.topLevelSpacePinnedItems(for: space.id).map(\.id),
            [firstPin.id, secondPin.id, folder.id]
        )

        try await waitForStore(in: container) { context in
            guard let storedFolder = try fetchFolder(folder.id, in: context),
                  let storedFirstPin = try fetchTab(firstPin.id, in: context),
                  let storedSecondPin = try fetchTab(secondPin.id, in: context)
            else {
                return false
            }
            return storedFirstPin.index == 0
                && storedSecondPin.index == 1
                && storedFolder.index == 2
        }

        let restoredManager = TabManager(context: ModelContext(container), loadPersistedState: false)
        let didLoad = await restoredManager.loadFromStoreAwaitingResult()

        XCTAssertTrue(didLoad)
        XCTAssertEqual(
            restoredManager.topLevelSpacePinnedItems(for: space.id).map(\.id),
            [firstPin.id, secondPin.id, folder.id]
        )
    }

    func testIncrementalSpaceMembershipAndOrderPersistence() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let profileId = UUID()
        let spaceA = tabManager.createSpace(name: "A", profileId: profileId)
        let tabA = tabManager.createNewTab(url: "https://example.com/a", in: spaceA, activate: true)
        _ = tabManager.createNewTab(url: "https://example.com/a2", in: spaceA, activate: false)
        let spaceB = tabManager.createSpace(name: "B", profileId: profileId)
        let tabB = tabManager.createNewTab(url: "https://example.com/b", in: spaceB, activate: true)

        tabManager.moveTab(tabA.id, to: spaceB.id)
        tabManager.reorderRegularTabs(tabA, in: spaceB.id, to: 0)

        try await waitForStore(in: container) { context in
            guard let storedMovedTab = try fetchTab(tabA.id, in: context),
                  let storedExistingTab = try fetchTab(tabB.id, in: context)
            else {
                return false
            }
            return storedMovedTab.spaceId == spaceB.id
                && storedMovedTab.index == 0
                && storedExistingTab.spaceId == spaceB.id
                && storedExistingTab.index == 1
        }

        let context = ModelContext(container)
        let storedMovedTab = try XCTUnwrap(fetchTab(tabA.id, in: context))
        let storedExistingTab = try XCTUnwrap(fetchTab(tabB.id, in: context))
        XCTAssertEqual(storedMovedTab.spaceId, spaceB.id)
        XCTAssertEqual(storedMovedTab.index, 0)
        XCTAssertEqual(storedExistingTab.spaceId, spaceB.id)
        XCTAssertEqual(storedExistingTab.index, 1)
    }

    func testReorderSpaceUpdatesPersistedIndicesAndPreservesCurrentSpace() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let profileId = UUID()
        let first = tabManager.createSpace(name: "First", profileId: profileId)
        let second = tabManager.createSpace(name: "Second", profileId: profileId)
        let third = tabManager.createSpace(name: "Third", profileId: profileId)
        tabManager.setActiveSpace(second)

        XCTAssertTrue(tabManager.reorderSpace(spaceId: first.id, to: 2))
        XCTAssertEqual(tabManager.spaces.map(\.id), [second.id, third.id, first.id])
        XCTAssertEqual(tabManager.currentSpace?.id, second.id)

        try await waitForStore(in: container) { context in
            let storedSpaces = try fetchSpacesSortedByIndex(in: context)
            return storedSpaces.map(\.id) == [second.id, third.id, first.id]
                && storedSpaces.map(\.index) == [0, 1, 2]
        }

        let storedSpaces = try fetchSpacesSortedByIndex(in: ModelContext(container))
        XCTAssertEqual(storedSpaces.map(\.id), [second.id, third.id, first.id])
        XCTAssertEqual(storedSpaces.map(\.index), [0, 1, 2])
        XCTAssertEqual(tabManager.currentSpace?.id, second.id)
    }

    func testReorderSpacePersistsThroughRestore() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let profileId = UUID()
        let first = tabManager.createSpace(name: "First", profileId: profileId)
        let second = tabManager.createSpace(name: "Second", profileId: profileId)
        let third = tabManager.createSpace(name: "Third", profileId: profileId)
        tabManager.setActiveSpace(second)

        XCTAssertTrue(tabManager.reorderSpace(spaceId: first.id, to: 2))

        try await waitForStore(in: container) { context in
            try fetchSpacesSortedByIndex(in: context).map(\.id) == [second.id, third.id, first.id]
        }

        let restoredManager = TabManager(context: ModelContext(container), loadPersistedState: false)
        let didLoad = await restoredManager.loadFromStoreAwaitingResult()

        XCTAssertTrue(didLoad)
        XCTAssertEqual(restoredManager.spaces.map(\.id), [second.id, third.id, first.id])
        XCTAssertEqual(restoredManager.currentSpace?.id, second.id)
        XCTAssertTrue(restoredManager.structuralDirtySet.isEmpty)
        XCTAssertNil(restoredManager.scheduledStructuralPersistTask)
    }

    func testReorderSpaceClampsInvalidTargetIndices() throws {
        let container = try makeInMemoryContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let profileId = UUID()
        let first = tabManager.createSpace(name: "First", profileId: profileId)
        let second = tabManager.createSpace(name: "Second", profileId: profileId)
        let third = tabManager.createSpace(name: "Third", profileId: profileId)

        XCTAssertTrue(tabManager.reorderSpace(spaceId: third.id, to: -100))
        XCTAssertEqual(tabManager.spaces.map(\.id), [third.id, first.id, second.id])
        XCTAssertTrue(tabManager.reorderSpace(spaceId: third.id, to: 100))
        XCTAssertEqual(tabManager.spaces.map(\.id), [first.id, second.id, third.id])
        XCTAssertFalse(tabManager.reorderSpace(spaceId: UUID(), to: 0))
    }

    func testSelectionOnlyPersistenceCreatesAndUpdatesState() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let space = tabManager.createSpace(name: "Select", profileId: UUID())
        _ = tabManager.createNewTab(url: "https://example.com/one", in: space, activate: true)
        let second = tabManager.createNewTab(url: "https://example.com/two", in: space, activate: false)

        try await waitForPersistedState(in: container) { state in
            state.currentSpaceID == space.id
        }
        tabManager.setActiveTab(second)

        try await waitForPersistedState(in: container) { state in
            state.currentTabID == second.id && state.currentSpaceID == space.id
        }
    }

    func testActiveTabStatePathsPersistSelectionWithoutSchedulingStructuralPersistence() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let profileId = UUID()
        let firstSpace = tabManager.createSpace(name: "First", profileId: profileId)
        let secondSpace = tabManager.createSpace(name: "Second", profileId: profileId)
        let first = tabManager.createNewTab(url: "https://example.com/first", in: firstSpace, activate: false)
        let alternate = tabManager.createNewTab(url: "https://example.com/alternate", in: firstSpace, activate: false)
        let second = tabManager.createNewTab(url: "https://example.com/second", in: secondSpace, activate: false)

        tabManager.setActiveTab(first)
        try await waitForStore(in: container) { context in
            guard let state = try context.fetch(FetchDescriptor<TabsStateEntity>()).first else {
                return false
            }
            return try fetchTab(first.id, in: context) != nil
                && fetchTab(alternate.id, in: context) != nil
                && fetchTab(second.id, in: context) != nil
                && state.currentTabID == first.id
                && state.currentSpaceID == firstSpace.id
                && tabManager.structuralDirtySet.isEmpty
                && tabManager.scheduledStructuralPersistTask == nil
        }

        tabManager.setActiveTab(second)

        XCTAssertEqual(tabManager.currentTab?.id, second.id)
        XCTAssertEqual(tabManager.currentSpace?.id, secondSpace.id)
        XCTAssertEqual(secondSpace.activeTabId, second.id)
        XCTAssertTrue(tabManager.structuralDirtySet.isEmpty)
        XCTAssertNil(tabManager.scheduledStructuralPersistTask)
        try await waitForPersistedState(in: container) { state in
            state.currentTabID == second.id && state.currentSpaceID == secondSpace.id
        }

        tabManager.updateActiveTabState(alternate)

        XCTAssertEqual(tabManager.currentTab?.id, alternate.id)
        XCTAssertEqual(tabManager.currentSpace?.id, firstSpace.id)
        XCTAssertEqual(firstSpace.activeTabId, alternate.id)
        XCTAssertTrue(tabManager.structuralDirtySet.isEmpty)
        XCTAssertNil(tabManager.scheduledStructuralPersistTask)
        try await waitForPersistedState(in: container) { state in
            state.currentTabID == alternate.id && state.currentSpaceID == firstSpace.id
        }
    }

    func testRuntimeStateBatchFlushUpdatesStoredTabFields() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let space = tabManager.createSpace(name: "Runtime", profileId: UUID())
        let tab = tabManager.createNewTab(url: "https://example.com/initial", in: space, activate: true)

        try await waitForStore(in: container) { context in
            try fetchTab(tab.id, in: context) != nil
        }

        tab.url = try XCTUnwrap(URL(string: "https://example.com/runtime"))
        tab.name = "Runtime Updated"
        tab.canGoBack = true
        tab.canGoForward = true

        tabManager.scheduleRuntimeStatePersistence(for: tab)
        let flushedCount = await tabManager.flushRuntimeStatePersistenceAwaitingResult()

        XCTAssertEqual(flushedCount, 1)
        let context = ModelContext(container)
        let storedTab = try XCTUnwrap(fetchTab(tab.id, in: context))
        XCTAssertEqual(storedTab.urlString, "https://example.com/runtime")
        XCTAssertEqual(storedTab.currentURLString, "https://example.com/runtime")
        XCTAssertEqual(storedTab.name, "Runtime Updated")
        XCTAssertTrue(storedTab.canGoBack)
        XCTAssertTrue(storedTab.canGoForward)
    }

    func testSplitGroupLayoutPersistsThroughStoreReload() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let space = tabManager.createSpace(name: "Split", profileId: UUID())
        let tabs = [
            tabManager.createNewTab(url: "https://example.com/one", in: space, activate: true),
            tabManager.createNewTab(url: "https://example.com/two", in: space, activate: false),
            tabManager.createNewTab(url: "https://example.com/three", in: space, activate: false)
        ]
        let baseGroup = try XCTUnwrap(
            SplitGroup.make(
                tabIds: tabs.map(\.id),
                layoutKind: .vertical,
                activeTabId: tabs[1].id
            )
        )
        let resizedGroup = SplitGroup(
            id: baseGroup.id,
            layoutKind: .vertical,
            layoutTree: baseGroup.layoutTree.updatingChildSizes(at: [], sizes: [0.2, 0.3, 0.5]),
            activeTabId: tabs[1].id
        )

        tabManager.upsertSplitGroup(resizedGroup)

        try await waitForPersistedState(in: container) { state in
            guard let data = state.splitGroupsData,
                  let decoded = try? JSONDecoder().decode([SplitGroup].self, from: data),
                  let storedGroup = decoded.first(where: { $0.id == resizedGroup.id })
            else {
                return false
            }
            return storedGroup.layoutKind == resizedGroup.layoutKind
                && storedGroup.layoutTree == resizedGroup.layoutTree
                && storedGroup.activeTabId == resizedGroup.activeTabId
        }

        let restoredManager = TabManager(context: ModelContext(container), loadPersistedState: false)
        let didLoad = await restoredManager.loadFromStoreAwaitingResult()

        XCTAssertTrue(didLoad)
        let restoredGroup = try XCTUnwrap(restoredManager.splitGroup(with: resizedGroup.id))
        XCTAssertEqual(restoredGroup.layoutKind, resizedGroup.layoutKind)
        XCTAssertEqual(restoredGroup.layoutTree, resizedGroup.layoutTree)
        XCTAssertEqual(restoredGroup.activeTabId, resizedGroup.activeTabId)
    }

    func testShortcutBackedSplitGroupPersistsThroughStoreReload() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let space = tabManager.createSpace(name: "Split", profileId: UUID())
        let regular = tabManager.createNewTab(url: "https://example.com/regular", in: space, activate: true)
        let pinnedSource = tabManager.createNewTab(
            url: "https://example.com/pinned",
            in: space,
            activate: false
        )
        let pin = try XCTUnwrap(
            tabManager.convertTabToShortcutPin(
                pinnedSource,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                at: 0
            )
        )
        let windowId = UUID()
        let livePinnedTab = tabManager.activateShortcutPin(pin, in: windowId, currentSpaceId: space.id)
        let group = try XCTUnwrap(
            SplitGroup.make(
                tabIds: [regular.id, livePinnedTab.id],
                layoutKind: .vertical,
                activeTabId: livePinnedTab.id,
                host: .regular(spaceId: space.id),
                members: [
                    SplitGroupMember(
                        tabId: regular.id,
                        pinId: nil,
                        origin: .regular(spaceId: space.id, index: regular.index)
                    ),
                    SplitGroupMember(
                        tabId: livePinnedTab.id,
                        pinId: pin.id,
                        origin: .spacePinned(spaceId: space.id, folderId: nil, index: pin.index)
                    )
                ]
            )
        )
        tabManager.upsertSplitGroup(group)

        try await waitForPersistedState(in: container) { state in
            guard let data = state.splitGroupsData,
                  let decoded = try? JSONDecoder().decode([SplitGroup].self, from: data)
            else {
                return false
            }
            return decoded.contains { $0.id == group.id && $0.contains(livePinnedTab.id) }
        }

        let restoredManager = TabManager(context: ModelContext(container), loadPersistedState: false)
        let didLoad = await restoredManager.loadFromStoreAwaitingResult()

        XCTAssertTrue(didLoad)
        let restoredGroup = try XCTUnwrap(restoredManager.splitGroup(containingPinId: pin.id))
        XCTAssertEqual(restoredGroup.id, group.id)
        XCTAssertTrue(restoredGroup.contains(regular.id))
        XCTAssertTrue(restoredGroup.containsPin(pin.id))
        XCTAssertFalse(restoredGroup.contains(livePinnedTab.id))
    }

    func testFullReconcileDeletesStaleEntitiesAndPreservesFolders() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let space = tabManager.createSpace(name: "Clean", profileId: UUID())
        let folder = tabManager.createFolder(for: space.id, name: "Keep")
        _ = tabManager.createNewTab(url: "https://example.com/keep", in: space, activate: true)
        try await waitForStore(in: container) { context in
            try fetchFolder(folder.id, in: context) != nil
        }

        let staleSpaceId = UUID()
        let staleTabId = UUID()
        let staleFolderId = UUID()
        let mutationContext = ModelContext(container)
        mutationContext.insert(
            SpaceEntity(id: staleSpaceId, name: "Stale", icon: "xmark", index: 99)
        )
        mutationContext.insert(
            TabEntity(
                id: staleTabId,
                urlString: "https://example.com/stale",
                name: "Stale",
                isPinned: false,
                index: 0,
                spaceId: staleSpaceId
            )
        )
        mutationContext.insert(
            FolderEntity(
                id: staleFolderId,
                name: "Stale",
                icon: "folder",
                color: "#000000",
                spaceId: staleSpaceId,
                isOpen: false,
                index: 0
            )
        )
        try mutationContext.save()

        let didFullReconcile = await tabManager.persistFullReconcileAwaitingResult(reason: "test full reconcile")
        XCTAssertTrue(didFullReconcile)

        let context = ModelContext(container)
        XCTAssertNil(try fetchSpace(staleSpaceId, in: context))
        XCTAssertNil(try fetchTab(staleTabId, in: context))
        XCTAssertNil(try fetchFolder(staleFolderId, in: context))
        XCTAssertNotNil(try fetchFolder(folder.id, in: context))
    }

    func testStartupRestorePreservesOrderingSelectionAndDoesNotScheduleStructuralPersistence() async throws {
        let container = try makeInMemoryContainer()
        let profileId = UUID()
        let spaceAId = UUID()
        let spaceBId = UUID()
        let selectedTabId = UUID()
        let firstTabId = UUID()
        let folderFirstId = UUID()
        let folderSecondId = UUID()
        let pinnedFirstId = UUID()
        let pinnedSecondId = UUID()
        let spacePinnedFirstId = UUID()
        let spacePinnedSecondId = UUID()

        let mutationContext = ModelContext(container)
        mutationContext.insert(
            SpaceEntity(
                id: spaceAId,
                name: "A",
                icon: "square.grid.2x2",
                index: 1,
                profileId: profileId
            )
        )
        mutationContext.insert(
            SpaceEntity(
                id: spaceBId,
                name: "B",
                icon: "🏠",
                index: 0,
                profileId: profileId
            )
        )
        mutationContext.insert(
            FolderEntity(
                id: folderSecondId,
                name: "Later",
                icon: "zen:book",
                color: "#111111",
                spaceId: spaceAId,
                isOpen: false,
                index: 1
            )
        )
        mutationContext.insert(
            FolderEntity(
                id: folderFirstId,
                name: "First",
                icon: "zen:bookmark",
                color: "#222222",
                spaceId: spaceAId,
                isOpen: true,
                index: 0
            )
        )
        mutationContext.insert(
            TabEntity(
                id: pinnedSecondId,
                urlString: "https://example.com/pinned-second",
                name: "Pinned Second",
                isPinned: true,
                index: 1,
                spaceId: nil,
                profileId: profileId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: pinnedFirstId,
                urlString: "https://example.com/pinned-first",
                name: "Pinned First",
                isPinned: true,
                index: 0,
                spaceId: nil,
                profileId: profileId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: spacePinnedSecondId,
                urlString: "https://example.com/space-pinned-second",
                name: "Space Pinned Second",
                isPinned: false,
                isSpacePinned: true,
                index: 1,
                spaceId: spaceAId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: spacePinnedFirstId,
                urlString: "https://example.com/space-pinned-first",
                name: "Space Pinned First",
                isPinned: false,
                isSpacePinned: true,
                index: 0,
                spaceId: spaceAId,
                folderId: folderFirstId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: selectedTabId,
                urlString: "https://example.com/selected",
                name: "Selected",
                isPinned: false,
                index: 1,
                spaceId: spaceAId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: firstTabId,
                urlString: "https://example.com/first",
                name: "First",
                isPinned: false,
                index: 0,
                spaceId: spaceAId
            )
        )
        mutationContext.insert(TabsStateEntity(currentTabID: selectedTabId, currentSpaceID: spaceAId))
        try mutationContext.save()

        let tabManager = TabManager(context: ModelContext(container), loadPersistedState: false)
        let didLoad = await tabManager.loadFromStoreAwaitingResult()

        XCTAssertTrue(didLoad)
        XCTAssertEqual(tabManager.spaces.map(\.id), [spaceBId, spaceAId])
        XCTAssertEqual(tabManager.tabsBySpace[spaceAId]?.map(\.id), [firstTabId, selectedTabId])
        XCTAssertEqual(tabManager.foldersBySpace[spaceAId]?.map(\.id), [folderFirstId, folderSecondId])
        XCTAssertEqual(tabManager.pinnedByProfile[profileId]?.map(\.id), [pinnedFirstId, pinnedSecondId])
        XCTAssertEqual(
            tabManager.spacePinnedShortcuts[spaceAId]?.map(\.id),
            [spacePinnedFirstId, spacePinnedSecondId]
        )
        XCTAssertEqual(tabManager.currentSpace?.id, spaceAId)
        XCTAssertEqual(tabManager.currentTab?.id, selectedTabId)
        XCTAssertTrue(tabManager.structuralDirtySet.isEmpty)
        XCTAssertNil(tabManager.scheduledStructuralPersistTask)
    }

    func testStartupRestoreRepairsMalformedPersistedStateAfterMainApply() async throws {
        let container = try makeInMemoryContainer()
        let profileId = UUID()
        let validSpaceId = UUID()
        let missingSpaceId = UUID()
        let validTabId = UUID()
        let orphanTabId = UUID()
        let orphanFolderId = UUID()
        let missingFolderId = UUID()
        let folderChildPinId = UUID()
        let noSpacePinId = UUID()

        let mutationContext = ModelContext(container)
        mutationContext.insert(
            SpaceEntity(
                id: validSpaceId,
                name: "Valid",
                icon: "square.grid.2x2",
                index: 0,
                profileId: profileId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: validTabId,
                urlString: "https://example.com/valid",
                name: "Valid",
                isPinned: false,
                index: 0,
                spaceId: validSpaceId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: orphanTabId,
                urlString: "https://example.com/orphan",
                name: "Orphan",
                isPinned: false,
                index: 1,
                spaceId: missingSpaceId
            )
        )
        mutationContext.insert(
            FolderEntity(
                id: orphanFolderId,
                name: "Orphan Folder",
                icon: "zen:book",
                color: "#333333",
                spaceId: missingSpaceId,
                isOpen: false,
                index: 0
            )
        )
        mutationContext.insert(
            TabEntity(
                id: folderChildPinId,
                urlString: "https://example.com/folder-child",
                name: "Folder Child",
                isPinned: false,
                isSpacePinned: true,
                index: 0,
                spaceId: validSpaceId,
                folderId: missingFolderId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: noSpacePinId,
                urlString: "https://example.com/no-space",
                name: "No Space",
                isPinned: false,
                isSpacePinned: true,
                index: 1,
                spaceId: nil
            )
        )
        mutationContext.insert(TabsStateEntity(currentTabID: UUID(), currentSpaceID: missingSpaceId))
        try mutationContext.save()

        let tabManager = TabManager(context: ModelContext(container), loadPersistedState: false)
        let didLoad = await tabManager.loadFromStoreAwaitingResult()

        XCTAssertTrue(didLoad)
        XCTAssertEqual(tabManager.currentSpace?.id, validSpaceId)
        XCTAssertEqual(tabManager.currentTab?.id, validTabId)
        XCTAssertEqual(tabManager.tabsBySpace[validSpaceId]?.map(\.id), [validTabId])
        let repairedPin = try XCTUnwrap(tabManager.spacePinnedShortcuts[validSpaceId]?.first)
        XCTAssertEqual(repairedPin.id, folderChildPinId)
        XCTAssertNil(repairedPin.folderId)
        XCTAssertNil(tabManager.spacePinnedShortcuts[missingSpaceId])
        XCTAssertTrue(tabManager.structuralDirtySet.isEmpty)
        XCTAssertNil(tabManager.scheduledStructuralPersistTask)

        try await waitForStore(in: container) { context in
            let repairedStoredPin = try fetchTab(folderChildPinId, in: context)
            let state = try context.fetch(FetchDescriptor<TabsStateEntity>()).first
            return try fetchTab(orphanTabId, in: context) == nil
                && fetchFolder(orphanFolderId, in: context) == nil
                && fetchTab(noSpacePinId, in: context) == nil
                && repairedStoredPin?.folderId == nil
                && state?.currentSpaceID == validSpaceId
                && state?.currentTabID == validTabId
        }
    }

    func testStartupRestoreNormalizesLauncherIconAssetsAndPersistsRepair() async throws {
        let container = try makeInMemoryContainer()
        let profileId = UUID()
        let spaceId = UUID()
        let pinnedId = UUID()
        let spacePinnedId = UUID()

        let mutationContext = ModelContext(container)
        mutationContext.insert(
            SpaceEntity(
                id: spaceId,
                name: "Work",
                icon: "square.grid.2x2",
                index: 0,
                profileId: profileId
            )
        )
        mutationContext.insert(
            TabEntity(
                id: pinnedId,
                urlString: "https://example.com/pinned",
                name: "Pinned",
                isPinned: true,
                index: 0,
                spaceId: nil,
                profileId: profileId,
                iconAsset: "   "
            )
        )
        mutationContext.insert(
            TabEntity(
                id: spacePinnedId,
                urlString: "https://example.com/space-pinned",
                name: "Space Pinned",
                isPinned: false,
                isSpacePinned: true,
                index: 0,
                spaceId: spaceId,
                iconAsset: "   "
            )
        )
        mutationContext.insert(TabsStateEntity(currentTabID: nil, currentSpaceID: spaceId))
        try mutationContext.save()

        let tabManager = TabManager(context: ModelContext(container), loadPersistedState: false)
        let didLoad = await tabManager.loadFromStoreAwaitingResult()

        XCTAssertTrue(didLoad)
        XCTAssertNil(tabManager.pinnedByProfile[profileId]?.first?.iconAsset)
        XCTAssertNil(tabManager.spacePinnedShortcuts[spaceId]?.first?.iconAsset)
        XCTAssertTrue(tabManager.structuralDirtySet.isEmpty)
        XCTAssertNil(tabManager.scheduledStructuralPersistTask)

        try await waitForStore(in: container) { context in
            try fetchTab(pinnedId, in: context)?.iconAsset == nil
                && fetchTab(spacePinnedId, in: context)?.iconAsset == nil
        }
    }

    func testStartupRestoreCurrentFormatDoesNotDuplicateAcrossRepeatedLoads() async throws {
        let container = try makeInMemoryContainer()
        let fixture = try insertCurrentFormatRestoreFixture(in: container)
        let tabManager = TabManager(context: ModelContext(container), loadPersistedState: false)

        let firstLoad = await tabManager.loadFromStoreAwaitingResult()
        XCTAssertTrue(firstLoad)
        try await waitPastStructuralDebounce()

        XCTAssertEqual(tabManager.spaces.map(\.id), [fixture.spaceAId, fixture.spaceBId])
        XCTAssertEqual(tabManager.tabsBySpace[fixture.spaceAId]?.map(\.id), [fixture.firstTabId, fixture.secondTabId])
        XCTAssertEqual(tabManager.currentSpace?.id, fixture.spaceAId)
        XCTAssertEqual(tabManager.currentTab?.id, fixture.secondTabId)
        try assertStoreShape(in: container, spaces: 2, folders: 1, tabs: 4)

        let secondLoad = await tabManager.loadFromStoreAwaitingResult()
        XCTAssertTrue(secondLoad)
        try await waitPastStructuralDebounce()

        XCTAssertEqual(tabManager.spaces.map(\.id), [fixture.spaceAId, fixture.spaceBId])
        XCTAssertEqual(tabManager.tabsBySpace[fixture.spaceAId]?.map(\.id), [fixture.firstTabId, fixture.secondTabId])
        try assertStoreShape(in: container, spaces: 2, folders: 1, tabs: 4)
    }

    func testPostRestoreStructuralMutationPersistsOnceWithoutDuplicatingRestoredGraph() async throws {
        let container = try makeInMemoryContainer()
        let fixture = try insertCurrentFormatRestoreFixture(in: container)
        let tabManager = TabManager(context: ModelContext(container), loadPersistedState: false)

        let didLoad = await tabManager.loadFromStoreAwaitingResult()
        XCTAssertTrue(didLoad)
        try await waitPastStructuralDebounce()

        let restoredSpace = try XCTUnwrap(tabManager.spaces.first { $0.id == fixture.spaceAId })
        let created = tabManager.createNewTab(
            url: "https://example.com/post-restore",
            in: restoredSpace,
            activate: false
        )

        try await waitForStore(in: container) { context in
            try fetchTab(created.id, in: context) != nil
        }
        XCTAssertNotNil(try fetchTab(created.id, in: ModelContext(container)))
        try assertStoreShape(in: container, spaces: 2, folders: 1, tabs: 5)
    }

    func testStructuralTransactionPersistsFinalOrderOnce() async throws {
        let container = try makeInMemoryContainer()
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let space = tabManager.createSpace(name: "Batch", profileId: UUID())
        let first = tabManager.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.createNewTab(url: "https://example.com/two", in: space, activate: false)
        let third = tabManager.createNewTab(url: "https://example.com/three", in: space, activate: false)

        try await waitForStore(in: container) { context in
            try fetchTab(first.id, in: context) != nil
                && (try fetchTab(second.id, in: context)) != nil
                && (try fetchTab(third.id, in: context)) != nil
        }

        tabManager.withStructuralUpdateTransaction {
            tabManager.reorderRegularTabs(first, in: space.id, to: 3)
            tabManager.reorderRegularTabs(second, in: space.id, to: 3)
        }

        try await waitForStore(in: container) { context in
            try fetchTab(third.id, in: context)?.index == 0
                && (try fetchTab(first.id, in: context))?.index == 1
                && (try fetchTab(second.id, in: context))?.index == 2
        }
        XCTAssertEqual(try fetchTab(third.id, in: ModelContext(container))?.index, 0)
        XCTAssertEqual(try fetchTab(first.id, in: ModelContext(container))?.index, 1)
        XCTAssertEqual(try fetchTab(second.id, in: ModelContext(container))?.index, 2)
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private struct CurrentFormatRestoreFixture {
        let profileId: UUID
        let spaceAId: UUID
        let spaceBId: UUID
        let folderId: UUID
        let firstTabId: UUID
        let secondTabId: UUID
        let pinnedTabId: UUID
        let spacePinnedTabId: UUID
    }

    private func insertCurrentFormatRestoreFixture(
        in container: ModelContainer
    ) throws -> CurrentFormatRestoreFixture {
        let fixture = CurrentFormatRestoreFixture(
            profileId: UUID(),
            spaceAId: UUID(),
            spaceBId: UUID(),
            folderId: UUID(),
            firstTabId: UUID(),
            secondTabId: UUID(),
            pinnedTabId: UUID(),
            spacePinnedTabId: UUID()
        )
        let context = ModelContext(container)
        context.insert(
            SpaceEntity(
                id: fixture.spaceAId,
                name: "A",
                icon: "square.grid.2x2",
                index: 0,
                profileId: fixture.profileId
            )
        )
        context.insert(
            SpaceEntity(
                id: fixture.spaceBId,
                name: "B",
                icon: "🏠",
                index: 1,
                profileId: fixture.profileId
            )
        )
        context.insert(
            FolderEntity(
                id: fixture.folderId,
                name: "Docs",
                icon: "zen:book",
                color: "#111111",
                spaceId: fixture.spaceAId,
                isOpen: true,
                index: 0
            )
        )
        context.insert(
            TabEntity(
                id: fixture.firstTabId,
                urlString: "https://example.com/one",
                name: "One",
                isPinned: false,
                index: 0,
                spaceId: fixture.spaceAId
            )
        )
        context.insert(
            TabEntity(
                id: fixture.secondTabId,
                urlString: "https://example.com/two",
                name: "Two",
                isPinned: false,
                index: 1,
                spaceId: fixture.spaceAId
            )
        )
        context.insert(
            TabEntity(
                id: fixture.pinnedTabId,
                urlString: "https://example.com/pinned",
                name: "Pinned",
                isPinned: true,
                index: 0,
                spaceId: nil,
                profileId: fixture.profileId
            )
        )
        context.insert(
            TabEntity(
                id: fixture.spacePinnedTabId,
                urlString: "https://example.com/space-pinned",
                name: "Space Pinned",
                isPinned: false,
                isSpacePinned: true,
                index: 0,
                spaceId: fixture.spaceAId,
                folderId: fixture.folderId
            )
        )
        context.insert(
            TabsStateEntity(
                currentTabID: fixture.secondTabId,
                currentSpaceID: fixture.spaceAId
            )
        )
        try context.save()
        return fixture
    }

    private func fetchTab(_ id: UUID, in context: ModelContext) throws -> TabEntity? {
        let tabId = id
        let predicate = #Predicate<TabEntity> { $0.id == tabId }
        return try context.fetch(FetchDescriptor<TabEntity>(predicate: predicate)).first
    }

    private func fetchFolder(_ id: UUID, in context: ModelContext) throws -> FolderEntity? {
        let folderId = id
        let predicate = #Predicate<FolderEntity> { $0.id == folderId }
        return try context.fetch(FetchDescriptor<FolderEntity>(predicate: predicate)).first
    }

    private func fetchSpace(_ id: UUID, in context: ModelContext) throws -> SpaceEntity? {
        let spaceId = id
        let predicate = #Predicate<SpaceEntity> { $0.id == spaceId }
        return try context.fetch(FetchDescriptor<SpaceEntity>(predicate: predicate)).first
    }

    private func fetchSpacesSortedByIndex(in context: ModelContext) throws -> [SpaceEntity] {
        try context.fetch(FetchDescriptor<SpaceEntity>()).sorted { lhs, rhs in
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func assertStoreShape(
        in container: ModelContainer,
        spaces expectedSpaces: Int,
        folders expectedFolders: Int,
        tabs expectedTabs: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let context = ModelContext(container)
        let spaces = try context.fetch(FetchDescriptor<SpaceEntity>())
        let folders = try context.fetch(FetchDescriptor<FolderEntity>())
        let tabs = try context.fetch(FetchDescriptor<TabEntity>())

        XCTAssertEqual(spaces.count, expectedSpaces, file: file, line: line)
        XCTAssertEqual(folders.count, expectedFolders, file: file, line: line)
        XCTAssertEqual(tabs.count, expectedTabs, file: file, line: line)
        XCTAssertEqual(Set(spaces.map(\.id)).count, spaces.count, file: file, line: line)
        XCTAssertEqual(Set(folders.map(\.id)).count, folders.count, file: file, line: line)
        XCTAssertEqual(Set(tabs.map(\.id)).count, tabs.count, file: file, line: line)
    }

    private func waitForPersistedState(
        in container: ModelContainer,
        matching predicate: (TabsStateEntity) throws -> Bool
    ) async throws {
        for _ in 0..<50 {
            let context = ModelContext(container)
            if let state = try context.fetch(FetchDescriptor<TabsStateEntity>()).first,
               try predicate(state) {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let context = ModelContext(container)
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<TabsStateEntity>()).first)
        XCTAssertTrue(try predicate(state))
    }

    private func waitForStore(
        in container: ModelContainer,
        file: StaticString = #filePath,
        line: UInt = #line,
        matching predicate: (ModelContext) throws -> Bool
    ) async throws {
        for _ in 0..<50 {
            let context = ModelContext(container)
            if try predicate(context) {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let context = ModelContext(container)
        XCTAssertTrue(try predicate(context), file: file, line: line)
    }

    private func waitPastStructuralDebounce() async throws {
        try await Task.sleep(nanoseconds: 350_000_000)
    }

    private static func sourceRange(
        in source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(
            source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound
        )
        return String(source[start..<end])
    }

    private static func source(named path: String) throws -> String {
        let url = repoRoot.appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static var repoRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        return url
    }
}
