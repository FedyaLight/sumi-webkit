import Foundation
import SumiDomain

enum SplitGroupVisualListItem: Hashable {
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

/// Pure sidebar ordering projection. Group folder/index placement comes from
/// its explicit durable container and is never inferred from live members.
@MainActor
struct SplitGroupVisualOrderingResolver {
    let spaceID: UUID
    let splitGroups: [SplitGroup]
    let folders: [TabFolder]
    let spacePinnedPins: [ShortcutPin]

    func shortcutSidebarGroups(inFolder folderID: UUID?) -> [SplitGroup] {
        shortcutSidebarGroups().filter {
            $0.container.shortcutSidebarFolderId == folderID
        }
    }

    func shortcutSidebarGroups() -> [SplitGroup] {
        splitGroups.filter { group in
            guard case .shortcutSidebar(let groupSpaceID, _, _, _) =
                group.container else {
                return false
            }
            return groupSpaceID == spaceID
        }
        .sorted(by: orderedBefore)
    }

    func hiddenPinIDs() -> Set<UUID> {
        Set(shortcutSidebarGroups().flatMap { group in
            group.memberIDs.compactMap { memberID -> UUID? in
                guard case .shortcutPin(let pinID) = memberID else { return nil }
                return pinID
            }
        })
    }

    func visualIndex(for group: SplitGroup) -> Int {
        group.container.shortcutSidebarIndex ?? 0
    }

    func topLevelItems() -> [SplitGroupVisualListItem] {
        let hiddenPinIDs = hiddenPinIDs()
        let folderItems = folders
            .filter { $0.parentFolderId == nil }
            .map {
                (
                    index: $0.index,
                    priority: 1,
                    item: SplitGroupVisualListItem.folder($0.id)
                )
            }
        let shortcutItems = spacePinnedPins
            .filter { $0.folderId == nil && !hiddenPinIDs.contains($0.id) }
            .map {
                (
                    index: $0.index,
                    priority: 2,
                    item: SplitGroupVisualListItem.shortcut($0.id)
                )
            }
        let groupItems = shortcutSidebarGroups(inFolder: nil).map {
            (
                index: visualIndex(for: $0),
                priority: 0,
                item: SplitGroupVisualListItem.splitGroup($0.id)
            )
        }
        return sortedItems(folderItems + shortcutItems + groupItems)
    }

    func folderItems(for folderID: UUID) -> [SplitGroupVisualListItem] {
        let hiddenPinIDs = hiddenPinIDs()
        let folderItems = folders
            .filter { $0.parentFolderId == folderID }
            .map {
                (
                    index: $0.index,
                    priority: 1,
                    item: SplitGroupVisualListItem.folder($0.id)
                )
            }
        let shortcutItems = spacePinnedPins
            .filter { $0.folderId == folderID && !hiddenPinIDs.contains($0.id) }
            .map {
                (
                    index: $0.index,
                    priority: 2,
                    item: SplitGroupVisualListItem.shortcut($0.id)
                )
            }
        let groupItems = shortcutSidebarGroups(inFolder: folderID).map {
            (
                index: visualIndex(for: $0),
                priority: 0,
                item: SplitGroupVisualListItem.splitGroup($0.id)
            )
        }
        return sortedItems(folderItems + shortcutItems + groupItems)
    }

    private func orderedBefore(_ lhs: SplitGroup, _ rhs: SplitGroup) -> Bool {
        let lhsIndex = visualIndex(for: lhs)
        let rhsIndex = visualIndex(for: rhs)
        if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func sortedItems(
        _ items: [(
            index: Int,
            priority: Int,
            item: SplitGroupVisualListItem
        )]
    ) -> [SplitGroupVisualListItem] {
        items.sorted { lhs, rhs in
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.item.id.uuidString < rhs.item.id.uuidString
        }
        .map(\.item)
    }
}
