import Foundation
import SumiDomain

@MainActor
final class TabStartupSplitGroupResetTransaction {
    private let store: SplitGroupStore
    private let mutations: SplitGroupMutationService

    init(
        store: SplitGroupStore,
        mutations: SplitGroupMutationService
    ) {
        self.store = store
        self.mutations = mutations
    }

    func removeRegularTabs(_ tabIDs: Set<UUID>) {
        guard tabIDs.isEmpty == false else { return }
        let currentGroups = store.groups
        let updatedGroups = currentGroups.compactMap {
            group -> SumiDomain.SplitGroup? in
            let removedMemberIDs = group.memberIDs.filter {
                guard case .regularTab(let tabID) = $0 else { return false }
                return tabIDs.contains(tabID)
            }
            return removedMemberIDs.reduce(Optional(group)) {
                $0?.removingMember($1)
            }
        }
        guard updatedGroups != currentGroups else { return }
        precondition(
            mutations.replaceAll(
                expected: currentGroups,
                with: updatedGroups,
                persist: false
            ),
            "Startup reset lost its exact split-group snapshot"
        )
    }
}
