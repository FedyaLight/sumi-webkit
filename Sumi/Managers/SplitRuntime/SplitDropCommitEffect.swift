import Foundation
import SumiDomain

/// Typed post-commit input for window reconciliation and launcher restoration.
/// It carries durable identities only; runtime tabs remain window-local.
struct SplitDropCommitEffect {
    let callerWindowID: UUID
    let sourceGroupID: UUID?
    let targetGroupID: UUID
    let movingMemberID: SplitMemberID
    let previousGroups: [SumiDomain.SplitGroup]
    let affectedGroupIDs: Set<UUID>
    let preferredActiveMemberID: SplitMemberID
    let releasedMembers: [SplitMember]

    static func resolving(
        callerWindowID: UUID,
        sourceGroup: SumiDomain.SplitGroup?,
        targetGroup: SumiDomain.SplitGroup?,
        committedTargetGroupID: UUID,
        movingMemberID: SplitMemberID,
        activatedMemberID: SplitMemberID,
        replacementGroups: [SumiDomain.SplitGroup]
    ) -> Self {
        let previousGroups = [sourceGroup, targetGroup]
            .compactMap { $0 }
            .reduce(into: [SumiDomain.SplitGroup]()) { result, group in
                if !result.contains(where: { $0.id == group.id }) {
                    result.append(group)
                }
            }
        let previousMembers = previousGroups.reduce(into: [SplitMember]()) {
            result, group in
            for member in group.members
                where !result.contains(where: {
                    $0.memberID == member.memberID
                }) {
                result.append(member)
            }
        }
        let remainingIDs = Set(replacementGroups.flatMap(\.memberIDs))
        let released = previousMembers.filter {
            $0.memberID != movingMemberID
                && !remainingIDs.contains($0.memberID)
        }
        return Self(
            callerWindowID: callerWindowID,
            sourceGroupID: sourceGroup?.id,
            targetGroupID: committedTargetGroupID,
            movingMemberID: movingMemberID,
            previousGroups: previousGroups,
            affectedGroupIDs: Set(
                previousGroups.map(\.id) + [committedTargetGroupID]
            ),
            preferredActiveMemberID: activatedMemberID,
            releasedMembers: released
        )
    }
}
