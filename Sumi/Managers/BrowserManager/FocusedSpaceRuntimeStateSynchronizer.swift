import Foundation

/// Derives process-wide Space runtime state only from the focused window.
/// Window-local selection changes use `BrowserWindowSpaceContextReconciler`
/// directly and cannot steal focus from another window.
@MainActor
final class FocusedSpaceRuntimeStateSynchronizer {
    private let activeWindow: () -> BrowserWindowState?
    private let windowContext: BrowserWindowSpaceContextReconciler
    private let runtimeState: SpaceProfileRuntimeStateService

    init(
        activeWindow: @escaping () -> BrowserWindowState?,
        windowContext: BrowserWindowSpaceContextReconciler,
        runtimeState: SpaceProfileRuntimeStateService
    ) {
        self.activeWindow = activeWindow
        self.windowContext = windowContext
        self.runtimeState = runtimeState
    }

    func synchronizeActiveWindow() {
        synchronize(activeWindow())
    }

    func synchronize(_ windowState: BrowserWindowState?) {
        guard windowState?.restorationState.isAwaitingInitialResolution != true else {
            return
        }

        let regularWindow = windowState.flatMap { windowState in
            windowState.isIncognito ? nil : windowState
        }
        if let regularWindow {
            windowContext.synchronize(regularWindow)
        }
        runtimeState.reconcile(
            focusedSpaceId: regularWindow?.currentSpaceId,
            selectedShortcutSpaceIds: regularWindow.map {
                Set($0.selectedShortcutPinForSpace.keys)
            } ?? []
        )
    }
}
