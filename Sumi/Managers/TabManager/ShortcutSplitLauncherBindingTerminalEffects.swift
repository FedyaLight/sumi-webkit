import Foundation

/// Owns the profile half of a staged launcher binding transition. Model
/// preparation happens before publication; asynchronous profile execution is
/// terminal and cannot participate in rollback.
@MainActor
final class ShortcutSplitLauncherProfileSettlement {
    private let profiles: TabProfileTransitionService

    init(profiles: TabProfileTransitionService) {
        self.profiles = profiles
    }

    func prepare(_ plan: ShortcutSplitLauncherBindingPlan) {
        _ = profiles.prepareForSpaceTransition(
            tab: plan.tab,
            targetSpaceID: plan.target.spaceID,
            desiredProfileID: plan.target.profileID
        )
    }

    func execute(_ plans: [ShortcutSplitLauncherBindingPlan]) {
        plans.forEach {
            profiles.assignProfile($0.target.profileID, to: $0.tab)
        }
    }
}

/// Persists only the exact windows captured by the admitted runtime attachment
/// lease. No mutable runtime locator is queried after model settlement.
@MainActor
final class ShortcutSplitLauncherWindowPersistence {
    private let structuralLookup: TabStructuralLookupCoordinator

    init(structuralLookup: TabStructuralLookupCoordinator) {
        self.structuralLookup = structuralLookup
    }

    func execute(
        _ states: [BrowserWindowState],
        using lease: TabRuntimePortLease
    ) {
        guard states.isEmpty == false else { return }
        let ordered = states.sorted { $0.id.uuidString < $1.id.uuidString }
        structuralLookup.runAfterCurrentBatch {
            ordered.forEach(lease.persistWindowSession(for:))
        }
    }
}
