@MainActor
extension BrowserManager {
    func createNewWindow() {
        windowShellService.createNewWindow(using: makeWindowShellContext())
    }

    func createIncognitoWindow() {
        windowShellService.createIncognitoWindow(using: makeWindowShellContext())
    }

    func closeIncognitoWindow(_ windowState: BrowserWindowState) async {
        await windowShellService.closeIncognitoWindow(
            windowState,
            using: makeWindowShellContext()
        )
    }

    func closeActiveWindow() {
        windowShellService.closeActiveWindow(in: windowRegistry)
    }

    func toggleFullScreenForActiveWindow() {
        windowShellService.toggleFullScreenForActiveWindow(in: windowRegistry)
    }

    private func makeWindowShellContext() -> BrowserWindowShellService.Context {
        return BrowserWindowShellService.Context(
            windowRegistry: windowRegistry,
            webViewCoordinator: webViewCoordinator,
            permissionLifecycleController: permissionLifecycleController,
            profileManager: profileManager,
            tabManager: tabManager,
            makeContentView: windowShellContentViewFactory,
            showEmptyState: { [weak self] windowState in
                self?.showEmptyState(in: windowState)
            }
        )
    }
}
