import Foundation

/// Concrete same-pin presentation transaction. It owns exact residence,
/// Tab, window, runtime-attachment, profile, and persistence evidence rather
/// than hiding that state behind callback slots.
@MainActor
final class ShortcutTabBindingRefreshTransaction {
    private enum State {
        case staged
        case modelSettled([BrowserWindowState])
        case committed
        case rolledBack
    }

    private let pin: ShortcutPin
    private let runtimeConnection: TabRuntimePortConnection
    private let runtimeLease: TabRuntimePortLease
    private let plans: [ShortcutSplitLauncherBindingPlan]
    private let residences: LiveShortcutPresentationResidenceTransaction
    private let windowMutations: BrowserWindowShortcutMutationOwner
    private let profileSettlement: ShortcutSplitLauncherProfileSettlement
    private let persistence: ShortcutSplitLauncherWindowPersistence
    private var state = State.staged

    init(
        pin: ShortcutPin,
        runtimeConnection: TabRuntimePortConnection,
        runtimeLease: TabRuntimePortLease,
        plans: [ShortcutSplitLauncherBindingPlan],
        residences: LiveShortcutPresentationResidenceTransaction,
        windowMutations: BrowserWindowShortcutMutationOwner,
        profileSettlement: ShortcutSplitLauncherProfileSettlement,
        persistence: ShortcutSplitLauncherWindowPersistence
    ) {
        self.pin = pin
        self.runtimeConnection = runtimeConnection
        self.runtimeLease = runtimeLease
        self.plans = plans
        self.residences = residences
        self.windowMutations = windowMutations
        self.profileSettlement = profileSettlement
        self.persistence = persistence
    }

    func isCurrent() -> Bool {
        guard case .staged = state,
              runtimeConnection.accepts(runtimeLease),
              residences.isCurrent() else { return false }
        return plans.allSatisfy { plan in
            plan.tabReceipt.accepts(plan.tab) && windowIsCurrent(plan)
        }
    }

    func canRollback() -> Bool {
        guard case .staged = state else { return false }
        return residences.canRollback()
    }

    /// The enclosing batch has already revalidated every participant. Only
    /// admitted, observation-silent model installation remains.
    func settleAdmittedModel() {
        guard case .staged = state else {
            preconditionFailure("Launcher binding was not staged")
        }
        var changedWindows: [UUID: BrowserWindowState] = [:]
        for plan in plans {
            settleTab(plan)
            guard let windowState = plan.windowState else { continue }
            var requiresPersistence = false
            windowMutations.stage(windowState) { state in
                requiresPersistence = ShortcutSelectionTransition.apply(
                    tab: plan.tab,
                    source: plan.sourceIdentity,
                    targetPin: pin,
                    isSelected: plan.wasSelected,
                    to: &state
                )
            }
            if requiresPersistence {
                changedWindows[windowState.id] = windowState
            }
        }
        state = .modelSettled(Array(changedWindows.values))
    }

    func rollback() -> Bool {
        guard canRollback(), residences.rollback() else { return false }
        state = .rolledBack
        return true
    }

    /// The enclosing batch restored its complete raw residence checkpoint.
    func discardAfterAggregateRollback() {
        guard case .staged = state else {
            preconditionFailure("Launcher binding was already settled")
        }
        residences.discardAfterAggregateRollback()
        state = .rolledBack
    }

    func publishAndExecute() {
        guard case .modelSettled(let changedWindows) = state else { return }
        state = .committed
        precondition(
            residences.publish(),
            "Launcher binding lost staged presentation residences"
        )
        profileSettlement.execute(plans)
        persistence.execute(changedWindows, using: runtimeLease)
    }

    private func settleTab(_ plan: ShortcutSplitLauncherBindingPlan) {
        let tab = plan.tab
        tab.isPinned = false
        tab.isSpacePinned = false
        tab.bindToShortcutPin(pin)
        profileSettlement.prepare(plan)
        tab.spaceId = plan.target.spaceID
        tab.folderId = plan.target.folderID
    }

    private func windowIsCurrent(
        _ plan: ShortcutSplitLauncherBindingPlan
    ) -> Bool {
        guard let state = plan.windowState,
              let receipt = plan.windowReceipt else {
            return runtimeLease.windowState(for: plan.windowID) == nil
        }
        return runtimeLease.windowState(for: state.id) === state
            && ShortcutSplitLauncherWindowReceipt(state) == receipt
    }
}
