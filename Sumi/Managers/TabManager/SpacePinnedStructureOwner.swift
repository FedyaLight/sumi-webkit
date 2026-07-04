import Foundation

@MainActor
final class SpacePinnedStructureOwner {
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

    struct Dependencies {
        let foldersBySpaceSnapshot: () -> [UUID: [TabFolder]]
        let visualOrderingResolver: (UUID) -> SplitGroupVisualOrderingResolver
        let childFolders: (UUID, UUID) -> [TabFolder]
        let folderPinnedPins: (UUID, UUID) -> [ShortcutPin]
        let spacePinnedShortcutsSnapshot: () -> [UUID: [ShortcutPin]]
        let withStructuralUpdateTransaction: (@MainActor () -> Void) -> Void
        let setFolders: ([TabFolder], UUID) -> Void
        let setSpacePinnedShortcuts: ([ShortcutPin], UUID) -> Void
        let spacePinnedPins: (UUID) -> [ShortcutPin]
        let scheduleStructuralPersistence: () -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func normalizedSpacePinnedShortcuts(_ items: [ShortcutPin]) -> [ShortcutPin] {
        SpacePinnedShortcutOrderOwner.normalizedShortcuts(
            items,
            foldersBySpace: dependencies.foldersBySpaceSnapshot()
        )
    }

    func folderChildVisualItems(for folderId: UUID, in spaceId: UUID) -> [FolderChildVisualItem] {
        dependencies.visualOrderingResolver(spaceId).folderItems(for: folderId).map { item in
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

            let childFolders = dependencies.childFolders(parentId, spaceId)
            let directPinsCount = dependencies.folderPinnedPins(parentId, spaceId).count
            let nestedCount = childFolders.reduce(0) { total, childFolder in
                total + 1 + countChildren(of: childFolder.id, visited: nextVisited)
            }
            return directPinsCount + nestedCount
        }

        return countChildren(of: folderId, visited: [])
    }

    func topLevelSpacePinnedItems(for spaceId: UUID) -> [SpacePinnedTopLevelItem] {
        SpacePinnedShortcutOrderOwner.topLevelItems(
            for: spaceId,
            foldersBySpace: dependencies.foldersBySpaceSnapshot(),
            spacePinnedShortcuts: dependencies.spacePinnedShortcutsSnapshot()
        )
    }

    func applyTopLevelSpacePinnedOrder(
        _ items: [SpacePinnedTopLevelItem],
        for spaceId: UUID
    ) {
        dependencies.withStructuralUpdateTransaction {
            let plan = SpacePinnedShortcutOrderOwner.topLevelOrderPlan(
                items,
                for: spaceId,
                foldersBySpace: dependencies.foldersBySpaceSnapshot(),
                spacePinnedShortcuts: dependencies.spacePinnedShortcutsSnapshot()
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
            dependencies.setFolders(finalFolders, spaceId)

            let finalPins = normalizedSpacePinnedShortcuts(plan.folderPins + plan.orderedTopLevelPins)
            dependencies.setSpacePinnedShortcuts(finalPins, spaceId)
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
        return dependencies.spacePinnedPins(spaceId).first(where: { $0.id == pin.id })
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
            return dependencies.spacePinnedPins(spaceId).first(where: { $0.id == pin.id })
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
            dependencies.scheduleStructuralPersistence()
            return true
        }
    }

    func withSpacePinnedShortcutGroup(
        for spaceId: UUID,
        folderId: UUID?,
        _ mutate: (inout [ShortcutPin]) -> Void
    ) {
        let allPins = dependencies.spacePinnedPins(spaceId)
        let rebuilt = SpacePinnedShortcutOrderOwner.mutatingShortcutGroup(
            in: allPins,
            folderId: folderId,
            foldersBySpace: dependencies.foldersBySpaceSnapshot(),
            mutate
        )
        dependencies.setSpacePinnedShortcuts(rebuilt, spaceId)
    }
}

extension SpacePinnedStructureOwner.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            foldersBySpaceSnapshot: { [weak tabManager] in
                tabManager?.folderCollectionStateOwner.foldersBySpaceSnapshot() ?? [:]
            },
            visualOrderingResolver: { [weak tabManager] spaceId in
                guard let tabManager else { preconditionFailure("TabManager dependency used after deallocation") }
                return tabManager.splitGroupStructureOwner.visualOrderingResolver(for: spaceId)
            },
            childFolders: { [weak tabManager] parentId, spaceId in
                tabManager?.folderCollectionStateOwner.childFolders(of: parentId, in: spaceId) ?? []
            },
            folderPinnedPins: { [weak tabManager] folderId, spaceId in
                tabManager?.shortcutPinCollectionStateOwner.folderPinnedPins(for: folderId, in: spaceId) ?? []
            },
            spacePinnedShortcutsSnapshot: { [weak tabManager] in
                tabManager?.shortcutPinCollectionStateOwner.spacePinnedShortcutsSnapshot() ?? [:]
            },
            withStructuralUpdateTransaction: { [weak tabManager] operation in
                guard let tabManager else {
                    operation()
                    return
                }
                tabManager.withStructuralUpdateTransaction(operation)
            },
            setFolders: { [weak tabManager] folders, spaceId in
                tabManager?.structuralCollectionMutationOwner.setFolders(folders, for: spaceId)
            },
            setSpacePinnedShortcuts: { [weak tabManager] pins, spaceId in
                tabManager?.structuralCollectionMutationOwner.setSpacePinnedShortcuts(pins, for: spaceId)
            },
            spacePinnedPins: { [weak tabManager] spaceId in
                tabManager?.shortcutPinCollectionStateOwner.spacePinnedPins(for: spaceId) ?? []
            },
            scheduleStructuralPersistence: { [weak tabManager] in
                tabManager?.scheduleStructuralPersistence()
            }
        )
    }
}
