import Foundation

@MainActor
final class TabProfileResolutionOwner {
    func resolveProfile(for tab: Tab) -> Profile? {
        if let profileId = tab.profileId {
            if let ephemeralProfile = tab.navigationRuntime.profileResolutionRuntime.ephemeralProfileForTab(tab.id, profileId) {
                return ephemeralProfile
            }

            if let profile = tab.navigationRuntime.profileResolutionRuntime.profile(profileId) {
                return profile
            }
        }

        if let spaceId = tab.spaceId,
           let profile = tab.navigationRuntime.profileResolutionRuntime.spaceProfile(spaceId) {
            return profile
        }

        if let currentProfile = tab.navigationRuntime.profileResolutionRuntime.currentProfile() {
            return currentProfile
        }
        return tab.navigationRuntime.profileResolutionRuntime.firstProfile()
    }
}
