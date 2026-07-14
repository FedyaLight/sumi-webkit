import Foundation

@MainActor
struct PlannedSpaceContentRetirement {
    let spaceId: UUID
    let tabs: [Tab]
    let runtime: RuntimePortRegistry
    let runtimeTeardown: PreparedTabRuntimeTeardown
}

@MainActor
struct PreparedSpaceContentRetirement {
    let footprint: SpaceRemovalFootprint
    let runtime: RuntimePortRegistry
    let runtimeTeardown: PreparedTabRuntimeTeardown
}

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
        liveShortcutTabs: LiveShortcutTabRegistry,
        runtimeTeardown: TabRuntimeTeardownService
    ) {
        transaction = SpaceContentRetirementTransaction(
            state: state,
            structuralMutations: structuralMutations,
            splitGroups: splitGroups,
            liveShortcutTabs: liveShortcutTabs
        )
        self.runtimeTeardown = runtimeTeardown
    }

    func plan(
        spaceId: UUID,
        using runtime: RuntimePortRegistry
    ) -> PlannedSpaceContentRetirement? {
        let inventory = transaction.inventory(spaceId: spaceId)
        guard let teardown = runtimeTeardown.preparation.prepare(
            inventory.all,
            using: runtime
        ) else { return nil }
        return PlannedSpaceContentRetirement(
            spaceId: spaceId,
            tabs: inventory.all,
            runtime: runtime,
            runtimeTeardown: teardown
        )
    }

    func commit(
        _ plan: PlannedSpaceContentRetirement
    ) -> PreparedSpaceContentRetirement? {
        guard let footprint = transaction.commit(plan) else { return nil }
        return PreparedSpaceContentRetirement(
            footprint: footprint,
            runtime: plan.runtime,
            runtimeTeardown: plan.runtimeTeardown
        )
    }

    func finish(_ prepared: PreparedSpaceContentRetirement) {
        runtimeTeardown.finish(prepared.runtimeTeardown)
    }
}
