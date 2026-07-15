@MainActor
final class PreparedRegularTabShortcutDurableTerminalDrain {
    private enum Disposition {
        case exact
        case preservingForeignState
    }

    private let structural: TabStructuralCollectionMutationOwner
        .PreparedAggregate
    private let topology: SplitGroupReplacementReceipt?
    private let presentation: PreparedWindowSplitPresentationSettlement?
    private let disposition: Disposition
    private var isFinished = false

    init?(
        structural: TabStructuralCollectionMutationOwner.PreparedAggregate,
        topology: SplitGroupReplacementReceipt?,
        presentation: PreparedWindowSplitPresentationSettlement?
    ) {
        guard structural.canAbandonForTerminalDrain() else { return nil }
        let topologyIsExact = topology?.canAbandonForTerminalDrain() ?? true
        let presentationIsExact = presentation?
            .canAbandonForTerminalDrain() ?? true
        if topologyIsExact, presentationIsExact {
            disposition = .exact
        } else {
            guard topologyIsExact
                || topology?.canForfeitPreservingCurrent() == true else {
                return nil
            }
            guard presentationIsExact
                || presentation?.canForfeitPreservingCurrent() == true else {
                return nil
            }
            disposition = .preservingForeignState
        }
        self.structural = structural
        self.topology = topology
        self.presentation = presentation
    }

    func matches(
        structural: TabStructuralCollectionMutationOwner.PreparedAggregate,
        topology: SplitGroupReplacementReceipt?,
        presentation: PreparedWindowSplitPresentationSettlement?
    ) -> Bool {
        self.structural === structural
            && sameIdentity(self.topology, topology)
            && sameIdentity(self.presentation, presentation)
            && canFinish()
    }

    func finish() {
        precondition(canFinish())
        isFinished = true
        structural.abandonForTerminalDrain()
        finishTopology()
        finishPresentation()
    }

    private func canFinish() -> Bool {
        guard isFinished == false,
              structural.canAbandonForTerminalDrain() else { return false }
        switch disposition {
        case .exact:
            return topology?.canAbandonForTerminalDrain() ?? true
                && (presentation?.canAbandonForTerminalDrain() ?? true)
        case .preservingForeignState:
            return canFinish(topology) && canFinish(presentation)
        }
    }

    private func canFinish(_ receipt: SplitGroupReplacementReceipt?) -> Bool {
        receipt?.canAbandonForTerminalDrain() ?? true
            || receipt?.canForfeitPreservingCurrent() == true
    }

    private func canFinish(
        _ receipt: PreparedWindowSplitPresentationSettlement?
    ) -> Bool {
        receipt?.canAbandonForTerminalDrain() ?? true
            || receipt?.canForfeitPreservingCurrent() == true
    }

    private func finishTopology() {
        guard let topology else { return }
        if topology.canAbandonForTerminalDrain() {
            topology.abandonForTerminalDrain()
        } else {
            topology.forfeitPreservingCurrent()
        }
    }

    private func finishPresentation() {
        guard let presentation else { return }
        if presentation.canAbandonForTerminalDrain() {
            presentation.abandonForTerminalDrain()
        } else {
            presentation.forfeitPreservingCurrent()
        }
    }

    private func sameIdentity<T: AnyObject>(_ lhs: T?, _ rhs: T?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case (.some(let lhs), .some(let rhs)): return lhs === rhs
        case (.some, nil), (nil, .some): return false
        }
    }
}
