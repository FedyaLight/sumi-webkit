import Foundation

/// Creates, closes, and toggles browser shell windows. Profile maintenance and
/// session persistence are deliberately outside this command surface.
@MainActor
final class BrowserWindowCommands {
    private let windows = BrowserWindowShellService()
    private weak var browserRuntime: BrowserManager?

    init(browserRuntime: BrowserManager) {
        self.browserRuntime = browserRuntime
    }

    @discardableResult
    func createNewWindow() -> BrowserWindowState {
        windows.createNewWindow(using: makeContext())
    }

    @discardableResult
    func createNewWindow(
        initializing initializeBeforePublication:
            BrowserWindowShellService.StateInitializer,
        discardPreparedState:
            BrowserWindowShellService.RejectedRegistrationCompensation
    ) -> BrowserWindowState? {
        windows.createNewWindow(
            using: makeContext(),
            initializeBeforePublication: initializeBeforePublication,
            validateAfterRegistration: {
                $0.isAwaitingInitialSessionResolution == false
            },
            compensateRejectedRegistration: { [weak self] windowState in
                discardPreparedState(windowState)
                self?.browserRuntime?.windowSessionBundle.restoration
                    .discardRegistration(windowState)
                self?.browserRuntime?.windowSessionBundle.activation
                    .discardDeferredActivation(windowState)
            }
        )
    }

    func createIncognitoWindow() {
        windows.createIncognitoWindow(using: makeContext())
    }

    func closeIncognitoWindow(_ windowState: BrowserWindowState) async {
        await windows.closeIncognitoWindow(windowState, using: makeContext())
    }

    func closeActiveWindow() {
        windows.closeActiveWindow(in: windowRegistry())
    }

    func closeWindow(_ windowState: BrowserWindowState) {
        windows.closeWindow(windowState, in: windowRegistry())
    }

    func toggleFullScreenForActiveWindow() {
        windows.toggleFullScreenForActiveWindow(in: windowRegistry())
    }

    private func windowRegistry() -> WindowRegistry {
        guard let browserRuntime else {
            preconditionFailure(
                "Browser runtime was released before a window command resolved its registry."
            )
        }
        return browserRuntime.shellRuntime.requireWindowRegistry()
    }

    private func makeContext() -> BrowserWindowShellService.Context {
        guard let browserRuntime else {
            preconditionFailure(
                "Browser runtime was released before a window command resolved its context."
            )
        }
        return BrowserWindowShellService.Context(
            windowRegistry: browserRuntime.shellRuntime.requireWindowRegistry(),
            webViewCoordinator: browserRuntime.shellRuntime.requireWebViewCoordinator(),
            permissionLifecycleController: browserRuntime.permissionRuntime.permissionLifecycleController,
            profileManager: browserRuntime.profileManager,
            tabManager: browserRuntime.tabManager,
            makeContentView: browserRuntime.shellRuntime.requireWindowShellContentViewFactory(),
            showEmptyState: { [weak browserRuntime] windowState, presentNewTabFloatingBar in
                browserRuntime?.showEmptyState(
                    in: windowState,
                    presentNewTabFloatingBar: presentNewTabFloatingBar
                )
            },
            sidebarHostRecoveryCoordinator: browserRuntime.sidebarHostRecoveryCoordinator
        )
    }
}
