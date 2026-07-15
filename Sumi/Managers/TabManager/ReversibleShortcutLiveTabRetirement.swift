import Foundation
import SumiWebRuntime

/// Reversible retirement used when shortcut residence and another structural
/// owner must commit together. A WebView generation is quarantined before the
/// exact residence is removed. Physical destruction and residence publication
/// remain terminal effects owned by the enclosing structural transaction.
@MainActor
final class ReversibleShortcutLiveTabRetirement:
    BrowserWindowShortcutAggregateParticipant {
    private enum State {
        case pending
        case residenceStaged
        case staged(RuntimeStage)
        case runtimeSealed(TerminalEffect)
        case windowSettled(TerminalEffect)
        case terminal
        case rolledBack
    }

    private enum RuntimeStage {
        case none
        case empty(PreparedTabRuntimeTeardown)
        case leased(TabRuntimeRetirementBatch)
    }

    private enum TerminalEffect {
        case none
        case empty(PreparedTabRuntimeTeardown)
        case committed(CommittedTabRuntimeRetirement)
        case terminallyDrained(Set<UUID>)
    }

    private let pinID: UUID
    private let windowID: UUID
    private let entry: LiveShortcutTabEntry?
    private let registry: LiveShortcutTabRegistry
    private let runtimeConnection: TabRuntimePortConnection
    private let runtimeLease: TabRuntimePortLease
    private let runtimeTeardown: TabRuntimeTeardownService
    private let windowState: BrowserWindowState?
    private let expectedWindowState: BrowserWindowShortcutMutationState?
    private let targetWindowState: BrowserWindowShortcutMutationState?
    private let result: ShortcutLiveTabRetirementResult
    private var residenceChange: LiveShortcutResidenceMutationStaging.Change?
    private var preparedResult: PreparedShortcutLiveTabRetirement?
    private var state = State.pending

    init?(
        pinID: UUID,
        windowID: UUID,
        registry: LiveShortcutTabRegistry,
        runtimeConnection: TabRuntimePortConnection,
        runtimeTeardown: TabRuntimeTeardownService
    ) {
        let entry = registry.entries(in: windowID).first {
            $0.pinId == pinID
        }
        let runtimeLease = runtimeConnection.captureLease()
        if entry != nil, runtimeLease.registry == nil { return nil }

        self.pinID = pinID
        self.windowID = windowID
        self.entry = entry
        self.registry = registry
        self.runtimeConnection = runtimeConnection
        self.runtimeLease = runtimeLease
        self.runtimeTeardown = runtimeTeardown

        let windowState = entry.flatMap {
            runtimeLease.windowState(for: $0.windowId)
        }
        self.windowState = windowState
        let expectedWindowState = windowState?.unpublishedShortcutMutationState
        self.expectedWindowState = expectedWindowState
        if let entry, let windowState, var target = expectedWindowState {
            let didClear: Bool
            if let currentTabID = target.currentTabId {
                didClear = currentTabID == entry.tab.id
                    || currentTabID == entry.pinId
            } else {
                didClear = target.currentShortcutPinId == entry.pinId
            }
            if target.currentTabId == entry.tab.id
                || target.currentTabId == entry.pinId {
                target.currentTabId = nil
            }
            if target.currentShortcutPinId == entry.pinId {
                target.currentShortcutPinId = nil
                target.currentShortcutPinRole = nil
            }
            targetWindowState = target
            result = ShortcutLiveTabRetirementResult(
                retiredTabIds: [entry.tab.id],
                didClearCurrentSelection: didClear,
                windowStatesNeedingPersistence: target == expectedWindowState
                    ? []
                    : [windowState]
            )
        } else {
            targetWindowState = expectedWindowState
            result = ShortcutLiveTabRetirementResult(
                retiredTabIds: entry.map { [$0.tab.id] } ?? []
            )
        }
    }

    func begin() -> Bool {
        guard case .pending = state else { return false }
        guard let entry else {
            guard registry.tab(for: pinID, in: windowID) == nil else {
                return false
            }
            state = .staged(.none)
            return true
        }
        guard canStageResidenceModel(),
              let runtime = runtimeLease.registry else { return false }

        if entry.tab.webViewSession.allKnownWebViews.isEmpty {
            guard runtime.webViewLifecycle.canRetireTabWebViews([entry.tab])
            else { return false }
            stageResidenceModel()
            state = .staged(.empty(PreparedTabRuntimeTeardown(
                tabs: [entry.tab],
                runtime: runtime
            )))
            return true
        }

        let model = WebViewRetirementModelTransactionReceipt(
            isCurrent: { [weak self] in
                self?.canStageResidenceModel() == true
            },
            commit: { [weak self] in
                self?.stageResidenceModel()
            },
            rollback: { [weak self] in
                self?.rollbackResidenceModel()
            }
        )
        switch runtimeTeardown.retirement.begin(
            tabs: [entry.tab],
            using: runtime,
            modelTransaction: model
        ) {
        case .began(let batch):
            guard case .residenceStaged = state else {
                preconditionFailure(
                    "Shortcut retirement lease lost its exact model commit"
                )
            }
            state = .staged(.leased(batch))
            return true
        case .terminallyDrained:
            guard case .residenceStaged = state else { return false }
            precondition(
                rollbackResidenceModel(),
                "Terminally drained shortcut retirement lost model rollback"
            )
            return false
        case .modelValidationFailed, .rejected:
            return false
        }
    }

    func isCurrent() -> Bool {
        guard case .staged(let runtimeStage) = state,
              stagedResidenceIsExact(),
              windowIsCurrent() else { return false }
        switch runtimeStage {
        case .none:
            return true
        case .empty(let prepared):
            return prepared.tabs.allSatisfy {
                $0.webViewSession.allKnownWebViews.isEmpty
            } && prepared.runtime.webViewLifecycle
                .canRetireTabWebViews(prepared.tabs)
        case .leased(let batch):
            return runtimeTeardown.retirement.canCommit(batch)
        }
    }

    /// Seals the reversible runtime lease only after launcher placement and
    /// residence evidence have both been staged and revalidated.
    func sealRuntime() -> Bool {
        guard isCurrent(), case .staged(let runtimeStage) = state else {
            return false
        }
        let effect: TerminalEffect
        switch runtimeStage {
        case .none:
            effect = .none
        case .empty(let prepared):
            effect = .empty(prepared)
        case .leased(let batch):
            switch runtimeTeardown.retirement.commit(batch) {
            case .committed(let committed):
                effect = .committed(committed)
            case .noLongerActive:
                effect = .terminallyDrained(batch.runtimeTabIDs)
            case .conflict:
                return false
            }
        }
        state = .runtimeSealed(effect)
        return true
    }

    func isCurrentForWindowSettlement() -> Bool {
        guard case .runtimeSealed = state else { return false }
        return stagedResidenceIsExact() && windowIsCurrent()
    }

    func settleAdmittedWindowModel(
        using owner: BrowserWindowShortcutMutationOwner
    ) {
        guard case .runtimeSealed(let effect) = state,
              isCurrentForWindowSettlement() else {
            preconditionFailure(
                "Shortcut retirement window model was not admitted"
            )
        }
        if let windowState,
           let targetWindowState,
           targetWindowState != expectedWindowState {
            owner.stage(windowState) { $0 = targetWindowState }
        }
        state = .windowSettled(effect)
    }

    func rollback() -> Bool {
        guard case .staged(let runtimeStage) = state else { return false }
        switch runtimeStage {
        case .leased(let batch):
            return runtimeTeardown.retirement.rollback(batch) == .rolledBack
                && isRolledBack
        case .none, .empty:
            return rollbackResidenceModel()
        }
    }

    func publishAdmittedModel() {
        guard case .windowSettled(let effect) = state else {
            preconditionFailure("Shortcut retirement window model was not settled")
        }
        state = .terminal
        if let residenceChange {
            registry.staging.publish([residenceChange])
        }
        let tabs = entry.map { [$0.tab] } ?? []
        switch effect {
        case .none:
            preparedResult = PreparedShortcutLiveTabRetirement(
                tabs: tabs,
                runtime: runtimeLease.registry,
                result: result
            )
        case .empty(let prepared):
            preparedResult = PreparedShortcutLiveTabRetirement(
                tabs: tabs,
                runtime: prepared.runtime,
                runtimeTeardown: prepared,
                result: result
            )
        case .committed(let committed):
            preparedResult = PreparedShortcutLiveTabRetirement(
                tabs: tabs,
                runtime: committed.runtime,
                committedRuntimeRetirement: committed,
                result: result
            )
        case .terminallyDrained(let tabIDs):
            preparedResult = PreparedShortcutLiveTabRetirement(
                tabs: tabs,
                runtime: runtimeLease.registry,
                terminallyDrainedTabIDs: tabIDs,
                result: result
            )
        }
    }

    func takePreparedResult() -> PreparedShortcutLiveTabRetirement {
        guard case .terminal = state, let preparedResult else {
            preconditionFailure("Shortcut retirement was not published")
        }
        self.preparedResult = nil
        return preparedResult
    }

    private var isRolledBack: Bool {
        if case .rolledBack = state { return true }
        return false
    }

    private func canStageResidenceModel() -> Bool {
        guard case .pending = state,
              let entry,
              runtimeConnection.accepts(runtimeLease),
              registry.entry(containing: entry.tab)?
                .isIdentical(to: entry) == true else { return false }
        return windowIsCurrent()
    }

    private func stageResidenceModel() {
        guard canStageResidenceModel(), let entry,
              let change = registry.staging.remove(entry) else {
            preconditionFailure(
                "Admitted shortcut retirement lost exact residence"
            )
        }
        residenceChange = change
        state = .residenceStaged
    }

    @discardableResult
    private func rollbackResidenceModel() -> Bool {
        switch state {
        case .residenceStaged, .staged:
            break
        default:
            return false
        }
        if let residenceChange,
           registry.staging.rollback([residenceChange]) == false {
            return false
        }
        state = .rolledBack
        return true
    }

    private func stagedResidenceIsExact() -> Bool {
        guard runtimeConnection.accepts(runtimeLease) else { return false }
        if let residenceChange {
            return registry.staging.canPublish([residenceChange])
        }
        return registry.tab(for: pinID, in: windowID) == nil
    }

    private func windowIsCurrent() -> Bool {
        guard let entry else { return true }
        guard runtimeLease.windowState(for: entry.windowId) === windowState else {
            return false
        }
        return windowState?.unpublishedShortcutMutationState
            == expectedWindowState
    }
}
