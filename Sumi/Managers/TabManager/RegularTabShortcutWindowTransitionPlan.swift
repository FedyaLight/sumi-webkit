import Foundation
import SumiDomain

struct RegularTabShortcutWindowTransitionPlan {
    let sourceGroupID: UUID?
    let targetGroupID: UUID?
    let replacementMemberID: SplitMemberID
    let activatesTargetForSelectedTab: Bool

    static func replacingSource(
        groupID: UUID?,
        memberID: SplitMemberID
    ) -> Self {
        Self(
            sourceGroupID: groupID,
            targetGroupID: groupID,
            replacementMemberID: memberID,
            activatesTargetForSelectedTab: false
        )
    }

    static func movingToShortcutSidebar(
        sourceGroupID: UUID?,
        targetGroupID: UUID,
        memberID: SplitMemberID
    ) -> Self {
        Self(
            sourceGroupID: sourceGroupID,
            targetGroupID: targetGroupID,
            replacementMemberID: memberID,
            activatesTargetForSelectedTab: true
        )
    }

    func selectedTargetGroupID(
        isSelected: Bool,
        selectedSourceGroupID: UUID?
    ) -> UUID? {
        guard selectedSourceGroupID != nil
                || (isSelected && activatesTargetForSelectedTab) else {
            return nil
        }
        return targetGroupID
    }
}
