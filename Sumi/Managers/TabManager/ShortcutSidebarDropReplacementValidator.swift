import Foundation
import SumiDomain

/// Accepts only the structural delta a regular-to-shortcut sidebar drop may
/// make: remove the regular source, change the exact target layout, preserve
/// every unrelated group and insert the prepared shortcut member once.
struct ShortcutSidebarDropReplacementValidator {
    func accepts(
        _ replacement: [SumiDomain.SplitGroup],
        for prepared: PreparedRegularTabShortcutSidebarDrop
    ) -> Bool {
        let expected = prepared.expectedSplitGroups
        let sourceID = SplitMemberID.regularTab(
            prepared.conversion.sourceTab.id
        )
        guard replacement != expected,
              SumiDomain.SplitGroup.sanitized(replacement) == replacement,
              replacement.allSatisfy({ !$0.contains(sourceID) }),
              expected.allSatisfy({ !$0.contains(prepared.member.memberID) }),
              let target = replacement.first(where: {
                  $0.id == prepared.targetGroup.id
              }),
              target.container == prepared.targetGroup.container,
              target.container.isShortcutSidebar,
              target.member(for: prepared.member.memberID) == prepared.member
        else {
            return false
        }
        if prepared.targetGroupWasExisting {
            guard expected.contains(prepared.targetGroup),
                  acceptsExistingTargetMembers(
                      target,
                      prepared: prepared
                  ) else { return false }
        } else {
            guard !expected.contains(where: {
                $0.id == prepared.targetGroup.id
            }), target == prepared.targetGroup,
                  expected.allSatisfy({ group in
                      prepared.targetGroup.memberIDs.allSatisfy {
                          !group.contains($0)
                      }
                  }) else { return false }
        }

        let sourceGroup = prepared.conversion.structure.sourceSplitGroup
        let mutableIDs = Set(
            [
                sourceGroup?.id,
                prepared.targetGroupWasExisting
                    ? prepared.targetGroup.id
                    : nil,
            ].compactMap { $0 }
        )
        for group in expected where !mutableIDs.contains(group.id) {
            guard replacement.first(where: { $0.id == group.id }) == group else {
                return false
            }
        }
        if let sourceGroup {
            guard replacement.first(where: { $0.id == sourceGroup.id })
                == sourceGroup.removingMember(sourceID) else {
                return false
            }
        }
        return replacementGroupIDsAreExact(
            replacement,
            expected: expected,
            sourceGroup: sourceGroup,
            sourceID: sourceID,
            createdTargetID: prepared.targetGroupWasExisting
                ? nil
                : prepared.targetGroup.id
        )
    }

    private func acceptsExistingTargetMembers(
        _ replacement: SumiDomain.SplitGroup,
        prepared: PreparedRegularTabShortcutSidebarDrop
    ) -> Bool {
        let previous = Set(prepared.targetGroup.memberIDs)
        let current = Set(replacement.memberIDs)
        guard current.subtracting(previous) == Set([prepared.member.memberID]),
              previous.subtracting(current).count <= 1 else {
            return false
        }
        return previous.intersection(current).allSatisfy {
            replacement.member(for: $0) == prepared.targetGroup.member(for: $0)
        }
    }

    private func replacementGroupIDsAreExact(
        _ replacement: [SumiDomain.SplitGroup],
        expected: [SumiDomain.SplitGroup],
        sourceGroup: SumiDomain.SplitGroup?,
        sourceID: SplitMemberID,
        createdTargetID: UUID?
    ) -> Bool {
        let expectedIDs = Set(expected.map(\.id))
        let replacementIDs = Set(replacement.map(\.id))
        let targetIDs = createdTargetID.map { Set([$0]) } ?? []
        guard let sourceGroup,
              sourceGroup.removingMember(sourceID) == nil else {
            return replacementIDs == expectedIDs.union(targetIDs)
        }
        return replacementIDs
            == expectedIDs.subtracting([sourceGroup.id])
                .union(targetIDs)
    }
}
