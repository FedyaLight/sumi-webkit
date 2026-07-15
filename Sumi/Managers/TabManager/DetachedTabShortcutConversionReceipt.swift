import SumiWebRuntime

/// Concrete prepared transaction for a detached regular-tab conversion. The
/// retirement lease, committed runtime evidence, reconciled windows, and
/// exact source admission live in one enum state instead of a mutable bag
/// shared by callback slots.
@MainActor
final class DetachedTabShortcutConversionReceipt {
    private enum State {
        case preparing
        case retirementModelStaged
        case staged(TabRuntimeRetirementBatch?)
        case runtimeSealed(CommittedTabRuntimeRetirement?)
        case modelSettled(
            CommittedTabRuntimeRetirement?,
            [BrowserWindowState]
        )
        case published
        case rolledBack
    }

    private let tab: Tab
    private let sourceSpaceID: UUID
    private let transition: RegularTabShortcutWindowTransitionPlan
    private let runtime: RuntimePortRegistry?
    private let participants: RegularTabShortcutCommitParticipants
    private let regularTabs: RegularTabCollectionOwner
    private let containerRemoval: ShortcutContainerRemovalOwner
    private let membership: TabCollectionMembershipOwner
    private let selection: TabSelectionStateOwner
    private let structuralLookup: TabStructuralLookupCoordinator
    private let runtimeTeardown: TabRuntimeTeardownService
    private let windowReconciler: RegularTabShortcutWindowReconciler
    private var state = State.preparing

    init?(
        transition: RegularTabShortcutWindowTransitionPlan,
        authorization: AuthorizedDetachedTabShortcutConversion,
        participants: RegularTabShortcutCommitParticipants,
        regularTabs: RegularTabCollectionOwner,
        containerRemoval: ShortcutContainerRemovalOwner,
        membership: TabCollectionMembershipOwner,
        selection: TabSelectionStateOwner,
        structuralLookup: TabStructuralLookupCoordinator,
        runtimeTeardown: TabRuntimeTeardownService,
        windowReconciler: RegularTabShortcutWindowReconciler
    ) {
        guard let sourceSpaceID = authorization.tab.spaceId else { return nil }
        tab = authorization.tab
        self.sourceSpaceID = sourceSpaceID
        self.transition = transition
        runtime = authorization.runtime
        self.participants = participants
        self.regularTabs = regularTabs
        self.containerRemoval = containerRemoval
        self.membership = membership
        self.selection = selection
        self.structuralLookup = structuralLookup
        self.runtimeTeardown = runtimeTeardown
        self.windowReconciler = windowReconciler
        guard stageRetirement() else { return nil }
    }

    func isCurrent() -> Bool {
        guard case .staged(let batch) = state,
              sourceAndParticipantsAreCurrent() else { return false }
        if let batch {
            return runtimeTeardown.retirement.canCommit(batch)
        }
        return tab.webViewSession.allKnownWebViews.isEmpty
    }

    func sealRuntime() -> Bool {
        guard case .staged(let batch) = state, isCurrent() else { return false }
        guard let batch else {
            state = .runtimeSealed(nil)
            return true
        }
        switch runtimeTeardown.retirement.commit(batch) {
        case .committed(let committed):
            state = .runtimeSealed(committed)
            return true
        case .noLongerActive, .conflict:
            return false
        }
    }

    func settleModel() {
        guard case .runtimeSealed(let committed) = state else {
            preconditionFailure("Detached conversion runtime was not sealed")
        }
        containerRemoval.removeFromCurrentContainer(tab)
        if runtime == nil { membership.detach(tab) }
        if selection.currentTab === tab {
            selection.replaceCurrentTab(nil)
        }
        let changedWindows = runtime.map {
            windowReconciler.reconcile(
                originalTabId: tab.id,
                splitTransition: transition,
                sourceSpaceId: sourceSpaceID,
                liveTabsByWindowId: [:],
                selectedWindowIds: [],
                using: $0
            )
        } ?? []
        state = .modelSettled(committed, changedWindows)
    }

    func rollback() -> Bool {
        guard case .staged(let batch) = state else { return false }
        if let batch,
           runtimeTeardown.retirement.rollback(batch) != .rolledBack {
            return false
        }
        state = .rolledBack
        return true
    }

    func publish() {
        guard case .modelSettled(let committed, let changedWindows) = state else {
            return
        }
        state = .published
        guard let runtime else { return }
        structuralLookup.runAfterCurrentBatch { [self] in
            let retiredIDs: Set<UUID>
            if let committed {
                retiredIDs = runtimeTeardown.retirement.publish(committed)
            } else {
                retiredIDs = runtimeTeardown.finish(
                    PreparedTabRuntimeTeardown(tabs: [tab], runtime: runtime)
                )
            }
            precondition(retiredIDs == [tab.id])
            changedWindows.forEach(runtime.persistWindowSession(for:))
        }
    }

    private func stageRetirement() -> Bool {
        let hasLiveWebViews = tab.webViewSession.allKnownWebViews.isEmpty == false
        if let runtime, hasLiveWebViews {
            let model = WebViewRetirementModelTransactionReceipt(
                isCurrent: { [weak self] in
                    self?.sourceAndParticipantsAreCurrent() == true
                },
                commit: { [weak self] in
                    guard let self, case .preparing = state else {
                        preconditionFailure("Detached retirement model restaged")
                    }
                    state = .retirementModelStaged
                },
                rollback: { [weak self] in
                    guard let self,
                          case .retirementModelStaged = state else { return }
                    state = .preparing
                }
            )
            guard case .began(let batch) = runtimeTeardown.retirement.begin(
                tabs: [tab],
                using: runtime,
                modelTransaction: model
            ), case .retirementModelStaged = state else { return false }
            state = .staged(batch)
            return true
        }
        guard hasLiveWebViews == false else { return false }
        if let runtime,
           runtime.webViewLifecycle.canRetireTabWebViews([tab]) == false {
            return false
        }
        guard sourceAndParticipantsAreCurrent() else { return false }
        state = .staged(nil)
        return true
    }

    private func sourceAndParticipantsAreCurrent() -> Bool {
        regularTabs.containsIdentical(tab, in: sourceSpaceID)
            && membership.tab(for: tab.id) === tab
            && tab.spaceId == sourceSpaceID
            && tab.isShortcutLiveInstance == false
            && participants.isCurrent()
    }
}
