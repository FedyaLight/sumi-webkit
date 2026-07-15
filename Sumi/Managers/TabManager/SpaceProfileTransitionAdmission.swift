import Foundation
import SumiWebRuntime

@MainActor
struct AdmittedSpaceProfileTransition {
    let profile: Profile
    let mutation: SpaceProfileMutationTransaction
    let tabCandidates: [SpaceProfileTabCandidate]
}

/// Resolves all fallible model and presentation authority, then creates one
/// exact intent/participant transaction before runtime execution begins.
@MainActor
final class SpaceProfileTransitionAdmission {
    private let policy: ProfileAssignmentPolicy
    private let profileMutations: SpaceProfileMutationService
    private let tabCandidates: SpaceProfileTabCandidatePlanner
    private let membership: TabCollectionMembershipOwner
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        policy: ProfileAssignmentPolicy,
        profileMutations: SpaceProfileMutationService,
        tabCandidates: SpaceProfileTabCandidatePlanner,
        membership: TabCollectionMembershipOwner,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.policy = policy
        self.profileMutations = profileMutations
        self.tabCandidates = tabCandidates
        self.membership = membership
        self.structuralLookup = structuralLookup
    }

    func admit(
        space: Space,
        targetProfileID: UUID
    ) -> AdmittedSpaceProfileTransition? {
        guard policy.profileExists(targetProfileID) else {
            RuntimeDiagnostics.emit(
                "⚠️ [TabManager] Attempted to assign space to unknown profile: \(targetProfileID)"
            )
            return nil
        }
        guard let profile = resolvedProfile(targetProfileID),
              let mutation = profileMutations.transaction(
                  space: space,
                  expectedProfileID: space.profileId,
                  targetProfileID: targetProfileID
              ), let candidates = tabCandidates.candidates(
                  in: space.id,
                  sourceProfileID: space.profileId,
                  targetProfileID: targetProfileID
              ), candidates.allSatisfy({
                  $0.tab.profileAssignment.hasUnsettledAssignment == false
              }) else { return nil }
        return AdmittedSpaceProfileTransition(
            profile: profile,
            mutation: mutation,
            tabCandidates: candidates
        )
    }

    func transaction(
        intent: DeferredWebViewSpaceProfileAssignmentIntent,
        tabs: [Tab],
        profileMutation: SpaceProfileMutationTransaction
    ) -> SpaceProfileTransaction? {
        SpaceProfileTransaction(
            intent: intent,
            tabs: tabs,
            profileMutation: profileMutation,
            membership: membership,
            structuralLookup: structuralLookup
        )
    }

    func resolvedProfile(_ profileID: UUID) -> Profile? {
        policy.resolvedPlacementProfile(profileID: profileID)
    }

    func targetURL(for tab: Tab) -> URL {
        policy.liveDocumentURL(for: tab) ?? tab.url
    }
}
