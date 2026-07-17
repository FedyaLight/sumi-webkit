import Foundation
import SumiDomain

@MainActor
final class BrowserWindowSpaceContextSynchronizer {
    private let spaceContext: BrowserWindowSpaceContextReconciler
    private let focusedRuntime: FocusedSpaceRuntimeStateSynchronizer

    init(
        spaceContext: BrowserWindowSpaceContextReconciler,
        focusedRuntime: FocusedSpaceRuntimeStateSynchronizer
    ) {
        self.spaceContext = spaceContext
        self.focusedRuntime = focusedRuntime
    }

    func reconcile(_ window: BrowserWindowState) -> Bool {
        spaceContext.reconcile(window)
    }

    func workspaceTheme(for window: BrowserWindowState) -> WorkspaceTheme {
        spaceContext.workspaceTheme(for: window)
    }

    func synchronize(_ window: BrowserWindowState) {
        spaceContext.synchronize(window)
        focusedRuntime.synchronizeActiveWindow()
    }

    func synchronizeActiveWindow() {
        focusedRuntime.synchronizeActiveWindow()
    }

    func synchronizeFocusedWindow(_ window: BrowserWindowState) {
        focusedRuntime.synchronize(window)
    }
}
