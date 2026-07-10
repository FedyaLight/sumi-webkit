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
    private let policy: ProfileAssignmentPolicy
    private var revisionBySpaceID: [UUID: UInt64] = [:]
    private var transactionsBySpaceID: [UUID: SpaceProfileTransaction] = [:]
    private var observersBySpaceID: [UUID: SettlementObserver] = [:]

    init(tabManager: TabManager, policy: ProfileAssignmentPolicy) {
        self.tabManager = tabManager
        self.policy = policy
    }

    func assign(spaceID: UUID, toProfile profileID: UUID) {
        _ = start(spaceID: spaceID, profileID: profileID)
    }

    @discardableResult
    func start(
        spaceID: UUID,
        profileID: UUID,
        intentPrepared: (DeferredWebViewSpaceProfileAssignmentIntent) -> Void = { _ in },
        settlementObserver: ProfileTransitionService.Settlement? = nil
    ) -> TabProfileAssignmentExecutionOutcome {
        guard let space = tabManager.spaceStateOwner.space(with: spaceID) else {
            return .failed
        }
        guard policy.profileExists(profileID) else {
            RuntimeDiagnostics.emit(
                "⚠️ [TabManager] Attempted to assign space to unknown profile: \(profileID)"
            )
            return .failed
        }
        if let transaction = transactionsBySpaceID[spaceID] {
            if transaction.state == .pending, space.profileId == profileID {
                cancelPending(spaceID: spaceID)
            }
            return .failed
        }
        guard space.profileId != profileID else { return .committed }
        guard let profile = policy.resolvedPlacementProfile(
            profileID: profileID
        ) else { return .failed }

        let tabs = tabsInSpace(spaceID).filter { $0.profileId == nil }
        guard tabs.allSatisfy({ !$0.hasUnsettledProfileAssignment }) else {
            return .failed
        }
        let tabIntents = tabs.map { tab in
            DeferredWebViewSpaceProfileTabIntent(
                tabID: tab.id,
                intent: tab.beginProfileAssignmentIntent(
                    desiredProfileID: nil,
                    resolvedProfileID: profile.id,
                    targetURL: policy.liveDocumentURL(for: tab) ?? tab.url,
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
        transactionsBySpaceID[spaceID] = makeTransaction(intent)
        intentPrepared(intent)
        if let settlementObserver {
            observersBySpaceID[spaceID] = SettlementObserver(
                revision: revision,
                callback: settlementObserver
            )
        }

        let outcome = execute(space: space, profile: profile, intent: intent)
        if let settlement = immediateSettlement(for: outcome),
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
              let profile = policy.resolvedPlacementProfile(
                  profileID: intent.desiredProfileID
              ), profile.id == intent.desiredProfileID else {
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

    func cancelPendingDeletionIntent(
        _ intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) {
        abortPending(intent)
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
        return lifecycle.executeSpaceProfileAssignment(
            space: space,
            targetProfile: profile,
            intent: intent,
            validateModel: { [weak self] in self?.isCurrent(intent) == true },
            modelCommit: { [weak self] in self?.stage(intent) == true },
            modelFinish: { [weak self] in self?.finish(intent) },
            modelRollback: { [weak self] in self?.rollback(intent) },
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

    private func stage(
        _ intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) -> Bool {
        guard let transaction = transaction(for: intent) else { return false }
        return transaction.stage(
            revision: revisionBySpaceID[intent.spaceID] ?? 0
        )
    }

    private func finish(_ intent: DeferredWebViewSpaceProfileAssignmentIntent) {
        guard let transaction = transaction(for: intent) else {
            preconditionFailure("Space profile transaction lost its exact state")
        }
        transaction.finish()
        transactionsBySpaceID.removeValue(forKey: intent.spaceID)
    }

    private func rollback(
        _ intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) {
        guard let transaction = transaction(for: intent) else {
            preconditionFailure("Space profile rollback lost its exact state")
        }
        transaction.rollback()
        transactionsBySpaceID.removeValue(forKey: intent.spaceID)
        publishStructuralMutation()
    }

    private func receive(
        _ settlement: ProfileTransitionSettlement,
        intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) {
        switch settlement {
        case .committed:
            publishStructuralMutation()
        case .rejected:
            abortPending(intent)
        case .rolledBack:
            break
        case .conflicted, .leaseLost, .terminalShutdown:
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
        guard let transaction = transaction(for: intent),
              transaction.state == .pending else { return }
        transaction.abortPending()
        transactionsBySpaceID.removeValue(forKey: intent.spaceID)
    }

    private func cancelPending(spaceID: UUID) {
        guard let transaction = transactionsBySpaceID[spaceID],
              transaction.state == .pending else { return }
        abortPending(transaction.intent)
    }

    private func transaction(
        for intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) -> SpaceProfileTransaction? {
        guard let transaction = transactionsBySpaceID[intent.spaceID],
              transaction.intent == intent else { return nil }
        return transaction
    }

    private func makeTransaction(
        _ intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) -> SpaceProfileTransaction {
        SpaceProfileTransaction(
            intent: intent,
            runtime: .init(
                profileID: { [weak tabManager] spaceID in
                    tabManager?.spaceStateOwner.profileId(for: spaceID)
                },
                assignProfile: { [weak tabManager] spaceID, profileID in
                    tabManager?.spaceStateOwner.assignProfile(
                        spaceId: spaceID,
                        profileId: profileID
                    ) ?? false
                },
                tab: { [weak tabManager] tabID in
                    tabManager?.tabCollectionMembershipOwner.tab(for: tabID)
                },
                sendObjectWillChange: { [weak tabManager] in
                    tabManager?.objectWillChange.send()
                }
            )
        )
    }

    private func tabsInSpace(_ spaceID: UUID) -> [Tab] {
        var seen: Set<UUID> = []
        return tabManager.tabCollectionMembershipOwner.allTabs()
            .filter { $0.spaceId == spaceID && seen.insert($0.id).inserted }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func publishStructuralMutation() {
        tabManager.structuralPersistence.markAllSpacesStructurallyDirty()
        tabManager.scheduleStructuralPersistence()
        tabManager.requestStructuralPublish()
    }

    private func immediateSettlement(
        for outcome: TabProfileAssignmentExecutionOutcome
    ) -> ProfileTransitionSettlement? {
        switch outcome {
        case .committed:
            return .committed
        case .stale:
            return .rejected(.stale)
        case .failed:
            return .rejected(.failed)
        case .deferred:
            return nil
        }
    }
}
