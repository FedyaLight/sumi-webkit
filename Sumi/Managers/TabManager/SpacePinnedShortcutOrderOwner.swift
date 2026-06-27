import Foundation

@MainActor
enum SpacePinnedShortcutOrderOwner {
    enum TopLevelItem {
        case folder(TabFolder)
        case shortcut(ShortcutPin)

        var id: UUID {
            switch self {
            case .folder(let folder): return folder.id
            case .shortcut(let pin): return pin.id
            }
        }
    }

    enum TopLevelReorderResult {
        case missing
        case unchanged
        case moved([TopLevelItem])
    }

    struct FolderPlacement {
        let folder: TabFolder
        let spaceId: UUID
        let parentFolderId: UUID?
        let index: Int
    }

    struct TopLevelOrderPlan {
        let folderPlacements: [FolderPlacement]
        let remainingFolders: [TabFolder]
        let orderedTopLevelPins: [ShortcutPin]
        let folderPins: [ShortcutPin]

        var orderedFolders: [TabFolder] {
            folderPlacements.map(\.folder)
        }
    }

    static func normalizedShortcuts(
        _ items: [ShortcutPin],
        foldersBySpace: [UUID: [TabFolder]]
    ) -> [ShortcutPin] {
        struct ContainerKey: Hashable {
            let spaceId: UUID?
            let folderId: UUID?
        }

        func reservedFolderIndexes(for key: ContainerKey) -> Set<Int> {
            guard let spaceId = key.spaceId else { return [] }
            return Set(
                (foldersBySpace[spaceId] ?? [])
                    .filter { $0.parentFolderId == key.folderId }
                    .map(\.index)
            )
        }

        func normalizedGroup(_ pins: [ShortcutPin], reservedIndexes: Set<Int>) -> [ShortcutPin] {
            var nextIndex = 0
            func nextAvailableIndex() -> Int {
                while reservedIndexes.contains(nextIndex) {
                    nextIndex += 1
                }
                defer { nextIndex += 1 }
                return nextIndex
            }

            return pins
                .sorted { lhs, rhs in
                    if lhs.index != rhs.index { return lhs.index < rhs.index }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                .map { pin in pin.refreshed(index: nextAvailableIndex()) }
        }

        let groupedByContainer = Dictionary(grouping: items) {
            ContainerKey(spaceId: $0.spaceId, folderId: $0.folderId)
        }

        return groupedByContainer.keys
            .sorted { lhs, rhs in
                let leftSpace = lhs.spaceId?.uuidString ?? ""
                let rightSpace = rhs.spaceId?.uuidString ?? ""
                if leftSpace != rightSpace { return leftSpace < rightSpace }
                let leftFolder = lhs.folderId?.uuidString ?? ""
                let rightFolder = rhs.folderId?.uuidString ?? ""
                return leftFolder < rightFolder
            }
            .flatMap { key in
                normalizedGroup(
                    groupedByContainer[key] ?? [],
                    reservedIndexes: reservedFolderIndexes(for: key)
                )
            }
    }

    static func topLevelItems(
        for spaceId: UUID,
        foldersBySpace: [UUID: [TabFolder]],
        spacePinnedShortcuts: [UUID: [ShortcutPin]]
    ) -> [TopLevelItem] {
        let folders = (foldersBySpace[spaceId] ?? [])
            .filter { $0.parentFolderId == nil }
            .map { ($0.index, TopLevelItem.folder($0)) }
        let pins = sortedPins(spacePinnedShortcuts[spaceId] ?? [])
            .filter { $0.folderId == nil }
            .map { ($0.index, TopLevelItem.shortcut($0)) }
        return (folders + pins)
            .sorted { lhs, rhs in
                if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
                return lhs.1.id.uuidString < rhs.1.id.uuidString
            }
            .map(\.1)
    }

    static func topLevelOrderPlan(
        _ items: [TopLevelItem],
        for spaceId: UUID,
        foldersBySpace: [UUID: [TabFolder]],
        spacePinnedShortcuts: [UUID: [ShortcutPin]]
    ) -> TopLevelOrderPlan {
        let folders = foldersBySpace[spaceId] ?? []
        let folderMap = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        var folderPlacements: [FolderPlacement] = []
        var orderedTopLevelPins: [ShortcutPin] = []

        for (index, item) in items.enumerated() {
            switch item {
            case .folder(let folder):
                let target = folderMap[folder.id] ?? folder
                folderPlacements.append(
                    FolderPlacement(
                        folder: target,
                        spaceId: spaceId,
                        parentFolderId: nil,
                        index: index
                    )
                )
            case .shortcut(let pin):
                orderedTopLevelPins.append(pin.refreshed(index: index).moved(toFolderId: nil))
            }
        }

        let orderedFolderIds = Set(folderPlacements.map { $0.folder.id })
        let remainingFolders = folders.filter { orderedFolderIds.contains($0.id) == false }
        let folderPins = (spacePinnedShortcuts[spaceId] ?? []).filter { $0.folderId != nil }

        return TopLevelOrderPlan(
            folderPlacements: folderPlacements,
            remainingFolders: remainingFolders,
            orderedTopLevelPins: orderedTopLevelPins,
            folderPins: folderPins
        )
    }

    static func insertingTopLevelShortcut(
        _ pin: ShortcutPin,
        in items: [TopLevelItem],
        at targetIndex: Int
    ) -> [TopLevelItem] {
        var updatedItems = items
        let safeIndex = max(0, min(targetIndex, updatedItems.count))
        updatedItems.insert(.shortcut(pin.moved(toFolderId: nil)), at: safeIndex)
        return updatedItems
    }

    static func reorderingTopLevelItem(
        id: UUID,
        in items: [TopLevelItem],
        to targetIndex: Int
    ) -> TopLevelReorderResult {
        var updatedItems = items
        guard let currentIndex = updatedItems.firstIndex(where: { $0.id == id }) else {
            return .missing
        }
        let adjustedIndex = adjustedSameContainerInsertionIndex(
            currentIndex: currentIndex,
            proposedIndex: targetIndex
        )
        guard currentIndex != adjustedIndex else { return .unchanged }
        let moving = updatedItems.remove(at: currentIndex)
        let safeIndex = max(0, min(adjustedIndex, updatedItems.count))
        updatedItems.insert(moving, at: safeIndex)
        return .moved(updatedItems)
    }

    static func adjustedSameContainerInsertionIndex(
        currentIndex: Int,
        proposedIndex: Int
    ) -> Int {
        let safeProposedIndex = max(0, proposedIndex)
        return currentIndex < safeProposedIndex
            ? max(0, safeProposedIndex - 1)
            : safeProposedIndex
    }

    static func mutatingShortcutGroup(
        in allPins: [ShortcutPin],
        folderId: UUID?,
        foldersBySpace: [UUID: [TabFolder]],
        _ mutate: (inout [ShortcutPin]) -> Void
    ) -> [ShortcutPin] {
        var targetGroup = allPins
            .filter { $0.folderId == folderId }
            .sorted { lhs, rhs in
                if lhs.index != rhs.index { return lhs.index < rhs.index }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        let otherPins = allPins.filter { $0.folderId != folderId }

        mutate(&targetGroup)

        let normalizedGroup = targetGroup.enumerated().map { index, pin in
            pin.refreshed(index: index)
        }
        return normalizedShortcuts(otherPins + normalizedGroup, foldersBySpace: foldersBySpace)
    }

    private static func sortedPins(_ pins: [ShortcutPin]) -> [ShortcutPin] {
        Array(pins).sorted { lhs, rhs in
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
