import Foundation
import SumiDomain

struct ShortcutPinRegularSplitTransition {
    enum Mutation {
        case replace(
            expected: SumiDomain.SplitGroup,
            replacement: SumiDomain.SplitGroup
        )
        case remove(expected: SumiDomain.SplitGroup)
    }

    let mutation: Mutation
    let windows: ShortcutTabPromotionSplitTransition
}

/// Pure durable transition for a shortcut pin promoted to a regular tab.
struct ShortcutPinRegularSplitTransitionPlanner {
    func transition(
        group: SumiDomain.SplitGroup,
        pinID: UUID,
        promotedTabID: UUID,
        targetSpaceID: UUID
    ) -> ShortcutPinRegularSplitTransition? {
        let pinMemberID = SplitMemberID.shortcutPin(pinID)
        if shouldRemoveFromGroup(group, targetSpaceID: targetSpaceID) {
            let remaining = group.removingMember(pinMemberID)
            return ShortcutPinRegularSplitTransition(
                mutation: remaining.map {
                    .replace(expected: group, replacement: $0)
                } ?? .remove(expected: group),
                windows: .removed(
                    groupID: group.id,
                    remainingGroup: remaining
                )
            )
        }

        let memberID = SplitMemberID.regularTab(promotedTabID)
        guard let replacement = group.replacingMember(
            pinMemberID,
            with: .regularTab(promotedTabID)
        ) else { return nil }
        return ShortcutPinRegularSplitTransition(
            mutation: .replace(expected: group, replacement: replacement),
            windows: .replaced(groupID: group.id, memberID: memberID)
        )
    }

    private func shouldRemoveFromGroup(
        _ group: SumiDomain.SplitGroup,
        targetSpaceID: UUID
    ) -> Bool {
        switch group.container {
        case .regularTabs(let spaceID):
            return spaceID != nil && spaceID != targetSpaceID
        case .shortcutSidebar:
            return true
        }
    }
}
