import Foundation

@MainActor
struct TabRuntimeFallbackProfileWitness {
    private let profileQuery: any TabProfileQueryPort
    let profileID: UUID

    init(
        profileQuery: any TabProfileQueryPort,
        profileID: UUID
    ) {
        self.profileQuery = profileQuery
        self.profileID = profileID
    }

    func isCurrent() -> Bool {
        (profileQuery.currentProfileId ?? profileQuery.defaultProfileId)
            == profileID
    }
}
