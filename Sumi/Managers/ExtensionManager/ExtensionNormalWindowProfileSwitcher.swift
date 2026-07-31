import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalWindowProfileSwitcher {
    private let profiles: ExtensionBrowserProfileQuery
    private let transition: ExtensionProfileRuntimeTransition
    private let warmup: ExtensionProfileRuntimeWarmup

    init(
        profiles: ExtensionBrowserProfileQuery,
        transition: ExtensionProfileRuntimeTransition,
        warmup: ExtensionProfileRuntimeWarmup
    ) {
        self.profiles = profiles
        self.transition = transition
        self.warmup = warmup
    }

    func switchToWindowProfile(_ window: BrowserWindowState) {
        if window.isIncognito, let profile = window.ephemeralProfile {
            warmup.cancel()
            transition.rememberProfile(profile)
            transition.switchProfile(profileID: profile.id)
        } else if let profileID = window.currentProfileId,
                  let profile = profiles.profile(profileID) {
            transition.rememberProfile(profile)
            warm(transition.switchProfile(profileID: profileID))
        } else if let currentProfile = profiles.currentProfile() {
            transition.rememberProfile(currentProfile)
            warm(transition.switchProfile(profileID: currentProfile.id))
        }
    }

    /// Focusing a window whose profile is not resident is the other way a
    /// profile becomes current without any popup being open — the same warm-up
    /// window as an explicit space switch. Already-ready profiles short-circuit
    /// inside the warm-up, so the reentrant focus published by a runtime load
    /// costs nothing.
    private func warm(_ receipt: ExtensionProfileRuntimeTransition.Receipt) {
        warmup.warm(profileID: receipt.profileID) { [transition] in
            transition.isCurrent(receipt)
        }
    }
}
