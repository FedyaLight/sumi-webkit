import Foundation

@MainActor
struct TabRuntimeProfileAssignmentWitness {
    private let profileQuery: any TabProfileQueryPort
    let sourceProfile: Profile
    let targetProfile: Profile

    init?(
        profileQuery: any TabProfileQueryPort,
        sourceProfile: Profile,
        targetProfile: Profile
    ) {
        guard profileQuery.profile(with: sourceProfile.id) === sourceProfile,
              profileQuery.profile(with: targetProfile.id) === targetProfile else {
            return nil
        }
        self.profileQuery = profileQuery
        self.sourceProfile = sourceProfile
        self.targetProfile = targetProfile
    }

    func isCurrent() -> Bool {
        profileQuery.profile(with: sourceProfile.id) === sourceProfile
            && profileQuery.profile(with: targetProfile.id) === targetProfile
    }
}
