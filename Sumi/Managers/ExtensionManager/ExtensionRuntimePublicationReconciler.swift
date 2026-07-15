import Foundation

/// Coordinates only generation-wide publication replacement and retirement.
/// Routine window and Tab events go directly to their exact lifecycle nodes.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimePublicationReconciler {
    private struct ReloadWork {
        let request: ExtensionRuntimeReloadTransaction.Request
        let auxiliaryControl: (any ExtensionAuxiliaryWindowControl)?
    }

    private struct ReloadExecution {
        let commit: ExtensionRuntimeReloadTransaction.Commit?
        let needsFollowUp: Bool
    }

    private let gate: ExtensionRuntimePublicationGate
    private let normalWindows: ExtensionNormalWindowLifecycle
    private let auxiliaryWindows: ExtensionAuxiliaryWindowLifecycle
    private let reloadTransaction: ExtensionRuntimeReloadTransaction
    private let tabClosure: ExtensionNormalTabCloseTransaction
    private let deferredTabClosures: ExtensionDeferredTabClosures
    private let replayScheduler: ExtensionRuntimePublicationReplayScheduler
    private let settleDeferredCommit:
        @MainActor (ExtensionRuntimeReloadTransaction.Commit) -> Void
    private var pendingReload: ReloadWork?

    init(
        gate: ExtensionRuntimePublicationGate,
        normalWindows: ExtensionNormalWindowLifecycle,
        auxiliaryWindows: ExtensionAuxiliaryWindowLifecycle,
        reloadTransaction: ExtensionRuntimeReloadTransaction,
        tabClosure: ExtensionNormalTabCloseTransaction,
        deferredTabClosures: ExtensionDeferredTabClosures = .init(),
        replayScheduler: ExtensionRuntimePublicationReplayScheduler = .init(),
        settleDeferredCommit: @escaping @MainActor (
            ExtensionRuntimeReloadTransaction.Commit
        ) -> Void
    ) {
        self.gate = gate
        self.normalWindows = normalWindows
        self.auxiliaryWindows = auxiliaryWindows
        self.reloadTransaction = reloadTransaction
        self.tabClosure = tabClosure
        self.deferredTabClosures = deferredTabClosures
        self.replayScheduler = replayScheduler
        self.settleDeferredCommit = settleDeferredCommit
    }

    func reload(
        _ request: ExtensionRuntimeReloadTransaction.Request,
        auxiliaryControl: (any ExtensionAuxiliaryWindowControl)?
    ) -> ExtensionRuntimeReloadTransaction.Commit? {
        let work = ReloadWork(
            request: request,
            auxiliaryControl: auxiliaryControl
        )
        guard let claim = gate.beginReload() else {
            if gate.canCoalesceReloadRequest {
                pendingReload = work
            }
            return nil
        }
        replayScheduler.cancel()

        guard let execution = execute(work, claim: claim) else {
            // Terminal retirement invalidates the claim. A request queued by
            // an earlier callback must not revive the retired graph.
            pendingReload = nil
            return nil
        }

        let followUp = pendingReload
            ?? (execution.needsFollowUp ? work : nil)
        pendingReload = nil
        guard let followUp else { return execution.commit }
        guard let followUpClaim = gate.beginReload(),
              let followUpExecution = execute(
                  followUp,
                  claim: followUpClaim
              )
        else {
            pendingReload = nil
            return nil
        }

        // At most two passes run synchronously. Work produced by the replay is
        // preserved, but it yields to the next MainActor turn before entering
        // another WebKit callback batch.
        let overflow = pendingReload
            ?? (followUpExecution.needsFollowUp ? followUp : nil)
        pendingReload = nil
        if let overflow, replayScheduler.canScheduleReplay {
            replayScheduler.replaceScheduledReplay { [weak self] in
                guard let self,
                      let commit = self.reload(
                        overflow.request,
                        auxiliaryControl: overflow.auxiliaryControl
                      )
                else {
                    return
                }
                self.settleDeferredCommit(commit)
            }
        }
        return followUpExecution.commit
    }

    @discardableResult
    func deferTabClose(_ tab: Tab) -> Bool {
        guard gate.exactTabCloseDisposition()
                == .deferUntilReloadHandoff
        else {
            return false
        }
        guard let receipt = tabClosure.prepareClose(tab) else { return false }
        deferredTabClosures.deferClose(receipt)
        return true
    }

    private func execute(
        _ work: ReloadWork,
        claim: ExtensionRuntimePublicationGate.ReloadClaim
    ) -> ReloadExecution? {
        let request = work.request

        let suspendedSessions = auxiliaryWindows.suspendForRuntimeReload(
            control: work.auxiliaryControl
        )
        guard gate.reloadIsCurrent(claim) else { return nil }

        let commit = reloadTransaction.reload(
            request,
            publicationClaim: claim
        )
        guard gate.reloadIsCurrent(claim) else { return nil }

        if normalWindows.acceptsNewPublications {
            auxiliaryWindows.republishAfterRuntimeReload(
                suspendedSessions,
                control: work.auxiliaryControl,
                continuingWhile: { [weak gate] in
                    gate?.reloadIsCurrent(claim) == true
                }
            )
        }

        drainDeferredTabClosures()
        guard gate.reloadIsCurrent(claim) else { return nil }

        guard let needsFollowUp = gate.takeDeferredStructuralEvent(
            for: claim
        ) else {
            return nil
        }
        guard gate.finishReload(
            claim,
            publicationIsAvailable: normalWindows.acceptsNewPublications
        ) else {
            return nil
        }
        return ReloadExecution(
            commit: commit,
            needsFollowUp: needsFollowUp
        )
    }

    @discardableResult
    func retire(
        auxiliaryControl: (any ExtensionAuxiliaryWindowControl)?
    ) -> ExtensionRuntimeReloadTransaction.RetirementOutcome {
        replayScheduler.cancel()
        pendingReload = nil
        guard gate.beginTerminalRetirement() else {
            return .alreadyUnavailable
        }
        drainDeferredTabClosures()
        auxiliaryWindows.closeAllForRuntimeTeardown(
            control: auxiliaryControl
        )
        let outcome = reloadTransaction.retireRuntime()
        gate.finishTerminalRetirement()
        return outcome
    }

    private func drainDeferredTabClosures() {
        for receipt in deferredTabClosures.takeAll() {
            tabClosure.close(receipt)
        }
    }
}
