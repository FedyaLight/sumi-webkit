import Foundation
import SumiDomain

/// Canonical in-memory store and index for durable split groups.
///
/// The index is keyed by typed durable member identity. Window-local shortcut
/// tabs are intentionally impossible to query through this store.
@MainActor
final class SplitGroupStore {
    private(set) var groups: [SumiDomain.SplitGroup] = []

    private var groupsByID: [UUID: SumiDomain.SplitGroup] = [:]
    private var groupIndexByID: [UUID: Int] = [:]
    private var groupIDByMemberID: [SplitMemberID: UUID] = [:]

    var groupMap: [UUID: SumiDomain.SplitGroup] {
        groupsByID
    }

    func replaceAll(with groups: [SumiDomain.SplitGroup]) {
        let sanitized = SumiDomain.SplitGroup.sanitized(groups)
        self.groups = sanitized
        rebuildIndex()
    }

    func removeAll() {
        groups.removeAll(keepingCapacity: false)
        groupsByID.removeAll(keepingCapacity: false)
        groupIndexByID.removeAll(keepingCapacity: false)
        groupIDByMemberID.removeAll(keepingCapacity: false)
    }

    func group(id: UUID) -> SumiDomain.SplitGroup? {
        groupsByID[id]
    }

    func group(containing memberID: SplitMemberID) -> SumiDomain.SplitGroup? {
        groupID(containing: memberID).flatMap { groupsByID[$0] }
    }

    func groupID(containing memberID: SplitMemberID) -> UUID? {
        groupIDByMemberID[memberID]
    }

    func index(of groupID: UUID) -> Int? {
        groupIndexByID[groupID]
    }

    /// Exact topology-preserving update used by live divider movement. Member
    /// and group indexes remain valid, so rebuilding them and publishing a
    /// topology event would be unnecessary work.
    @discardableResult
    func replaceLayout(
        _ expected: SumiDomain.SplitGroup,
        with replacement: SumiDomain.SplitGroup
    ) -> Bool {
        guard replacement.id == expected.id,
              replacement.container == expected.container,
              replacement.members == expected.members,
              let index = groupIndexByID[expected.id],
              groups[index] == expected,
              replacement != expected else {
            return false
        }
        groups[index] = replacement
        groupsByID[replacement.id] = replacement
        return true
    }

    private func rebuildIndex() {
        groupsByID.removeAll(keepingCapacity: true)
        groupIndexByID.removeAll(keepingCapacity: true)
        groupIDByMemberID.removeAll(keepingCapacity: true)

        for (index, group) in groups.enumerated() {
            groupsByID[group.id] = group
            groupIndexByID[group.id] = index
            for memberID in group.memberIDs {
                groupIDByMemberID[memberID] = group.id
            }
        }
    }
}
