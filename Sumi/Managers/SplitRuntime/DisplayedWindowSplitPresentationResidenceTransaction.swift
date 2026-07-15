@MainActor
final class DisplayedWindowSplitPresentationResidenceTransaction {
    private enum State { case prepared, staged, bound, published, terminal }

    private let activation: ShortcutPresentationActivationReceipt
    private let contribution: PreparedDisplayedShortcutResidenceContribution
    let shortcutWitnesses: [WindowSplitPresentationShortcutWitness]
    private var state = State.prepared

    init?(
        activation: ShortcutPresentationActivationReceipt,
        contribution: PreparedDisplayedShortcutResidenceContribution
    ) {
        guard let witnesses = contribution.makeShortcutWitnesses(
            activationTabs: activation.tabs
        ) else { return nil }
        self.activation = activation
        self.contribution = contribution
        shortcutWitnesses = witnesses
    }

    func admitCatalogIdentityHandoff(
        _ handoff: ShortcutPresentationCatalogIdentityHandoff
    ) -> Bool {
        guard case .prepared = state else { return false }
        return activation.admitCatalogIdentityHandoff(handoff)
    }

    func stagePrepared() -> Bool {
        guard case .prepared = state,
              contribution.preparedIdentityIsExact(),
              activation.stage() else { return false }
        state = .staged
        guard activation.canPublish(),
              contribution.preparedIdentityIsExact() else {
            activation.rollback()
            state = .terminal
            return false
        }
        return true
    }

    func acceptBoundIdentity() -> Bool {
        guard case .staged = state,
              activation.canPublish(),
              contribution.acceptBoundIdentity() else { return false }
        state = .bound
        return true
    }

    func preparedIdentityIsExact() -> Bool {
        guard case .staged = state else { return false }
        return activation.canPublish()
            && contribution.preparedIdentityIsExact()
    }

    func canPublish() -> Bool {
        guard case .bound = state else { return false }
        return activation.canPublish() && contribution.boundIdentityIsExact()
    }

    func publish() {
        precondition(canPublish())
        activation.publish()
        state = .published
    }

    func publishedModelIsExact() -> Bool {
        guard case .published = state else { return false }
        return activation.publishedModelIsExact()
            && contribution.terminalIdentityIsExact()
    }

    func rollback() {
        switch state {
        case .staged, .bound:
            activation.rollback()
            state = .terminal
        case .prepared, .published, .terminal:
            preconditionFailure("Displayed split residence was not reversible")
        }
    }

    func abandonForTerminalDrain() {
        precondition(canPublish())
        activation.abandonForTerminalDrain()
        state = .terminal
    }

    func forfeitPreservingCurrent() {
        switch state {
        case .staged, .bound:
            break
        case .prepared, .published, .terminal:
            preconditionFailure("Displayed split residence was not staged")
        }
        activation.forfeitPreservingCurrent()
        state = .terminal
    }
}
