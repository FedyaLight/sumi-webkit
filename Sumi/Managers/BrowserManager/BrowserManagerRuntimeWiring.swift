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

    static func tabSelectionRuntimeNotifications(
        for browserManager: BrowserManager
    ) -> BrowserTabSelectionOwner.RuntimeNotifications {
        BrowserTabSelectionOwner.RuntimeNotifications(
            tabActivated: { [weak browserManager] newTab, previousTab in
                guard let browserManager else { return }
                notifyExtensionTabActivated(
                    newTab,
                    previous: previousTab,
                    for: browserManager
                )
            },
            tabSelectionChanged: { [weak browserManager] reason in
                guard let browserManager else { return }
                scheduleTabRuntimeReconcile(for: browserManager, reason: reason)
            }
        )
    }

    static func notifyExtensionWindowOpened(
        _ windowState: BrowserWindowState,
        for browserManager: BrowserManager
    ) {
        browserManager.extensionsModule.notifyWindowOpenedIfLoaded(windowState)
    }

    static func notifyExtensionWindowFocused(
        _ windowState: BrowserWindowState,
        for browserManager: BrowserManager
    ) {
        browserManager.extensionsModule.notifyWindowFocusedIfLoaded(windowState)
    }

    static func notifyExtensionTabClosed(
        _ tab: Tab,
        for browserManager: BrowserManager
    ) {
        browserManager.extensionsModule.notifyTabClosedIfLoaded(tab)
    }

    private static func bindTabManagerStructuralUpdates(
        for browserManager: BrowserManager
    ) -> AnyCancellable {
        browserManager.tabManager.structuralChanges
            .receive(on: RunLoop.main)
            .sink { [weak browserManager] _ in
                guard let browserManager else { return }
                handleTabManagerStructuralChange(for: browserManager)
            }
    }

    private static func handleTabManagerStructuralChange(for browserManager: BrowserManager) {
        browserManager.tabStructuralRevision &+= 1
        scheduleTabRuntimeReconcile(for: browserManager, reason: "tab-structure-changed")
    }

    private static func notifyExtensionTabActivated(
        _ newTab: Tab,
        previous: Tab?,
        for browserManager: BrowserManager
    ) {
        browserManager.extensionsModule.notifyTabActivatedIfLoaded(
            newTab: newTab,
            previous: previous
        )
    }

    private static func scheduleTabRuntimeReconcile(
        for browserManager: BrowserManager,
        reason: String
    ) {
        browserManager.tabSuspensionService.scheduleProactiveTimerReconcile(reason: reason)
        browserManager.backgroundMediaOptimizationService.scheduleReconcile(reason: reason)
    }
}
