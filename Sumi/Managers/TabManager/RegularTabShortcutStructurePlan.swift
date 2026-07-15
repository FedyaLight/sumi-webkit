import Foundation
import SumiDomain

/// Exact durable and profile facts captured before shortcut conversion.
struct RegularTabShortcutStructurePlan {
    let sourceTabID: UUID
    let expectedSplitGroups: [SumiDomain.SplitGroup]
    let sourceSplitGroup: SumiDomain.SplitGroup?
    let structuralRevision: UInt64
    let profileRevision: UInt64

    var sourceMemberID: SplitMemberID {
        .regularTab(sourceTabID)
    }

    var sourceSplitGroupID: UUID? {
        sourceSplitGroup?.id
    }

    func replacingSource(
        with replacementMember: SplitMember
    ) -> [SumiDomain.SplitGroup]? {
        guard replacementMember.memberID != sourceMemberID else {
            return nil
        }
        guard let sourceSplitGroup else {
            return expectedSplitGroups
        }
        guard let sourceIndex = expectedSplitGroups.firstIndex(
            where: { $0 == sourceSplitGroup }
        ), let replacementGroup = sourceSplitGroup.replacingMember(
            sourceMemberID,
            with: replacementMember
        ) else {
            return nil
        }

        var replacement = expectedSplitGroups
        replacement[sourceIndex] = replacementGroup
        return replacement
    }
}
