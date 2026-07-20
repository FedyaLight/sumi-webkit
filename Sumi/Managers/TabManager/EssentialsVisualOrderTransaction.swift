import Foundation
import SumiDomain

@MainActor
final class EssentialsVisualOrderTransaction {
    private let ordering: SplitGroupSidebarOrderingService
    private let groupMutations: SplitGroupMutationService
    private let pins: ShortcutPinCollectionStateOwner
    private let structuralMutations: TabStructuralCollectionMutationOwner

    init(
        ordering: SplitGroupSidebarOrderingService,
        groupMutations: SplitGroupMutationService,
        pins: ShortcutPinCollectionStateOwner,
        structuralMutations: TabStructuralCollectionMutationOwner
    ) {
        self.ordering = ordering
        self.groupMutations = groupMutations
        self.pins = pins
        self.structuralMutations = structuralMutations
    }

    func reorder(
        _ movingItem: SplitGroupVisualListItem,
        for profileID: UUID,
        to proposedIndex: Int
    ) -> Bool {
        let currentPins = pins.essentialPins(for: profileID)
        let currentGroups = ordering.groupsSnapshot
        var items = SidebarVisualOrdering.essentialItems(
            pins: currentPins,
            groups: currentGroups,
            profileID: profileID
        )
        guard let currentIndex = items.firstIndex(of: movingItem) else {
            return false
        }
        let targetIndex = SpacePinnedShortcutOrderOwner
            .adjustedSameContainerInsertionIndex(
                currentIndex: currentIndex,
                proposedIndex: proposedIndex
            )
        guard targetIndex != currentIndex else { return false }

        let moving = items.remove(at: currentIndex)
        items.insert(moving, at: max(0, min(targetIndex, items.count)))
        guard let plan = plan(
            items: items,
            profileID: profileID,
            currentPins: currentPins,
            currentGroups: currentGroups
        ) else { return false }

        if plan.groups == currentGroups {
            structuralMutations.setPinnedTabs(plan.pins, for: profileID)
            structuralMutations.schedulePersistence()
            return true
        }

        return groupMutations.replaceAll(
            expected: currentGroups,
            with: plan.groups,
            alongside: { [structuralMutations] in
                structuralMutations.setPinnedTabs(plan.pins, for: profileID)
            }
        )
    }

    private func plan(
        items: [SplitGroupVisualListItem],
        profileID: UUID,
        currentPins: [ShortcutPin],
        currentGroups: [SplitGroup]
    ) -> (pins: [ShortcutPin], groups: [SplitGroup])? {
        let pinsByID = Dictionary(uniqueKeysWithValues: currentPins.map {
            ($0.id, $0)
        })
        let groupsByID = Dictionary(uniqueKeysWithValues: currentGroups.map {
            ($0.id, $0)
        })
        var orderedPins: [ShortcutPin] = []
        var groupReplacements: [UUID: SplitGroup] = [:]

        for item in items {
            switch item {
            case .shortcut(let pinID):
                guard let pin = pinsByID[pinID] else { return nil }
                orderedPins.append(pin)

            case .splitGroup(let groupID):
                guard let group = groupsByID[groupID],
                      case .essentialSidebar(let ownerProfileID, _) = group.container,
                      ownerProfileID == nil || ownerProfileID == profileID else {
                    return nil
                }
                let rawIndex = orderedPins.count
                let memberPins = group.memberIDs.compactMap { memberID -> ShortcutPin? in
                    guard case .shortcutPin(let pinID) = memberID else {
                        return nil
                    }
                    return pinsByID[pinID]
                }
                guard memberPins.count == group.memberIDs.count,
                      let replacement = group.changingContainer(
                        to: .essentialSidebar(
                            profileId: ownerProfileID,
                            index: rawIndex
                        )
                      ) else { return nil }
                orderedPins.append(contentsOf: memberPins)
                groupReplacements[groupID] = replacement

            case .folder:
                return nil
            }
        }

        guard orderedPins.count == currentPins.count,
              Set(orderedPins.map(\.id)) == Set(currentPins.map(\.id)) else {
            return nil
        }
        return (
            ShortcutPin.reindexed(orderedPins),
            currentGroups.map { groupReplacements[$0.id] ?? $0 }
        )
    }
}
