import Foundation

@MainActor
final class TabProfileResolutionOwner {
    func resolveProfile(for tab: Tab) -> Profile? {
        if let profileId = tab.profileId {
            if let windowState = tab.browserManager?.windowRegistry?.windows.values.first(where: { window in
                window.ephemeralTabs.contains(where: { $0.id == tab.id })
            }),
               let ephemeralProfile = windowState.ephemeralProfile,
               ephemeralProfile.id == profileId {
                return ephemeralProfile
            }

            if let profile = tab.browserManager?.profileManager.profiles.first(where: { $0.id == profileId }) {
                return profile
            }
        }

        if let spaceId = tab.spaceId,
           let space = tab.browserManager?.tabManager.spaces.first(where: { $0.id == spaceId }),
           let profileId = space.profileId,
           let profile = tab.browserManager?.profileManager.profiles.first(where: { $0.id == profileId }) {
            return profile
        }

        if let currentProfile = tab.browserManager?.currentProfile {
            return currentProfile
        }
        return tab.browserManager?.profileManager.profiles.first
    }
}
