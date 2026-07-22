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
            foldersBySpace: folders.foldersBySpaceSnapshot(),
            splitGroups: splitGroups.groups
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
        let plan = orderTransaction.planTopLevelOrder(
            items,
            in: spaceId,
            splitGroups: splitGroups.groups
        )
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
            splitGroups: splitGroups.groups,
            mutate
        )
        orderTransaction.setPins(rebuilt, in: spaceId)
    }
}

@MainActor
final class SpacePinnedOrderTransaction {
    struct VisualContainerOrder {
        let folderID: UUID?
        let items: [SplitGroupVisualListItem]
    }

    struct Plan {
        let spaceID: UUID
        let expectedFolders: [TabFolder]
        let expectedPins: [ShortcutPin]
        let folderPlacements: [SpacePinnedShortcutOrderOwner.FolderPlacement]
        let finalFolders: [TabFolder]
        let finalPins: [ShortcutPin]
        let splitGroups: [SplitGroup]
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
        in spaceID: UUID,
        splitGroups: [SplitGroup]
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
            finalPins: order.folderPins + order.orderedTopLevelPins,
            splitGroups: splitGroups
        )
    }

    func planVisualOrder(
        _ items: [SplitGroupVisualListItem],
        in spaceID: UUID,
        groups: [SplitGroup]
    ) -> (plan: Plan, groups: [SplitGroup])? {
        planVisualOrders(
            [VisualContainerOrder(folderID: nil, items: items)],
            in: spaceID,
            groups: groups
        )
    }

    func planVisualOrders(
        _ orders: [VisualContainerOrder],
        in spaceID: UUID,
        groups: [SplitGroup]
    ) -> (plan: Plan, groups: [SplitGroup])? {
        let containerIDs = orders.map(\.folderID)
        guard Set(containerIDs).count == containerIDs.count else {
            return nil
        }
        let currentFolders = folders.folders(for: spaceID)
        let currentPins = pins.spacePinnedPins(for: spaceID)
        let folderMap = Dictionary(
            uniqueKeysWithValues: currentFolders.map { ($0.id, $0) }
        )
        let pinMap = Dictionary(
            uniqueKeysWithValues: currentPins.map { ($0.id, $0) }
        )
        let groupMap = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        var placements: [UUID: SpacePinnedShortcutOrderOwner.FolderPlacement] = [:]
        var pinReplacements: [UUID: ShortcutPin] = [:]
        var replacements: [UUID: SplitGroup] = [:]

        for order in orders {
            for (index, item) in order.items.enumerated() {
                switch item {
                case .folder(let folderID):
                    guard let folder = folderMap[folderID] else { continue }
                    placements[folderID] = .init(
                        folder: folder,
                        spaceId: spaceID,
                        parentFolderId: order.folderID,
                        index: index
                    )
                case .shortcut(let pinID):
                    guard let pin = pinMap[pinID] else { continue }
                    pinReplacements[pinID] = pin
                        .refreshed(index: index)
                        .moved(toFolderId: order.folderID)
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
                                folderId: order.folderID,
                                index: index
                            )
                          ) else { return nil }
                    replacements[groupID] = replacement
                    for memberID in group.memberIDs {
                        guard case .shortcutPin(let pinID) = memberID,
                              let pin = pinMap[pinID] else { continue }
                        pinReplacements[pinID] = pin
                            .refreshed(index: .max)
                            .moved(toFolderId: order.folderID)
                    }
                }
            }
        }

        let finalPins = currentPins.map { pinReplacements[$0.id] ?? $0 }
        let finalGroups = groups.map { replacements[$0.id] ?? $0 }
        return (
            Plan(
                spaceID: spaceID,
                expectedFolders: currentFolders,
                expectedPins: currentPins,
                folderPlacements: Array(placements.values),
                finalFolders: currentFolders,
                finalPins: finalPins,
                splitGroups: finalGroups
            ),
            finalGroups
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
            foldersBySpace: folders.foldersBySpaceSnapshot(),
            splitGroups: plan.splitGroups
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
