import Combine
import Foundation

@MainActor
enum BrowserManagerRuntimeWiring {
    static func attach(to browserManager: BrowserManager) -> AnyCancellable {
        browserManager.compositorManager.attach(runtime: .live(browserManager: browserManager))
        browserManager.tabSuspensionService.attach(browserManager: browserManager)
        browserManager.backgroundMediaOptimizationService.attach(
            runtime: backgroundMediaOptimizationRuntime(for: browserManager)
        )
        browserManager.splitManager.attach(runtime: .live(browserManager: browserManager))
        browserManager.splitManager.windowRegistry = browserManager.windowRegistry
        browserManager.tabManager.browserManager = browserManager
        browserManager.tabManager.attachRuntimeContext(
            BrowserManagerTabRuntimeContext(browserManager: browserManager)
        )
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

    static func nativeNowPlayingRuntimeContext(
        for browserManager: BrowserManager
    ) -> SumiNativeNowPlayingRuntimeContext {
        SumiNativeNowPlayingRuntimeContext.live(
            runtime: nativeNowPlayingBrowserRuntime(for: browserManager)
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

    private static func backgroundMediaOptimizationRuntime(
        for browserManager: BrowserManager
    ) -> SumiBackgroundMediaOptimizationRuntime {
        SumiBackgroundMediaOptimizationRuntime(
            webViewCoordinator: { [weak browserManager] in
                browserManager?.webViewCoordinator
            },
            energySaverActive: { [weak browserManager] in
                browserManager?.sumiSettings?.energySaverActivation.isActive ?? false
            },
            allKnownTabs: { [weak browserManager] in
                guard let browserManager else { return [] }
                return allBackgroundMediaOptimizationTabs(for: browserManager)
            },
            visibleTabIDsByWindow: { [weak browserManager] in
                guard let browserManager else { return [:] }
                return backgroundMediaVisibleTabIDsByWindow(for: browserManager)
            }
        )
    }

    private static func nativeNowPlayingBrowserRuntime(
        for browserManager: BrowserManager
    ) -> SumiNativeNowPlayingBrowserRuntime {
        SumiNativeNowPlayingBrowserRuntime(
            windowStates: { [weak browserManager] in
                browserManager?.windowRegistry?.windows.values.map { $0 } ?? []
            },
            windowState: { [weak browserManager] windowId in
                browserManager?.windowRegistry?.windows[windowId]
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.currentTab(for: windowState)
            },
            mediaCandidateTabs: { [weak browserManager] windowState in
                browserManager?.windowScopedMediaCandidateTabs(in: windowState) ?? []
            },
            tab: { [weak browserManager] tabId in
                browserManager?.tabManager.tab(for: tabId)
            },
            resolvedNowPlayingWebView: { [weak browserManager] tab, windowState in
                guard let browserManager else { return nil }
                return tab.authoritativeMediaWebView(
                    resolvedWindowWebView: browserManager.webViewRoutingService.webView(
                        for: tab.id,
                        in: windowState.id
                    )
                )
            },
            selectTab: { [weak browserManager] tab, windowState in
                browserManager?.selectTab(tab, in: windowState)
            }
        )
    }

    private static func backgroundMediaVisibleTabIDsByWindow(
        for browserManager: BrowserManager
    ) -> [UUID: Set<UUID>] {
        guard let windowRegistry = browserManager.windowRegistry else { return [:] }

        var visibleTabIDsByWindow: [UUID: Set<UUID>] = [:]
        for windowState in windowRegistry.windows.values where windowState.windowVisibilityState.isEffectivelyVisible {
            let tabIDs = VisibleTabPreparationPlan.visibleTabIDs(
                currentTabId: browserManager.currentTab(for: windowState)?.id,
                splitTabIds: browserManager.splitManager.visibleTabIds(for: windowState.id)
            )
            visibleTabIDsByWindow[windowState.id] = Set(tabIDs)
        }
        return visibleTabIDsByWindow
    }

    private static func allBackgroundMediaOptimizationTabs(
        for browserManager: BrowserManager
    ) -> [Tab] {
        var seen = Set<UUID>()
        var tabs: [Tab] = []

        func append(_ tab: Tab) {
            guard seen.insert(tab.id).inserted else { return }
            tabs.append(tab)
        }

        browserManager.tabManager.allTabs().forEach(append)
        (browserManager.windowRegistry?.windows.values.map { $0 } ?? [])
            .flatMap(\.ephemeralTabs)
            .forEach(append)
        return tabs
    }
}
