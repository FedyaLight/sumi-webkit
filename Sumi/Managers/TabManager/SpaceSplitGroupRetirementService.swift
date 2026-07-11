import Foundation
import SumiDomain

/// Removes one Space's durable members with one exact-snapshot commit.
@MainActor
final class SpaceSplitGroupRetirementService {
    private let store: SplitGroupStore
    private let mutations: SplitGroupMutationService

    init(
        store: SplitGroupStore,
        mutations: SplitGroupMutationService
    ) {
        self.store = store
        self.mutations = mutations
    }

    func retireGroups(
        in spaceID: UUID,
        regularTabIDs: Set<UUID>,
        shortcutPinIDs: Set<UUID>
    ) -> Set<UUID> {
        let currentGroups = store.groups
        var affectedGroupIDs = Set<UUID>()
        let remainingGroups = currentGroups.compactMap {
            group -> SumiDomain.SplitGroup? in
            if group.container.spaceId == spaceID {
                affectedGroupIDs.insert(group.id)
                return nil
            }
            let removedMembers = group.memberIDs.filter { memberID in
                switch memberID {
                case .regularTab(let tabID):
                    return regularTabIDs.contains(tabID)
                case .shortcutPin(let pinID):
                    return shortcutPinIDs.contains(pinID)
                }
            }
            guard !removedMembers.isEmpty else { return group }
            affectedGroupIDs.insert(group.id)
            return removedMembers.reduce(Optional(group)) {
                $0?.removingMember($1)
            }
        }
        guard remainingGroups != currentGroups else {
            return affectedGroupIDs
        }
        precondition(
            mutations.replaceAll(
                expected: currentGroups,
                with: remainingGroups,
                persist: false
            ),
            "Space retirement lost its exact split-group snapshot"
        )
        return affectedGroupIDs
    }
}
