import Foundation
import WebKit

/// Builds and revalidates requested-Tab evidence. Every post-callback check is
/// read-only: window reconciliation is owned solely by pre-receipt admission.
@available(macOS 15.5, *)
@MainActor
final class ExtensionCreatedTabPublicationValidator {
    private let runtimeSession: ExtensionRuntimeSession
    private let profileRuntime: ExtensionProfileRuntime
    private let controllers: any ExtensionTabControllerQuery
    private let webViews: ExtensionExactTabWebViewQuery
    private let controllerAdmission: any ExtensionWebViewControllerAdmitting
    private let contextLoading: any ExtensionContentScriptContextLoading
    private let publications: ExtensionWindowPublicationQuery
    private let adapters: ExtensionCreatedTabAdapterPublication
    private let extensionsLoaded: @MainActor () -> Bool

    init(
        runtimeSession: ExtensionRuntimeSession,
        profileRuntime: ExtensionProfileRuntime,
        controllers: any ExtensionTabControllerQuery,
        webViews: ExtensionExactTabWebViewQuery,
        controllerAdmission: any ExtensionWebViewControllerAdmitting,
        contextLoading: any ExtensionContentScriptContextLoading,
        publications: ExtensionWindowPublicationQuery,
        adapters: ExtensionCreatedTabAdapterPublication,
        extensionsLoaded: @escaping @MainActor () -> Bool
    ) {
        self.runtimeSession = runtimeSession
        self.profileRuntime = profileRuntime
        self.controllers = controllers
        self.webViews = webViews
        self.controllerAdmission = controllerAdmission
        self.contextLoading = contextLoading
        self.publications = publications
        self.adapters = adapters
        self.extensionsLoaded = extensionsLoaded
    }

    func prepareBase(
        for tab: Tab,
        runtime: ExtensionManagerRuntime
    ) -> ExtensionCreatedTabPublicationBaseEvidence? {
        guard extensionsLoaded(),
              tab.isEphemeral == false,
              let profileID = profileRuntime.resolvedProfileId(
                  for: tab,
                  runtime: runtime
              ), contextLoading.profileHasLoadedContentScriptContexts(
                  profileId: profileID
              ), let dataStore = runtime.profile(profileID)?.dataStore,
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
            generation: runtimeSession.tabOpenNotificationGeneration,
            extensionLoadGeneration: runtimeSession.extensionLoadGeneration,
            contextBindingGeneration: profileRuntime
                .contextBindingGeneration(for: profileID)
        )
    }

    func preparedEvidenceIsCurrent(
        _ evidence: ExtensionCreatedTabPublicationEvidence,
        runtime: ExtensionManagerRuntime
    ) -> Bool {
        capturedRuntimeStateIsCurrent(evidence, runtime: runtime)
            && evidence.tab.extensionPageRuntimeOwner
                .canCommitWindowPrepublication(evidence.stateToken)
            && evidence.tab.extensionPageRuntimeOwner
                .hasDidOpenTabNotification(for: evidence.generation) == false
    }

    func capturedOpenIsCurrent(
        _ evidence: ExtensionCreatedTabPublicationEvidence,
        runtime: ExtensionManagerRuntime
    ) -> Bool {
        capturedRuntimeStateIsCurrent(evidence, runtime: runtime)
            && evidence.tab.extensionPageRuntimeOwner
                .isCommittedWindowPrepublicationCurrent(
                    evidence.stateToken,
                    generation: evidence.generation
                )
            && adapterIsOpenInProfileContexts(evidence)
    }

    func currentGenerationOpenIsExact(
        _ evidence: ExtensionCreatedTabPublicationEvidence,
        runtime: ExtensionManagerRuntime
    ) -> Bool {
        let base = evidence.base
        let currentGeneration = runtimeSession.tabOpenNotificationGeneration
        let binding = base.tab.extensionPageRuntimeOwner
            .documentBindingSnapshot()
        guard extensionsLoaded(),
              profileRuntime.resolvedProfileId(
                  for: base.tab,
                  runtime: runtime
              ) == base.profileID,
              runtime.profile(base.profileID)?.dataStore === base.dataStore,
              base.webView.configuration.websiteDataStore === base.dataStore,
              contextLoading.profileHasLoadedContentScriptContexts(
                  profileId: base.profileID
              ), let currentController = profileRuntime.controller(
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
              binding.openNotifiedContextReadiness == .loaded,
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
        _ evidence: ExtensionCreatedTabPublicationEvidence,
        runtime: ExtensionManagerRuntime
    ) -> Bool {
        let base = evidence.base
        return extensionsLoaded()
            && runtimeSession.extensionLoadGeneration
                == base.extensionLoadGeneration
            && runtimeSession.tabOpenNotificationGeneration
                == base.generation
            && profileRuntime.resolvedProfileId(
                for: base.tab,
                runtime: runtime
            ) == base.profileID
            && runtime.profile(base.profileID)?.dataStore === base.dataStore
            && base.webView.configuration.websiteDataStore === base.dataStore
            && profileRuntime.controller(for: base.profileID)
                === base.controller
            && profileRuntime.contextBindingGeneration(for: base.profileID)
                == base.contextBindingGeneration
            && contextLoading.profileHasLoadedContentScriptContexts(
                profileId: base.profileID
            )
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
}
