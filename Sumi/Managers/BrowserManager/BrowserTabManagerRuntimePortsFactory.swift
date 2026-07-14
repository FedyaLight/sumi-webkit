import Foundation

@MainActor
enum BrowserTabManagerRuntimePortsFactory {
    static func registry(for browserManager: BrowserManager) -> RuntimePortRegistry {
        let runtime = BrowserManagerRuntimeReference(browserManager)
        return RuntimePortRegistry(
            profileQuery: LiveTabProfileQueryPort(
                currentProfileAuthority: browserManager.currentProfileAuthority,
                profileManager: browserManager.profileManager,
                settingsAttachment: browserManager.settingsAttachment
            ),
            windowQuery: LiveTabWindowQueryPort(runtime: runtime),
            splitCoordination: LiveTabSplitCoordinationPort(
                tabClosures: browserManager.splitComposition.tabClosures,
                query: browserManager.splitComposition.query
            ),
            extensionLifecycle: LiveTabExtensionLifecyclePort(runtime: runtime),
            sessionSideEffects: LiveTabSessionSideEffectsPort(
                recentlyClosedManager: browserManager.recentlyClosedManager,
                notificationPresenter: browserManager.notificationPresenter,
                webViewCloseRouter: browserManager.webViewCloseRouter,
                liveFolderManager: browserManager.liveFolderManager
            ),
            webViewLifecycle: BrowserTabManagerWebViewLifecycleFactory.service(runtime: runtime)
        )
    }
}
