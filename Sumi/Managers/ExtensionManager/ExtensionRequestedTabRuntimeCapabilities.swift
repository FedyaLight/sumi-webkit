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
protocol ExtensionControllerBinding: AnyObject {
    func extensionController(for tab: Tab) -> WKWebExtensionController?
    func ownedUntrackedCurrentWebView(for tab: Tab) -> WKWebView?
    func attachExtensionControllerIfNeeded(
        to webView: WKWebView,
        for tab: Tab
    ) -> Bool
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionContentScriptContextLoading: AnyObject {
    func profileHasLoadedContentScriptContexts(profileId: UUID) -> Bool
    func ensureContentScriptContextsLoaded(for profileId: UUID) async
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabOpenNotifying: AnyObject {
    func notifyTabOpened(_ tab: Tab) -> Bool
}
