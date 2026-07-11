import Foundation
import SumiWebRuntime
import WebKit

/// Read-only validation for a captured initial-Tab publication. It never
/// reconciles a window, materializes an adapter, or repairs stale state.
@available(macOS 15.5, *)
@MainActor
final class ExtensionInitialTabPublicationValidator {
    private let runtimeSession: ExtensionRuntimeSession
    private let profileRuntime: ExtensionProfileRuntime
    private let controllerQuery: any ExtensionControllerBindingQuery
    private let contextLoading: any ExtensionContentScriptContextLoading
    private let windowRegistry: any ExtensionWindowQuery
    private let windowPublications: ExtensionWindowPublicationQuery
    private let adapters: ExtensionCreatedTabAdapterPublication
    private let extensionsLoaded: @MainActor () -> Bool

    init(
        runtimeSession: ExtensionRuntimeSession,
        profileRuntime: ExtensionProfileRuntime,
        controllerQuery: any ExtensionControllerBindingQuery,
        contextLoading: any ExtensionContentScriptContextLoading,
        windowRegistry: any ExtensionWindowQuery,
        windowPublications: ExtensionWindowPublicationQuery,
        adapters: ExtensionCreatedTabAdapterPublication,
        extensionsLoaded: @escaping @MainActor () -> Bool
    ) {
        self.runtimeSession = runtimeSession
        self.profileRuntime = profileRuntime
        self.controllerQuery = controllerQuery
        self.contextLoading = contextLoading
        self.windowRegistry = windowRegistry
        self.windowPublications = windowPublications
        self.adapters = adapters
        self.extensionsLoaded = extensionsLoaded
    }

    func preparedEvidenceIsCurrent(
        _ evidence: ExtensionInitialTabPublicationEvidence,
        requiresPublishedWindow: Bool
    ) -> Bool {
        capturedRuntimeStateIsCurrent(evidence)
            && evidence.tab.extensionPageRuntimeOwner
                .canCommitWindowPrepublication(evidence.stateToken)
            && (
                requiresPublishedWindow == false
                    || exactWindowPublicationIsCurrent(evidence)
            )
    }

    func capturedOpenIsCurrent(
        _ evidence: ExtensionInitialTabPublicationEvidence
    ) -> Bool {
        capturedRuntimeStateIsCurrent(evidence)
            && exactWindowPublicationIsCurrent(evidence)
            && evidence.tab.extensionPageRuntimeOwner
                .isCommittedWindowPrepublicationCurrent(
                    evidence.stateToken,
                    generation: evidence.tabGeneration
                )
            && adapterIsOpenInProfileContexts(evidence)
    }

    /// A callback may hand publication to the ordinary current-generation
    /// lifecycle. In that case this stale receipt must neither close nor remove
    /// the adapter now owned by the newer exact generation.
    func currentGenerationOpenEvidence(
        _ evidence: ExtensionInitialTabPublicationEvidence
    ) -> ExtensionInitialTabDelegatedOpenEvidence? {
        let generation = runtimeSession.tabOpenNotificationGeneration
        let binding = evidence.tab.extensionPageRuntimeOwner
            .documentBindingSnapshot()
        guard extensionsLoaded(),
              physicalResidenceIsExact(evidence),
              exactRegisteredWindowIsCurrent(evidence),
              windowPublications.tabPublicationIsCurrent(
                  evidence.tab,
                  profileID: evidence.profileID
              ),
              capturedProfileIsCurrent(evidence),
              evidence.webView.configuration.websiteDataStore
                === evidence.dataStore,
              contextLoading.profileHasLoadedContentScriptContexts(
                  profileId: evidence.profileID
              ),
              let controller = profileRuntime.controller(
                  for: evidence.profileID
              ),
              controllerQuery.extensionController(for: evidence.tab)
                === controller,
              controllerQuery.resolvedLiveWebView(for: evidence.tab)
                === evidence.webView,
              evidence.webView.configuration.webExtensionController
                === controller,
              adapters.isCurrent(evidence.adapter, for: evidence.tab),
              evidence.tab.extensionPageRuntimeOwner.isEligible(
                  for: generation
              ),
              evidence.tab.extensionPageRuntimeOwner
                .hasDidOpenTabNotification(for: generation),
              let claim = evidence.tab.extensionPageRuntimeOwner
                .currentOpenPublicationClaim(generation: generation),
              binding.openNotifiedContextReadiness == .loaded,
              binding.openNotifiedContextBindingGeneration
                == profileRuntime.contextBindingGeneration(
                    for: evidence.profileID
                ),
              adapterIsOpenInProfileContexts(evidence)
        else {
            return nil
        }
        return ExtensionInitialTabDelegatedOpenEvidence(
            generation: generation,
            controller: controller,
            claim: claim
        )
    }

    func delegatedOpenIsCurrent(
        _ delegated: ExtensionInitialTabDelegatedOpenEvidence,
        for evidence: ExtensionInitialTabPublicationEvidence
    ) -> Bool {
        guard let current = currentGenerationOpenEvidence(evidence) else {
            return false
        }
        return current.generation == delegated.generation
            && current.controller === delegated.controller
            && current.claim === delegated.claim
    }

    func adapterIsOpenInProfileContexts(
        _ evidence: ExtensionInitialTabPublicationEvidence
    ) -> Bool {
        profileRuntime.contexts(for: evidence.profileID).values.contains {
            context in
            context.openTabs.contains { openTab in
                (openTab as AnyObject) === evidence.adapter
            }
        }
    }

    func createdAdapterCanBeRetired(
        _ evidence: ExtensionInitialTabPublicationEvidence
    ) -> Bool {
        evidence.createdAdapter
            && adapters.isCurrent(evidence.adapter, for: evidence.tab)
            && evidence.tab.extensionPageRuntimeOwner
                .hasAnyDidOpenTabNotification() == false
            && adapterIsOpenInProfileContexts(evidence) == false
    }

    private func capturedRuntimeStateIsCurrent(
        _ evidence: ExtensionInitialTabPublicationEvidence
    ) -> Bool {
        extensionsLoaded()
            && runtimeSession.extensionLoadGeneration
                == evidence.extensionLoadGeneration
            && runtimeSession.tabOpenNotificationGeneration
                == evidence.tabGeneration
            && profileRuntime.contextBindingGeneration(
                for: evidence.profileID
            ) == evidence.contextBindingGeneration
            && capturedProfileIsCurrent(evidence)
            && evidence.webView.configuration.websiteDataStore
                === evidence.dataStore
            && contextLoading.profileHasLoadedContentScriptContexts(
                profileId: evidence.profileID
            )
            && profileRuntime.controller(for: evidence.profileID)
                === evidence.controller
            && controllerQuery.extensionController(for: evidence.tab)
                === evidence.controller
            && controllerQuery.resolvedLiveWebView(for: evidence.tab)
                === evidence.webView
            && evidence.webView.configuration.webExtensionController
                === evidence.controller
            && adapters.isCurrent(evidence.adapter, for: evidence.tab)
            && evidence.tab.extensionPageRuntimeOwner.isEligible(
                for: evidence.tabGeneration
            )
            && physicalResidenceIsExact(evidence)
    }

    private func exactWindowPublicationIsCurrent(
        _ evidence: ExtensionInitialTabPublicationEvidence
    ) -> Bool {
        exactRegisteredWindowIsCurrent(evidence)
            && windowPublications.windowPublicationIsCurrent(
                evidence.window,
                selectedTab: evidence.tab,
                profileID: evidence.profileID
            )
    }

    private func capturedProfileIsCurrent(
        _ evidence: ExtensionInitialTabPublicationEvidence
    ) -> Bool {
        evidence.profile.id == evidence.profileID
            && evidence.profile.dataStore === evidence.dataStore
            && evidence.window.currentProfileId == evidence.profileID
            && evidence.tab.resolveProfile() === evidence.profile
    }

    private func exactRegisteredWindowIsCurrent(
        _ evidence: ExtensionInitialTabPublicationEvidence
    ) -> Bool {
        windowRegistry.extensionWindowState(for: evidence.window.id)
            === evidence.window
            && windowRegistry.currentExtensionTab(in: evidence.window)
                === evidence.tab
    }

    private func physicalResidenceIsExact(
        _ evidence: ExtensionInitialTabPublicationEvidence
    ) -> Bool {
        guard evidence.window.isIncognito == false,
              evidence.window.currentTabId == evidence.tab.id,
              evidence.webView.owningTab === evidence.tab,
              evidence.window.tabManager?.tabCollectionMembershipOwner.tab(
                  for: evidence.tab.id
              ) === evidence.tab,
              case .window(let trackedOwner) = evidence.tab.webViewSession
                .residence(of: evidence.webView)
        else {
            return false
        }
        return trackedOwner == TrackedWebViewOwner(
            tabID: evidence.tab.id,
            windowID: evidence.window.id
        )
    }
}
