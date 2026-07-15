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
    private weak var profiles: (any ExtensionTabProfileResolving)?
    private weak var webViews: ExtensionExactTabWebViewQuery?
    private weak var controllerAdmission:
        (any ExtensionWebViewControllerAdmitting)?

    init(
        profileRuntime: ExtensionProfileRuntime,
        contextPublications: ExtensionContextPublicationQuery,
        profiles: any ExtensionTabProfileResolving,
        webViews: ExtensionExactTabWebViewQuery,
        controllerAdmission: any ExtensionWebViewControllerAdmitting
    ) {
        self.profileRuntime = profileRuntime
        self.contextPublications = contextPublications
        self.profiles = profiles
        self.webViews = webViews
        self.controllerAdmission = controllerAdmission
    }

    func extensionWebView(
        for tab: Tab,
        extensionContext: WKWebExtensionContext
    ) -> WKWebView? {
        guard let profileRuntime,
              let identity = contextPublications?.currentIdentity(
                for: extensionContext
              ),
              webViews?.isCanonical(tab) == true,
              tab.isEphemeral == false,
              profiles?.profileID(for: tab) == identity.profileID,
              let controller = profileRuntime.controller(
                for: identity.profileID
              ),
              let webView = webViews?.liveWebView(for: tab),
              controllerAdmission?.admit(
                  controller,
                  profileID: identity.profileID,
                  to: webView,
                  for: tab
              ).isUsable == true,
              contextPublications?.isCurrent(
                extensionContext,
                extensionID: identity.extensionID,
                profileID: identity.profileID
              ) == true,
              webViews?.isCanonical(tab) == true,
              profiles?.profileID(for: tab) == identity.profileID,
              webViews?.liveWebView(for: tab) === webView,
              webView.configuration.webExtensionController === controller
        else {
            return nil
        }
        return webView
    }
}
