import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionAuxiliaryTabPublicationAdmissionEvidence {
    let dataStore: WKWebsiteDataStore
    let controller: WKWebExtensionController
    let contextBindingGeneration: UInt64
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionAuxiliaryTabPublicationAdmission {
    private let profileRuntime: ExtensionProfileRuntime
    private let browserProfiles: ExtensionBrowserProfileQuery
    private let tabProfiles: any ExtensionTabProfileResolving
    private let controllers: any ExtensionTabControllerQuery
    private let webViews: ExtensionExactTabWebViewQuery
    private let controllerAdmission: any ExtensionWebViewControllerAdmitting
    private let extensionsLoaded: @MainActor () -> Bool

    init(
        profileRuntime: ExtensionProfileRuntime,
        browserProfiles: ExtensionBrowserProfileQuery,
        tabProfiles: any ExtensionTabProfileResolving,
        controllers: any ExtensionTabControllerQuery,
        webViews: ExtensionExactTabWebViewQuery,
        controllerAdmission: any ExtensionWebViewControllerAdmitting,
        extensionsLoaded: @escaping @MainActor () -> Bool
    ) {
        self.profileRuntime = profileRuntime
        self.browserProfiles = browserProfiles
        self.tabProfiles = tabProfiles
        self.controllers = controllers
        self.webViews = webViews
        self.controllerAdmission = controllerAdmission
        self.extensionsLoaded = extensionsLoaded
    }

    func admit(
        session: AuxiliaryWindowSession,
        profileID: UUID,
        ownerExtensionID: String,
        ownerContext: WKWebExtensionContext
    ) -> ExtensionAuxiliaryTabPublicationAdmissionEvidence? {
        let tab = session.tab
        let webView = session.webView
        guard extensionsLoaded(),
              session.isPrivate == false,
              tabProfiles.profileID(for: tab) == profileID,
              let dataStore = browserProfiles.anyProfile(profileID)?.dataStore,
              webView.configuration.websiteDataStore === dataStore,
              profileRuntime.profileId(for: ownerContext) == profileID,
              profileRuntime.extensionId(for: ownerContext) == ownerExtensionID,
              profileRuntime.contexts(for: profileID)[ownerExtensionID]
                === ownerContext,
              webViews.untrackedWebView(for: tab) === webView,
              let controller = controllers.existingController(for: tab),
              controllerAdmission.admit(
                  controller,
                  profileID: profileID,
                  to: webView,
                  for: tab
              ).isUsable,
              profileRuntime.controller(for: profileID) === controller,
              webView.configuration.webExtensionController === controller
        else { return nil }
        return ExtensionAuxiliaryTabPublicationAdmissionEvidence(
            dataStore: dataStore,
            controller: controller,
            contextBindingGeneration: profileRuntime
                .contextBindingGeneration(for: profileID)
        )
    }
}
