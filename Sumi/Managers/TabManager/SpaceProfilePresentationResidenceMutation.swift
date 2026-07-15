import Foundation

/// Prevalidated, observation-silent residence mutation paired with a Space
/// profile retirement receipt. Publication is explicit and terminally ordered.
@MainActor
final class SpaceProfilePresentationResidenceMutation {
    private enum State { case pending, staged, rolledBack }

    private let relocations: [SpaceProfilePresentationTransition.Relocation]
    private let retirements: [LiveShortcutTabEntry]
    private let registry: LiveShortcutTabRegistry
    private let plans: [LiveShortcutResidenceMutationStaging.Plan]?
    private var changes: [LiveShortcutResidenceMutationStaging.Change] = []
    private var state: State = .pending

    init(
        relocations: [SpaceProfilePresentationTransition.Relocation],
        retirements: [LiveShortcutTabEntry],
        registry: LiveShortcutTabRegistry
    ) {
        self.relocations = relocations
        self.retirements = retirements
        self.registry = registry
        let relocationPlans: [LiveShortcutResidenceMutationStaging.Plan] =
            relocations.compactMap { relocation in
            guard relocation.entry.presentationPage != relocation.targetPage
            else { return nil }
            return registry.staging.prepareRelocation(
                relocation.entry.tab,
                from: relocation.entry.pinId,
                to: relocation.entry.pinId,
                in: relocation.entry.windowId,
                presentationPage: relocation.targetPage
            )
        }
        let retirementPlans = retirements.compactMap(
            registry.staging.prepareRemoval
        )
        if relocationPlans.count == relocations.filter({
            $0.entry.presentationPage != $0.targetPage
        }).count, retirementPlans.count == retirements.count {
            plans = relocationPlans + retirementPlans
        } else {
            plans = nil
        }
    }

    func canStage() -> Bool {
        guard state == .pending else { return false }
        guard let plans, registry.staging.canStage(plans) else { return false }
        return relocations.allSatisfy { relocation in
            guard registry.entry(containing: relocation.entry.tab)?
                .isIdentical(to: relocation.entry) == true else { return false }
            return true
        } && retirements.allSatisfy { entry in
            registry.entry(containing: entry.tab)?
                .isIdentical(to: entry) == true
        }
    }

    func commit() -> Bool {
        guard canStage() else { return false }
        guard let plans, let staged = registry.staging.stage(plans) else {
            return false
        }
        changes = staged
        state = .staged
        return true
    }

    func canRollback() -> Bool {
        state == .staged && registry.staging.canPublish(changes)
    }

    func rollback() -> Bool {
        guard canRollback(), registry.staging.rollback(changes) else {
            return false
        }
        state = .rolledBack
        return true
    }

    func isCurrentStaged() -> Bool {
        state == .staged && registry.staging.canPublish(changes)
    }

    func publish() {
        precondition(state != .pending)
        if changes.isEmpty == false {
            registry.staging.publish(changes)
        }
    }
}
