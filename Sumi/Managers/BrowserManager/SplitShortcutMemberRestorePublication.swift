@MainActor
final class SplitShortcutMemberRestorePublication {
    private enum State { case prepared, claimed, observablePublished, terminal }

    private let presentation: PreparedWindowSplitPresentationSettlement
    private let retirement: ReversibleShortcutLiveTabRetirement?
    private let topology: SplitGroupReplacementReceipt
    private let retirementService: ShortcutLiveTabRetirementService
    private var retirementEffect: PreparedShortcutLiveTabRetirementTerminalEffect?
    private var state = State.prepared

    init(
        presentation: PreparedWindowSplitPresentationSettlement,
        retirement: ReversibleShortcutLiveTabRetirement?,
        topology: SplitGroupReplacementReceipt,
        retirementService: ShortcutLiveTabRetirementService
    ) {
        self.presentation = presentation
        self.retirement = retirement
        self.topology = topology
        self.retirementService = retirementService
    }

    func claim() -> Bool {
        guard case .prepared = state else { return false }
        if let retirement {
            retirement.publishAdmittedModel()
            guard let effect = retirementService.prepareTerminalEffect(
                retirement.takePreparedResult()
            ) else { return false }
            retirementEffect = effect
        }
        state = .claimed
        return true
    }

    func publishObservableModel() {
        guard case .claimed = state else {
            preconditionFailure("Split restore publication was not claimed")
        }
        state = .observablePublished
        topology.publish()
        presentation.publishAdmittedModel()
        retirementEffect?.queueResidencePublication()
    }

    func publishTerminalEffects() {
        guard case .observablePublished = state else {
            preconditionFailure("Split restore model was not published")
        }
        state = .terminal
        presentation.publishTerminalEffects()
        retirementEffect?.publishLifecycleAndPhysical()
    }
}
