import Combine
import Foundation
import SumiSidebarChrome

@MainActor
enum BrowserManagerRuntimeWiring {
    static func attach(to browserManager: BrowserManager) -> AnyCancellable {
        browserManager.compositorManager.attach(runtime: .make(browserManager: browserManager))
        let tabRuntimeCompositionCancellable = BrowserTabRuntimeCompositionService.attach(
            to: browserManager
        )
        browserManager.splitManager.attach(
            runtime: BrowserSplitViewRuntimeFactory.runtime(for: browserManager)
        )
        let runtimePortRegistry = BrowserTabManagerRuntimePortsFactory.registry(for: browserManager)
        browserManager.attachRuntimePortRegistry(runtimePortRegistry)
        browserManager.tabManager.runtimePortsAttachmentOwner.attach(runtimePortRegistry)
        // W8/R12: bind chrome commanding so SumiSidebarChrome peels stay hub-free.
        SidebarChromeModule.bind(browserManager.sidebarChromeCommanding)
        // Live Folders runtime attaches only when the module is enabled (W4/R9),
        // via OptionalModuleHost.attachEnabled.
        browserManager.downloadManager.retryRuntime = BrowserDownloadRetryRuntimeFactory.runtime(for: browserManager)
        browserManager.optionalModuleHost.attachEnabled(into: browserManager)
        browserManager.auxiliaryWindowManager.attach(
            runtime: BrowserAuxiliaryWindowRuntimeService.runtime(for: browserManager)
        )
        browserManager.glanceManager.attach(
            runtime: BrowserGlanceRuntimeService.runtime(for: browserManager)
        )
        browserManager.authenticationManager.attach(
            runtime: BrowserAuthenticationRuntimeFactory.runtime(for: browserManager)
        )
        return tabRuntimeCompositionCancellable
    }

    static func tabSelectionRuntimeNotifications(
        for browserManager: BrowserManager
    ) -> BrowserTabSelectionOwner.RuntimeNotifications {
        BrowserTabRuntimeCompositionService.tabSelectionRuntimeNotifications(
            for: browserManager
        )
    }

    static func nativeNowPlayingRuntimeContext(
        for browserManager: BrowserManager
    ) -> SumiNativeNowPlayingRuntimeContext {
        BrowserNativeNowPlayingRuntimeFactory.context(for: browserManager)
    }
}
