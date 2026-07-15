import Foundation
import SumiWebRuntime

/// One exact Space/profile model transaction. It retains pending and staged
/// physical participants until the shared WebView replacement pipeline settles.
@MainActor
final class SpaceProfileTransaction {
    private struct TabParticipant {
        let tab: Tab
        let intent: DeferredWebViewSpaceProfileTabIntent
    }

    enum State: Equatable {
        case pending
        case staged
        case retainedCleanupConflict
        case terminal
    }

    let intent: DeferredWebViewSpaceProfileAssignmentIntent
    private let profileMutation: SpaceProfileMutationTransaction
    private let tabParticipants: [TabParticipant]
    private let membership: TabCollectionMembershipOwner
    private let structuralLookup: TabStructuralLookupCoordinator
    private var terminalEffects: SpaceProfilePresentationTerminalEffectReceipt?
    private(set) var state: State = .pending

    init?(
        intent: DeferredWebViewSpaceProfileAssignmentIntent,
        tabs: [Tab],
        profileMutation: SpaceProfileMutationTransaction,
        membership: TabCollectionMembershipOwner,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        guard profileMutation.spaceID == intent.spaceID,
              profileMutation.expectedProfileID == intent.expectedProfileID,
              profileMutation.targetProfileID == intent.desiredProfileID,
              tabs.count == intent.tabIntents.count else { return nil }
        var seen: Set<UUID> = []
        var participants: [TabParticipant] = []
        for (tab, tabIntent) in zip(tabs, intent.tabIntents) {
            guard tab.id == tabIntent.tabID,
                  tab.spaceId == intent.spaceID,
                  seen.insert(tab.id).inserted,
                  tab.profileAssignment.isCurrent(tabIntent.intent) else {
                return nil
            }
            participants.append(TabParticipant(tab: tab, intent: tabIntent))
        }
        self.intent = intent
        self.profileMutation = profileMutation
        tabParticipants = participants
        self.membership = membership
        self.structuralLookup = structuralLookup
    }

    var desiredProfileID: UUID { intent.desiredProfileID }

    /// Hands the WebView runtime the exact retained participants. The runtime
    /// must never re-resolve these identities through a UUID index because a
    /// later same-ID object is not part of this transaction.
    func exactParticipantTabs(revision: UInt64) -> [Tab]? {
        guard isCurrentPending(revision: revision) else { return nil }
        return tabParticipants.map(\.tab)
    }

    func isCurrentPending(revision: UInt64) -> Bool {
        guard state == .pending,
              revision == intent.revision,
              profileMutation.isCurrentPending(),
              exactTabResidencesAreCurrent() else {
            return false
        }
        return tabParticipants.allSatisfy {
            $0.tab.profileAssignment.isCurrent($0.intent.intent)
                && navigationIsCurrent($0)
        }
    }

    @discardableResult
    func stage(revision: UInt64) -> Bool {
        guard isCurrentPending(revision: revision),
              profileMutation.prepare() else { return false }
        guard profileMutation.requiresRetirementBatch else {
            guard commitModel(revision: revision) else { return false }
            publishStagedModel()
            return true
        }
        let modelTransaction = WebViewRetirementModelTransactionReceipt(
            isCurrent: { [weak self] in
                self?.isCurrentPending(revision: revision) == true
                    && self?.profileMutation.prepare() == true
            },
            commit: { [weak self] in
                self?.commitModel(revision: revision) == true
            },
            rollback: { [weak self] in
                self?.rollbackModel() == true
            }
        )
        switch profileMutation.beginRetirement(
            modelTransaction: modelTransaction
        ) {
        case .modelCommitted:
            guard state == .staged else { return false }
            publishStagedModel()
            return true
        case .terminallyDrainedModelCommitted:
            if rollbackModel() == false {
                state = .retainedCleanupConflict
            }
            return false
        case .modelConflict(let batch):
            return settleFailedRetirementStage(batch)
        case .notRequired, .rejected:
            return false
        }
    }

    func stagedModelIsExact() -> Bool {
        state == .staged
            && profileMutation.stagedModelIsExact()
            && exactTabResidencesAreCurrent()
            && tabParticipants.allSatisfy {
                $0.tab.profileAssignment.isCurrentStaged($0.intent.intent)
                    && navigationIsCurrent($0)
            }
    }

    func canSealCommit() -> Bool {
        stagedModelIsExact()
            && canFinishStagedModel()
            && profileMutation.canCommitRetirement()
    }

    func sealCommit() -> WebViewReplacementTerminalModelClaimOutcome {
        guard canSealCommit(), profileMutation.claimTerminalModel() else {
            return .terminallyDrained
        }
        switch profileMutation.commitRetirement() {
        case .committed(let effects):
            let receipt = SpaceProfilePresentationTerminalEffectReceipt.normal(
                effects
            )
            terminalEffects = receipt
            guard profileMutation.commitSilentTerminalModel() else {
                return .terminallyDrained
            }
            finishPrevalidatedStagedModel()
            return .sealed
        case .cleanupRequired(let effects):
            terminalEffects = SpaceProfilePresentationTerminalEffectReceipt.drainOnly(
                effects
            )
            guard profileMutation.commitSilentTerminalModel() else {
                return .terminallyDrained
            }
            finishPrevalidatedStagedModel()
            return .terminallyDrained
        case .terminallyDrained:
            profileMutation.cancelTerminalModelClaim()
            finishPrevalidatedStagedModel()
            return .terminallyDrained
        case .conflict:
            return .terminallyDrained
        }
    }

    func claimedModelIsExact() -> Bool {
        state == .terminal
            && profileMutation.claimedModelIsExact()
            && exactTabResidencesAreCurrent()
            && tabParticipants.allSatisfy {
                $0.tab.profileAssignment.isCurrentFinished($0.intent.intent)
                    && navigationIsCurrent($0)
            }
    }

    func publishCommit(onTerminalEffectsConsumed: @escaping () -> Void) {
        guard state == .terminal, let terminalEffects else { return }
        precondition(
            terminalEffects.registerConsumption(onTerminalEffectsConsumed),
            "Space profile terminal effects were published more than once"
        )
        profileMutation.publishTerminalEffects(terminalEffects)
    }

    @discardableResult
    func rollback() -> Bool {
        guard canRollbackModel() else { return false }
        if let outcome = profileMutation.rollbackRetirement() {
            return outcome == .rolledBack && state == .terminal
        }
        return rollbackModel()
    }

    /// A terminal repository drain owns every WebView generation and prevents
    /// the outer settlement from reporting commit or rollback. Settle the exact
    /// retained model witnesses without resolving replacement objects by UUID.
    func canSettleTerminalDrain() -> Bool {
        switch state {
        case .pending, .terminal:
            return true
        case .staged, .retainedCleanupConflict:
            return tabParticipants.allSatisfy {
                $0.tab.profileAssignment.canSettleTerminalDrain(
                    $0.intent.intent
                )
            }
        }
    }

    @discardableResult
    func settleTerminalDrain() -> Bool {
        guard canSettleTerminalDrain() else { return false }
        switch state {
        case .pending:
            abortPending()
            return state == .terminal
        case .staged:
            structuralLookup.withTransaction { [self] in
                for participant in tabParticipants {
                    precondition(participant.tab.profileAssignment
                        .settleTerminalDrain(participant.intent.intent))
                }
                profileMutation.settleTerminalModelAfterDrain()
            }
            let effects = terminalEffects
            state = .terminal
            if let effects {
                profileMutation.settleTerminalDrain(effects)
            }
            return true
        case .retainedCleanupConflict:
            structuralLookup.withTransaction { [self] in
                for participant in tabParticipants {
                    precondition(participant.tab.profileAssignment
                        .settleTerminalDrain(participant.intent.intent))
                }
                profileMutation.settleTerminalModelAfterDrain()
            }
            let effects = terminalEffects
            state = .terminal
            if let effects {
                profileMutation.settleTerminalDrain(effects)
            }
            return true
        case .terminal:
            if let terminalEffects {
                profileMutation.settleTerminalDrain(terminalEffects)
            }
            return true
        }
    }

    func publishRolledBackModel() {
        guard state == .terminal else { return }
        structuralLookup.withTransaction {
            profileMutation.publishRolledBackModel()
        }
    }

    private func publishStagedModel() {
        guard state == .staged else { return }
        structuralLookup.withTransaction {
            profileMutation.publishStagedModel()
        }
    }

    @discardableResult
    private func commitModel(revision: UInt64) -> Bool {
        guard isCurrentPending(revision: revision) else { return false }
        var compensated = false
        let didStage = structuralLookup.withTransaction { [self] in
            guard profileMutation.stageModel() else {
                return false
            }
            var stagedParticipants: [TabParticipant] = []
            for participant in tabParticipants {
                guard participant.tab.profileAssignment.stage(
                    participant.intent.intent
                ) else {
                    var restoredTabs = true
                    for staged in stagedParticipants.reversed()
                        where staged.tab.profileAssignment.rollback(
                            staged.intent.intent
                        ) == false {
                        restoredTabs = false
                    }
                    tabParticipants.forEach {
                        $0.tab.profileAssignment.abort($0.intent.intent)
                    }
                    let profileRestored = profileMutation.rollbackModel()
                    compensated = restoredTabs && profileRestored
                    return false
                }
                stagedParticipants.append(participant)
            }
            return true
        }
        if didStage {
            state = .staged
        } else if compensated {
            state = .terminal
        } else if state == .pending {
            let modelRemainedPending = isCurrentPending(revision: revision)
            if modelRemainedPending == false {
                state = .retainedCleanupConflict
            }
        }
        return didStage
    }

    private func settleFailedRetirementStage(
        _ batch: TabRuntimeRetirementBatch
    ) -> Bool {
        let outcome: SpaceProfileRetirementModelConflictOutcome
        switch state {
        case .pending, .terminal:
            outcome = profileMutation
                .settleCompensatedRetirementModelConflict(batch)
        case .retainedCleanupConflict, .staged:
            outcome = profileMutation
                .settleRetainedRetirementModelConflict(batch)
        }
        switch outcome {
        case .restored:
            return false
        case .cleanupRequired(let ownership):
            terminalEffects = SpaceProfilePresentationTerminalEffectReceipt.drainOnly(
                .committed(ownership)
            )
            state = .retainedCleanupConflict
            return false
        case .terminallyDrained:
            guard settleFailedModelAfterRepositoryDrain() else {
                state = .retainedCleanupConflict
                return false
            }
            return false
        }
    }

    private func settleFailedModelAfterRepositoryDrain() -> Bool {
        guard tabParticipants.allSatisfy({
            $0.tab.profileAssignment.canSettleTerminalDrain($0.intent.intent)
        }) else { return false }
        structuralLookup.withTransaction { [self] in
            tabParticipants.forEach {
                precondition($0.tab.profileAssignment
                    .settleTerminalDrain($0.intent.intent))
            }
            profileMutation.settleTerminalModelAfterDrain()
        }
        state = .terminal
        return true
    }

    private func canRollbackModel() -> Bool {
        state == .staged
            && profileMutation.canRollbackModel()
            && tabParticipants.allSatisfy {
                $0.tab.profileAssignment.isCurrentStaged($0.intent.intent)
            }
    }

    @discardableResult
    private func rollbackModel() -> Bool {
        guard canRollbackModel() else { return false }
        let didRollback = structuralLookup.withTransaction { [self] in
            guard profileMutation.rollbackModel() else { return false }
            var result = true
            for participant in tabParticipants
                where participant.tab.profileAssignment.rollback(
                    participant.intent.intent
                ) == false {
                result = false
            }
            return result
        }
        if didRollback {
            state = .terminal
        }
        return didRollback
    }

    private func canFinishStagedModel() -> Bool {
        state == .staged
            && profileMutation.canFinishModel()
            && tabParticipants.allSatisfy {
                $0.tab.profileAssignment.isCurrentStaged($0.intent.intent)
            }
    }

    private func finishPrevalidatedStagedModel() {
        precondition(canFinishStagedModel())
        structuralLookup.withTransaction { [self] in
            for participant in tabParticipants {
                precondition(participant.tab.profileAssignment.finish(
                    participant.intent.intent
                ))
            }
            profileMutation.finishPrevalidatedModel()
        }
        state = .terminal
    }

    func abortPending() {
        guard state == .pending else { return }
        tabParticipants.forEach {
            $0.tab.profileAssignment.abort($0.intent.intent)
        }
        state = .terminal
    }

    private func exactTabResidencesAreCurrent() -> Bool {
        var currentTabsByID: [UUID: Tab] = [:]
        for tab in membership.allIdentityWitnesses() {
            guard currentTabsByID.updateValue(tab, forKey: tab.id) == nil else {
                return false
            }
        }
        return tabParticipants.allSatisfy { participant in
            currentTabsByID[participant.tab.id] === participant.tab
                && participant.tab.spaceId == intent.spaceID
        }
    }

    private func navigationIsCurrent(_ participant: TabParticipant) -> Bool {
        let current = participant.tab.mainFrameLoads.currentIntent
        return current.revision == participant.intent.intent.navigationRevision
            && current.targetURL == participant.intent.intent.targetURL
    }
}
