import Foundation

@MainActor
extension WindowWebContentContext {
    static func make(
        browserManager: BrowserManager
    ) -> WindowWebContentContext {
        WindowWebContentContext(
            browserContext: browserManager.composeWebsiteViewBrowserContext(),
            nativeSurfaceRootBuilders: WebsiteViewContextFactory.nativeSurfaceRootBuilders(
                for: browserManager
            ),
            webViewOwnershipQuery: browserManager.webViewRuntime.ownershipQuery,
            webViewCompositorRuntime: browserManager.webViewRuntime.compositorRuntime,
            webViewProtectionRuntime: browserManager.webViewRuntime.protectionRuntime
        )
    }
}

@MainActor
extension WindowSplitContext {
    static func make(browserManager: BrowserManager) -> WindowSplitContext {
        browserManager.splitWindowContext
    }
}

@MainActor
extension WindowSidebarContext {
    static func make(
        browserManager: BrowserManager,
        updaterService: SumiUpdaterService,
        nowPlayingController: SumiNativeNowPlayingController
    ) -> WindowSidebarContext {
        browserManager.composeWindowSidebarContext(
            updaterService: updaterService,
            nowPlayingController: nowPlayingController
        )
    }
}

@MainActor
extension WindowNativeModalContext {
    static func make(browserManager: BrowserManager) -> WindowNativeModalContext {
        let presentationOwner = browserManager.chromeBundle.nativeDialogPresentationOwner
        let profileManager = browserManager.profileManager
        let historyManager = browserManager.historyManager
        let websiteDataCleanupService = browserManager.dataServices
            .websiteDataCleanupService
        let currentProfileAuthority = browserManager.currentProfileAuthority

        return WindowNativeModalContext(
            presentationOwner: presentationOwner,
            presentationState: browserManager.nativeModalPresentationState,
            browsingDataDialogContext: SumiBrowsingDataDialogContext(
                cleanupService: browserManager.browsingDataCleanupService,
                profileSnapshot: { [profileManager] in
                    profileManager.profiles
                },
                activeCleanupDependencies: {
                    [
                        currentProfileAuthority,
                        profileManager,
                        historyManager,
                        websiteDataCleanupService
                    ] in
                    guard currentProfileAuthority.currentProfile != nil else { return nil }
                    return BrowsingDataDialogCleanupDependencies(
                        historyManager: historyManager,
                        profiles: profileManager.profiles,
                        websiteDataCleanupService: websiteDataCleanupService
                    )
                },
                dismissNativeModalPresentation: { [presentationOwner] in
                    presentationOwner.dismissNativeModalPresentation()
                }
            )
        )
    }
}

@MainActor
extension WindowFindContext {
    static func make(browserManager: BrowserManager) -> WindowFindContext {
        WindowFindContext(manager: browserManager.findManager)
    }
}

@MainActor
extension WindowThemeChromeContext {
    static func make(browserManager: BrowserManager) -> WindowThemeChromeContext {
        browserManager.composeWindowThemeChromeContext()
    }
}
