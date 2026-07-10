import Foundation

struct AuxiliaryWindowTabIdentity: Equatable {
    let profileID: UUID?
    let spaceID: UUID?
}

enum AuxiliaryWindowTabIdentityPolicy {
    static func resolve(
        explicitProfileID: UUID?,
        openerProfileID: UUID?,
        openerSpaceID: UUID?,
        currentProfileID: UUID?,
        currentSpaceID: UUID?,
        currentSpaceProfileID: UUID?
    ) -> AuxiliaryWindowTabIdentity {
        let profileID = explicitProfileID
            ?? openerProfileID
            ?? currentProfileID
            ?? currentSpaceProfileID

        let spaceID: UUID?
        if let profileID,
           openerProfileID == profileID,
           let openerSpaceID {
            spaceID = openerSpaceID
        } else if let profileID,
                  currentSpaceProfileID == profileID {
            spaceID = currentSpaceID
        } else {
            spaceID = nil
        }

        return AuxiliaryWindowTabIdentity(
            profileID: profileID,
            spaceID: spaceID
        )
    }
}
