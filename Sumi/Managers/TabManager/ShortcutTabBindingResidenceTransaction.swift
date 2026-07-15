@MainActor
protocol ShortcutTabBindingResidenceTransaction: AnyObject {
    func validateForStaging() -> Bool
    func stage() -> Bool
    func stagedModelIsExact() -> Bool
    func cancelPrepared() -> Bool
    func canRollback() -> Bool
    func publish() -> Bool
    func rollback() -> Bool
    func canAbandonForTerminalDrain() -> Bool
    func abandonForTerminalDrain()
}

@MainActor
final class ShortcutTabBindingResidenceReceiptTransaction:
    ShortcutTabBindingResidenceTransaction {
    private let receipt: LiveShortcutPresentationResidenceTransaction

    init(_ receipt: LiveShortcutPresentationResidenceTransaction) {
        self.receipt = receipt
    }

    func validateForStaging() -> Bool { receipt.validateForStaging() }
    func stage() -> Bool { receipt.stage() }
    func stagedModelIsExact() -> Bool { receipt.stagedModelIsExact() }
    func cancelPrepared() -> Bool { receipt.cancelPrepared() }
    func canRollback() -> Bool { receipt.canRollback() }
    func publish() -> Bool { receipt.publish() }
    func rollback() -> Bool { receipt.rollback() }
    func canAbandonForTerminalDrain() -> Bool {
        receipt.canAbandonForTerminalDrain()
    }
    func abandonForTerminalDrain() {
        receipt.abandonForTerminalDrain()
    }
}

@MainActor
final class ShortcutTabBindingResidenceCompositeTransaction:
    ShortcutTabBindingResidenceTransaction {
    private let participants: [any ShortcutTabBindingResidenceTransaction]

    init(_ participants: [any ShortcutTabBindingResidenceTransaction]) {
        self.participants = participants
    }

    func validateForStaging() -> Bool {
        participants.allSatisfy { $0.validateForStaging() }
    }

    func stage() -> Bool {
        guard validateForStaging() else { return false }
        var staged: [any ShortcutTabBindingResidenceTransaction] = []
        for (index, participant) in participants.enumerated() {
            guard participant.stage() else {
                staged.reversed().forEach { precondition($0.rollback()) }
                participants.dropFirst(index + 1).forEach {
                    _ = $0.cancelPrepared()
                }
                return false
            }
            staged.append(participant)
        }
        return stagedModelIsExact()
    }

    func stagedModelIsExact() -> Bool {
        participants.allSatisfy { $0.stagedModelIsExact() }
    }

    func cancelPrepared() -> Bool {
        var cancelled = true
        for participant in participants.reversed()
        where participant.cancelPrepared() == false {
            cancelled = false
        }
        return cancelled
    }

    func canRollback() -> Bool {
        participants.allSatisfy { $0.canRollback() }
    }

    func publish() -> Bool {
        guard stagedModelIsExact() else { return false }
        participants.forEach { precondition($0.publish()) }
        return true
    }

    func rollback() -> Bool {
        guard canRollback() else { return false }
        participants.reversed().forEach { precondition($0.rollback()) }
        return true
    }

    func canAbandonForTerminalDrain() -> Bool {
        participants.allSatisfy { $0.canAbandonForTerminalDrain() }
    }

    func abandonForTerminalDrain() {
        precondition(canAbandonForTerminalDrain())
        participants.forEach { $0.abandonForTerminalDrain() }
    }
}
