import Combine
import Foundation

/// Composition root for the per-tab runtime: assembles the `TabBrowserRuntime`
/// handed to each `Tab` from narrowly scoped runtime adapters over browser subsystems.
@MainActor
enum TabBrowserRuntimeFactory {
    static func make(for browserManager: BrowserManager) -> TabBrowserRuntime {
        TabBrowserRuntime(
            browserActionService: TabBrowserActionServiceFactory.make(for: browserManager),
            webViewRoutingRuntime: TabBrowserHostServicesRuntimeFactory.webViewRoutingRuntime(for: browserManager),
            persistenceRuntimeCallbacks: TabBrowserHostServicesRuntimeFactory.persistenceCallbacks(for: browserManager),
            mediaRuntimeCallbacks: TabBrowserHostServicesRuntimeFactory.mediaCallbacks(for: browserManager),
            navigationCommandRuntime: TabBrowserNavigationRuntimeFactory.navigationCommandRuntime(for: browserManager),
            profileResolutionRuntime: TabBrowserNavigationRuntimeFactory.profileResolutionRuntime(for: browserManager),
            reloadPolicyRuntime: TabBrowserNavigationRuntimeFactory.reloadPolicyRuntime(for: browserManager),
            historySwipeRuntime: TabBrowserNavigationRuntimeFactory.historySwipeRuntime(for: browserManager),
            historyRecordingRuntime: TabBrowserNavigationRuntimeFactory.historyRecordingRuntime(for: browserManager),
            findInPageRuntime: TabBrowserNavigationRuntimeFactory.findInPageRuntime(for: browserManager),
            extensionPropertiesRuntime: TabBrowserExtensionRuntimeFactory.extensionPropertiesRuntime(for: browserManager),
            closeLifecycleRuntime: TabBrowserHostServicesRuntimeFactory.closeLifecycleRuntime(for: browserManager),
            lifecycleNavigationRuntime: TabBrowserNavigationRuntimeFactory.lifecycleNavigationRuntime(for: browserManager),
            permissionRuntime: TabBrowserHostServicesRuntimeFactory.permissionRuntime(for: browserManager),
            webViewCleanupRuntime: TabBrowserWebViewRuntimeFactory.cleanupRuntime(for: browserManager),
            normalWebViewExtensionRuntime: TabBrowserExtensionRuntimeFactory.normalWebViewExtensionRuntime(for: browserManager),
            scriptMessageRuntime: TabBrowserHostServicesRuntimeFactory.scriptMessageRuntime(for: browserManager),
            navigationDelegateRuntime: TabBrowserNavigationRuntimeFactory.navigationDelegateRuntime(for: browserManager),
            faviconExtensionRuntime: TabBrowserExtensionRuntimeFactory.faviconExtensionRuntime(for: browserManager),
            popupHandlingRuntime: TabPopupRuntimeFactory.make(for: browserManager),
            installNavigationRuntime: TabBrowserNavigationRuntimeFactory.installNavigationRuntime(for: browserManager),
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
}
