import Foundation

@MainActor
final class BrowserWindowFocusedContextSynchronizer {
    private let windowState: BrowserWindowStateReconciler
    private let profileAdoption: BrowserProfileAdoptionService

    init(
        windowState: BrowserWindowStateReconciler,
        profileAdoption: BrowserProfileAdoptionService
    ) {
        self.windowState = windowState
        self.profileAdoption = profileAdoption
    }

    func synchronize(_ windowState: BrowserWindowState) {
        self.windowState.synchronizeFocusedSpaceContext(in: windowState)
        guard !windowState.isIncognito else { return }
        profileAdoption.adoptProfileIfNeeded(
            for: windowState,
            context: .windowActivation
        )
    }
}
