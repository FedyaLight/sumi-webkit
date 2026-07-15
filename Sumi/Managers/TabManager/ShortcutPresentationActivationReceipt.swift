import Foundation

/// Concrete prepared shortcut-presentation transaction. Planner evidence and
/// staged membership/residence mutation remain typed and rollback-owned until
/// exact downstream settlement succeeds.
@MainActor
final class ShortcutPresentationActivationReceipt {
    private enum State {
        case prepared
        case staged(ShortcutPresentationActivationStagedMutation)
        case published
        case rolledBack
    }

    let tabs: [Tab]
    private let admissions: [ShortcutPresentationActivationAdmission]
    private let planner: ShortcutPresentationActivationPlanner
    private let committer: ShortcutPresentationActivationCommitter
    private var state = State.prepared

    init(
        admissions: [ShortcutPresentationActivationAdmission],
        planner: ShortcutPresentationActivationPlanner,
        committer: ShortcutPresentationActivationCommitter
    ) {
        tabs = admissions.map(\.tab)
        self.admissions = admissions
        self.planner = planner
        self.committer = committer
    }

    func stage() -> Bool {
        guard case .prepared = state,
              planner.canStage(admissions),
              let mutation = committer.stage(admissions) else { return false }
        state = .staged(mutation)
        return true
    }

    func canPublish() -> Bool {
        guard case .staged(let mutation) = state else { return false }
        return mutation.canPublish() && planner.acceptsStaged(admissions)
    }

    func publish() {
        guard case .staged(let mutation) = state else {
            preconditionFailure("Shortcut activation was not staged")
        }
        state = .published
        mutation.publish()
    }

    func rollback() {
        guard case .staged(let mutation) = state else {
            preconditionFailure("Shortcut activation was not staged")
        }
        mutation.rollback()
        state = .rolledBack
    }
}
