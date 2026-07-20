//
//  SpacePinnedListProjection.swift
//  Sumi
//

import Foundation

typealias SpacePinnedListItem = SplitGroupVisualListItem

struct SpacePinnedDisplayEntry: Identifiable {
    let item: SpacePinnedListItem
    let dropIndex: Int
    let id: String
}

/// Pairs the space-pinned items with stable drop indices and `ForEach`
/// identities. The list is never mutated during drag — the drop indicator
/// line marks the insertion point instead — so this is a plain enumeration.
/// Pure value type so the identity logic stays directly testable.
struct SpacePinnedListProjection {
    let spaceId: UUID
    let items: [SpacePinnedListItem]

    var displayEntries: [SpacePinnedDisplayEntry] {
        items.enumerated().map { index, item in
            SpacePinnedDisplayEntry(
                item: item,
                dropIndex: index,
                id: "item-\(item.id.uuidString)"
            )
        }
    }
}
