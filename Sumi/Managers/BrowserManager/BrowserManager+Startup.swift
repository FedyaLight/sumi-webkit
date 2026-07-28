import Foundation

extension BrowserManager {
    private var startupServices: BrowserStartupServices {
        if let startupServicesStorage {
            return startupServicesStorage
        }
        let services = BrowserStartupServices(
            browserManager: self,
            splitQuery: splitQuery
        )
        startupServicesStorage = services
        return services
    }

    var profileWebKitBootstrap: BrowserProfileWebKitBootstrap {
        startupServices.profileWebKitBootstrap
    }

    var pageActivationPerformance: PageActivationPerformanceMonitor {
        startupServices.pageActivationPerformance
    }

    func prepareRuntimeForStartupRecovery() {
        startupServices.prepareRuntimeForStartupRecovery()
    }

    func startRuntimeAfterStartupRecovery() {
        startupServices.startRuntime(
            after: profileRetirementStartupPreflight
        )
    }

    func makeInitialWindowState(
        preparesForLaunch: Bool = true
    ) -> BrowserWindowState {
        let windowState = BrowserWindowState(
            initialWorkspaceTheme: spaceStateOwner.currentSpace?.workspaceTheme,
            awaitsInitialSessionResolution: true,
            sidebarRecoveryCoordinator: sidebarHostRecoveryCoordinator
        )
        if preparesForLaunch {
            prepareInitialWindowState(windowState)
        }
        return windowState
    }

    func prepareInitialWindowState(_ windowState: BrowserWindowState) {
        _ = windowSessionBundle.restoreService.prepareInitialWindow(
            windowState,
            currentProfile: currentProfile
        )
    }
}
