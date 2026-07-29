import Foundation
import SumiDomain

/// Expands a split's members at the split group's visual position while
/// committing the corresponding topology replacement.
@MainActor
final class SplitGroupReleaseOrderingService {
    private struct Plan {
        let groups: [SplitGroup]
        let apply: @MainActor () -> Bool
    }

    private let splitGroups: SplitGroupStore
    private let mutations: SplitGroupMutationService
    private let ordering: SplitGroupSidebarOrderingService
    private let regularTabs: RegularTabCollectionOwner
    private let pins: ShortcutPinCollectionStateOwner
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let spacePinnedOrder: SpacePinnedOrderTransaction

    init(
        splitGroups: SplitGroupStore,
        mutations: SplitGroupMutationService,
        ordering: SplitGroupSidebarOrderingService,
        regularTabs: RegularTabCollectionOwner,
        pins: ShortcutPinCollectionStateOwner,
        structuralMutations: TabStructuralCollectionMutationOwner,
        spacePinnedOrder: SpacePinnedOrderTransaction
    ) {
        self.splitGroups = splitGroups
        self.mutations = mutations
        self.ordering = ordering
        self.regularTabs = regularTabs
        self.pins = pins
        self.structuralMutations = structuralMutations
        self.spacePinnedOrder = spacePinnedOrder
    }

    func commit(
        _ group: SplitGroup,
        replacingWith replacementGroup: SplitGroup?
    ) -> Bool {
        let expectedGroups = splitGroups.groups
        guard let groupIndex = expectedGroups.firstIndex(where: {
            $0 == group
        }) else { return false }

        var replacementGroups = expectedGroups
        if let replacementGroup {
            guard replacementGroup.id == group.id else { return false }
            replacementGroups[groupIndex] = replacementGroup
        } else {
            replacementGroups.remove(at: groupIndex)
        }

        guard let plan = plan(
            group,
            replacingWith: replacementGroup,
            groups: replacementGroups
        ) else { return false }
        return mutations.replaceAllAtomically(
            expected: expectedGroups,
            with: plan.groups,
            applying: plan.apply
        )
    }

    private func plan(
        _ group: SplitGroup,
        replacingWith replacementGroup: SplitGroup?,
        groups: [SplitGroup]
    ) -> Plan? {
        switch group.container {
        case .regularTabs(let storedSpaceID):
            return regularPlan(
                group,
                storedSpaceID: storedSpaceID,
                groups: groups
            )
        case .shortcutSidebar(let spaceID, _, let folderID, _):
            return spacePinnedPlan(
                group,
                replacingWith: replacementGroup,
                spaceID: spaceID,
                folderID: folderID,
                groups: groups
            )
        case .essentialSidebar(let storedProfileID, _):
            return essentialPlan(
                group,
                replacingWith: replacementGroup,
                storedProfileID: storedProfileID,
                groups: groups
            )
        }
    }

    private func regularPlan(
        _ group: SplitGroup,
        storedSpaceID: UUID?,
        groups: [SplitGroup]
    ) -> Plan? {
        let memberIDs = group.memberIDs.compactMap { memberID -> UUID? in
            guard case .regularTab(let tabID) = memberID else { return nil }
            return tabID
        }
        guard memberIDs.count == group.memberIDs.count else { return nil }

        let resolvedSpaceID = storedSpaceID
            ?? memberIDs.compactMap { regularTabs.tab(for: $0)?.spaceId }.first
        guard let spaceID = resolvedSpaceID else { return nil }
        let currentTabs = regularTabs.tabs(in: spaceID)
        let memberIDSet = Set(memberIDs)
        let tabByID = Dictionary(uniqueKeysWithValues: currentTabs.map {
            ($0.id, $0)
        })
        let orderedMembers = memberIDs.compactMap { tabByID[$0] }
        guard orderedMembers.count == memberIDs.count,
              let firstMemberIndex = currentTabs.firstIndex(where: {
                  memberIDSet.contains($0.id)
              }) else { return nil }

        let insertionIndex = currentTabs[..<firstMemberIndex].reduce(0) {
            $0 + (memberIDSet.contains($1.id) ? 0 : 1)
        }
        var expandedTabs = currentTabs.filter {
            !memberIDSet.contains($0.id)
        }
        expandedTabs.insert(
            contentsOf: orderedMembers,
            at: min(insertionIndex, expandedTabs.count)
        )
        let orderChanged = expandedTabs.map(\.id) != currentTabs.map(\.id)

        return Plan(groups: groups) { [structuralMutations] in
            guard orderChanged else { return true }
            for (index, tab) in expandedTabs.enumerated() {
                tab.index = index
            }
            structuralMutations.setTabs(expandedTabs, for: spaceID)
            return true
        }
    }

    private func spacePinnedPlan(
        _ group: SplitGroup,
        replacingWith replacementGroup: SplitGroup?,
        spaceID: UUID,
        folderID: UUID?,
        groups: [SplitGroup]
    ) -> Plan? {
        let resolver = ordering.resolver(for: spaceID)
        let currentItems = folderID.map(resolver.folderItems(for:))
            ?? resolver.topLevelItems()
        guard let expandedItems = expandedLauncherItems(
            currentItems,
            group: group,
            replacementGroup: replacementGroup
        ), let planned = spacePinnedOrder.planVisualOrders(
            [.init(folderID: folderID, items: expandedItems)],
            in: spaceID,
            groups: groups
        ) else { return nil }

        return Plan(groups: planned.groups) { [spacePinnedOrder] in
            spacePinnedOrder.apply(planned.plan)
        }
    }

    private func essentialPlan(
        _ group: SplitGroup,
        replacingWith replacementGroup: SplitGroup?,
        storedProfileID: UUID?,
        groups: [SplitGroup]
    ) -> Plan? {
        let memberPins = group.memberIDs.compactMap {
            memberID -> ShortcutPin? in
            guard case .shortcutPin(let pinID) = memberID else { return nil }
            return pins.shortcutPin(by: pinID)
        }
        guard memberPins.count == group.memberIDs.count,
              let profileID = storedProfileID ?? memberPins.first?.profileId
        else { return nil }

        let currentPins = pins.essentialPins(for: profileID)
        let currentItems = ordering.essentialItems(for: profileID)
        guard let expandedItems = expandedLauncherItems(
            currentItems,
            group: group,
            replacementGroup: replacementGroup
        ) else { return nil }

        let pinByID = Dictionary(uniqueKeysWithValues: currentPins.map {
            ($0.id, $0)
        })
        let groupByID = Dictionary(uniqueKeysWithValues: groups.map {
            ($0.id, $0)
        })
        var orderedPins: [ShortcutPin] = []
        var groupReplacements: [UUID: SplitGroup] = [:]

        for item in expandedItems {
            switch item {
            case .shortcut(let pinID):
                guard let pin = pinByID[pinID] else { return nil }
                orderedPins.append(pin)
            case .splitGroup(let groupID):
                guard let currentGroup = groupByID[groupID],
                      case .essentialSidebar(let ownerProfileID, _) =
                        currentGroup.container,
                      ownerProfileID == nil || ownerProfileID == profileID
                else { return nil }
                let groupPins = currentGroup.memberIDs.compactMap {
                    memberID -> ShortcutPin? in
                    guard case .shortcutPin(let pinID) = memberID else {
                        return nil
                    }
                    return pinByID[pinID]
                }
                guard groupPins.count == currentGroup.memberIDs.count,
                      let replacement = currentGroup.changingContainer(
                        to: .essentialSidebar(
                            profileId: ownerProfileID,
                            index: orderedPins.count
                        )
                      ) else { return nil }
                orderedPins.append(contentsOf: groupPins)
                groupReplacements[groupID] = replacement
            case .folder:
                return nil
            }
        }

        guard orderedPins.count == currentPins.count,
              Set(orderedPins.map(\.id)) == Set(currentPins.map(\.id))
        else { return nil }
        let finalPins = ShortcutPin.reindexed(orderedPins)
        let finalGroups = groups.map {
            groupReplacements[$0.id] ?? $0
        }
        return Plan(groups: finalGroups) { [structuralMutations] in
            structuralMutations.setPinnedTabs(
                finalPins,
                for: profileID
            )
            return true
        }
    }

    private func expandedLauncherItems(
        _ currentItems: [SplitGroupVisualListItem],
        group: SplitGroup,
        replacementGroup: SplitGroup?
    ) -> [SplitGroupVisualListItem]? {
        guard let groupIndex = currentItems.firstIndex(
            of: .splitGroup(group.id)
        ) else { return nil }
        let retainedMemberIDs = Set(replacementGroup?.memberIDs ?? [])
        var emittedReplacementGroup = false
        var expansion: [SplitGroupVisualListItem] = []

        for memberID in group.memberIDs {
            if retainedMemberIDs.contains(memberID) {
                if !emittedReplacementGroup {
                    expansion.append(.splitGroup(group.id))
                    emittedReplacementGroup = true
                }
                continue
            }
            guard case .shortcutPin(let pinID) = memberID else { return nil }
            expansion.append(.shortcut(pinID))
        }
        guard replacementGroup == nil || emittedReplacementGroup else {
            return nil
        }

        var result = currentItems
        result.replaceSubrange(groupIndex...groupIndex, with: expansion)
        return result
    }
}
