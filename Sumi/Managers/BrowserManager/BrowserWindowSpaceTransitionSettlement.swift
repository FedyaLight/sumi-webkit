import Foundation

@MainActor
final class BrowserWindowSpaceTransitionSettlement {
    private let windows: WindowRegistry
    private let windowStateReconciler: BrowserWindowStateReconciler
    private let profileAdoption: BrowserProfileAdoptionService
    private let persistence: WindowSessionPersistenceCoordinator
    private let splitFocus: SplitShortcutFocusService

    init(
        windows: WindowRegistry,
        windowState: BrowserWindowStateReconciler,
        profileAdoption: BrowserProfileAdoptionService,
        persistence: WindowSessionPersistenceCoordinator,
        splitFocus: SplitShortcutFocusService
    ) {
        self.windows = windows
        windowStateReconciler = windowState
        self.profileAdoption = profileAdoption
        self.persistence = persistence
        self.splitFocus = splitFocus
    }

    func admit(
        _ windowState: BrowserWindowState
    ) -> WindowRegistry.WindowRegistrationReceipt? {
        windows.registrationReceipt(for: windowState)
    }

    func resolve(
        _ receipt: WindowRegistry.WindowRegistrationReceipt
    ) -> BrowserWindowState? {
        windows.window(ifCurrent: receipt)
    }

    func isActiveWindow(_ windowState: BrowserWindowState) -> Bool {
        windows.activeWindow === windowState
    }

    func synchronizeFocusedSpaceContext(in windowState: BrowserWindowState) {
        windowStateReconciler.synchronizeFocusedSpaceContext(in: windowState)
    }

    func adoptProfileForSpaceChange(in windowState: BrowserWindowState) {
        profileAdoption.adoptProfileIfNeeded(
            for: windowState,
            context: .spaceChange
        )
    }

    func persist(_ windowState: BrowserWindowState) {
        persistence.persist(windowState)
    }

    func completePendingSplitGroupFocus(
        in windowState: BrowserWindowState,
        spaceID: UUID
    ) {
        splitFocus.completePendingSplitGroupFocusIfReady(
            in: windowState,
            spaceId: spaceID
        )
    }
}
