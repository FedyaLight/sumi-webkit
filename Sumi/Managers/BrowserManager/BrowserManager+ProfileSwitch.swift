import Foundation

extension BrowserManager {
    enum ProfileSwitchContext {
        case userInitiated
        case spaceChange
        case windowActivation
        case recovery
    }

    func adoptProfileIfNeeded(
        for windowState: BrowserWindowState, context: ProfileSwitchContext
    ) {
        sumiProfileRouter.adoptProfileIfNeeded(
            for: windowState,
            context: context,
            support: self
        )
    }

    func switchToProfile(
        _ profile: Profile, context: ProfileSwitchContext = .userInitiated,
        in windowState: BrowserWindowState? = nil
    ) async {
        await profileLifecycleBundle.profileSwitchTransitionOwner.switchToProfile(
            profile,
            context: context,
            in: windowState
        )
    }

    func duplicateCurrentTab() {
        guard let activeWindow = windowRegistry?.activeWindow,
              let currentTab = urlBarBundle.activePageRoutingOwner.currentTabForActiveWindow() else {
            return
        }
        tabLifecycleService.opening.duplicateTab(currentTab, in: activeWindow)
    }
}
