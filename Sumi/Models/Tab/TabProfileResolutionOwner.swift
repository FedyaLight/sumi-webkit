import Foundation

@MainActor
final class TabProfileResolutionOwner {
    func resolveProfile(for tab: Tab) -> Profile? {
        if let profileId = tab.profileId {
            if let ephemeralProfile = tab.profileResolutionRuntime.ephemeralProfileForTab(tab.id, profileId) {
                return ephemeralProfile
            }

            if let profile = tab.profileResolutionRuntime.profile(profileId) {
                return profile
            }
        }

        if let spaceId = tab.spaceId,
           let profile = tab.profileResolutionRuntime.spaceProfile(spaceId) {
            return profile
        }

        if let currentProfile = tab.profileResolutionRuntime.currentProfile() {
            return currentProfile
        }
        return tab.profileResolutionRuntime.firstProfile()
    }
}
