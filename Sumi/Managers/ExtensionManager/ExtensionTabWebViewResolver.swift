import Foundation
import WebKit

/// Resolves the exact live WebView an already-admitted extension Tab may use.
/// Controller attachment is the only mutation; every identity involved is
/// revalidated after that synchronous boundary before the WebView escapes.
@available(macOS 15.5, *)
@MainActor
final class ExtensionTabWebViewResolver: ExtensionTabWebViewProjectionQuery {
    private weak var profileRuntime: ExtensionProfileRuntime?
    private weak var contextPublications: ExtensionContextPublicationQuery?
    private weak var controllerAttachment: (any ExtensionControllerAttaching)?
    private let profileID: @MainActor (Tab) -> UUID?
    private let tabIsCurrent: @MainActor (Tab) -> Bool
    private let liveWebView: @MainActor (Tab) -> WKWebView?

    init(
        profileRuntime: ExtensionProfileRuntime,
        contextPublications: ExtensionContextPublicationQuery,
        controllerAttachment: any ExtensionControllerAttaching,
        profileID: @escaping @MainActor (Tab) -> UUID?,
        tabIsCurrent: @escaping @MainActor (Tab) -> Bool,
        liveWebView: @escaping @MainActor (Tab) -> WKWebView?
    ) {
        self.profileRuntime = profileRuntime
        self.contextPublications = contextPublications
        self.controllerAttachment = controllerAttachment
        self.profileID = profileID
        self.tabIsCurrent = tabIsCurrent
        self.liveWebView = liveWebView
    }

    func extensionWebView(
        for tab: Tab,
        extensionContext: WKWebExtensionContext
    ) -> WKWebView? {
        guard let profileRuntime,
              let identity = contextPublications?.currentIdentity(
                for: extensionContext
              ),
              tabIsCurrent(tab),
              tab.isEphemeral == false,
              profileID(tab) == identity.profileID,
              let webView = liveWebView(tab),
              controllerAttachment?.attachExtensionControllerIfNeeded(
                to: webView,
                for: tab
              ) == true,
              contextPublications?.isCurrent(
                extensionContext,
                extensionID: identity.extensionID,
                profileID: identity.profileID
              ) == true,
              tabIsCurrent(tab),
              profileID(tab) == identity.profileID,
              liveWebView(tab) === webView,
              let controller = profileRuntime.controller(for: identity.profileID),
              webView.configuration.webExtensionController === controller
        else {
            return nil
        }
        return webView
    }
}
