import Foundation
import WebKit

/// Builds and revalidates requested-Tab evidence. Every post-callback check is
/// read-only: window reconciliation is owned solely by pre-receipt admission.
@available(macOS 15.5, *)
@MainActor
final class ExtensionCreatedTabPublicationValidator {
    private let runtimePublicationEvidence:
        ExtensionRuntimePublicationEvidenceIssuer
    private let profileRuntime: ExtensionProfileRuntime
    private let tabProfiles: any ExtensionTabProfileResolving
    private let browserProfiles: ExtensionBrowserProfileQuery
    private let controllers: any ExtensionTabControllerQuery
    private let webViews: ExtensionExactTabWebViewQuery
    private let controllerAdmission: any ExtensionWebViewControllerAdmitting
    private let contextLoading: any ExtensionContentScriptContextLoading
    private let publications: ExtensionWindowPublicationQuery
    private let adapters: ExtensionCreatedTabAdapterPublication

    init(
        runtimePublicationEvidence:
            ExtensionRuntimePublicationEvidenceIssuer,
        profileRuntime: ExtensionProfileRuntime,
        tabProfiles: any ExtensionTabProfileResolving,
        browserProfiles: ExtensionBrowserProfileQuery,
        controllers: any ExtensionTabControllerQuery,
        webViews: ExtensionExactTabWebViewQuery,
        controllerAdmission: any ExtensionWebViewControllerAdmitting,
        contextLoading: any ExtensionContentScriptContextLoading,
        publications: ExtensionWindowPublicationQuery,
        adapters: ExtensionCreatedTabAdapterPublication
    ) {
        self.runtimePublicationEvidence = runtimePublicationEvidence
        self.profileRuntime = profileRuntime
        self.tabProfiles = tabProfiles
        self.browserProfiles = browserProfiles
        self.controllers = controllers
        self.webViews = webViews
        self.controllerAdmission = controllerAdmission
        self.contextLoading = contextLoading
        self.publications = publications
        self.adapters = adapters
    }

    func prepareBase(
        for tab: Tab
    ) -> ExtensionCreatedTabPublicationBaseEvidence? {
        guard tab.isEphemeral == false,
              let profileID = tabProfiles.profileID(for: tab),
              profileIsReady(profileID),
              let dataStore = browserProfiles.anyProfile(profileID)?.dataStore,
              let webView = webViews.liveWebView(for: tab),
              webView.configuration.websiteDataStore === dataStore,
              let controller = controllers.existingController(for: tab),
              controllerAdmission.admit(
                  controller,
                  profileID: profileID,
                  to: webView,
                  for: tab
              ).isUsable,
              profileRuntime.controller(for: profileID) === controller,
              webView.configuration.webExtensionController === controller
        else {
            return nil
        }

        return ExtensionCreatedTabPublicationBaseEvidence(
            tab: tab,
            webView: webView,
            dataStore: dataStore,
            profileID: profileID,
            controller: controller,
            runtimePublication: runtimePublicationEvidence.issue(),
            contextBindingGeneration: profileRuntime
                .contextBindingGeneration(for: profileID)
        )
    }

    func preparedEvidenceIsCurrent(
        _ evidence: ExtensionCreatedTabPublicationEvidence
    ) -> Bool {
        capturedRuntimeStateIsCurrent(evidence)
            && evidence.tab.extensionPageRuntimeOwner
                .canCommitWindowPrepublication(evidence.stateToken)
            && evidence.tab.extensionPageRuntimeOwner
                .hasDidOpenTabNotification(for: evidence.generation) == false
    }

    func capturedOpenIsCurrent(
        _ evidence: ExtensionCreatedTabPublicationEvidence
    ) -> Bool {
        capturedRuntimeStateIsCurrent(evidence)
            && evidence.tab.extensionPageRuntimeOwner
                .isCommittedWindowPrepublicationCurrent(
                    evidence.stateToken,
                    generation: evidence.generation
                )
            && adapterIsOpenInProfileContexts(evidence)
    }

    func currentGenerationOpenIsExact(
        _ evidence: ExtensionCreatedTabPublicationEvidence
    ) -> Bool {
        let base = evidence.base
        let currentRuntimePublication = runtimePublicationEvidence.issue()
        let currentGeneration = currentRuntimePublication.tabPublication
        let binding = base.tab.extensionPageRuntimeOwner
            .documentBindingSnapshot()
        guard profileIsReady(base.profileID),
              tabProfiles.profileID(for: base.tab) == base.profileID,
              browserProfiles.anyProfile(base.profileID)?.dataStore
                === base.dataStore,
              base.webView.configuration.websiteDataStore === base.dataStore,
              let currentController = profileRuntime.controller(
                  for: base.profileID
              ), controllers.existingController(for: base.tab)
                === currentController,
              webViews.liveWebView(for: base.tab)
                === base.webView,
              base.webView.configuration.webExtensionController
                === currentController,
              publications.tabPublicationIsCurrent(
                  base.tab,
                  profileID: base.profileID
              ), adapters.isCurrent(evidence.adapter, for: base.tab),
              base.tab.extensionPageRuntimeOwner.isEligible(
                  for: currentGeneration
              ), base.tab.extensionPageRuntimeOwner
                .hasSettledDidOpenTabNotification(for: currentGeneration),
              runtimePublicationEvidence.isCurrent(
                  currentRuntimePublication
              ), binding.openNotifiedContextReadiness == .loaded,
              binding.openNotifiedContextBindingGeneration
                == profileRuntime.contextBindingGeneration(
                    for: base.profileID
                ), adapterIsOpenInProfileContexts(evidence)
        else {
            return false
        }
        return true
    }

    func adapterIsOpenInProfileContexts(
        _ evidence: ExtensionCreatedTabPublicationEvidence
    ) -> Bool {
        profileRuntime.contexts(for: evidence.base.profileID).values.contains {
            context in
            context.openTabs.contains { openTab in
                (openTab as AnyObject) === evidence.adapter
            }
        }
    }

    private func capturedRuntimeStateIsCurrent(
        _ evidence: ExtensionCreatedTabPublicationEvidence
    ) -> Bool {
        let base = evidence.base
        return profileIsReady(base.profileID)
            && runtimePublicationEvidence.isCurrent(
                base.runtimePublication
            )
            && tabProfiles.profileID(for: base.tab) == base.profileID
            && browserProfiles.anyProfile(base.profileID)?.dataStore
                === base.dataStore
            && base.webView.configuration.websiteDataStore === base.dataStore
            && profileRuntime.controller(for: base.profileID)
                === base.controller
            && profileRuntime.contextBindingGeneration(for: base.profileID)
                == base.contextBindingGeneration
            && controllers.existingController(for: base.tab)
                === base.controller
            && webViews.liveWebView(for: base.tab)
                === base.webView
            && base.webView.configuration.webExtensionController
                === base.controller
            && publications.tabPublicationIsCurrent(
                base.tab,
                profileID: base.profileID
            )
            && adapters.isCurrent(evidence.adapter, for: base.tab)
            && base.tab.extensionPageRuntimeOwner.isEligible(
                for: base.generation
            )
    }

    private func profileIsReady(_ profileID: UUID) -> Bool {
        contextLoading.profileHasLoadedContentScriptContexts(
            profileId: profileID
        )
    }
}
