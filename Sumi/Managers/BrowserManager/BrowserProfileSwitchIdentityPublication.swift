import Combine
import Foundation

@MainActor
final class BrowserProfileSwitchIdentityPublication {
    private let currentProfile: BrowserCurrentProfileAuthority
    private let profileChanges: ObservableObjectPublisher
    private let auxiliaryWindows: AuxiliaryWindowTeardownService

    init(
        currentProfile: BrowserCurrentProfileAuthority,
        profileChanges: ObservableObjectPublisher,
        auxiliaryWindows: AuxiliaryWindowTeardownService
    ) {
        self.currentProfile = currentProfile
        self.profileChanges = profileChanges
        self.auxiliaryWindows = auxiliaryWindows
    }

    func publish(
        _ profile: Profile,
        to window: BrowserWindowState?,
        isAnimated: Bool
    ) {
        auxiliaryWindows.closeAll(reason: .profileSwitch)
        currentProfile.setTransitioning(isAnimated)
        profileChanges.send()
        currentProfile.setCurrentProfile(profile)
        window?.currentProfileId = profile.id
    }

    func currentProfileName() -> String {
        currentProfile.currentProfile?.name ?? "none"
    }

    func finishAnimatedTransition() {
        currentProfile.setTransitioning(false)
    }
}
