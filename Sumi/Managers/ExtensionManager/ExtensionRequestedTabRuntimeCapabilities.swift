import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
protocol ExtensionWebViewConfigurationPreparing: AnyObject {
    func prepareWebViewConfigForExtensionRuntime(
        _ configuration: WKWebViewConfiguration,
        profileId: UUID?,
        reason: String
    )

}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionLiveWebViewRuntimePreparing: AnyObject {
    func prepareWebViewForExtensionRuntime(
        _ webView: WKWebView,
        currentURL: URL?,
        reason: String
    )
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionContentScriptContextLoading: AnyObject {
    func profileHasLoadedContentScriptContexts(profileId: UUID) -> Bool
    func ensureContentScriptContextsLoaded(for profileId: UUID) async
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabLifecycleEventSink: AnyObject {
    func emitDidOpenTab(
        _ tab: Tab,
        controller: WKWebExtensionController,
        adapter: ExtensionTabAdapter
    )
    func emitDidCloseTab(
        _ tab: Tab,
        controller: WKWebExtensionController,
        adapter: ExtensionTabAdapter
    )
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionInitialTabLifecycleEventSink: AnyObject {
    func emitDidOpenInitialTab(
        _ tab: Tab,
        controller: WKWebExtensionController,
        adapter: ExtensionTabAdapter
    )
    func emitDidCloseInitialTab(
        _ tab: Tab,
        controller: WKWebExtensionController,
        adapter: ExtensionTabAdapter
    )
}
