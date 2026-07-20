import Foundation
import SumiDomain

/// Canonical ordering of Sidebar Visual Items. Render projections, drag source
/// inventory, and commit index conversion all consume this same ordering.
@MainActor
enum SidebarVisualOrdering {
    struct RegularBlock: Equatable {
        enum Identity: Equatable {
            case tab(UUID)
            case splitGroup(UUID)
        }

        let identity: Identity
        let tabIDs: [UUID]

        var firstTabID: UUID? { tabIDs.first }
    }

    static func regularBlocks(
        tabs: [Tab],
        groups: [SplitGroup]
    ) -> [RegularBlock] {
        let groupByMemberID = groups.reduce(into: [UUID: SplitGroup]()) {
            result, group in
            guard case .regularTabs = group.container else { return }
            for memberID in group.memberIDs {
                guard case .regularTab(let tabID) = memberID else { continue }
                result[tabID] = group
            }
        }
        var emittedGroupIDs = Set<UUID>()

        return tabs.compactMap { tab in
            guard let group = groupByMemberID[tab.id] else {
                return RegularBlock(
                    identity: .tab(tab.id),
                    tabIDs: [tab.id]
                )
            }
            guard emittedGroupIDs.insert(group.id).inserted else { return nil }
            let memberIDs = Set(group.memberIDs.compactMap { memberID -> UUID? in
                guard case .regularTab(let tabID) = memberID else { return nil }
                return tabID
            })
            return RegularBlock(
                identity: .splitGroup(group.id),
                tabIDs: tabs.filter { memberIDs.contains($0.id) }.map(\.id)
            )
        }
    }

    static func rawInsertionIndex(
        movingGroupID: UUID,
        proposedVisualIndex: Int,
        blocks: [RegularBlock]
    ) -> Int? {
        guard let currentIndex = blocks.firstIndex(where: {
            $0.identity == .splitGroup(movingGroupID)
        }) else { return nil }
        let targetIndex = SpacePinnedShortcutOrderOwner
            .adjustedSameContainerInsertionIndex(
                currentIndex: currentIndex,
                proposedIndex: proposedVisualIndex
            )
        var remaining = blocks
        remaining.remove(at: currentIndex)
        let safeTarget = max(0, min(targetIndex, remaining.count))
        return remaining.prefix(safeTarget).reduce(0) {
            $0 + $1.tabIDs.count
        }
    }

    static func essentialItems(
        pins: [ShortcutPin],
        groups: [SplitGroup],
        profileID: UUID?
    ) -> [SplitGroupVisualListItem] {
        let pinIDs = Set(pins.map(\.id))
        let visibleGroups = groups.filter { group in
            guard case .essentialSidebar(let ownerProfileID, _) = group.container,
                  ownerProfileID == nil || ownerProfileID == profileID else {
                return false
            }
            return group.memberIDs.allSatisfy { memberID in
                guard case .shortcutPin(let pinID) = memberID else { return false }
                return pinIDs.contains(pinID)
            }
        }
        let hiddenPinIDs = Set(visibleGroups.flatMap(\.memberIDs).compactMap {
            memberID -> UUID? in
            guard case .shortcutPin(let pinID) = memberID else { return nil }
            return pinID
        })
        let pinItems = pins.filter { !hiddenPinIDs.contains($0.id) }.map {
            (index: $0.index, priority: 1, item: SplitGroupVisualListItem.shortcut($0.id))
        }
        let groupItems = visibleGroups.map { group in
            let memberIndex = group.memberIDs.compactMap { memberID -> Int? in
                guard case .shortcutPin(let pinID) = memberID else { return nil }
                return pins.first(where: { $0.id == pinID })?.index
            }.min() ?? 0
            let index: Int
            if case .essentialSidebar(_, let containerIndex) = group.container {
                index = containerIndex ?? memberIndex
            } else {
                index = memberIndex
            }
            return (
                index: index,
                priority: 0,
                item: SplitGroupVisualListItem.splitGroup(group.id)
            )
        }
        return (pinItems + groupItems).sorted { lhs, rhs in
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.item.id.uuidString < rhs.item.id.uuidString
        }.map(\.item)
    }
}
