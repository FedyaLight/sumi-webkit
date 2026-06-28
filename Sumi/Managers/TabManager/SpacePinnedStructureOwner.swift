import Foundation

@MainActor
final class SpacePinnedStructureOwner {
    unowned let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    func normalizedSpacePinnedShortcuts(_ items: [ShortcutPin]) -> [ShortcutPin] {
        SpacePinnedShortcutOrderOwner.normalizedShortcuts(
            items,
            foldersBySpace: tabManager.foldersBySpace
        )
    }

    func folderChildVisualItems(for folderId: UUID, in spaceId: UUID) -> [TabManager.FolderChildVisualItem] {
        tabManager.splitGroupVisualOrderingResolver(for: spaceId).folderItems(for: folderId).map { item in
            switch item {
            case .folder(let id):
                return .folder(id)
            case .shortcut(let id):
                return .shortcut(id)
            case .splitGroup(let id):
                return .splitGroup(id)
            }
        }
    }

    func folderDirectChildCount(for folderId: UUID, in spaceId: UUID) -> Int {
        folderChildVisualItems(for: folderId, in: spaceId).count
    }

    func folderRecursiveChildCount(for folderId: UUID, in spaceId: UUID) -> Int {
        func countChildren(of parentId: UUID, visited: Set<UUID>) -> Int {
            guard visited.contains(parentId) == false else { return 0 }
            var nextVisited = visited
            nextVisited.insert(parentId)

            let childFolders = tabManager.childFolders(of: parentId, in: spaceId)
            let directPinsCount = tabManager.folderPinnedPins(for: parentId, in: spaceId).count
            let nestedCount = childFolders.reduce(0) { total, childFolder in
                total + 1 + countChildren(of: childFolder.id, visited: nextVisited)
            }
            return directPinsCount + nestedCount
        }

        return countChildren(of: folderId, visited: [])
    }

    func topLevelSpacePinnedItems(for spaceId: UUID) -> [TabManager.SpacePinnedTopLevelItem] {
        SpacePinnedShortcutOrderOwner.topLevelItems(
            for: spaceId,
            foldersBySpace: tabManager.foldersBySpace,
            spacePinnedShortcuts: tabManager.spacePinnedShortcuts
        )
    }

    func applyTopLevelSpacePinnedOrder(
        _ items: [TabManager.SpacePinnedTopLevelItem],
        for spaceId: UUID
    ) {
        tabManager.withStructuralUpdateTransaction {
            let plan = SpacePinnedShortcutOrderOwner.topLevelOrderPlan(
                items,
                for: spaceId,
                foldersBySpace: tabManager.foldersBySpace,
                spacePinnedShortcuts: tabManager.spacePinnedShortcuts
            )
            for placement in plan.folderPlacements {
                placement.folder.index = placement.index
                placement.folder.spaceId = placement.spaceId
                placement.folder.parentFolderId = placement.parentFolderId
            }
            let finalFolders = (plan.orderedFolders + plan.remainingFolders).sorted { lhs, rhs in
                if lhs.index != rhs.index { return lhs.index < rhs.index }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            tabManager.setFolders(finalFolders, for: spaceId)

            let finalPins = normalizedSpacePinnedShortcuts(plan.folderPins + plan.orderedTopLevelPins)
            tabManager.setSpacePinnedShortcuts(finalPins, for: spaceId)
        }
    }

    func insertTopLevelSpacePinnedShortcut(
        _ pin: ShortcutPin,
        in spaceId: UUID,
        at targetIndex: Int
    ) -> ShortcutPin? {
        let items = SpacePinnedShortcutOrderOwner.insertingTopLevelShortcut(
            pin,
            in: topLevelSpacePinnedItems(for: spaceId),
            at: targetIndex
        )
        applyTopLevelSpacePinnedOrder(items, for: spaceId)
        return tabManager.spacePinnedShortcuts[spaceId]?.first(where: { $0.id == pin.id })
    }

    func adjustedSameContainerInsertionIndex(
        currentIndex: Int,
        proposedIndex: Int
    ) -> Int {
        SpacePinnedShortcutOrderOwner.adjustedSameContainerInsertionIndex(
            currentIndex: currentIndex,
            proposedIndex: proposedIndex
        )
    }

    @discardableResult
    func reorderTopLevelSpacePinnedShortcut(
        _ pin: ShortcutPin,
        in spaceId: UUID,
        to targetIndex: Int
    ) -> ShortcutPin? {
        switch SpacePinnedShortcutOrderOwner.reorderingTopLevelItem(
            id: pin.id,
            in: topLevelSpacePinnedItems(for: spaceId),
            to: targetIndex
        ) {
        case .missing:
            return nil
        case .unchanged:
            return pin
        case .moved(let items):
            applyTopLevelSpacePinnedOrder(items, for: spaceId)
            return tabManager.spacePinnedShortcuts[spaceId]?.first(where: { $0.id == pin.id })
        }
    }

    @discardableResult
    func reorderFolderInTopLevelPinned(
        _ folder: TabFolder,
        in spaceId: UUID,
        to targetIndex: Int
    ) -> Bool {
        switch SpacePinnedShortcutOrderOwner.reorderingTopLevelItem(
            id: folder.id,
            in: topLevelSpacePinnedItems(for: spaceId),
            to: targetIndex
        ) {
        case .missing, .unchanged:
            return false
        case .moved(let items):
            applyTopLevelSpacePinnedOrder(items, for: spaceId)
            tabManager.scheduleStructuralPersistence()
            return true
        }
    }

    func withSpacePinnedShortcutGroup(
        for spaceId: UUID,
        folderId: UUID?,
        _ mutate: (inout [ShortcutPin]) -> Void
    ) {
        let allPins = tabManager.spacePinnedShortcuts[spaceId] ?? []
        let rebuilt = SpacePinnedShortcutOrderOwner.mutatingShortcutGroup(
            in: allPins,
            folderId: folderId,
            foldersBySpace: tabManager.foldersBySpace,
            mutate
        )
        tabManager.setSpacePinnedShortcuts(rebuilt, for: spaceId)
    }
}

@MainActor
extension TabManager {
    typealias SpacePinnedTopLevelItem = SpacePinnedShortcutOrderOwner.TopLevelItem

    enum FolderChildVisualItem: Hashable {
        case folder(UUID)
        case shortcut(UUID)
        case splitGroup(UUID)

        var id: UUID {
            switch self {
            case .folder(let id), .shortcut(let id), .splitGroup(let id):
                return id
            }
        }
    }

    func normalizedSpacePinnedShortcuts(_ items: [ShortcutPin]) -> [ShortcutPin] {
        spacePinnedStructureOwner.normalizedSpacePinnedShortcuts(items)
    }

    func folderChildVisualItems(for folderId: UUID, in spaceId: UUID) -> [FolderChildVisualItem] {
        spacePinnedStructureOwner.folderChildVisualItems(for: folderId, in: spaceId)
    }

    func folderDirectChildCount(for folderId: UUID, in spaceId: UUID) -> Int {
        spacePinnedStructureOwner.folderDirectChildCount(for: folderId, in: spaceId)
    }

    func folderRecursiveChildCount(for folderId: UUID, in spaceId: UUID) -> Int {
        spacePinnedStructureOwner.folderRecursiveChildCount(for: folderId, in: spaceId)
    }

    func topLevelSpacePinnedItems(for spaceId: UUID) -> [SpacePinnedTopLevelItem] {
        spacePinnedStructureOwner.topLevelSpacePinnedItems(for: spaceId)
    }

    func applyTopLevelSpacePinnedOrder(
        _ items: [SpacePinnedTopLevelItem],
        for spaceId: UUID
    ) {
        spacePinnedStructureOwner.applyTopLevelSpacePinnedOrder(items, for: spaceId)
    }

    func insertTopLevelSpacePinnedShortcut(
        _ pin: ShortcutPin,
        in spaceId: UUID,
        at targetIndex: Int
    ) -> ShortcutPin? {
        spacePinnedStructureOwner.insertTopLevelSpacePinnedShortcut(pin, in: spaceId, at: targetIndex)
    }

    func adjustedSameContainerInsertionIndex(
        currentIndex: Int,
        proposedIndex: Int
    ) -> Int {
        spacePinnedStructureOwner.adjustedSameContainerInsertionIndex(
            currentIndex: currentIndex,
            proposedIndex: proposedIndex
        )
    }

    @discardableResult
    func reorderTopLevelSpacePinnedShortcut(
        _ pin: ShortcutPin,
        in spaceId: UUID,
        to targetIndex: Int
    ) -> ShortcutPin? {
        spacePinnedStructureOwner.reorderTopLevelSpacePinnedShortcut(pin, in: spaceId, to: targetIndex)
    }

    @discardableResult
    func reorderFolderInTopLevelPinned(
        _ folder: TabFolder,
        in spaceId: UUID,
        to targetIndex: Int
    ) -> Bool {
        spacePinnedStructureOwner.reorderFolderInTopLevelPinned(folder, in: spaceId, to: targetIndex)
    }

    func withSpacePinnedShortcutGroup(
        for spaceId: UUID,
        folderId: UUID?,
        _ mutate: (inout [ShortcutPin]) -> Void
    ) {
        spacePinnedStructureOwner.withSpacePinnedShortcutGroup(
            for: spaceId,
            folderId: folderId,
            mutate
        )
    }
}
