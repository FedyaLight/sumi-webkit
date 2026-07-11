import Foundation

@MainActor
enum BrowserTabManagerRuntimePortsFactory {
    static func registry(for browserManager: BrowserManager) -> RuntimePortRegistry {
        let runtime = BrowserManagerRuntimeReference(browserManager)
        return RuntimePortRegistry(
            profileQuery: LiveTabProfileQueryPort(runtime: runtime),
            windowQuery: LiveTabWindowQueryPort(runtime: runtime),
            splitCoordination: LiveTabSplitCoordinationPort(
                tabClosures: browserManager.splitComposition.tabClosures,
                query: browserManager.splitComposition.query
            ),
            extensionLifecycle: LiveTabExtensionLifecyclePort(runtime: runtime),
            sessionSideEffects: LiveTabSessionSideEffectsPort(runtime: runtime),
            webViewLifecycle: BrowserTabManagerWebViewLifecycleFactory.service(runtime: runtime)
        )
    }
}
