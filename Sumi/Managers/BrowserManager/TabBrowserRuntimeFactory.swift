import Combine
import Foundation

/// Composition root for the per-tab runtime: assembles the `TabBrowserRuntime`
/// handed to each `Tab` from narrowly scoped runtime adapters over browser subsystems.
@MainActor
enum TabBrowserRuntimeFactory {
    static func make(for browserManager: BrowserManager) -> TabBrowserRuntime {
        let webViewRuntime = browserManager.webViewRuntime
        let physicalSources = PhysicalWebViewSourceResolver(
            ownership: webViewRuntime.ownershipQuery,
            tabs: browserManager.tabManager,
            profiles: browserManager.profileManager,
            registry: { [weak browserManager] in
                browserManager?.windowRegistry
            }
        )
        let physicalTabOpening = PhysicalSourceTabOpeningService(
            tabs: browserManager.tabManager,
            opening: browserManager.tabLifecycleService.opening,
            select: { [weak browserManager] tab, window, loadPolicy in
                browserManager?.selectTab(
                    tab,
                    in: window,
                    loadPolicy: loadPolicy
                )
            }
        )
        let extensions = browserManager.optionalModules.extensions
        let extensionExternalTabs = ExtensionExternalTabOpeningService(
            sources: physicalSources,
            tabs: physicalTabOpening,
            extensionTabs: extensions
        )
        let physicalWebPopups = PhysicalWebPopupOpeningService(
            sources: physicalSources,
            popups: browserManager.auxiliaryWindows.popups
        )
        let childTabs = WebKitChildTabOpeningService(
            sources: physicalSources,
            tabs: browserManager.tabManager,
            placement: webViewRuntime.trackedWebViewAdmission,
            selection: BrowserTabSelectionCommand {
                [weak browserManager] tab, window, loadPolicy in
                browserManager?.selectTab(
                    tab,
                    in: window,
                    loadPolicy: loadPolicy
                )
            },
            notifications: browserManager.notificationPresenter,
            extensionTabs: extensions
        )
        let childWindows = WebKitChildWindowOpeningService(
            windowTransaction: WebKitChildWindowShellTransaction(
                commands: browserManager.windowCommands,
                restoration: browserManager.windowSessionBundle.restoreService,
                profiles: browserManager.profileManager,
                tabs: browserManager.tabManager
            ),
            tabs: browserManager.tabManager,
            placement: webViewRuntime.trackedWebViewAdmission,
            ownershipQuery: webViewRuntime.ownershipQuery,
            sourceResolver: physicalSources,
            lifecycle: webViewRuntime.lifecycleService,
            extensionPublication: browserManager.windowExtensionPublication,
            persistWindowSession: { [weak browserManager] window in
                browserManager?.windowSessionBundle.persistence.persist(window)
            }
        )
        return TabBrowserRuntime(
            linkPresentationCommands: makeLinkPresentationCommands(
                for: browserManager,
                sourceResolver: physicalSources,
                tabOpening: physicalTabOpening
            ),
            webPageMenuCommands: TabWebPageMenuCommandsFactory.make(
                for: browserManager,
                ownershipQuery: webViewRuntime.ownershipQuery
            ),
            webViewRoutingRuntime: TabBrowserHostServicesRuntimeFactory.webViewRoutingRuntime(for: browserManager),
            persistenceRuntimeCallbacks: TabBrowserHostServicesRuntimeFactory.persistenceCallbacks(for: browserManager),
            mediaRuntimeCallbacks: TabBrowserHostServicesRuntimeFactory.mediaCallbacks(for: browserManager),
            navigationCommandRuntime: TabBrowserNavigationRuntimeFactory.navigationCommandRuntime(for: browserManager),
            profileResolutionRuntime: TabBrowserNavigationRuntimeFactory.profileResolutionRuntime(for: browserManager),
            reloadPolicies: TabBrowserNavigationRuntimeFactory.reloadPolicies(
                for: browserManager
            ),
            historySwipeRuntime: TabBrowserNavigationRuntimeFactory.historySwipeRuntime(for: browserManager),
            historyRecordingRuntime: TabBrowserNavigationRuntimeFactory.historyRecordingRuntime(for: browserManager),
            findInPageRuntime: TabBrowserNavigationRuntimeFactory.findInPageRuntime(for: browserManager),
            extensionPropertiesRuntime: TabBrowserExtensionRuntimeFactory.extensionPropertiesRuntime(for: browserManager),
            closeLifecycleRuntime: TabBrowserHostServicesRuntimeFactory.closeLifecycleRuntime(for: browserManager),
            lifecycleNavigationRuntime: TabBrowserNavigationRuntimeFactory.lifecycleNavigationRuntime(for: browserManager),
            permissionRuntime: TabBrowserHostServicesRuntimeFactory.permissionRuntime(
                for: browserManager,
                ownershipQuery: webViewRuntime.ownershipQuery,
                visibility: webViewRuntime.visibilityRuntime
            ),
            webViewCleanupRuntime: TabBrowserWebViewRuntimeFactory.cleanupRuntime(for: browserManager),
            untrackedWebViewInstallation:
                webViewRuntime.untrackedWebViewInstallationService,
            normalWebViewExtensionRuntime: TabBrowserExtensionRuntimeFactory.normalWebViewExtensionRuntime(for: browserManager),
            navigationDelegateRuntime: TabBrowserNavigationRuntimeFactory.navigationDelegateRuntime(for: browserManager),
            faviconExtensionRuntime: TabBrowserExtensionRuntimeFactory.faviconExtensionRuntime(for: browserManager),
            popupPermissionEvaluator:
                browserManager.permissionRuntime.popupPermissionBridge,
            extensionPopupRequestConsumer: extensions,
            extensionExternalTabOpening: extensionExternalTabs,
            physicalWebPopupOpening: physicalWebPopups,
            webKitChildTabOpening: childTabs,
            webKitChildWindowOpening: childWindows,
            webKitUIRuntime: TabBrowserWebViewRuntimeFactory.webKitUIRuntime(for: browserManager),
            webViewReplacementRuntime: TabBrowserWebViewRuntimeFactory.replacementRuntime(for: browserManager),
            webViewConfigurationContext: { [weak browserManager] in
                browserManager.map { TabBrowserWebViewRuntimeFactory.configurationContext(for: $0) } ?? .empty
            },
            dataServices: { [weak browserManager] in
                browserManager.flatMap { TabBrowserHostServicesRuntimeFactory.dataServices(for: $0) }
            },
            currentProfileUpdates: { [weak browserManager] in
                browserManager?.$currentProfile.eraseToAnyPublisher()
            },
            settings: { [weak browserManager] in
                browserManager?.sumiSettings
            }
        )
    }

    private static func makeLinkPresentationCommands(
        for browserManager: BrowserManager,
        sourceResolver: PhysicalWebViewSourceResolver,
        tabOpening: PhysicalSourceTabOpeningService
    ) -> TabLinkPresentationCommands {
        let linkWindows = BrowserLinkWindowTransaction(
            commands: browserManager.windowCommands,
            restoration: browserManager.windowSessionBundle.restoreService,
            extensionPublication: browserManager.windowExtensionPublication,
            profiles: browserManager.profileManager,
            tabs: browserManager.tabManager,
            persistWindow: { [weak browserManager] window in
                browserManager?.windowSessionBundle.persistence.persist(window)
            },
            materialize: { [weak browserManager] tab, window in
                guard let browserManager else { return nil }
                browserManager.materializeVisibleTabWebViewIfNeeded(
                    tab,
                    in: window
                )
                return browserManager.webViewRuntime.ownershipQuery.webView(
                    for: tab.id,
                    in: window.id
                ) as? FocusableWKWebView
            }
        )
        return TabLinkPresentationCommandsFactory.make(
            sourceResolver: sourceResolver,
            openTab: { [tabOpening] url, source, selected in
                tabOpening.open(
                    url,
                    from: source,
                    selected: selected
                ) != nil
            },
            openWindow: { [linkWindows] url, source, selected in
                linkWindows.open(
                    url,
                    from: source,
                    activate: selected
                ) != nil
            },
            activateSource: { [weak browserManager] source in
                guard let browserManager else { return false }
                browserManager.selectTab(
                    source.tab,
                    in: source.window,
                    loadPolicy: .immediate
                )
                return source.window.currentTabId == source.tab.id
            },
            presentGlance: { [weak browserManager] url, source, originRect in
                browserManager?.glanceManager.presentExternalURL(
                    url,
                    from: source.tab,
                    in: source.window,
                    originRectInWindow: originRect
                ) ?? false
            }
        )
    }
}
