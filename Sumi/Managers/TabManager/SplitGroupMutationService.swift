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
    private let withStructuralTransaction: (@MainActor () -> Void) -> Void
    private let announceChange: () -> Void
    private let requestStructuralPublish: () -> Void
    private let markStructurallyDirty: () -> Void
    private let schedulePersistence: () -> Void

    init(
        store: SplitGroupStore,
        withStructuralTransaction: @escaping (@MainActor () -> Void) -> Void,
        announceChange: @escaping () -> Void,
        requestStructuralPublish: @escaping () -> Void,
        markStructurallyDirty: @escaping () -> Void,
        schedulePersistence: @escaping () -> Void
    ) {
        self.store = store
        self.withStructuralTransaction = withStructuralTransaction
        self.announceChange = announceChange
        self.requestStructuralPublish = requestStructuralPublish
        self.markStructurallyDirty = markStructurallyDirty
        self.schedulePersistence = schedulePersistence
    }

    @discardableResult
    func insert(
        _ group: SumiDomain.SplitGroup,
        persist: Bool = true,
        alongside: @escaping @MainActor () -> Void = {}
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
        persist: Bool = true,
        alongside: @escaping @MainActor () -> Void = {}
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
        persist: Bool = true,
        alongside: @escaping @MainActor () -> Void = {}
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
        persist: Bool = true,
        alongside: @escaping @MainActor () -> Void = {}
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

    /// Startup installation has no competing runtime mutation, but still
    /// rejects corrupt or overlapping input instead of silently changing it.
    @discardableResult
    func installRestoredGroups(_ groups: [SumiDomain.SplitGroup]) -> Bool {
        guard SumiDomain.SplitGroup.sanitized(groups) == groups else { return false }
        guard store.groups != groups else { return true }
        withStructuralTransaction {
            announceChange()
            store.replaceAll(with: groups)
            requestStructuralPublish()
        }
        return true
    }

    private func commit(
        expected: [SumiDomain.SplitGroup],
        replacement: [SumiDomain.SplitGroup],
        persist: Bool,
        alongside: @escaping @MainActor () -> Void
    ) -> Bool {
        guard store.groups == expected,
              replacement != expected,
              SumiDomain.SplitGroup.sanitized(replacement) == replacement
        else {
            return false
        }

        withStructuralTransaction {
            // MainActor serialization plus the exact snapshot guard above make
            // this mutation indivisible with respect to other split commits.
            announceChange()
            store.replaceAll(with: replacement)
            alongside()
            markStructurallyDirty()
            requestStructuralPublish()
        }
        if persist {
            schedulePersistence()
        }
        return true
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
        withStructuralTransaction {
            guard sideEffect() else { return }
            announceChange()
            store.replaceAll(with: replacement)
            markStructurallyDirty()
            requestStructuralPublish()
            committed = true
        }
        guard committed else { return false }
        if persist {
            schedulePersistence()
        }
        return true
    }
}

extension SplitGroupMutationService {
    convenience init(tabManager: TabManager) {
        self.init(
            store: tabManager.splitGroupStore,
            withStructuralTransaction: { [weak tabManager] operation in
                guard let tabManager else {
                    operation()
                    return
                }
                tabManager.structuralLookupCoordinator.withTransaction {
                    operation()
                }
            },
            announceChange: { [weak tabManager] in
                tabManager?.objectWillChange.send()
            },
            requestStructuralPublish: { [weak tabManager] in
                tabManager?.structuralLookupCoordinator.requestPublish()
            },
            markStructurallyDirty: { [weak tabManager] in
                tabManager?.structuralPersistence
                    .markSplitGroupsStructurallyDirty()
            },
            schedulePersistence: { [weak tabManager] in
                tabManager?.structuralPersistence
                    .scheduleStructuralPersistence()
            }
        )
    }
}
