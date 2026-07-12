import Foundation

@MainActor
extension BrowserWindowCommands {
    static func live(browserRuntime: BrowserManager) -> BrowserWindowCommands {
        BrowserWindowCommands(
            context: { [weak browserRuntime] in
                guard let browserRuntime else {
                    preconditionFailure(
                        "Browser runtime was released before a window command resolved its context."
                    )
                }
                return BrowserWindowShellService.Context(
                    windowRegistry: browserRuntime.shellRuntime
                        .requireWindowRegistry(),
                    permissionLifecycleController: browserRuntime
                        .permissionRuntime.permissionLifecycleController,
                    profileManager: browserRuntime.profileManager,
                    tabManager: browserRuntime.tabManager,
                    makeContentView: browserRuntime.shellRuntime
                        .requireWindowShellContentViewFactory(),
                    showEmptyState: { [weak browserRuntime] window, presentBar in
                        browserRuntime?.showEmptyState(
                            in: window,
                            presentNewTabFloatingBar: presentBar
                        )
                    },
                    sidebarHostRecoveryCoordinator: browserRuntime
                        .sidebarHostRecoveryCoordinator
                )
            },
            windowRegistry: { [weak browserRuntime] in
                guard let browserRuntime else {
                    preconditionFailure(
                        "Browser runtime was released before a window command resolved its registry."
                    )
                }
                return browserRuntime.shellRuntime.requireWindowRegistry()
            },
            discardRegistration: { [weak browserRuntime] window in
                browserRuntime?.windowSessionBundle.restoration
                    .discardRegistration(window)
            },
            discardActivation: { [weak browserRuntime] window in
                browserRuntime?.windowSessionBundle.activation
                    .discardDeferredActivation(window)
            }
        )
    }
}
