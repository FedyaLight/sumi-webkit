import Foundation
import SumiWebRuntime

enum SpaceProfileRetirementBeginOutcome: Equatable {
    case notRequired
    case modelCommitted
    case terminallyDrainedModelCommitted
    case rejected
}

@MainActor
enum SpaceProfileRetirementCommitOutcome {
    case committed(SpaceProfilePresentationTerminalEffects)
    case terminallyDrained
    case conflict
}

@MainActor
enum SpaceProfilePresentationTerminalEffects {
    case none
    case committed(CommittedTabRuntimeRetirement)
    case empty(PreparedTabRuntimeTeardown)
}

/// Sole owner of terminal presentation effects after an inner retirement has
/// committed. Normal publication and terminal drain may race through reentrant
/// callbacks, but exactly one path can claim and consume the retained effects.
@MainActor
final class SpaceProfilePresentationTerminalEffectReceipt {
    private enum State {
        case pending
        case claimedNormal
        case claimedDrain
        case finished
    }

    private var effects: SpaceProfilePresentationTerminalEffects?
    private var state = State.pending
    private var onConsumed: (() -> Void)?

    init(_ effects: SpaceProfilePresentationTerminalEffects) {
        self.effects = effects
    }

    func registerConsumption(_ action: @escaping () -> Void) -> Bool {
        guard case .pending = state, onConsumed == nil else { return false }
        onConsumed = action
        return true
    }

    @discardableResult
    func claimNormal(
        _ consume: (SpaceProfilePresentationTerminalEffects) -> Void
    ) -> Bool {
        claim(as: .claimedNormal, consume)
    }

    @discardableResult
    func claimDrain(
        _ consume: (SpaceProfilePresentationTerminalEffects) -> Void
    ) -> Bool {
        claim(as: .claimedDrain, consume)
    }

    private func claim(
        as claimedState: State,
        _ consume: (SpaceProfilePresentationTerminalEffects) -> Void
    ) -> Bool {
        guard case .pending = state, let effects else { return false }
        state = claimedState
        self.effects = nil
        consume(effects)
        state = .finished
        let completion = onConsumed
        onConsumed = nil
        completion?()
        return true
    }
}

/// Couples exact live-shortcut page mutation to pure WebView retirement.
/// Receipt callbacks are observation-silent; publication happens only after
/// repository settlement has made the corresponding model state externally safe.
@MainActor
final class SpaceProfilePresentationTransition {
    struct Relocation {
        let entry: LiveShortcutTabEntry
        let targetPage: LiveShortcutPresentationPageReceipt
    }

    struct Retirement {
        let entry: LiveShortcutTabEntry
        let window: BrowserWindowState
    }

    private enum State: Equatable {
        case pending
        case prepared
        case staged
        case terminal
    }

    private let retirements: [Retirement]
    private let runtimeConnection: TabRuntimePortConnection
    private let runtimeLease: TabRuntimePortLease
    private let runtimeTeardown: TabRuntimeTeardownService
    private let terminalPublisher: SpaceProfilePresentationTerminalEffectPublisher
    private let residences: SpaceProfilePresentationResidenceMutation
    private var preparedRuntime: RuntimePortRegistry?
    private var retirementBatch: TabRuntimeRetirementBatch?
    private var state: State = .pending

    init(
        relocations: [Relocation],
        retirements: [Retirement],
        registry: LiveShortcutTabRegistry,
        runtimeConnection: TabRuntimePortConnection,
        runtimeLease: TabRuntimePortLease,
        runtimeTeardown: TabRuntimeTeardownService,
        terminalPublisher: SpaceProfilePresentationTerminalEffectPublisher
    ) {
        self.retirements = retirements
        self.runtimeConnection = runtimeConnection
        self.runtimeLease = runtimeLease
        self.runtimeTeardown = runtimeTeardown
        self.terminalPublisher = terminalPublisher
        residences = SpaceProfilePresentationResidenceMutation(
            relocations: relocations,
            retirements: retirements.map(\.entry),
            registry: registry
        )
    }

    func prepare() -> Bool {
        guard state == .pending, residences.canStage() else { return false }
        if retirements.isEmpty == false {
            guard runtimeConnection.accepts(runtimeLease),
                  let runtime = runtimeLease.registry,
                  retirementWindowsAreCurrent(in: runtime) else { return false }
            preparedRuntime = runtime
        }
        guard residences.canStage() else { return false }
        state = .prepared
        return true
    }

    func canStage() -> Bool {
        state == .prepared
            && residences.canStage()
            && (retirements.isEmpty
                || (runtimeConnection.accepts(runtimeLease)
                    && preparedRuntime.map(retirementWindowsAreCurrent) == true))
    }

    var requiresRetirementBatch: Bool {
        retirements.contains {
            $0.entry.tab.webViewSession.allKnownWebViews.isEmpty == false
        }
    }

    func beginRetirement(
        modelTransaction: WebViewRetirementModelTransactionReceipt
    ) -> SpaceProfileRetirementBeginOutcome {
        guard canStage(), requiresRetirementBatch,
              let runtime = preparedRuntime else { return .rejected }
        switch runtimeTeardown.retirement.begin(
            tabs: retirements.map(\.entry.tab),
            using: runtime,
            modelTransaction: modelTransaction
        ) {
        case .began(let batch):
            retirementBatch = batch
            guard state == .staged else { return .rejected }
            return .modelCommitted
        case .terminallyDrained:
            guard state == .staged else { return .rejected }
            return .terminallyDrainedModelCommitted
        case .modelValidationFailed, .rejected:
            return .rejected
        }
    }

    func stageModel() -> Bool {
        guard canStage(), residences.commit() else { return false }
        state = .staged
        return true
    }

    func publishStagedModel() {
        precondition(state == .staged)
        residences.publish()
    }

    func canRollbackModel() -> Bool {
        state == .staged && residences.canRollback()
    }

    func rollbackModel() -> Bool {
        guard canRollbackModel(), residences.rollback() else { return false }
        state = .terminal
        return true
    }

    func publishRolledBackModel() {
        precondition(state == .terminal)
        residences.publish()
    }

    func rollbackRetirement() -> TabRuntimeRetirementRollbackOutcome? {
        guard let retirementBatch else { return nil }
        let outcome = runtimeTeardown.retirement.rollback(retirementBatch)
        if outcome == .rolledBack {
            self.retirementBatch = nil
        }
        return outcome
    }

    func stagedModelIsExact() -> Bool {
        state == .staged && residences.isCurrentStaged()
    }

    func canCommitRetirement() -> Bool {
        guard stagedModelIsExact() else { return false }
        if let retirementBatch {
            return runtimeTeardown.retirement.canCommit(retirementBatch)
        }
        guard retirements.isEmpty == false else { return true }
        return preparedRuntime?.webViewLifecycle
            .canRetireTabWebViews(retirements.map(\.entry.tab)) == true
            && retirements.allSatisfy {
                $0.entry.tab.webViewSession.allKnownWebViews.isEmpty
            }
    }

    func commitRetirement() -> SpaceProfileRetirementCommitOutcome {
        guard state == .staged else { return .conflict }
        if let retirementBatch {
            switch runtimeTeardown.retirement.commit(retirementBatch) {
            case .committed(let committed):
                return .committed(.committed(committed))
            case .noLongerActive:
                return .terminallyDrained
            case .conflict:
                return .conflict
            }
        }
        guard retirements.isEmpty == false else {
            return .committed(.none)
        }
        guard let runtime = preparedRuntime,
              retirements.allSatisfy({
                  $0.entry.tab.webViewSession.allKnownWebViews.isEmpty
              }) else {
            return .conflict
        }
        return .committed(.empty(PreparedTabRuntimeTeardown(
            tabs: TabRuntimeTeardownPreparationService.orderedUnique(
                retirements.map(\.entry.tab)
            ),
            runtime: runtime
        )))
    }

    func canFinishModel() -> Bool {
        state == .staged
    }

    func finishPrevalidatedModel() {
        precondition(canFinishModel())
        state = .terminal
    }

    func settleTerminalModelAfterDrain() {
        retirementBatch = nil
        state = .terminal
    }

    func publishTerminalEffects(
        _ receipt: SpaceProfilePresentationTerminalEffectReceipt
    ) {
        precondition(state == .terminal)
        let expectedTabIDs = Set(retirements.map(\.entry.tab.id))
        terminalPublisher.publish(
            receipt,
            expectedTabIDs: expectedTabIDs,
            canPublishNormally: { [runtimeConnection, runtimeLease] in
                runtimeConnection.accepts(runtimeLease)
            }
        ) { [self] runtime in
            guard let runtime else { return }
            reconcileRetiredSelections(using: runtime)
        }
    }

    func settleTerminalDrain(
        _ receipt: SpaceProfilePresentationTerminalEffectReceipt
    ) {
        precondition(state == .terminal)
        receipt.claimDrain { [runtimeTeardown] effects in
            guard case .committed(let committed) = effects else { return }
            runtimeTeardown.retirement.destroyAfterTerminalDrain(committed)
        }
    }

    private func reconcileRetiredSelections(using runtime: RuntimePortRegistry) {
        var result = ShortcutLiveTabRetirementResult()
        for retirement in retirements {
            let entry = retirement.entry
            guard runtime.windowState(for: entry.windowId)
                === retirement.window else { continue }
            let windowState = retirement.window
            result.merge(ShortcutSelectionReconciler.reconcileRetiredInstance(
                pinId: entry.pinId,
                tabId: entry.tab.id,
                in: windowState
            ))
        }
        let validatedWindowIDs = result.didClearCurrentSelection
            ? runtime.validateWindowStates()
            : []
        for windowState in result.windowStatesNeedingPersistence
            where validatedWindowIDs.contains(windowState.id) == false {
            runtime.persistWindowSession(for: windowState)
        }
    }

    private func retirementWindowsAreCurrent(
        in runtime: RuntimePortRegistry
    ) -> Bool {
        retirements.allSatisfy { retirement in
            runtime.windowState(for: retirement.entry.windowId)
                === retirement.window
        }
    }
}
