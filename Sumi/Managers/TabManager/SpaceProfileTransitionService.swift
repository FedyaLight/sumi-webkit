import Foundation
import SumiWebRuntime

/// Owns one Space/profile transaction, including every inherited Tab intent,
/// until the shared WebView replacement pipeline settles it.
@MainActor
final class SpaceProfileTransitionService {
    private struct SettlementObserver {
        let revision: UInt64
        let callback: ProfileTransitionService.Settlement
    }

    private unowned let tabManager: TabManager
    private let pendingInheritance: PendingTabProfileInheritance
    private let admission: SpaceProfileTransitionAdmission
    private var revisionBySpaceID: [UUID: UInt64] = [:]
    private var transactionsBySpaceID: [UUID: SpaceProfileTransaction] = [:]
    private var observersBySpaceID: [UUID: SettlementObserver] = [:]

    init(
        tabManager: TabManager,
        pendingInheritance: PendingTabProfileInheritance,
        admission: SpaceProfileTransitionAdmission
    ) {
        self.tabManager = tabManager
        self.pendingInheritance = pendingInheritance
        self.admission = admission
    }

    @discardableResult
    func assign(
        spaceID: UUID,
        toProfile profileID: UUID
    ) -> TabProfileAssignmentExecutionOutcome {
        start(spaceID: spaceID, profileID: profileID)
    }

    @discardableResult
    func start(
        spaceID: UUID,
        profileID: UUID,
        settlementObserver: ProfileTransitionService.Settlement? = nil
    ) -> TabProfileAssignmentExecutionOutcome {
        start(
            spaceID: spaceID,
            profileID: profileID,
            intentObserver: nil,
            settlementObserver: settlementObserver
        )
    }

    @discardableResult
    func start(
        spaceID: UUID,
        profileID: UUID,
        capturingIntent: @escaping (
            DeferredWebViewSpaceProfileAssignmentIntent
        ) -> Void,
        settlementObserver: ProfileTransitionService.Settlement? = nil
    ) -> TabProfileAssignmentExecutionOutcome {
        start(
            spaceID: spaceID,
            profileID: profileID,
            intentObserver: capturingIntent,
            settlementObserver: settlementObserver
        )
    }

    private func start(
        spaceID: UUID,
        profileID: UUID,
        intentObserver: ((DeferredWebViewSpaceProfileAssignmentIntent) -> Void)?,
        settlementObserver: ProfileTransitionService.Settlement?
    ) -> TabProfileAssignmentExecutionOutcome {
        guard let space = tabManager.spaceStateOwner.space(with: spaceID) else {
            return .failed
        }
        if let transaction = transactionsBySpaceID[spaceID] {
            if transaction.state == .pending, space.profileId == profileID {
                cancelPending(spaceID: spaceID)
            }
            return .failed
        }
        guard space.profileId != profileID else { return .committed }
        guard let admitted = admission.admit(
            space: space,
            targetProfileID: profileID
        ) else {
            return .failed
        }
        let tabIntents = admitted.tabCandidates.map { candidate in
            DeferredWebViewSpaceProfileTabIntent(
                tabID: candidate.tab.id,
                intent: candidate.tab.profileAssignment.begin(
                    desiredProfileID: candidate.desiredProfileID,
                    resolvedProfileID: admitted.profile.id,
                    targetURL: admission.targetURL(for: candidate.tab),
                    requiresStructuralPersistence: false
                )
            )
        }
        let revision = (revisionBySpaceID[spaceID] ?? 0) &+ 1
        revisionBySpaceID[spaceID] = revision
        let intent = DeferredWebViewSpaceProfileAssignmentIntent(
            revision: revision,
            spaceID: spaceID,
            expectedProfileID: space.profileId,
            desiredProfileID: profileID,
            tabIntents: tabIntents
        )
        guard let transaction = admission.transaction(
            intent: intent,
            tabs: admitted.tabCandidates.map(\.tab),
            profileMutation: admitted.mutation
        ) else {
            for (candidate, tabIntent) in zip(
                admitted.tabCandidates,
                tabIntents
            ) {
                candidate.tab.profileAssignment.abort(tabIntent.intent)
            }
            return .failed
        }
        transactionsBySpaceID[spaceID] = transaction
        intentObserver?(intent)
        if let settlementObserver {
            observersBySpaceID[spaceID] = SettlementObserver(
                revision: revision,
                callback: settlementObserver
            )
        }

        let outcome = execute(
            space: space,
            profile: admitted.profile,
            intent: intent
        )
        if let settlement = outcome.immediateSettlement,
           observersBySpaceID[spaceID]?.revision == revision {
            receive(settlement, intent: intent)
        }
        return outcome
    }

    @discardableResult
    func executeDeferred(
        _ intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) -> Bool {
        guard isCurrent(intent),
              let space = tabManager.spaceStateOwner.space(
                  with: intent.spaceID
              ),
              let profile = admission.resolvedProfile(intent.desiredProfileID),
              profile.id == intent.desiredProfileID else {
            receive(.rejected(.stale), intent: intent)
            return false
        }
        return execute(space: space, profile: profile, intent: intent)
            .wasAccepted
    }

    func isCurrentDeferred(
        _ intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) -> Bool {
        isCurrent(intent)
    }

    func inFlightProfileID(for spaceID: UUID) -> UUID? {
        guard let transaction = transactionsBySpaceID[spaceID],
              transaction.state != .terminal
        else { return nil }
        return transaction.desiredProfileID
    }

    @discardableResult
    func registerCreationFollower(
        _ tab: Tab,
        in spaceID: UUID,
        profileID: UUID
    ) -> Bool {
        guard let transaction = transactionsBySpaceID[spaceID],
              transaction.state != .terminal,
              transaction.desiredProfileID == profileID,
              tab.profileId == profileID,
              tabIsMember(tab, of: spaceID)
        else { return false }

        pendingInheritance.record(
            tab: tab,
            spaceID: spaceID,
            spaceRevision: transaction.intent.revision,
            inheritedProfileID: profileID
        )
        return true
    }

    func cancelPendingDeletionIntent(
        _ intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) {
        abortPending(intent)
        pendingInheritance.discard(spaceIntent: intent)
        if observersBySpaceID[intent.spaceID]?.revision == intent.revision {
            observersBySpaceID.removeValue(forKey: intent.spaceID)
        }
    }

    private func execute(
        space: Space,
        profile: Profile,
        intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) -> TabProfileAssignmentExecutionOutcome {
        guard let lifecycle = tabManager.runtimePorts?.webViewLifecycle else {
            receive(.rejected(.failed), intent: intent)
            return .failed
        }
        guard let transaction = transaction(for: intent) else {
            receive(.rejected(.stale), intent: intent)
            return .stale
        }
        let model = SpaceProfileReplacementModelParticipant(
            transaction: transaction,
            owner: self,
            intent: intent,
            revision: revisionBySpaceID[intent.spaceID] ?? 0
        )
        return lifecycle.executeSpaceProfileAssignment(
            space: space,
            targetProfile: profile,
            intent: intent,
            model: model,
            settlement: { [weak self] settlement in
                self?.receive(settlement, intent: intent)
            }
        )
    }

    private func isCurrent(
        _ intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) -> Bool {
        guard let transaction = transaction(for: intent) else { return false }
        return transaction.isCurrentPending(
            revision: revisionBySpaceID[intent.spaceID] ?? 0
        )
    }

    private func receive(
        _ settlement: ProfileTransitionSettlement,
        intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) {
        switch settlement {
        case .committed:
            pendingInheritance.spaceTransitionCommitted(
                intent: intent,
                canonicalProfileID: tabManager.spaceStateOwner.profileId(
                    for: intent.spaceID
                ),
                isTabStillInSpace: { [weak tabManager] tab, spaceID in
                    tabManager?.tabCollectionMembershipOwner.allTabs().contains {
                        $0 === tab && $0.spaceId == spaceID
                    } == true
                }
            )
            publishStructuralMutation(spaceID: intent.spaceID)
        case .rejected:
            abortPending(intent)
            pendingInheritance.discard(spaceIntent: intent)
        case .rolledBack:
            pendingInheritance.discard(spaceIntent: intent)
        case .leaseLost, .terminalShutdown:
            if let transaction = transaction(for: intent) {
                if transaction.settleTerminalDrain() {
                    transactionsBySpaceID.removeValue(forKey: intent.spaceID)
                }
            }
            pendingInheritance.discard(spaceIntent: intent)
        case .conflicted:
            break
        }

        guard let observer = observersBySpaceID[intent.spaceID],
              observer.revision == intent.revision else { return }
        observersBySpaceID.removeValue(forKey: intent.spaceID)
        observer.callback(settlement)
    }

    private func abortPending(
        _ intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) {
        guard let transaction = transaction(for: intent) else { return }
        switch transaction.state {
        case .pending:
            transaction.abortPending()
            transactionsBySpaceID.removeValue(forKey: intent.spaceID)
        case .terminal:
            transactionsBySpaceID.removeValue(forKey: intent.spaceID)
        case .staged:
            return
        }
    }

    private func cancelPending(spaceID: UUID) {
        guard let transaction = transactionsBySpaceID[spaceID],
              transaction.state == .pending else { return }
        abortPending(transaction.intent)
        pendingInheritance.discard(spaceIntent: transaction.intent)
    }

    private func transaction(
        for intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) -> SpaceProfileTransaction? {
        guard let transaction = transactionsBySpaceID[intent.spaceID],
              transaction.intent == intent else { return nil }
        return transaction
    }

    func ownsReplacementModel(
        _ candidate: SpaceProfileTransaction,
        intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) -> Bool {
        transaction(for: intent) === candidate
    }

    func replacementModelDidPublishCommit(
        _ candidate: SpaceProfileTransaction,
        intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) {
        guard ownsReplacementModel(candidate, intent: intent) else { return }
        transactionsBySpaceID.removeValue(forKey: intent.spaceID)
    }

    func replacementModelDidPublishRollback(
        _ candidate: SpaceProfileTransaction,
        intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) {
        guard ownsReplacementModel(candidate, intent: intent) else { return }
        transactionsBySpaceID.removeValue(forKey: intent.spaceID)
        publishStructuralMutation(spaceID: intent.spaceID)
    }

    func replacementModelDidSettleTerminalDrain(
        _ candidate: SpaceProfileTransaction,
        intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) {
        if ownsReplacementModel(candidate, intent: intent) {
            transactionsBySpaceID.removeValue(forKey: intent.spaceID)
        }
        pendingInheritance.discard(spaceIntent: intent)
    }

    private func tabIsMember(_ candidate: Tab, of spaceID: UUID) -> Bool {
        tabManager.tabCollectionMembershipOwner.allTabs().contains { tab in
            tab === candidate && tab.spaceId == spaceID
        }
    }

    private func publishStructuralMutation(spaceID: UUID) {
        tabManager.structuralPersistence.markAllSpacesStructurallyDirty()
        tabManager.structuralPersistence.markRegularTabsStructurallyDirty(
            for: spaceID
        )
        tabManager.structuralPersistence.scheduleStructuralPersistence()
        tabManager.structuralLookupCoordinator.requestPublish(scope: .space(spaceID, catalog: true))
    }
}
