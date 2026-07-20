import Foundation
import SumiDomain

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

    private let folders: TabFolderCollectionStateOwner
    private let pins: ShortcutPinCollectionStateOwner
    private let splitGroups: SplitGroupStore
    private let orderTransaction: SpacePinnedOrderTransaction

    init(
        folders: TabFolderCollectionStateOwner,
        pins: ShortcutPinCollectionStateOwner,
        splitGroups: SplitGroupStore,
        orderTransaction: SpacePinnedOrderTransaction
    ) {
        self.folders = folders
        self.pins = pins
        self.splitGroups = splitGroups
        self.orderTransaction = orderTransaction
    }

    func normalizedSpacePinnedShortcuts(_ items: [ShortcutPin]) -> [ShortcutPin] {
        SpacePinnedShortcutOrderOwner.normalizedShortcuts(
            items,
            foldersBySpace: folders.foldersBySpaceSnapshot()
        )
    }

    func folderChildVisualItems(for folderId: UUID, in spaceId: UUID) -> [FolderChildVisualItem] {
        SplitGroupVisualOrderingResolver(
            spaceID: spaceId,
            splitGroups: splitGroups.groups,
            folders: folders.folders(for: spaceId),
            spacePinnedPins: pins.spacePinnedPins(for: spaceId)
        ).folderItems(for: folderId).map { item in
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

    func folderRecursiveChildCount(for folderId: UUID, in spaceId: UUID) -> Int {
        func countChildren(of parentId: UUID, visited: Set<UUID>) -> Int {
            guard visited.contains(parentId) == false else { return 0 }
            var nextVisited = visited
            nextVisited.insert(parentId)

            let childFolders = folders.childFolders(of: parentId, in: spaceId)
            let directPinsCount = pins.folderPinnedPins(for: parentId, in: spaceId).count
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
            foldersBySpace: folders.foldersBySpaceSnapshot(),
            spacePinnedShortcuts: pins.spacePinnedShortcutsSnapshot()
        )
    }

    func applyTopLevelSpacePinnedOrder(
        _ items: [SpacePinnedTopLevelItem],
        for spaceId: UUID
    ) {
        let plan = orderTransaction.planTopLevelOrder(items, in: spaceId)
        precondition(
            orderTransaction.apply(plan),
            "Space-pinned order changed while applying its synchronous plan"
        )
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
        return pins.spacePinnedPins(for: spaceId).first(where: { $0.id == pin.id })
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

    func withSpacePinnedShortcutGroup(
        for spaceId: UUID,
        folderId: UUID?,
        _ mutate: (inout [ShortcutPin]) -> Void
    ) {
        let allPins = pins.spacePinnedPins(for: spaceId)
        let rebuilt = SpacePinnedShortcutOrderOwner.mutatingShortcutGroup(
            in: allPins,
            folderId: folderId,
            foldersBySpace: folders.foldersBySpaceSnapshot(),
            mutate
        )
        orderTransaction.setPins(rebuilt, in: spaceId)
    }
}

@MainActor
final class SpacePinnedOrderTransaction {
    struct Plan {
        let spaceID: UUID
        let expectedFolders: [TabFolder]
        let expectedPins: [ShortcutPin]
        let folderPlacements: [SpacePinnedShortcutOrderOwner.FolderPlacement]
        let finalFolders: [TabFolder]
        let finalPins: [ShortcutPin]
    }

    private let folders: TabFolderCollectionStateOwner
    private let pins: ShortcutPinCollectionStateOwner
    private let mutations: TabStructuralCollectionMutationOwner

    init(
        folders: TabFolderCollectionStateOwner,
        pins: ShortcutPinCollectionStateOwner,
        mutations: TabStructuralCollectionMutationOwner
    ) {
        self.folders = folders
        self.pins = pins
        self.mutations = mutations
    }

    func planTopLevelOrder(
        _ items: [SpacePinnedShortcutOrderOwner.TopLevelItem],
        in spaceID: UUID
    ) -> Plan {
        let foldersBySpace = folders.foldersBySpaceSnapshot()
        let pinsBySpace = pins.spacePinnedShortcutsSnapshot()
        let order = SpacePinnedShortcutOrderOwner.topLevelOrderPlan(
            items,
            for: spaceID,
            foldersBySpace: foldersBySpace,
            spacePinnedShortcuts: pinsBySpace
        )
        let placements = Dictionary(
            uniqueKeysWithValues: order.folderPlacements.map {
                ($0.folder.id, $0.index)
            }
        )
        let finalFolders = (order.orderedFolders + order.remainingFolders)
            .sorted { lhs, rhs in
                let lhsIndex = placements[lhs.id] ?? lhs.index
                let rhsIndex = placements[rhs.id] ?? rhs.index
                if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        return Plan(
            spaceID: spaceID,
            expectedFolders: folders.folders(for: spaceID),
            expectedPins: pins.spacePinnedPins(for: spaceID),
            folderPlacements: order.folderPlacements,
            finalFolders: finalFolders,
            finalPins: order.folderPins + order.orderedTopLevelPins
        )
    }

    func planVisualOrder(
        _ items: [SplitGroupVisualListItem],
        in spaceID: UUID,
        groups: [SplitGroup]
    ) -> (plan: Plan, groups: [SplitGroup])? {
        let currentFolders = folders.folders(for: spaceID)
        let currentPins = pins.spacePinnedPins(for: spaceID)
        let folderMap = Dictionary(
            uniqueKeysWithValues: currentFolders.map { ($0.id, $0) }
        )
        let pinMap = Dictionary(
            uniqueKeysWithValues: currentPins.map { ($0.id, $0) }
        )
        let groupMap = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        var placements: [SpacePinnedShortcutOrderOwner.FolderPlacement] = []
        var orderedPins: [ShortcutPin] = []
        var visiblePinIDs = Set<UUID>()
        var hiddenPinIDs = Set<UUID>()
        var replacements: [UUID: SplitGroup] = [:]

        for (index, item) in items.enumerated() {
            switch item {
            case .folder(let folderID):
                guard let folder = folderMap[folderID] else { continue }
                placements.append(.init(
                    folder: folder,
                    spaceId: spaceID,
                    parentFolderId: nil,
                    index: index
                ))
            case .shortcut(let pinID):
                guard let pin = pinMap[pinID] else { continue }
                visiblePinIDs.insert(pinID)
                orderedPins.append(
                    pin.refreshed(index: index).moved(toFolderId: nil)
                )
            case .splitGroup(let groupID):
                guard let group = groupMap[groupID],
                      case .shortcutSidebar(
                        let groupSpaceID,
                        let profileID,
                        _,
                        _
                      ) = group.container,
                      groupSpaceID == spaceID,
                      let replacement = group.changingContainer(
                        to: .shortcutSidebar(
                            spaceId: spaceID,
                            profileId: profileID,
                            folderId: nil,
                            index: index
                        )
                      ) else { return nil }
                hiddenPinIDs.formUnion(group.memberIDs.compactMap {
                    guard case .shortcutPin(let pinID) = $0 else { return nil }
                    return pinID
                })
                replacements[groupID] = replacement
            }
        }

        let orderedFolderIDs = Set(placements.map { $0.folder.id })
        let folderIndexes = Dictionary(
            uniqueKeysWithValues: placements.map {
                ($0.folder.id, $0.index)
            }
        )
        let finalFolders = (placements.map(\.folder) + currentFolders.filter {
            !orderedFolderIDs.contains($0.id)
        }).sorted { lhs, rhs in
            let lhsIndex = folderIndexes[lhs.id] ?? lhs.index
            let rhsIndex = folderIndexes[rhs.id] ?? rhs.index
            if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let folderPins = currentPins.filter { $0.folderId != nil }
        let unorderedPins = currentPins.filter {
            $0.folderId == nil
                && !visiblePinIDs.contains($0.id)
                && !hiddenPinIDs.contains($0.id)
        }
        let hiddenPins = currentPins.filter {
            $0.folderId == nil && hiddenPinIDs.contains($0.id)
        }.map { $0.refreshed(index: .max) }
        return (
            Plan(
                spaceID: spaceID,
                expectedFolders: currentFolders,
                expectedPins: currentPins,
                folderPlacements: placements,
                finalFolders: finalFolders,
                finalPins: folderPins + unorderedPins + orderedPins + hiddenPins
            ),
            groups.map { replacements[$0.id] ?? $0 }
        )
    }

    @discardableResult
    func apply(_ plan: Plan) -> Bool {
        guard sameObjects(
            folders.folders(for: plan.spaceID),
            plan.expectedFolders
        ), sameObjects(
            pins.spacePinnedPins(for: plan.spaceID),
            plan.expectedPins
        ) else { return false }

        plan.folderPlacements.forEach { placement in
            placement.folder.installPlacement(TabFolderPlacement(
                spaceID: placement.spaceId,
                parentFolderID: placement.parentFolderId,
                index: placement.index
            ))
        }
        mutations.setFolders(plan.finalFolders, for: plan.spaceID)
        let normalizedPins = SpacePinnedShortcutOrderOwner.normalizedShortcuts(
            plan.finalPins,
            foldersBySpace: folders.foldersBySpaceSnapshot()
        )
        mutations.setSpacePinnedShortcuts(normalizedPins, for: plan.spaceID)
        return true
    }

    func setPins(_ replacement: [ShortcutPin], in spaceID: UUID) {
        mutations.setSpacePinnedShortcuts(replacement, for: spaceID)
    }

    func schedulePersistence() {
        mutations.schedulePersistence()
    }

    private func sameObjects<T: AnyObject>(_ lhs: [T], _ rhs: [T]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0 === $1 }
    }
}
