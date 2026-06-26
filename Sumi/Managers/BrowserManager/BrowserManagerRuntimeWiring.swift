import Combine
import Foundation

@MainActor
enum BrowserManagerRuntimeWiring {
    static func attach(to browserManager: BrowserManager) -> AnyCancellable {
        browserManager.compositorManager.browserManager = browserManager
        browserManager.tabSuspensionService.attach(browserManager: browserManager)
        browserManager.backgroundMediaOptimizationService.attach(browserManager: browserManager)
        browserManager.splitManager.browserManager = browserManager
        browserManager.splitManager.windowRegistry = browserManager.windowRegistry
        browserManager.tabManager.browserManager = browserManager
        browserManager.tabManager.reattachBrowserManager(browserManager)
        browserManager.liveFolderManager.attach(browserManager: browserManager)
        browserManager.downloadManager.browserManager = browserManager
        browserManager.extensionsModule.attach(browserManager: browserManager)
        browserManager.userscriptsModule.attach(browserManager: browserManager)
        browserManager.boostsModule.attach(browserManager: browserManager)
        let structuralChangeCancellable = bindTabManagerStructuralUpdates(for: browserManager)
        browserManager.auxiliaryWindowManager.attach(browserManager: browserManager)
        browserManager.glanceManager.attach(browserManager: browserManager)
        browserManager.authenticationManager.attach(browserManager: browserManager)
        return structuralChangeCancellable
    }

    private static func bindTabManagerStructuralUpdates(
        for browserManager: BrowserManager
    ) -> AnyCancellable {
        browserManager.tabManager.structuralChanges
            .receive(on: RunLoop.main)
            .sink { [weak browserManager] _ in
                browserManager?.tabStructuralRevision &+= 1
                browserManager?.tabSuspensionService.scheduleProactiveTimerReconcile(
                    reason: "tab-structure-changed"
                )
                browserManager?.backgroundMediaOptimizationService.scheduleReconcile(
                    reason: "tab-structure-changed"
                )
            }
    }
}
