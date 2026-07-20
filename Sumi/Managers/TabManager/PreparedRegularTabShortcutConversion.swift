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
            BrowserWindowShortcutMutationOwner,
            TabFolderOpenStateService
        )
    }

    private enum State {
        case staged
        case modelSettled
        case modelPublished
        case committed
        case rolledBack
    }

    private let payload: Payload
    private var state = State.staged

    init(
        batch: any ShortcutSplitLauncherMoveBatchParticipant,
        windowMutations: BrowserWindowShortcutMutationOwner,
        folderOpenState: TabFolderOpenStateService
    ) {
        payload = .launcher(batch, windowMutations, folderOpenState)
    }

    private init(payload: Payload) {
        self.payload = payload
    }

    func isCurrent() -> Bool {
        guard case .staged = state else { return false }
        switch payload {
        case .noChange:
            return true
        case .launcher(let batch, _, _):
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
            state = .modelPublished
            return true
        case .launcher(let batch, let windowMutations, _):
            return windowMutations.withAggregate({
                guard batch.settleAdmittedModel() else { return false }
                participant?.settleAdmittedWindowModel(
                    using: windowMutations
                )
                state = .modelSettled
                return true
            }, beforePublication: {
                participant?.publishAdmittedModel()
                batch.publishAdmittedModel()
                self.state = .modelPublished
            })
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
        guard case .launcher(
            let batch,
            let windowMutations,
            let folderOpenState
        ) = payload else {
            return false
        }
        let settled = windowMutations.withAggregate({
            guard batch.settleAdmittedModel() else { return false }
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
            batch.publishAdmittedModel()
            self.state = .modelPublished
        })
        guard settled else { return false }
        commit(batch, openingFoldersWith: folderOpenState)
        return true
    }

    /// The enclosing aggregate has already revalidated every participant.
    func settleAdmittedModel() -> Bool {
        guard case .staged = state else {
            preconditionFailure("Sidebar mutation was not staged")
        }
        if case .launcher(let batch, _, _) = payload {
            guard batch.settleAdmittedModel() else { return false }
        }
        state = .modelSettled
        return true
    }

    func rollback() -> Bool {
        guard case .staged = state else { return false }
        if case .launcher(let batch, _, _) = payload,
           batch.rollback() == false { return false }
        state = .rolledBack
        return true
    }

    func publishAdmittedModel() {
        guard case .modelSettled = state else {
            preconditionFailure("Sidebar model was not settled")
        }
        if case .launcher(let batch, _, _) = payload {
            batch.publishAdmittedModel()
        }
        state = .modelPublished
    }

    func commit() {
        guard case .modelPublished = state else {
            preconditionFailure("Sidebar model was not published")
        }
        if case .launcher(let batch, _, let folderOpenState) = payload {
            commit(batch, openingFoldersWith: folderOpenState)
        } else {
            state = .committed
        }
    }

    private func commit(
        _ batch: any ShortcutSplitLauncherMoveBatchParticipant,
        openingFoldersWith folderOpenState: TabFolderOpenStateService
    ) {
        state = .committed
        batch.commitTerminalEffects(openingFoldersWith: folderOpenState)
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
        case launcher(PreparedShortcutSplitLauncherMoveBatch)
    }

    private let payload: Payload

    private init(payload: Payload) {
        self.payload = payload
    }

    func preflightBindingContribution()
        -> RegularTabShortcutSidebarBindingPreflight? {
        switch payload {
        case .noChange:
            return .noChange
        case .launcher(let preparedMoves):
            return preparedMoves.preflightBindingContribution().map {
                .launcher(preparedMoves, $0)
            }
        }
    }

    static var noChange: RegularTabShortcutSidebarMutationPreparation {
        Self(payload: .noChange)
    }

    static func launcher(
        _ preparedMoves: PreparedShortcutSplitLauncherMoveBatch
    ) -> RegularTabShortcutSidebarMutationPreparation {
        Self(payload: .launcher(preparedMoves))
    }
}
