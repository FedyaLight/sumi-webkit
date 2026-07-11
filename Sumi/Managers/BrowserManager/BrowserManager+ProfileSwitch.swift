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
        SumiProfileRouting.adoptProfileIfNeeded(
            for: windowState,
            context: context,
            support: self
        )
    }

    func switchToProfile(
        _ profile: Profile, context: ProfileSwitchContext = .userInitiated,
        in windowState: BrowserWindowState? = nil
    ) async {
        await profileLifecycleBundle.profileSwitchTransition.switchToProfile(
            profile,
            context: context,
            in: windowState
        )
    }

    func duplicateCurrentTab() {
        guard let activeWindow = windowRegistry?.activeWindow,
              let currentTab = shellRuntime.windowTabs.currentTab(for: activeWindow) else {
            return
        }
        tabLifecycleService.opening.duplicateTab(currentTab, in: activeWindow)
    }
}
