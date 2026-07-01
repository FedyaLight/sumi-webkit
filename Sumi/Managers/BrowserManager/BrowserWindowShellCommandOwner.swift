import Foundation

/// Routes window-level shell commands (new window, incognito, close, full screen)
/// through `BrowserWindowShellService`, owning the service instance.
@MainActor
final class BrowserWindowShellCommandOwner {
    struct Dependencies {
        let windowRegistry: @MainActor () -> WindowRegistry
        let makeWindowShellContext: @MainActor () -> BrowserWindowShellService.Context
    }

    let windowShellService = BrowserWindowShellService()
    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func createNewWindow() {
        windowShellService.createNewWindow(using: dependencies.makeWindowShellContext())
    }

    func createIncognitoWindow() {
        windowShellService.createIncognitoWindow(using: dependencies.makeWindowShellContext())
    }

    func closeIncognitoWindow(_ windowState: BrowserWindowState) async {
        await windowShellService.closeIncognitoWindow(
            windowState,
            using: dependencies.makeWindowShellContext()
        )
    }

    func closeActiveWindow() {
        windowShellService.closeActiveWindow(in: dependencies.windowRegistry())
    }

    func closeWindow(_ windowState: BrowserWindowState) {
        windowShellService.closeWindow(windowState)
    }

    func toggleFullScreenForActiveWindow() {
        windowShellService.toggleFullScreenForActiveWindow(in: dependencies.windowRegistry())
    }
}

extension BrowserWindowShellCommandOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            windowRegistry: { [weak browserManager] in
                guard let browserManager else {
                    preconditionFailure(
                        "BrowserManager was released before window shell commands resolved the registry."
                    )
                }
                return browserManager.requireWindowRegistry()
            },
            makeWindowShellContext: { [weak browserManager] in
                guard let browserManager else {
                    preconditionFailure(
                        "BrowserManager was released before window shell commands resolved their context."
                    )
                }
                return BrowserWindowShellService.Context(
                    windowRegistry: browserManager.requireWindowRegistry(),
                    webViewCoordinator: browserManager.requireWebViewCoordinator(),
                    permissionLifecycleController: browserManager.permissionRuntime.permissionLifecycleController,
                    profileManager: browserManager.profileManager,
                    tabManager: browserManager.tabManager,
                    makeContentView: browserManager.requireWindowShellContentViewFactory(),
                    showEmptyState: { [weak browserManager] windowState in
                        browserManager?.showEmptyState(in: windowState)
                    }
                )
            }
        )
    }
}
