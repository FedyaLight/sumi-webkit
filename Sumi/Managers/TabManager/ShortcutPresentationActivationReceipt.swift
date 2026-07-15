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
        case abandoned
    }

    let tabs: [Tab]
    let requests: [ShortcutPresentationActivationService.Request]
    private let admissions: [ShortcutPresentationActivationAdmission]
    private let planner: ShortcutPresentationActivationPlanner
    private let committer: ShortcutPresentationActivationCommitter
    private var identityAuthority = ShortcutPresentationPinIdentityAuthority
        .canonical
    private var state = State.prepared

    init(
        admissions: [ShortcutPresentationActivationAdmission],
        planner: ShortcutPresentationActivationPlanner,
        committer: ShortcutPresentationActivationCommitter
    ) {
        tabs = admissions.map(\.tab)
        requests = admissions.map(\.request)
        self.admissions = admissions
        self.planner = planner
        self.committer = committer
    }

    func admitCatalogIdentityHandoff(
        _ handoff: ShortcutPresentationCatalogIdentityHandoff
    ) -> Bool {
        guard case .prepared = state, identityAuthority.isCanonical else {
            return false
        }
        identityAuthority = .catalogHandoff(handoff)
        return true
    }

    func stage() -> Bool {
        guard case .prepared = state,
              canStage(),
              let mutation = committer.stage(admissions) else { return false }
        state = .staged(mutation)
        return true
    }

    func canPublish() -> Bool {
        guard case .staged(let mutation) = state else { return false }
        return mutation.canPublish() && acceptsStagedIntent()
    }

    func publish() {
        guard case .staged(let mutation) = state else {
            preconditionFailure("Shortcut activation was not staged")
        }
        state = .published
        mutation.publish()
    }

    func publishedModelIsExact() -> Bool {
        guard case .published = state else { return false }
        return acceptsStagedIntent()
    }

    func rollback() {
        guard case .staged(let mutation) = state else {
            preconditionFailure("Shortcut activation was not staged")
        }
        mutation.rollback()
        state = .rolledBack
    }

    func abandonForTerminalDrain() {
        guard canPublish() else {
            preconditionFailure("Shortcut activation lost terminal model")
        }
        state = .abandoned
    }

    func forfeitPreservingCurrent() {
        guard case .staged = state else {
            preconditionFailure("Shortcut activation is not staged")
        }
        state = .abandoned
    }

    private func acceptsStagedIntent() -> Bool {
        planner.acceptsStaged(admissions, authority: identityAuthority)
    }

    private func canStage() -> Bool {
        planner.canStage(admissions, authority: identityAuthority)
    }
}
