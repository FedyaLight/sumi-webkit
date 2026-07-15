import Foundation

/// Prevalidated, observation-silent residence mutation paired with a Space
/// profile retirement receipt. Publication is explicit and terminally ordered.
@MainActor
final class SpaceProfilePresentationResidenceMutation {
    private enum State { case pending, staged, rolledBack }

    private let relocations: [SpaceProfilePresentationTransition.Relocation]
    private let retirements: [LiveShortcutTabEntry]
    private let registry: LiveShortcutTabRegistry
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
    }

    func canStage() -> Bool {
        guard state == .pending else { return false }
        return relocations.allSatisfy { relocation in
            guard registry.entry(containing: relocation.entry.tab)?
                .isIdentical(to: relocation.entry) == true else { return false }
            return relocation.entry.presentationPage == relocation.targetPage
                || registry.staging.canRelocate(
                    relocation.entry.tab,
                    from: relocation.entry.pinId,
                    to: relocation.entry.pinId,
                    in: relocation.entry.windowId,
                    presentationPage: relocation.targetPage
                )
        } && retirements.allSatisfy { entry in
            registry.entry(containing: entry.tab)?
                .isIdentical(to: entry) == true
        }
    }

    func commit() -> Bool {
        guard canStage() else { return false }
        let checkpoint = registry.staging.beginBatchCheckpoint()
        var staged: [LiveShortcutResidenceMutationStaging.Change] = []
        for relocation in relocations
            where relocation.entry.presentationPage != relocation.targetPage {
            guard let change = registry.staging.relocate(
                relocation.entry.tab,
                from: relocation.entry.pinId,
                to: relocation.entry.pinId,
                in: relocation.entry.windowId,
                presentationPage: relocation.targetPage
            ) else {
                _ = checkpoint.restore()
                return false
            }
            staged.append(change)
        }
        for entry in retirements {
            guard let change = registry.staging.remove(entry) else {
                _ = checkpoint.restore()
                return false
            }
            staged.append(change)
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
