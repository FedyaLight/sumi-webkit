import Foundation
import SumiDomain

/// Exact durable facts captured before a regular tab becomes a shortcut.
///
/// The plan deliberately contains no mutation callbacks. Its full split-store
/// snapshot is both the stale-write token and the input for a typed replacement
/// value computed before commit.
struct RegularTabShortcutStructurePlan {
    let sourceTabID: UUID
    let expectedSplitGroups: [SumiDomain.SplitGroup]
    let sourceSplitGroup: SumiDomain.SplitGroup?
    let structuralRevision: UInt64

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
