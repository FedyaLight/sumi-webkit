import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
protocol ExtensionWebViewRuntimePreparing: AnyObject {
    func prepareWebViewConfigForExtensionRuntime(
        _ configuration: WKWebViewConfiguration,
        profileId: UUID?,
        reason: String
    )

    func prepareWebViewForExtensionRuntime(
        _ webView: WKWebView,
        currentURL: URL?,
        reason: String
    )
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionControllerBindingQuery: AnyObject {
    func extensionController(for tab: Tab) -> WKWebExtensionController?
    func resolvedLiveWebView(for tab: Tab) -> WKWebView?
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionControllerAttaching: AnyObject {
    func attachExtensionControllerIfNeeded(
        to webView: WKWebView,
        for tab: Tab
    ) -> Bool
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionControllerBinding:
    ExtensionControllerBindingQuery,
    ExtensionControllerAttaching {
    func ownedUntrackedCurrentWebView(for tab: Tab) -> WKWebView?
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
