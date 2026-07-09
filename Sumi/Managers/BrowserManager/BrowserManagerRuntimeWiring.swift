import Combine
import Foundation

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
        browserManager.tabManager.runtimeContextAttachmentOwner.attach(
            BrowserTabManagerRuntimeContextFactory.runtime(for: browserManager)
        )
        browserManager.liveFolderManager.attach(
            runtime: BrowserLiveFolderRuntimeService.runtime(for: browserManager)
        )
        browserManager.downloadManager.retryRuntime = BrowserDownloadRetryRuntimeFactory.runtime(for: browserManager)
        browserManager.extensionsModule.attach(
            runtime: BrowserExtensionsModuleRuntimeFactory.runtime(for: browserManager)
        )
        browserManager.userscriptsModule.attach(
            runtime: BrowserUserscriptRuntimeFactory.runtime(for: browserManager)
        )
        browserManager.boostsModule.attach(
            runtime: BrowserBoostRuntimeFactory.runtime(for: browserManager)
        )
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
