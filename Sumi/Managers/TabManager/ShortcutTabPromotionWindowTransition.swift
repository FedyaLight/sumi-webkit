import Foundation
import SumiDomain

@MainActor
final class ShortcutTabPromotionWindowTransition {
    private let registry: LiveShortcutTabRegistry
    private let membership: TabCollectionMembershipOwner

    init(
        registry: LiveShortcutTabRegistry,
        membership: TabCollectionMembershipOwner
    ) {
        self.registry = registry
        self.membership = membership
    }

    func project(
        plan: ShortcutTabPromotionPlan,
        split: ShortcutTabPromotionSplitTransition
    ) -> [UUID: BrowserWindowShortcutMutationState] {
        Dictionary(uniqueKeysWithValues: plan.selectedWindowStates.compactMap {
            window -> (UUID, BrowserWindowShortcutMutationState)? in
            let source = window.unpublishedShortcutMutationState
            var target = source
            apply(
                plan: plan,
                split: split,
                windowID: window.id,
                to: &target
            )
            return target == source ? nil : (window.id, target)
        })
    }

    private func apply(
        plan: ShortcutTabPromotionPlan,
        split: ShortcutTabPromotionSplitTransition,
        windowID: UUID,
        to state: inout BrowserWindowShortcutMutationState
    ) {
        switch split {
        case .none:
            if windowID == plan.chosenEntry?.windowId {
                select(plan.tab, in: &state)
            }
        case .replaced(let groupID, let memberID):
            guard state.splitSelection?.groupID == groupID else { return }
            select(plan.tab, in: &state)
            state.splitSelection = WindowSplitSelection(
                groupID: groupID,
                activeMemberID: memberID
            )
        case .removed(let groupID, let remainingGroup):
            guard state.splitSelection?.groupID == groupID else { return }
            if let memberID = remainingGroup?.memberIDs.first,
               let tab = resolvedTab(for: memberID, windowID: windowID) {
                select(tab, in: &state)
                state.splitSelection = WindowSplitSelection(
                    groupID: groupID,
                    activeMemberID: memberID
                )
            } else {
                state.splitSelection = nil
                if windowID == plan.chosenEntry?.windowId {
                    select(plan.tab, in: &state)
                }
            }
        }
    }

    private func select(
        _ tab: Tab,
        in state: inout BrowserWindowShortcutMutationState
    ) {
        _ = WindowTabSelectionStateApplicator.apply(
            tab,
            to: &state,
            updateSpaceFromTab: true,
            rememberSelection: true
        )
    }

    private func resolvedTab(
        for memberID: SplitMemberID,
        windowID: UUID
    ) -> Tab? {
        switch memberID {
        case .regularTab(let tabID): return membership.tab(for: tabID)
        case .shortcutPin(let pinID):
            return registry.tab(for: pinID, in: windowID)
        }
    }
}
