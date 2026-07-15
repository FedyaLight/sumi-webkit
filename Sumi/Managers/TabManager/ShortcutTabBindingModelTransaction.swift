import SumiWebRuntime

@MainActor
protocol ShortcutTabBindingAggregateTransaction:
    WebViewReplacementModelTransaction {
    var exactBindingTabs: [Tab] { get }
    func cancelPrepared() -> Bool
}

@MainActor
final class ShortcutTabBindingModelTransaction:
    ShortcutTabBindingAggregateTransaction {
    struct Input {
        let pin: ShortcutPin
        let plans: [ShortcutSplitLauncherBindingPlan]
        let residences: LiveShortcutPresentationResidenceTransaction
    }

    private enum State {
        case prepared, staged, claimed, modelPublished, conflicted, terminal
    }

    private let targets: ShortcutTabBindingTargetModelParticipant
    private let windows: ShortcutTabBindingWindowTransaction
    private let structuralLookup: TabStructuralLookupCoordinator
    private var state = State.prepared

    var exactBindingTabs: [Tab] { targets.exactTabs }

    init(
        inputs: [Input],
        residences: any ShortcutTabBindingResidenceTransaction,
        windowBatch: ShortcutTabBindingWindowBatch,
        persistence: ShortcutSplitLauncherWindowPersistence,
        runtimeConnection: TabRuntimePortConnection,
        runtimeLease: TabRuntimePortLease,
        profiles: TabProfileTransitionService,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        precondition(Self.uniqueTabs(in: inputs))
        targets = ShortcutTabBindingTargetModelParticipant(
            inputs: inputs,
            residences: residences,
            runtimeConnection: runtimeConnection,
            runtimeLease: runtimeLease,
            profiles: profiles
        )
        windows = ShortcutTabBindingWindowTransaction(
            batch: windowBatch,
            persistence: persistence,
            runtimeConnection: runtimeConnection,
            runtimeLease: runtimeLease
        )
        self.structuralLookup = structuralLookup
    }

    func validateForStaging() -> Bool {
        guard case .prepared = state else { return false }
        return targets.validateForStaging() && windows.validateForStaging()
    }

    func retainsModelAfterFailedStage() -> Bool {
        if case .conflicted = state { return true }
        return false
    }

    func stage() throws {
        guard validateForStaging() else {
            guard cancelPrepared() else { throw ShortcutTabBindingModelError.stale }
            throw ShortcutTabBindingModelError.restoredAfterFailedStage
        }
        switch targets.stage() {
        case .staged: break
        case .restored:
            _ = windows.cancelPrepared()
            state = .terminal
            throw ShortcutTabBindingModelError.restoredAfterFailedStage
        case .conflicted:
            _ = windows.cancelPrepared()
            state = .conflicted
            throw ShortcutTabBindingModelError.stale
        }
        switch windows.stage() {
        case .staged:
            state = .staged
        case .restored:
            let targetsRestored = targets.rollback()
            state = targetsRestored ? .terminal : .conflicted
            throw targetsRestored
                ? ShortcutTabBindingModelError.restoredAfterFailedStage
                : ShortcutTabBindingModelError.stale
        case .conflicted:
            _ = targets.rollback()
            state = .conflicted
            throw ShortcutTabBindingModelError.stale
        }
    }

    func stagedModelIsExact() -> Bool {
        guard case .staged = state else { return false }
        return targets.stagedModelIsExact() && windows.stagedModelIsExact()
    }

    func canClaimTerminalModel() -> Bool { stagedModelIsExact() }

    func claimTerminalModel() -> WebViewReplacementTerminalModelClaimOutcome {
        guard canClaimTerminalModel() else { return .terminallyDrained }
        state = .claimed
        return .sealed
    }

    func claimedModelIsExact() -> Bool {
        guard case .claimed = state else { return false }
        return targets.stagedModelIsExact() && windows.stagedModelIsExact()
    }

    func publishCommit() {
        structuralLookup.withTransaction {
            publishModelCommit(beforeWindowPublication: {})
            publishTerminalEffects()
        }
    }

    func publishModelCommit(beforeWindowPublication: () -> Void) {
        guard case .claimed = state else {
            preconditionFailure("Shortcut binding model was not claimed")
        }
        state = .modelPublished
        windows.publish {
            beforeWindowPublication()
            targets.publishModel()
            structuralLookup.flushPendingWritesForRead()
        }
    }

    func publishTerminalEffects() {
        guard case .modelPublished = state else {
            preconditionFailure("Shortcut binding model was not published")
        }
        state = .terminal
        targets.publishTerminalEffects()
        windows.publishTerminalEffects()
    }

    func cancelPrepared() -> Bool {
        guard case .prepared = state else { return false }
        let targetsCancelled = targets.cancelPrepared()
        let windowsCancelled = windows.cancelPrepared()
        state = targetsCancelled && windowsCancelled ? .terminal : .conflicted
        return targetsCancelled && windowsCancelled
    }

    func rollback() throws {
        guard stagedModelIsExact() else { throw ShortcutTabBindingModelError.stale }
        let windowsRestored = windows.rollback()
        let targetsRestored = targets.rollback()
        guard windowsRestored, targetsRestored else {
            state = .conflicted
            throw ShortcutTabBindingModelError.stale
        }
        state = .terminal
    }

    func publishRollback() {}

    func canSettleTerminalDrain() -> Bool {
        switch state {
        case .staged, .claimed:
            return targets.canSettleTerminalDrain()
                && windows.canSettleTerminalDrain()
        case .modelPublished, .terminal: return true
        case .prepared, .conflicted: return false
        }
    }

    func settleTerminalDrain() -> Bool {
        guard canSettleTerminalDrain() else { return false }
        let windowsSettled = windows.settleTerminalDrain()
        let targetsSettled = targets.settleTerminalDrain()
        state = windowsSettled && targetsSettled ? .terminal : .conflicted
        return windowsSettled && targetsSettled
    }

    private static func uniqueTabs(in inputs: [Input]) -> Bool {
        let tabs = inputs.flatMap(\.plans).map(\.tab)
        return Set(tabs.map(ObjectIdentifier.init)).count == tabs.count
    }
}
