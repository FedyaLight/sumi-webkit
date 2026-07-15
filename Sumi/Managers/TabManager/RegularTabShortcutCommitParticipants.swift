/// Exact durable topology and sidebar participants shared by displayed and
/// detached regular-tab conversion paths.
@MainActor
final class RegularTabShortcutCommitParticipants {
    private enum State {
        case staged
        case modelSettled
        case sidebarCommitted
        case published
        case rolledBack
    }

    private let topology: SplitGroupReplacementReceipt?
    private let sidebar: RegularTabShortcutSidebarMutation
    private let windowMutations: BrowserWindowShortcutMutationOwner
    private var state = State.staged

    init(
        topology: SplitGroupReplacementReceipt?,
        sidebar: RegularTabShortcutSidebarMutation,
        windowMutations: BrowserWindowShortcutMutationOwner
    ) {
        self.topology = topology
        self.sidebar = sidebar
        self.windowMutations = windowMutations
    }

    func isCurrent() -> Bool {
        guard case .staged = state else { return false }
        return (topology?.isCurrent() ?? true) && sidebar.isCurrent()
    }

    func settleDisplayed(
        _ runtime: DisplayedTabShortcutConversionReceipt
    ) -> Bool {
        guard isCurrent(), runtime.isCurrent() else { return false }
        if let topology, topology.commitModel() == false { return false }
        precondition(windowMutations.withAggregate {
            sidebar.settleAdmittedModel()
            runtime.settleAdmittedModel()
            return true
        })
        state = .modelSettled
        return true
    }

    func settleDetached(
        _ runtime: DetachedTabShortcutConversionReceipt
    ) {
        guard case .staged = state else {
            preconditionFailure("Shortcut commit participants were not staged")
        }
        precondition(windowMutations.withAggregate {
            topology?.commitAdmittedModel()
            runtime.settleModel()
            sidebar.settleAdmittedModel()
            return true
        })
        state = .modelSettled
    }

    func rollback() -> Bool {
        guard case .staged = state, sidebar.rollback() else { return false }
        topology?.rollback()
        state = .rolledBack
        return true
    }

    func commitSidebar() {
        guard case .modelSettled = state else {
            preconditionFailure("Shortcut commit model was not settled")
        }
        sidebar.commit()
        state = .sidebarCommitted
    }

    func publishTopology() {
        guard case .sidebarCommitted = state else { return }
        state = .published
        topology?.publish()
    }
}
