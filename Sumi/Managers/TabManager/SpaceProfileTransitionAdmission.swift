import Foundation
import SumiWebRuntime

/// Resolves all fallible model and presentation authority, then creates one
/// exact intent/participant transaction before runtime execution begins.
@MainActor
final class SpaceProfileTransitionAdmission {
    private let profileMutations: SpaceProfileMutationService
    private let tabCandidates: SpaceProfileTabCandidatePlanner
    private let membership: TabCollectionMembershipOwner
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        profileMutations: SpaceProfileMutationService,
        tabCandidates: SpaceProfileTabCandidatePlanner,
        membership: TabCollectionMembershipOwner,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.profileMutations = profileMutations
        self.tabCandidates = tabCandidates
        self.membership = membership
        self.structuralLookup = structuralLookup
    }

    func prepare(
        space: Space,
        targetProfileID: UUID,
        revision: UInt64,
        using runtimeLease: TabRuntimePortLease,
        connection: TabRuntimePortConnection
    ) -> SpaceProfileTransaction? {
        guard connection.accepts(runtimeLease),
              let runtime = runtimeLease.registry else { return nil }
        let profileExists = runtime.profileExists(targetProfileID)
        guard connection.accepts(runtimeLease) else { return nil }
        guard profileExists else {
            RuntimeDiagnostics.emit(
                "⚠️ [SpaceProfile] Attempted to assign space to unknown profile: \(targetProfileID)"
            )
            return nil
        }
        let profile = runtime.profile(with: targetProfileID)
        guard connection.accepts(runtimeLease),
              let profile,
              let mutation = profileMutations.transaction(
                  space: space,
                  expectedProfileID: space.profileId,
                  targetProfileID: targetProfileID,
                  using: runtimeLease
              ), let candidates = tabCandidates.candidates(
                  in: space.id,
                  sourceProfileID: space.profileId,
                  targetProfileID: targetProfileID
              ), candidates.allSatisfy({
                  $0.tab.profileAssignment.hasUnsettledAssignment == false
              }), connection.accepts(runtimeLease) else { return nil }
        let tabIntents = candidates.map { candidate in
            let navigation = candidate.tab.mainFrameLoads.currentIntent
            return DeferredWebViewSpaceProfileTabIntent(
                tabID: candidate.tab.id,
                intent: candidate.tab.profileAssignment.begin(
                    desiredProfileID: candidate.desiredProfileID,
                    resolvedProfileID: profile.id,
                    targetURL: navigation.targetURL,
                    navigationRevision: navigation.revision,
                    requiresStructuralPersistence: false
                )
            )
        }
        let intent = DeferredWebViewSpaceProfileAssignmentIntent(
            revision: revision,
            spaceID: space.id,
            expectedProfileID: space.profileId,
            desiredProfileID: targetProfileID,
            tabIntents: tabIntents
        )
        guard let transaction = SpaceProfileTransaction(
            intent: intent,
            targetProfile: profile,
            tabs: candidates.map(\.tab),
            profileMutation: mutation,
            runtimeLease: runtimeLease,
            membership: membership,
            structuralLookup: structuralLookup
        ) else {
            for (candidate, tabIntent) in zip(candidates, tabIntents) {
                candidate.tab.profileAssignment.abort(tabIntent.intent)
            }
            return nil
        }
        return transaction
    }
}
