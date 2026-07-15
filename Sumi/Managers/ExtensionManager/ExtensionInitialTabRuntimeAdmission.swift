import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionInitialTabRuntimeAdmission {
    private let profileRuntime: ExtensionProfileRuntime
    private let contextLoading: any ExtensionContentScriptContextLoading
    private let controllerQuery: any ExtensionTabControllerQuery
    private let controllerAdmission: any ExtensionWebViewControllerAdmitting
    private let extensionsLoaded: @MainActor () -> Bool

    init(
        profileRuntime: ExtensionProfileRuntime,
        contextLoading: any ExtensionContentScriptContextLoading,
        controllerQuery: any ExtensionTabControllerQuery,
        controllerAdmission: any ExtensionWebViewControllerAdmitting,
        extensionsLoaded: @escaping @MainActor () -> Bool
    ) {
        self.profileRuntime = profileRuntime
        self.contextLoading = contextLoading
        self.controllerQuery = controllerQuery
        self.controllerAdmission = controllerAdmission
        self.extensionsLoaded = extensionsLoaded
    }

    func admit(
        tab: Tab,
        webView: FocusableWKWebView,
        profileID: UUID
    ) -> WKWebExtensionController? {
        guard extensionsLoaded(),
              contextLoading.profileHasLoadedContentScriptContexts(
                  profileId: profileID
              ),
              let controller = controllerQuery.existingController(for: tab),
              controllerAdmission.admit(
                  controller,
                  profileID: profileID,
                  to: webView,
                  for: tab
              ).isUsable,
              profileRuntime.controller(for: profileID) === controller,
              webView.configuration.webExtensionController === controller
        else { return nil }
        return controller
    }
}
