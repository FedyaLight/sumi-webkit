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
                    tabResidences: browserRuntime.tabResidenceAuthority,
                    makeContentView: browserRuntime.shellRuntime
                        .requireWindowShellContentViewFactory(),
                    showEmptyState: { [weak browserRuntime] window, presentBar in
                        browserRuntime?.showEmptyState(
                            in: window,
                            presentNewTabCommandPalette: presentBar
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
                browserRuntime?.windowActivation
                    .discardDeferredActivation(window)
            }
        )
    }

    func createArchivedWindow(
        from snapshot: LastSessionWindowSnapshot,
        sessionRestore: WindowSessionRestoreService
    ) -> BrowserWindowState? {
        var didPrepareArchivedSession = false
        return createPreparedWindow(
            initialize: { windowState in
                didPrepareArchivedSession = sessionRestore.prepareArchivedWindow(
                    snapshot,
                    forRegistration: windowState
                )
            },
            validateBeforeShell: { _ in didPrepareArchivedSession },
            discardPreparedState: {
                sessionRestore.cancelPreparedWindowRegistration($0)
            }
        )
    }
}
