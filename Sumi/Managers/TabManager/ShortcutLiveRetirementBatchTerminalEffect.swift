@MainActor
final class ShortcutLiveRetirementBatchTerminalEffect {
    private enum State { case prepared, residenceQueued, terminal }

    private let terminalModel: PreparedTabTerminalModelRetirement?
    private let residence: ShortcutLiveRetirementBatchResidencePublication
    private let physical: ShortcutLiveRetirementBatchPhysicalEffect
    private var state = State.prepared

    init(
        terminalModel: PreparedTabTerminalModelRetirement?,
        residence: ShortcutLiveRetirementBatchResidencePublication,
        physical: ShortcutLiveRetirementBatchPhysicalEffect
    ) {
        self.terminalModel = terminalModel
        self.residence = residence
        self.physical = physical
        if let terminalModel {
            precondition(terminalModel.claimPhysicalEffect {
                { [physical] in physical.publish() }
            } == .claimed)
        }
    }

    func queueResidencePublication() {
        guard case .prepared = state else { return }
        state = .residenceQueued
        residence.publish()
    }

    func publishLifecycleAndPhysical() {
        guard case .residenceQueued = state else { return }
        state = .terminal
        if let terminalModel {
            precondition(terminalModel.publishLifecycle())
            precondition(terminalModel.finishPhysicalEffect())
        } else {
            physical.publish()
        }
    }

    func publish() {
        queueResidencePublication()
        publishLifecycleAndPhysical()
    }
}
