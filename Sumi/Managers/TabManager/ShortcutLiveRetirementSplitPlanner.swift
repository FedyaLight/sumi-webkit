import SumiDomain

@MainActor
final class ShortcutLiveRetirementSplitPlanner {
    struct Plan {
        let source: [SumiDomain.SplitGroup]
        let replacement: [SumiDomain.SplitGroup]
        let receipt: SplitGroupReplacementReceipt?
    }

    private let store: SplitGroupStore
    private let mutations: SplitGroupMutationService

    init(store: SplitGroupStore, mutations: SplitGroupMutationService) {
        self.store = store
        self.mutations = mutations
    }

    func prepare(deleting pinIDs: Set<UUID>) -> Plan? {
        let source = store.groups
        let replacement = ShortcutLiveRetirementSplitProjection
            .removingDeletedPins(pinIDs, from: source)
        if replacement == source {
            return Plan(source: source, replacement: replacement, receipt: nil)
        }
        guard let receipt = mutations.prepareReplaceAll(
            expected: source, with: replacement
        ) else { return nil }
        return Plan(source: source, replacement: replacement, receipt: receipt)
    }

    func selectionExcludes(
        _ pinIDs: Set<UUID>,
        state: BrowserWindowShortcutMutationState
    ) -> Bool {
        guard let groupID = state.splitSelection?.groupID,
              let group = store.group(id: groupID) else { return true }
        return group.memberIDs.allSatisfy { member in
            guard case .shortcutPin(let pinID) = member else { return true }
            return pinIDs.contains(pinID) == false
        }
    }
}
