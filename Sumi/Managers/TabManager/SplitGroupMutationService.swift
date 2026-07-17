import Foundation
import SumiDomain

/// Commits durable split-group changes against exact snapshots.
///
/// All fallible validation happens before the structural transaction. A
/// successful commit publishes once and schedules at most one persistence
/// write; stale callers leave the store untouched.
@MainActor
final class SplitGroupMutationService {
    private let store: SplitGroupStore
    private let publication: TabStructuralMutationPublisher

    init(
        store: SplitGroupStore,
        publication: TabStructuralMutationPublisher
    ) {
        self.store = store
        self.publication = publication
    }

    @discardableResult
    func insert(
        _ group: SumiDomain.SplitGroup,
        persist: Bool = true
    ) -> Bool {
        insertResolved(group, persist: persist, alongside: nil)
    }

    @discardableResult
    func insert(
        _ group: SumiDomain.SplitGroup,
        persist: Bool = true,
        alongside: @escaping @MainActor () -> Void
    ) -> Bool {
        insertResolved(group, persist: persist, alongside: alongside)
    }

    private func insertResolved(
        _ group: SumiDomain.SplitGroup,
        persist: Bool,
        alongside: (@MainActor () -> Void)?
    ) -> Bool {
        guard store.group(id: group.id) == nil,
              group.memberIDs.allSatisfy({ store.groupID(containing: $0) == nil })
        else {
            return false
        }
        return commit(
            expected: store.groups,
            replacement: store.groups + [group],
            persist: persist,
            alongside: alongside
        )
    }

    @discardableResult
    func replace(
        _ expectedGroup: SumiDomain.SplitGroup,
        with replacement: SumiDomain.SplitGroup,
        persist: Bool = true
    ) -> Bool {
        replaceResolved(
            expectedGroup,
            with: replacement,
            persist: persist,
            alongside: nil
        )
    }

    @discardableResult
    func replace(
        _ expectedGroup: SumiDomain.SplitGroup,
        with replacement: SumiDomain.SplitGroup,
        persist: Bool = true,
        alongside: @escaping @MainActor () -> Void
    ) -> Bool {
        replaceResolved(
            expectedGroup,
            with: replacement,
            persist: persist,
            alongside: alongside
        )
    }

    private func replaceResolved(
        _ expectedGroup: SumiDomain.SplitGroup,
        with replacement: SumiDomain.SplitGroup,
        persist: Bool,
        alongside: (@MainActor () -> Void)?
    ) -> Bool {
        guard replacement.id == expectedGroup.id,
              let index = store.index(of: expectedGroup.id),
              store.groups[index] == expectedGroup
        else {
            return false
        }

        let otherMemberIDs = Set(
            store.groups.lazy
                .filter { $0.id != expectedGroup.id }
                .flatMap(\.memberIDs)
        )
        guard Set(replacement.memberIDs).isDisjoint(with: otherMemberIDs) else {
            return false
        }

        var updated = store.groups
        updated[index] = replacement
        return commit(
            expected: store.groups,
            replacement: updated,
            persist: persist,
            alongside: alongside
        )
    }

    @discardableResult
    func remove(
        _ expectedGroup: SumiDomain.SplitGroup,
        persist: Bool = true
    ) -> Bool {
        removeResolved(expectedGroup, persist: persist, alongside: nil)
    }

    @discardableResult
    func remove(
        _ expectedGroup: SumiDomain.SplitGroup,
        persist: Bool = true,
        alongside: @escaping @MainActor () -> Void
    ) -> Bool {
        removeResolved(
            expectedGroup,
            persist: persist,
            alongside: alongside
        )
    }

    private func removeResolved(
        _ expectedGroup: SumiDomain.SplitGroup,
        persist: Bool,
        alongside: (@MainActor () -> Void)?
    ) -> Bool {
        guard let index = store.index(of: expectedGroup.id),
              store.groups[index] == expectedGroup
        else {
            return false
        }
        var updated = store.groups
        updated.remove(at: index)
        return commit(
            expected: store.groups,
            replacement: updated,
            persist: persist,
            alongside: alongside
        )
    }

    /// Compound mutation for a fallible, preflighted catalog side effect such
    /// as restoring shortcut launcher placement. The side effect runs first
    /// inside the same structural batch; the split store is changed only when
    /// it succeeds, and persistence is requested once by this service.
    @discardableResult
    func removeAtomically(
        _ expectedGroup: SumiDomain.SplitGroup,
        persist: Bool = true,
        applying sideEffect: @escaping @MainActor () -> Bool
    ) -> Bool {
        guard let index = store.index(of: expectedGroup.id),
              store.groups[index] == expectedGroup else {
            return false
        }
        var replacement = store.groups
        replacement.remove(at: index)
        return commitAtomically(
            expected: store.groups,
            replacement: replacement,
            persist: persist,
            applying: sideEffect
        )
    }

    @discardableResult
    func replaceAtomically(
        _ expectedGroup: SumiDomain.SplitGroup,
        with replacement: SumiDomain.SplitGroup,
        persist: Bool = true,
        applying sideEffect: @escaping @MainActor () -> Bool
    ) -> Bool {
        guard replacement.id == expectedGroup.id,
              let index = store.index(of: expectedGroup.id),
              store.groups[index] == expectedGroup else {
            return false
        }
        let otherMemberIDs = Set(
            store.groups.lazy
                .filter { $0.id != expectedGroup.id }
                .flatMap(\.memberIDs)
        )
        guard Set(replacement.memberIDs).isDisjoint(with: otherMemberIDs) else {
            return false
        }
        var groups = store.groups
        groups[index] = replacement
        return commitAtomically(
            expected: store.groups,
            replacement: groups,
            persist: persist,
            applying: sideEffect
        )
    }

    /// Exact batch commit for operations that legitimately affect multiple
    /// groups, such as deleting a Space or moving a member between groups.
    @discardableResult
    func replaceAll(
        expected: [SumiDomain.SplitGroup],
        with replacement: [SumiDomain.SplitGroup],
        persist: Bool = true
    ) -> Bool {
        replaceAllResolved(
            expected: expected,
            with: replacement,
            persist: persist,
            alongside: nil
        )
    }

    @discardableResult
    func replaceAll(
        expected: [SumiDomain.SplitGroup],
        with replacement: [SumiDomain.SplitGroup],
        persist: Bool = true,
        alongside: @escaping @MainActor () -> Void
    ) -> Bool {
        replaceAllResolved(
            expected: expected,
            with: replacement,
            persist: persist,
            alongside: alongside
        )
    }

    private func replaceAllResolved(
        expected: [SumiDomain.SplitGroup],
        with replacement: [SumiDomain.SplitGroup],
        persist: Bool,
        alongside: (@MainActor () -> Void)?
    ) -> Bool {
        guard SumiDomain.SplitGroup.sanitized(replacement) == replacement else {
            return false
        }
        return commit(
            expected: expected,
            replacement: replacement,
            persist: persist,
            alongside: alongside
        )
    }

    @discardableResult
    func replaceAllAtomically(
        expected: [SumiDomain.SplitGroup],
        with replacement: [SumiDomain.SplitGroup],
        persist: Bool = true,
        applying sideEffect: @escaping @MainActor () -> Bool
    ) -> Bool {
        guard SumiDomain.SplitGroup.sanitized(replacement) == replacement else {
            return false
        }
        return commitAtomically(
            expected: expected,
            replacement: replacement,
            persist: persist,
            applying: sideEffect
        )
    }

    /// Prepares an exact multi-group replacement whose terminal publication
    /// cannot reject. Callers compose this receipt with other prepared model
    /// receipts and publish only after every participant remains current.
    func prepareReplaceAll(
        expected: [SumiDomain.SplitGroup],
        with replacement: [SumiDomain.SplitGroup],
        persist: Bool = true
    ) -> SplitGroupReplacementReceipt? {
        guard store.groups == expected,
              replacement != expected,
              SumiDomain.SplitGroup.sanitized(replacement) == replacement
        else { return nil }
        return SplitGroupReplacementReceipt(
            store: store,
            publisher: self,
            plan: SplitGroupReplacementPlan(
                expected: expected,
                replacement: replacement,
                persist: persist
            )
        )
    }

    /// Startup installation has no competing runtime mutation, but still
    /// rejects corrupt or overlapping input instead of silently changing it.
    @discardableResult
    func installRestoredGroups(_ groups: [SumiDomain.SplitGroup]) -> Bool {
        guard SumiDomain.SplitGroup.sanitized(groups) == groups else { return false }
        guard store.groups != groups else { return true }
        publication.withTransaction {
            announceBeforeStructuralPublication()
            store.replaceAll(with: groups)
            publication.publishSplitGroupChange(scope: scope(for: groups))
        }
        return true
    }

    private func commit(
        expected: [SumiDomain.SplitGroup],
        replacement: [SumiDomain.SplitGroup],
        persist: Bool,
        alongside: (@MainActor () -> Void)?
    ) -> Bool {
        guard store.groups == expected,
              replacement != expected,
              SumiDomain.SplitGroup.sanitized(replacement) == replacement
        else {
            return false
        }

        publication.withTransaction {
            // MainActor serialization plus the exact snapshot guard above make
            // this mutation indivisible with respect to other split commits.
            announceBeforeStructuralPublication()
            store.replaceAll(with: replacement)
            alongside?()
            publication.publishSplitGroupChange(
                scope: scope(for: expected + replacement)
            )
        }
        if persist {
            publication.schedulePersistence()
        }
        return true
    }

    func publishPreparedReplacement(_ plan: SplitGroupReplacementPlan) {
        publication.withTransaction {
            announceBeforeStructuralPublication()
            publication.publishSplitGroupChange(
                scope: scope(for: plan.expected + plan.replacement)
            )
        }
        if plan.persist {
            publication.schedulePersistence()
        }
    }

    private func commitAtomically(
        expected: [SumiDomain.SplitGroup],
        replacement: [SumiDomain.SplitGroup],
        persist: Bool,
        applying sideEffect: @escaping @MainActor () -> Bool
    ) -> Bool {
        guard store.groups == expected,
              replacement != expected,
              SumiDomain.SplitGroup.sanitized(replacement) == replacement else {
            return false
        }

        var committed = false
        publication.withTransaction {
            store.replaceAll(with: replacement)
            guard sideEffect() else {
                precondition(
                    store.groups == replacement,
                    "Rejected split aggregate published a reentrant topology"
                )
                store.replaceAll(with: expected)
                return
            }
            announceBeforeStructuralPublication()
            publication.publishSplitGroupChange(
                scope: scope(for: expected + replacement)
            )
            committed = true
        }
        guard committed else { return false }
        if persist {
            publication.schedulePersistence()
        }
        return true
    }

    private func scope(
        for groups: [SumiDomain.SplitGroup]
    ) -> TabStructureChangeScope {
        guard groups.allSatisfy({ $0.container.spaceId != nil }) else {
            return .all
        }
        return .spaces(Set(groups.compactMap(\.container.spaceId)))
    }

    private func announceBeforeStructuralPublication() {
        publication.announceStateChange()
    }
}
