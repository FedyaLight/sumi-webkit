import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalWindowProfileSwitcher {
    private let profiles: ExtensionBrowserProfileQuery
    private let transition: ExtensionProfileRuntimeTransition

    init(
        profiles: ExtensionBrowserProfileQuery,
        transition: ExtensionProfileRuntimeTransition
    ) {
        self.profiles = profiles
        self.transition = transition
    }

    func switchToWindowProfile(_ window: BrowserWindowState) {
        if window.isIncognito, let profile = window.ephemeralProfile {
            transition.rememberProfile(profile)
            transition.switchProfile(profileID: profile.id)
        } else if let profileID = window.currentProfileId,
                  let profile = profiles.profile(profileID) {
            transition.rememberProfile(profile)
            transition.switchProfile(profileID: profileID)
        } else if let currentProfile = profiles.currentProfile() {
            transition.rememberProfile(currentProfile)
            transition.switchProfile(profileID: currentProfile.id)
        }
    }
}
