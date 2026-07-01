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
        windowShellService.closeActiveWindow(in: requireWindowRegistry())
    }

    func closeWindow(_ windowState: BrowserWindowState) {
        windowShellService.closeWindow(windowState)
    }

    func toggleFullScreenForActiveWindow() {
        windowShellService.toggleFullScreenForActiveWindow(in: requireWindowRegistry())
    }

    private func makeWindowShellContext() -> BrowserWindowShellService.Context {
        return BrowserWindowShellService.Context(
            windowRegistry: requireWindowRegistry(),
            webViewCoordinator: requireWebViewCoordinator(),
            permissionLifecycleController: permissionLifecycleController,
            profileManager: profileManager,
            tabManager: tabManager,
            makeContentView: requireWindowShellContentViewFactory(),
            showEmptyState: { [weak self] windowState in
                self?.showEmptyState(in: windowState)
            }
        )
    }
}
