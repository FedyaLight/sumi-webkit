@MainActor
final class ShortcutTabBindingWindowTransaction {
    private enum State { case prepared, staged, published, terminal, conflicted }

    private let windows: BrowserWindowShortcutMutationOwner.PreparedAggregate
    private let changedWindows: [BrowserWindowState]
    private let persistence: ShortcutSplitLauncherWindowPersistence
    private let runtimeConnection: TabRuntimePortConnection
    private let runtimeLease: TabRuntimePortLease
    private var state = State.prepared

    init(
        batch: ShortcutTabBindingWindowBatch,
        persistence: ShortcutSplitLauncherWindowPersistence,
        runtimeConnection: TabRuntimePortConnection,
        runtimeLease: TabRuntimePortLease
    ) {
        windows = batch.aggregate
        changedWindows = batch.changedWindows
        self.persistence = persistence
        self.runtimeConnection = runtimeConnection
        self.runtimeLease = runtimeLease
    }

    func validateForStaging() -> Bool {
        guard case .prepared = state else { return false }
        return windows.isCurrent()
            && runtimeConnection.acceptsExactAttachment(runtimeLease)
    }

    func stage() -> ShortcutTabBindingTargetModelParticipant.StageOutcome {
        guard validateForStaging() else {
            return cancelPrepared() ? .restored : .conflicted
        }
        guard windows.stage() else {
            let restored = windows.rollback()
            state = restored ? .terminal : .conflicted
            return restored ? .restored : .conflicted
        }
        state = .staged
        guard stagedModelIsExact() else {
            return rollback() ? .restored : .conflicted
        }
        return .staged
    }

    func stagedModelIsExact() -> Bool {
        guard case .staged = state else { return false }
        return stagedModelOwnershipIsExact()
            && runtimeConnection.acceptsExactAttachment(runtimeLease)
    }

    private func stagedModelOwnershipIsExact() -> Bool { windows.isCurrent() }

    func publish(_ body: () -> Void) {
        guard stagedModelIsExact() else {
            preconditionFailure("Shortcut binding windows were not exact")
        }
        state = .published
        windows.publish(beforePublication: body)
    }

    func publishTerminalEffects() {
        guard case .published = state else {
            preconditionFailure("Shortcut binding windows were not published")
        }
        state = .terminal
        if runtimeConnection.acceptsExactAttachment(runtimeLease) {
            persistence.execute(changedWindows, using: runtimeLease)
        }
    }

    func cancelPrepared() -> Bool {
        guard case .prepared = state else { return false }
        let cancelled = windows.discardPrepared()
        state = cancelled ? .terminal : .conflicted
        return cancelled
    }

    func rollback() -> Bool {
        guard stagedModelIsExact() else { return false }
        let restored = windows.rollback()
        state = restored ? .terminal : .conflicted
        return restored
    }

    func canSettleTerminalDrain() -> Bool {
        switch state {
        case .staged:
            return stagedModelOwnershipIsExact()
                && windows.canAbandonForTerminalDrain()
        case .published, .terminal: return true
        case .prepared, .conflicted: return false
        }
    }

    func settleTerminalDrain() -> Bool {
        guard canSettleTerminalDrain() else { return false }
        if case .staged = state { windows.abandonForTerminalDrain() }
        state = .terminal
        return true
    }
}
