import Foundation
import SumiWebRuntime

/// Owns one Tab's profile intent from creation through WebView replacement
/// settlement and structural publication.
@MainActor
final class TabProfileTransitionService {
    private struct SettlementObserver {
        let revision: UInt64
        let callback: ProfileTransitionService.Settlement
    }

    private unowned let tabManager: TabManager
    private let policy: ProfileAssignmentPolicy
    private let pendingInheritance: PendingTabProfileInheritance
    private var observersByTabID: [UUID: SettlementObserver] = [:]

    init(
        tabManager: TabManager,
        policy: ProfileAssignmentPolicy,
        pendingInheritance: PendingTabProfileInheritance
    ) {
        self.tabManager = tabManager
        self.policy = policy
        self.pendingInheritance = pendingInheritance
    }

    @discardableResult
    func assign(_ tab: Tab, toProfile profileID: UUID) -> Bool {
        guard policy.profileExists(profileID) else {
            RuntimeDiagnostics.emit(
                "⚠️ [TabManager] Attempted to assign tab to unknown profile: \(profileID)"
            )
            return false
        }
        if tab.profileId == profileID {
            let didCancel = tab.cancelPendingProfileAssignment()
            if didCancel, reconcileStableInheritance(for: tab) {
                publishStructuralMutation(for: tab)
            }
            return didCancel
        }
        if tab.hasPendingProfileAssignment(to: profileID) {
            return false
        }
        guard tab.hasUnsettledProfileAssignment == false else { return false }
        return start(
            desiredProfileID: profileID,
            tab: tab,
            requiresStructuralPersistence: true
        ).wasAccepted
    }

    func assignProfile(_ profileID: UUID?, to tab: Tab) {
        guard tab.hasPendingProfileAssignment(to: profileID) == false,
              tab.hasUnsettledProfileAssignment == false else { return }
        if tab.profileId == profileID {
            return
        }
        _ = start(
            desiredProfileID: profileID,
            tab: tab,
            requiresStructuralPersistence: false
        )
    }

    func prepareForSpaceTransition(
        tab: Tab,
        targetSpaceID: UUID?,
        desiredProfileID: UUID? = nil
    ) -> TabSpaceProfileTransitionPreparation? {
        guard tab.spaceId != targetSpaceID else { return nil }
        // Both callers have already committed to changing `spaceId`; a nil
        // preparation only means that no WebView profile replacement is needed.
        pendingInheritance.tabLeftSourceSpace(tab)
        guard let profileIDs = policy.profileIDsForSpaceTransition(
            tab: tab,
            targetSpaceID: targetSpaceID,
            desiredProfileID: desiredProfileID
        ) else { return nil }

        _ = tab.cancelPendingProfileAssignment()
        let preparation = TabSpaceProfileTransitionPreparation(
            tabID: tab.id,
            sourceSpaceID: tab.spaceId,
            targetSpaceID: targetSpaceID,
            pinnedProfileID: profileIDs.current
        )
        tab.profileId = profileIDs.current
        return preparation
    }

    @discardableResult
    func finishSpaceTransition(
        _ preparation: TabSpaceProfileTransitionPreparation,
        for tab: Tab
    ) -> TabProfileAssignmentExecutionOutcome {
        guard tab.id == preparation.tabID,
              tab.spaceId == preparation.targetSpaceID,
              tab.profileId == preparation.pinnedProfileID else {
            return .stale
        }
        return start(
            desiredProfileID: nil,
            tab: tab,
            requiresStructuralPersistence: true
        )
    }

    @discardableResult
    func executeDeferred(
        tab: Tab,
        intent: DeferredWebViewProfileAssignmentIntent
    ) -> Bool {
        guard tab.isCurrentProfileAssignmentIntent(intent),
              let profile = policy.resolvedAssignmentProfile(
                  for: tab,
                  desiredProfileID: intent.desiredProfileID
              ), profile.id == intent.resolvedProfileID else {
            receive(.rejected(.stale), tab: tab, intent: intent)
            return false
        }
        return execute(tab: tab, profile: profile, intent: intent).wasAccepted
    }

    @discardableResult
    func start(
        desiredProfileID: UUID?,
        tab: Tab,
        requiresStructuralPersistence: Bool,
        intentPrepared: (DeferredWebViewProfileAssignmentIntent) -> Void = { _ in /* No-op. */ },
        settlementObserver: ProfileTransitionService.Settlement? = nil
    ) -> TabProfileAssignmentExecutionOutcome {
        guard let profile = policy.resolvedAssignmentProfile(
            for: tab,
            desiredProfileID: desiredProfileID
        ) else {
            return .failed
        }
        let intent = tab.beginProfileAssignmentIntent(
            desiredProfileID: desiredProfileID,
            resolvedProfileID: profile.id,
            targetURL: policy.liveDocumentURL(for: tab) ?? tab.url,
            requiresStructuralPersistence: requiresStructuralPersistence
        )
        intentPrepared(intent)
        if let settlementObserver {
            observersByTabID[tab.id] = SettlementObserver(
                revision: intent.revision,
                callback: settlementObserver
            )
        }

        let outcome = execute(tab: tab, profile: profile, intent: intent)
        if let settlement = immediateSettlement(for: outcome),
           observersByTabID[tab.id]?.revision == intent.revision {
            receive(settlement, tab: tab, intent: intent)
        }
        return outcome
    }

    func cancelPendingDeletionIntent(
        tab: Tab,
        intent: DeferredWebViewProfileAssignmentIntent
    ) {
        tab.abortProfileAssignmentIntent(intent)
        if reconcileStableInheritance(for: tab) {
            publishStructuralMutation(for: tab)
        }
        if observersByTabID[tab.id]?.revision == intent.revision {
            observersByTabID.removeValue(forKey: tab.id)
        }
    }

    private func execute(
        tab: Tab,
        profile: Profile,
        intent: DeferredWebViewProfileAssignmentIntent
    ) -> TabProfileAssignmentExecutionOutcome {
        guard let lifecycle = tabManager.runtimePorts?.webViewLifecycle else {
            receive(.rejected(.failed), tab: tab, intent: intent)
            return .failed
        }
        return lifecycle.executeProfileAssignment(
            for: tab,
            targetProfile: profile,
            intent: intent,
            settlement: { [weak self, weak tab] settlement in
                guard let self, let tab else { return }
                receive(settlement, tab: tab, intent: intent)
            }
        )
    }

    private func receive(
        _ settlement: ProfileTransitionSettlement,
        tab: Tab,
        intent: DeferredWebViewProfileAssignmentIntent
    ) {
        var requiresStructuralPublication = false
        switch settlement {
        case .committed:
            requiresStructuralPublication = intent.requiresStructuralPersistence
        case .rejected:
            tab.abortProfileAssignmentIntent(intent)
        case .rolledBack:
            requiresStructuralPublication = intent.requiresStructuralPersistence
        case .conflicted, .leaseLost, .terminalShutdown:
            break
        }
        let didNormalizeInheritance = pendingInheritance.tabTransitionSettled(
            settlement,
            tab: tab,
            intent: intent,
            canonicalProfileID: tab.spaceId.flatMap {
                tabManager.spaceStateOwner.profileId(for: $0)
            },
            isTabStillInSpace: tabManager.tabCollectionMembershipOwner
                .allTabs().contains { $0 === tab && $0.spaceId == tab.spaceId }
        )
        if requiresStructuralPublication || didNormalizeInheritance {
            publishStructuralMutation(for: tab)
        }

        guard let observer = observersByTabID[tab.id],
              observer.revision == intent.revision else { return }
        observersByTabID.removeValue(forKey: tab.id)
        observer.callback(settlement)
    }

    private func publishStructuralMutation(for tab: Tab) {
        if let spaceID = tab.spaceId {
            tabManager.structuralPersistence
                .markRegularTabsStructurallyDirty(for: spaceID)
        }
        tabManager.structuralPersistence.scheduleStructuralPersistence()
        tabManager.structuralLookupCoordinator.requestPublish()
    }

    private func reconcileStableInheritance(for tab: Tab) -> Bool {
        pendingInheritance.tabBecameStable(
            tab,
            canonicalProfileID: tab.spaceId.flatMap {
                tabManager.spaceStateOwner.profileId(for: $0)
            },
            isTabStillInSpace: tabManager.tabCollectionMembershipOwner
                .allTabs().contains { $0 === tab && $0.spaceId == tab.spaceId }
        )
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
