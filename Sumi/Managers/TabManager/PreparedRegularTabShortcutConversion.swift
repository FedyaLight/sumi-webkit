import Foundation
import SumiDomain

@MainActor
struct PreparedRegularTabShortcutConversion {
    let sourceTab: Tab
    let preparation: TabShortcutConversionPreparation
    let structure: RegularTabShortcutStructurePlan
    let candidatePin: ShortcutPin
    let destination: TabShortcutPinDestination
}

/// Stable, fully typed input for a regular-tab drop into an existing shortcut
/// sidebar group. The candidate pin is created once and `member` is the exact
/// durable leaf the drop layout must contain.
@MainActor
struct PreparedRegularTabShortcutSidebarDrop {
    let candidatePin: ShortcutPin
    let member: SplitMember
    let expectedSplitGroups: [SumiDomain.SplitGroup]

    let conversion: PreparedRegularTabShortcutConversion
    let targetGroup: SumiDomain.SplitGroup
}

/// Typed sidebar participant for a regular-tab conversion. `noChange` is an
/// explicit payload selected by the caller, never a fail-open initializer
/// default. Launcher batches retain their concrete window/model transaction.
@MainActor
final class RegularTabShortcutSidebarMutation {
    private enum Payload {
        case noChange
        case launcher(
            any ShortcutSplitLauncherMoveBatchParticipant,
            BrowserWindowShortcutMutationOwner
        )
    }

    private enum State {
        case staged
        case modelSettled
        case committed
        case rolledBack
    }

    private let payload: Payload
    private var state = State.staged

    init(
        batch: any ShortcutSplitLauncherMoveBatchParticipant,
        windowMutations: BrowserWindowShortcutMutationOwner
    ) {
        payload = .launcher(batch, windowMutations)
    }

    private init(payload: Payload) {
        self.payload = payload
    }

    func isCurrent() -> Bool {
        guard case .staged = state else { return false }
        switch payload {
        case .noChange:
            return true
        case .launcher(let batch, _):
            return batch.isCurrent()
        }
    }

    @discardableResult
    func settleModel(
        alongside participant: (
            any BrowserWindowShortcutAggregateParticipant
        )? = nil
    ) -> Bool {
        guard case .staged = state, isCurrent(),
              participant?.isCurrentForWindowSettlement() ?? true else {
            return false
        }
        switch payload {
        case .noChange:
            guard participant == nil else { return false }
            state = .modelSettled
            return true
        case .launcher(let batch, let windowMutations):
            return windowMutations.withAggregate {
                batch.settleAdmittedModel()
                participant?.settleAdmittedWindowModel(
                    using: windowMutations
                )
                state = .modelSettled
                return true
            }
        }
    }

    /// Terminal aggregate used by split commands whose topology is already
    /// installed without observation. Every participant is validated first;
    /// raw windows are then installed, model receipts publish, and only then
    /// does window Observation open.
    func settleAndPublishModel(
        alongside participants: [
            any BrowserWindowShortcutAggregateParticipant
        ]
    ) -> Bool {
        guard case .staged = state, isCurrent(),
              participants.allSatisfy({
                  $0.isCurrentForWindowSettlement()
              }) else { return false }
        guard case .launcher(let batch, let windowMutations) = payload else {
            return false
        }
        let settled = windowMutations.withAggregate({
            batch.settleAdmittedModel()
            participants.forEach {
                $0.settleAdmittedWindowModel(using: windowMutations)
            }
            state = .modelSettled
            return true
        }, beforePublication: {
            guard case .modelSettled = self.state else {
                preconditionFailure("Sidebar aggregate lost terminal model")
            }
            participants.forEach { $0.publishAdmittedModel() }
        })
        guard settled else { return false }
        state = .committed
        batch.publishAndExecute()
        return true
    }

    /// The enclosing aggregate has already revalidated every participant.
    func settleAdmittedModel() {
        guard case .staged = state else {
            preconditionFailure("Sidebar mutation was not staged")
        }
        if case .launcher(let batch, _) = payload {
            batch.settleAdmittedModel()
        }
        state = .modelSettled
    }

    func rollback() -> Bool {
        guard case .staged = state else { return false }
        if case .launcher(let batch, _) = payload,
           batch.rollback() == false { return false }
        state = .rolledBack
        return true
    }

    func commit() {
        guard case .modelSettled = state else { return }
        state = .committed
        if case .launcher(let batch, _) = payload {
            batch.publishAndExecute()
        }
    }

    static var noChange: RegularTabShortcutSidebarMutation {
        Self(payload: .noChange)
    }
}

/// Closure-free preparation staged only after pin insertion establishes the
/// catalog snapshot against which launcher moves must commit.
@MainActor
final class RegularTabShortcutSidebarMutationPreparation {
    private enum Payload {
        case noChange
        case launcher(
            ShortcutSplitLauncherMoveTransaction,
            [PreparedShortcutSplitLauncherRestoration]
        )
    }

    private let payload: Payload

    private init(payload: Payload) {
        self.payload = payload
    }

    func stage() -> RegularTabShortcutSidebarMutation? {
        switch payload {
        case .noChange:
            return .noChange
        case .launcher(let transaction, let restorations):
            return transaction.stage(restorations)
        }
    }

    static var noChange: RegularTabShortcutSidebarMutationPreparation {
        Self(payload: .noChange)
    }

    static func launcher(
        transaction: ShortcutSplitLauncherMoveTransaction,
        restorations: [PreparedShortcutSplitLauncherRestoration]
    ) -> RegularTabShortcutSidebarMutationPreparation {
        Self(payload: .launcher(transaction, restorations))
    }
}
