import Foundation
import SumiDomain

/// Applies sidebar placement changes for shortcut-backed split groups. Query
/// projection and mutation are kept separate from the split store itself.
@MainActor
final class SplitGroupSidebarOrderingService {
    private let store: SplitGroupStore
    private let mutations: SplitGroupMutationService
    private let folders: (UUID) -> [TabFolder]
    private let spacePinnedPins: (UUID) -> [ShortcutPin]
    private let adjustedInsertionIndex: (_ current: Int, _ proposed: Int) -> Int
    private let setFolders: ([TabFolder], UUID) -> Void
    private let normalizePins: ([ShortcutPin]) -> [ShortcutPin]
    private let setPins: ([ShortcutPin], UUID) -> Void

    init(
        store: SplitGroupStore,
        mutations: SplitGroupMutationService,
        folders: @escaping (UUID) -> [TabFolder],
        spacePinnedPins: @escaping (UUID) -> [ShortcutPin],
        adjustedInsertionIndex: @escaping (_ current: Int, _ proposed: Int) -> Int,
        setFolders: @escaping ([TabFolder], UUID) -> Void,
        normalizePins: @escaping ([ShortcutPin]) -> [ShortcutPin],
        setPins: @escaping ([ShortcutPin], UUID) -> Void
    ) {
        self.store = store
        self.mutations = mutations
        self.folders = folders
        self.spacePinnedPins = spacePinnedPins
        self.adjustedInsertionIndex = adjustedInsertionIndex
        self.setFolders = setFolders
        self.normalizePins = normalizePins
        self.setPins = setPins
    }

    func resolver(for spaceID: UUID) -> SplitGroupVisualOrderingResolver {
        SplitGroupVisualOrderingResolver(
            spaceID: spaceID,
            splitGroups: store.groups,
            folders: folders(spaceID),
            spacePinnedPins: spacePinnedPins(spaceID)
        )
    }

    func groups(for spaceID: UUID, folderID: UUID? = nil) -> [SplitGroup] {
        resolver(for: spaceID).shortcutSidebarGroups(inFolder: folderID)
    }

    func folderID(for group: SplitGroup, in spaceID: UUID) -> UUID? {
        guard group.container.spaceId == spaceID,
              group.container.isShortcutSidebar else {
            return nil
        }
        return group.container.shortcutSidebarFolderId
    }

    func topLevelItems(for spaceID: UUID) -> [SplitGroupVisualListItem] {
        resolver(for: spaceID).topLevelItems()
    }

    @discardableResult
    func moveGroup(
        _ group: SplitGroup,
        in spaceID: UUID,
        to proposedIndex: Int
    ) -> Bool {
        guard store.group(id: group.id) == group,
              case .shortcutSidebar(
                let groupSpaceID,
                _,
                nil,
                _
              ) = group.container,
              groupSpaceID == spaceID else {
            return false
        }

        let currentItems = topLevelItems(for: spaceID)
        let currentIndex = currentItems.firstIndex { item in
            if case .splitGroup(let groupID) = item { return groupID == group.id }
            return false
        }
        let targetIndex = currentIndex.map {
            adjustedInsertionIndex($0, proposedIndex)
        } ?? proposedIndex
        var reorderedItems = currentItems
        let movingItem: SplitGroupVisualListItem
        if let currentIndex {
            movingItem = reorderedItems.remove(at: currentIndex)
        } else {
            movingItem = .splitGroup(group.id)
        }
        reorderedItems.insert(
            movingItem,
            at: max(0, min(targetIndex, reorderedItems.count))
        )
        guard reorderedItems != currentItems else { return false }

        return applyTopLevelOrder(reorderedItems, in: spaceID)
    }

    private func applyTopLevelOrder(
        _ items: [SplitGroupVisualListItem],
        in spaceID: UUID
    ) -> Bool {
        let currentGroups = store.groups
        let folderMap = Dictionary(
            uniqueKeysWithValues: folders(spaceID).map { ($0.id, $0) }
        )
        let currentPins = spacePinnedPins(spaceID)
        let pinMap = Dictionary(uniqueKeysWithValues: currentPins.map { ($0.id, $0) })
        let groupMap = store.groupMap
        var orderedFolders: [TabFolder] = []
        var orderedVisiblePins: [ShortcutPin] = []
        var visiblePinIDs = Set<UUID>()
        var hiddenSplitPinIDs = Set<UUID>()
        var updatedGroupsByID: [UUID: SplitGroup] = [:]

        for (index, item) in items.enumerated() {
            switch item {
            case .folder(let folderID):
                guard let folder = folderMap[folderID] else { continue }
                folder.installPlacement(TabFolderPlacement(
                    spaceID: spaceID,
                    parentFolderID: nil,
                    index: index
                ))
                orderedFolders.append(folder)

            case .shortcut(let pinID):
                guard let pin = pinMap[pinID] else { continue }
                visiblePinIDs.insert(pin.id)
                orderedVisiblePins.append(
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
                      groupSpaceID == spaceID else {
                    continue
                }
                hiddenSplitPinIDs.formUnion(group.memberIDs.compactMap {
                    memberID -> UUID? in
                    guard case .shortcutPin(let pinID) = memberID else {
                        return nil
                    }
                    return pinID
                })
                guard let updated = group.changingContainer(
                    to: .shortcutSidebar(
                        spaceId: spaceID,
                        profileId: profileID,
                        folderId: nil,
                        index: index
                    )
                ) else {
                    return false
                }
                updatedGroupsByID[group.id] = updated
            }
        }

        let remainingFolders = folders(spaceID).filter { folder in
            !orderedFolders.contains { $0.id == folder.id }
        }
        let finalFolders = (orderedFolders + remainingFolders).sorted {
            if $0.index != $1.index { return $0.index < $1.index }
            return $0.id.uuidString < $1.id.uuidString
        }
        let folderPins = currentPins.filter { $0.folderId != nil }
        let unorderedTopLevelPins = currentPins.filter {
            $0.folderId == nil
                && !visiblePinIDs.contains($0.id)
                && !hiddenSplitPinIDs.contains($0.id)
        }
        let hiddenPins = currentPins
            .filter {
                $0.folderId == nil && hiddenSplitPinIDs.contains($0.id)
            }
            .map { $0.refreshed(index: .max) }
        let finalPins = normalizePins(
            folderPins + unorderedTopLevelPins + orderedVisiblePins + hiddenPins
        )
        let updatedGroups = currentGroups.map {
            updatedGroupsByID[$0.id] ?? $0
        }

        return mutations.replaceAll(
            expected: currentGroups,
            with: updatedGroups,
            alongside: { [setFolders, setPins] in
                setFolders(finalFolders, spaceID)
                setPins(finalPins, spaceID)
            }
        )
    }
}

extension SplitGroupSidebarOrderingService {
    convenience init(tabManager: TabManager) {
        self.init(
            store: tabManager.splitGroupStore,
            mutations: tabManager.splitGroupMutations,
            folders: { [weak tabManager] in
                tabManager?.folderCollectionStateOwner.folders(for: $0) ?? []
            },
            spacePinnedPins: { [weak tabManager] in
                tabManager?.shortcutPinCollectionStateOwner
                    .spacePinnedPins(for: $0) ?? []
            },
            adjustedInsertionIndex: { [weak tabManager] current, proposed in
                tabManager?.spacePinnedStructureOwner
                    .adjustedSameContainerInsertionIndex(
                        currentIndex: current,
                        proposedIndex: proposed
                    ) ?? proposed
            },
            setFolders: { [weak tabManager] folders, spaceID in
                tabManager?.structuralCollectionMutationOwner
                    .setFolders(folders, for: spaceID)
            },
            normalizePins: { [weak tabManager] pins in
                tabManager?.spacePinnedStructureOwner
                    .normalizedSpacePinnedShortcuts(pins) ?? pins
            },
            setPins: { [weak tabManager] pins, spaceID in
                tabManager?.structuralCollectionMutationOwner
                    .setSpacePinnedShortcuts(pins, for: spaceID)
            }
        )
    }
}
