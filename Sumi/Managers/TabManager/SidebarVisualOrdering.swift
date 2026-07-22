import Foundation
import SumiDomain

/// Canonical ordering for launcher containers outside the regular-tab scene.
@MainActor
enum SidebarVisualOrdering {
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
