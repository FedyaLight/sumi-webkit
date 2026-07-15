@MainActor
final class PreparedShortcutLiveTabRetirementTerminalEffect {
    private enum State { case prepared, residenceQueued, terminal }

    private let terminalModel: PreparedTabTerminalModelRetirement
    private let residencePublication: PreparedShortcutLiveResidencePublication
    private var state = State.prepared

    init(
        terminalModel: PreparedTabTerminalModelRetirement,
        residencePublication: PreparedShortcutLiveResidencePublication
    ) {
        precondition(terminalModel.physicalEffectIsClaimed())
        self.terminalModel = terminalModel
        self.residencePublication = residencePublication
    }

    func queueResidencePublication() {
        guard case .prepared = state else { return }
        state = .residenceQueued
        residencePublication.publish()
    }

    func publishLifecycleAndPhysical() {
        guard case .residenceQueued = state else { return }
        state = .terminal
        precondition(terminalModel.publishLifecycle())
        precondition(terminalModel.finishPhysicalEffect())
    }

    func publish() {
        queueResidencePublication()
        publishLifecycleAndPhysical()
    }
}
