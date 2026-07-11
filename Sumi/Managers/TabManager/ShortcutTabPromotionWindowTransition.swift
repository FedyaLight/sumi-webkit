import Foundation
import SumiDomain

/// Applies window-local selection changes after durable split identity has
/// already moved from shortcut pin to regular tab.
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

    func apply(
        plan: ShortcutTabPromotionPlan,
        split: ShortcutTabPromotionSplitTransition
    ) -> [BrowserWindowState] {
        plan.selectedWindowStates.compactMap { state in
            let before = ShortcutPromotionWindowSnapshot(state)
            apply(plan: plan, split: split, to: state)
            return before == ShortcutPromotionWindowSnapshot(state) ? nil : state
        }
    }

    private func apply(
        plan: ShortcutTabPromotionPlan,
        split: ShortcutTabPromotionSplitTransition,
        to state: BrowserWindowState
    ) {
        switch split {
        case .none:
            if state.id == plan.chosenEntry?.windowId {
                select(plan.tab, in: state)
            }
        case .replaced(let groupID, let memberID):
            guard state.splitSelection?.groupID == groupID else { return }
            select(plan.tab, in: state)
            state.splitSelection = WindowSplitSelection(
                groupID: groupID,
                activeMemberID: memberID
            )
        case .removed(let groupID, let remainingGroup):
            guard state.splitSelection?.groupID == groupID else { return }
            applyRemovedGroup(
                plan: plan,
                groupID: groupID,
                remainingGroup: remainingGroup,
                to: state
            )
        }
    }

    private func applyRemovedGroup(
        plan: ShortcutTabPromotionPlan,
        groupID: UUID,
        remainingGroup: SumiDomain.SplitGroup?,
        to state: BrowserWindowState
    ) {
        if let memberID = remainingGroup?.memberIDs.first,
           let tab = resolvedTab(for: memberID, in: state) {
            select(tab, in: state)
            state.splitSelection = WindowSplitSelection(
                groupID: groupID,
                activeMemberID: memberID
            )
            return
        }
        state.splitSelection = nil
        if state.id == plan.chosenEntry?.windowId { select(plan.tab, in: state) }
    }

    private func select(_ tab: Tab, in state: BrowserWindowState) {
        _ = WindowTabSelectionStateApplicator.apply(
            tab,
            to: state,
            updateSpaceFromTab: true,
            rememberSelection: true
        )
    }

    private func resolvedTab(
        for memberID: SplitMemberID,
        in state: BrowserWindowState
    ) -> Tab? {
        switch memberID {
        case .regularTab(let tabID): return membership.tab(for: tabID)
        case .shortcutPin(let pinID):
            return registry.tab(for: pinID, in: state.id)
        }
    }
}

@MainActor
private struct ShortcutPromotionWindowSnapshot: Equatable {
    let currentTabID: UUID?
    let currentSpaceID: UUID?
    let currentShortcutPinID: UUID?
    let currentShortcutPinRole: ShortcutPinRole?
    let splitSelection: WindowSplitSelection?

    init(_ state: BrowserWindowState) {
        currentTabID = state.currentTabId
        currentSpaceID = state.currentSpaceId
        currentShortcutPinID = state.currentShortcutPinId
        currentShortcutPinRole = state.currentShortcutPinRole
        splitSelection = state.splitSelection
    }
}
