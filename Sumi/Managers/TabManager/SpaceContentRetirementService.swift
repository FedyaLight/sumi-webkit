import Foundation

/// Retires every collection and live runtime scoped to one Space. Removing the
/// Space catalog entry and repairing window state remain the caller's job.
@MainActor
final class SpaceContentRetirementService {
    private let transaction: SpaceContentRetirementTransaction
    private let runtimeTeardown: TabRuntimeTeardownService

    init(
        state: TabStateStore,
        structuralMutations: TabStructuralCollectionMutationOwner,
        splitGroups: SpaceSplitGroupRetirementService,
        liveShortcutRetirement: LiveShortcutTabBatchRetirement,
        runtimeTeardown: TabRuntimeTeardownService
    ) {
        transaction = SpaceContentRetirementTransaction(
            state: state,
            structuralMutations: structuralMutations,
            splitGroups: splitGroups,
            liveShortcutRetirement: liveShortcutRetirement
        )
        self.runtimeTeardown = runtimeTeardown
    }

    func plan(
        spaceIds: [UUID],
        using runtime: TabRuntimePortLease
    ) -> [PlannedSpaceContentRetirement]? {
        guard let runtimePorts = runtime.registry else { return nil }
        var plans: [PlannedSpaceContentRetirement] = []
        for spaceId in spaceIds {
            let inventory = transaction.inventory(spaceId: spaceId)
            guard let teardown = runtimeTeardown.preparation.prepare(
                inventory.all,
                using: runtimePorts
            ) else {
                return nil
            }
            plans.append(
                PlannedSpaceContentRetirement(
                    spaceId: spaceId,
                    tabs: inventory.all,
                    runtime: runtime,
                    runtimeTeardown: teardown
                )
            )
        }
        return plans
    }

    func commit(
        _ plans: [PlannedSpaceContentRetirement]
    ) -> [PreparedSpaceContentRetirement]? {
        var retirements: [PreparedSpaceContentRetirement] = []
        for plan in plans {
            guard let footprint = transaction.commit(plan) else {
                precondition(
                    retirements.isEmpty,
                    "Space retirement batch diverged after a partial commit"
                )
                return nil
            }
            retirements.append(
                PreparedSpaceContentRetirement(
                    footprint: footprint,
                    runtime: plan.runtime,
                    runtimeTeardown: plan.runtimeTeardown
                )
            )
        }
        return retirements
    }

    func finish(_ prepared: PreparedSpaceContentRetirement) {
        runtimeTeardown.finish(prepared.runtimeTeardown)
    }
}
