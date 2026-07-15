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
                _ = self?.commitModel(revision: revision)
            },
            rollback: { [weak self] in
                _ = self?.rollbackModel()
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
            _ = rollbackModel()
            return false
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
            }
    }

    func canSealCommit() -> Bool {
        stagedModelIsExact()
            && canFinishStagedModel()
            && profileMutation.canCommitRetirement()
    }

    func sealCommit() -> WebViewReplacementTerminalModelClaimOutcome {
        guard canSealCommit() else { return .terminallyDrained }
        switch profileMutation.commitRetirement() {
        case .committed(let effects):
            let receipt = SpaceProfilePresentationTerminalEffectReceipt(effects)
            terminalEffects = receipt
            finishPrevalidatedStagedModel()
            return .sealed
        case .terminallyDrained:
            finishPrevalidatedStagedModel()
            return .terminallyDrained
        case .conflict:
            return .terminallyDrained
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
    @discardableResult
    func settleTerminalDrain() -> Bool {
        switch state {
        case .pending:
            abortPending()
            return state == .terminal
        case .staged:
            guard tabParticipants.allSatisfy({
                $0.tab.profileAssignment.canSettleTerminalDrain(
                    $0.intent.intent
                )
            }) else { return false }
            structuralLookup.withTransaction { [self] in
                for participant in tabParticipants {
                    precondition(participant.tab.profileAssignment
                        .settleTerminalDrain(participant.intent.intent))
                }
                profileMutation.settleTerminalModelAfterDrain()
            }
            state = .terminal
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
            guard profileMutation.stageModel() else { return false }
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
        }
        return didStage
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
}
