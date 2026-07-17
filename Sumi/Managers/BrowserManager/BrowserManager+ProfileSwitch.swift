import Foundation

enum BrowserProfileSwitchContext {
    case userInitiated
    case spaceChange
    case windowActivation
    case recovery
    case profileRetirement
}

extension BrowserManager {
    typealias ProfileSwitchContext = BrowserProfileSwitchContext

    func adoptProfileIfNeeded(
        for windowState: BrowserWindowState, context: ProfileSwitchContext
    ) {
        profileAdoption.adoptProfileIfNeeded(
            for: windowState,
            context: context
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
}
