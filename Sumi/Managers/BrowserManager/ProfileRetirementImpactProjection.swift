import Foundation

/// Projects permanent profile-retirement loss in one pass over the live
/// browser inventory. The projection is built only while Settings asks for it.
@MainActor
final class ProfileRetirementImpactProjection {
    private let spaces: TabSpaceCollectionStateOwner
    private let tabs: TabCollectionMembershipOwner
    private let pins: ShortcutPinCollectionStateOwner

    init(
        spaces: TabSpaceCollectionStateOwner,
        tabs: TabCollectionMembershipOwner,
        pins: ShortcutPinCollectionStateOwner
    ) {
        self.spaces = spaces
        self.tabs = tabs
        self.pins = pins
    }

    func snapshot() -> [UUID: ProfileUsage] {
        var spaceCountByProfile: [UUID: Int] = [:]
        var profileBySpaceID: [UUID: UUID] = [:]
        for space in spaces.spaces {
            guard let profileID = space.profileId else { continue }
            profileBySpaceID[space.id] = profileID
            spaceCountByProfile[profileID, default: 0] += 1
        }

        var retiredPageIDsByProfile: [UUID: Set<UUID>] = [:]
        for tab in tabs.allIdentityWitnesses() {
            guard let spaceID = tab.spaceId,
                  let profileID = profileBySpaceID[spaceID] else {
                continue
            }
            retiredPageIDsByProfile[profileID, default: []].insert(tab.id)
        }
        for (profileID, profilePins) in pins.pinnedByProfileSnapshot() {
            retiredPageIDsByProfile[profileID, default: []]
                .formUnion(profilePins.map(\.id))
        }
        for (spaceID, spacePins) in pins.spacePinnedShortcutsSnapshot() {
            guard let profileID = profileBySpaceID[spaceID] else { continue }
            retiredPageIDsByProfile[profileID, default: []]
                .formUnion(spacePins.map(\.id))
        }

        let profileIDs = Set(spaceCountByProfile.keys)
            .union(retiredPageIDsByProfile.keys)
        return Dictionary(uniqueKeysWithValues: profileIDs.map { profileID in
            (
                profileID,
                ProfileUsage(
                    spaces: spaceCountByProfile[profileID, default: 0],
                    tabs: retiredPageIDsByProfile[profileID]?.count ?? 0
                )
            )
        })
    }
}
