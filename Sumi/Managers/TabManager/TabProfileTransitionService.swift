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

    private struct RuntimeAdmission {
        let revision: UInt64
        let lease: TabRuntimePortLease
    }

    private let runtimeConnection: TabRuntimePortConnection
    private let policy: ProfileAssignmentPolicy
    private let pendingInheritance: PendingTabProfileInheritance
    private let publication: TabProfileTransitionPublication
    private var observersByTabID: [UUID: SettlementObserver] = [:]
    private var runtimeAdmissionsByTabID: [UUID: RuntimeAdmission] = [:]

    init(
        runtimeConnection: TabRuntimePortConnection,
        policy: ProfileAssignmentPolicy,
        pendingInheritance: PendingTabProfileInheritance,
        publication: TabProfileTransitionPublication
    ) {
        self.runtimeConnection = runtimeConnection
        self.policy = policy
        self.pendingInheritance = pendingInheritance
        self.publication = publication
    }

    @discardableResult
    func assign(_ tab: Tab, toProfile profileID: UUID) -> Bool {
        if tab.profileId == profileID {
            let pendingRevision = tab.profileAssignment.changeRevision
            let lease = runtimeConnection.captureLease()
            guard policy.profileExists(profileID, using: lease),
                  runtimeConnection.acceptsExactAttachment(lease) else {
                RuntimeDiagnostics.emit(
                    "⚠️ [TabManager] Attempted to assign tab to unknown profile: \(profileID)"
                )
                return false
            }
            let didCancel = tab.profileAssignment.cancelPending()
            if didCancel {
                removeRuntimeAdmission(
                    for: tab,
                    revision: pendingRevision
                )
            }
            if didCancel, reconcileStableInheritance(for: tab) {
                publishStructuralMutation(for: tab)
            }
            return didCancel
        }
        if tab.profileAssignment.hasPendingAssignment(to: profileID) {
            return false
        }
        guard tab.profileAssignment.hasUnsettledAssignment == false else {
            return false
        }
        return start(
            desiredProfileID: profileID,
            tab: tab,
            requiresStructuralPersistence: true
        ).wasAccepted
    }

    func assignProfile(_ profileID: UUID?, to tab: Tab) {
        guard tab.profileAssignment.hasPendingAssignment(to: profileID) == false,
              tab.profileAssignment.hasUnsettledAssignment == false else {
            return
        }
        if tab.profileId == profileID {
            return
        }
        _ = start(
            desiredProfileID: profileID,
            tab: tab,
            requiresStructuralPersistence: false
        )
    }

    /// Executes the physical half of an assignment whose stable model was
    /// already published by an enclosing aggregate transaction.
    func reconcilePublishedProfile(
        _ profileID: UUID?,
        for tab: Tab,
        expectedRevision: UInt64
    ) -> TabProfileAssignmentExecutionOutcome {
        guard tab.profileId == profileID,
              tab.profileAssignment.changeRevision == expectedRevision,
              tab.profileAssignment.hasUnsettledAssignment == false else {
            return .stale
        }
        return start(
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
        let lease = runtimeConnection.captureLease()
        guard let profileIDs = policy.profileIDsForSpaceTransition(
            tab: tab,
            targetSpaceID: targetSpaceID,
            desiredProfileID: desiredProfileID,
            using: lease
        ), runtimeConnection.acceptsExactAttachment(lease) else {
            return nil
        }

        let pendingRevision = tab.profileAssignment.changeRevision
        if tab.profileAssignment.cancelPending() {
            removeRuntimeAdmission(for: tab, revision: pendingRevision)
        }
        let preparation = TabSpaceProfileTransitionPreparation(
            tabID: tab.id,
            sourceSpaceID: tab.spaceId,
            targetSpaceID: targetSpaceID,
            pinnedProfileID: profileIDs.current
        )
        tab.profileId = profileIDs.current
        return preparation
    }

    func prepareShortcutAssignment(
        tab: Tab,
        desiredProfileID: UUID?,
        resolvedProfileID: UUID,
        runtimeFallback: TabRuntimeFallbackProfileWitness?,
        using lease: TabRuntimePortLease
    ) -> ShortcutTabProfileAssignmentAdmission? {
        guard runtimeConnection.acceptsExactAttachment(lease),
              tab.profileAssignment.hasUnsettledAssignment == false else {
            return nil
        }
        let sourceProfileID = tab.profileId
        let sourceRevision = tab.profileAssignment.changeRevision
        guard let sourceProfile = policy.resolvedAssignmentProfile(
            for: tab,
            desiredProfileID: sourceProfileID,
            using: lease
        ), let targetProfile = lease.profile(with: resolvedProfileID),
           let profileWitness = lease.captureProfileAssignmentWitness(
               sourceProfile: sourceProfile,
               targetProfile: targetProfile
           ) else {
            return nil
        }
        let navigationIntent = tab.mainFrameLoads.currentIntent
        let sourceWebView = lease.liveDocumentWebView(for: tab)
        let assignment = PreparedTabProfileAssignment(
            tab: tab,
            sourceProfileID: sourceProfileID,
            profileWitness: profileWitness,
            sourceRevision: sourceRevision,
            desiredProfileID: desiredProfileID,
            runtimeFallback: runtimeFallback,
            navigationIntent: navigationIntent,
            sourceWebView: sourceWebView,
            sourceSessionGeneration: tab.webViewSession.generation,
            sourceSessionWebViews: tab.webViewSession.allKnownWebViews,
            targetURL: sourceWebView?.url ?? tab.url
        )
        guard runtimeConnection.acceptsExactAttachment(lease) else {
            return nil
        }
        return ShortcutTabProfileAssignmentAdmission(
            assignment: assignment
        )
    }

    func didCommitShortcutSpaceDeparture(_ tab: Tab) {
        pendingInheritance.tabLeftSourceSpace(tab)
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
        guard tab.profileAssignment.isCurrent(intent),
              tab.mainFrameLoads.isCurrent(
                  revision: intent.navigationRevision,
                  targetURL: intent.targetURL
              ),
              let admission = runtimeAdmissionsByTabID[tab.id],
              admission.revision == intent.revision else {
            receive(.rejected(.stale), tab: tab, intent: intent)
            return false
        }
        guard runtimeConnection.acceptsExactAttachment(admission.lease) else {
            receive(.leaseLost, tab: tab, intent: intent)
            return false
        }
        let profile = policy.resolvedAssignmentProfile(
            for: tab,
            desiredProfileID: intent.desiredProfileID,
            using: admission.lease
        )
        guard runtimeConnection.acceptsExactAttachment(admission.lease) else {
            receive(.leaseLost, tab: tab, intent: intent)
            return false
        }
        guard let profile, profile.id == intent.resolvedProfileID else {
            receive(.rejected(.stale), tab: tab, intent: intent)
            return false
        }
        return execute(
            tab: tab,
            profile: profile,
            intent: intent,
            using: admission.lease
        ).wasAccepted
    }

    @discardableResult
    func start(
        desiredProfileID: UUID?,
        tab: Tab,
        requiresStructuralPersistence: Bool,
        using runtimeLease: TabRuntimePortLease? = nil,
        settlementObserver: ProfileTransitionService.Settlement? = nil
    ) -> TabProfileAssignmentExecutionOutcome {
        start(
            desiredProfileID: desiredProfileID,
            tab: tab,
            requiresStructuralPersistence: requiresStructuralPersistence,
            runtimeLease: runtimeLease,
            intentObserver: nil,
            settlementObserver: settlementObserver
        )
    }

    @discardableResult
    func start(
        desiredProfileID: UUID?,
        tab: Tab,
        requiresStructuralPersistence: Bool,
        using runtimeLease: TabRuntimePortLease? = nil,
        capturingIntent: @escaping (
            DeferredWebViewProfileAssignmentIntent
        ) -> Void,
        settlementObserver: ProfileTransitionService.Settlement? = nil
    ) -> TabProfileAssignmentExecutionOutcome {
        start(
            desiredProfileID: desiredProfileID,
            tab: tab,
            requiresStructuralPersistence: requiresStructuralPersistence,
            runtimeLease: runtimeLease,
            intentObserver: capturingIntent,
            settlementObserver: settlementObserver
        )
    }

    private func start(
        desiredProfileID: UUID?,
        tab: Tab,
        requiresStructuralPersistence: Bool,
        runtimeLease: TabRuntimePortLease?,
        intentObserver: ((DeferredWebViewProfileAssignmentIntent) -> Void)?,
        settlementObserver: ProfileTransitionService.Settlement?
    ) -> TabProfileAssignmentExecutionOutcome {
        let lease = runtimeLease ?? runtimeConnection.captureLease()
        guard runtimeConnection.acceptsExactAttachment(lease),
              let profile = policy.resolvedAssignmentProfile(
            for: tab,
            desiredProfileID: desiredProfileID,
            using: lease
        ), runtimeConnection.acceptsExactAttachment(lease) else {
            return .failed
        }
        let navigationIntent = tab.mainFrameLoads.currentIntent
        let intent = tab.profileAssignment.begin(
            desiredProfileID: desiredProfileID,
            resolvedProfileID: profile.id,
            targetURL: navigationIntent.targetURL,
            navigationRevision: navigationIntent.revision,
            requiresStructuralPersistence: requiresStructuralPersistence
        )
        runtimeAdmissionsByTabID[tab.id] = RuntimeAdmission(
            revision: intent.revision,
            lease: lease
        )
        intentObserver?(intent)
        if let settlementObserver {
            observersByTabID[tab.id] = SettlementObserver(
                revision: intent.revision,
                callback: settlementObserver
            )
        }

        let outcome = execute(
            tab: tab,
            profile: profile,
            intent: intent,
            using: lease
        )
        if let settlement = outcome.immediateSettlement,
           runtimeAdmissionsByTabID[tab.id]?.revision == intent.revision {
            receive(settlement, tab: tab, intent: intent)
        }
        return outcome
    }

    func cancelPendingDeletionIntent(
        tab: Tab,
        intent: DeferredWebViewProfileAssignmentIntent
    ) {
        tab.profileAssignment.abort(intent)
        removeRuntimeAdmission(for: tab, revision: intent.revision)
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
        intent: DeferredWebViewProfileAssignmentIntent,
        using lease: TabRuntimePortLease
    ) -> TabProfileAssignmentExecutionOutcome {
        guard runtimeConnection.acceptsExactAttachment(lease) else {
            receive(.leaseLost, tab: tab, intent: intent)
            return .failed
        }
        guard let lifecycle = lease.registry?.webViewLifecycle else {
            receive(.rejected(.failed), tab: tab, intent: intent)
            return .failed
        }
        return lifecycle.executeProfileAssignment(
            for: tab,
            targetProfile: profile,
            intent: intent,
            settlement: { [weak self, weak tab] settlement in
                guard let self, let tab else { return }
                receive(
                    runtimeConnection.acceptsExactAttachment(lease)
                        ? settlement
                        : .leaseLost,
                    tab: tab,
                    intent: intent
                )
            }
        )
    }

    private func receive(
        _ settlement: ProfileTransitionSettlement,
        tab: Tab,
        intent: DeferredWebViewProfileAssignmentIntent
    ) {
        removeRuntimeAdmission(for: tab, revision: intent.revision)
        var requiresStructuralPublication = false
        switch settlement {
        case .committed:
            requiresStructuralPublication = intent.requiresStructuralPersistence
        case .rejected:
            tab.profileAssignment.abort(intent)
        case .rolledBack:
            requiresStructuralPublication = intent.requiresStructuralPersistence
        case .leaseLost, .terminalShutdown:
            tab.profileAssignment.abort(intent)
        case .conflicted:
            break
        }
        let didNormalizeInheritance = pendingInheritance.tabTransitionSettled(
            settlement,
            tab: tab,
            intent: intent,
            canonicalProfileID: tab.spaceId.flatMap {
                publication.profileID(for: $0)
            },
            isTabStillInSpace: publication.containsExact(tab)
        )
        if requiresStructuralPublication || didNormalizeInheritance {
            publishStructuralMutation(for: tab)
        }

        guard let observer = observersByTabID[tab.id],
              observer.revision == intent.revision else { return }
        observersByTabID.removeValue(forKey: tab.id)
        observer.callback(settlement)
    }

    private func removeRuntimeAdmission(for tab: Tab, revision: UInt64) {
        guard runtimeAdmissionsByTabID[tab.id]?.revision == revision else {
            return
        }
        runtimeAdmissionsByTabID.removeValue(forKey: tab.id)
    }

    private func publishStructuralMutation(for tab: Tab) {
        publication.publishStructuralMutation(for: tab)
    }

    private func reconcileStableInheritance(for tab: Tab) -> Bool {
        pendingInheritance.tabBecameStable(
            tab,
            canonicalProfileID: tab.spaceId.flatMap {
                publication.profileID(for: $0)
            },
            isTabStillInSpace: publication.containsExact(tab)
        )
    }
}
