import Foundation

/// Revalidates only extension-runtime publication authority.
@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalWindowRuntimePublicationValidator {
    private let runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority
    private let profileRuntime: ExtensionProfileRuntime
    private let preparedTabs: ExtensionPreparedNormalTabQuery
    private let controllers: ExtensionExistingExactTabControllerQuery
    private let adapterStore: ExtensionBrowserAdapterStore
    private let runtimePublicationEvidence:
        ExtensionRuntimePublicationEvidenceIssuer

    init(
        runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority,
        profileRuntime: ExtensionProfileRuntime,
        preparedTabs: ExtensionPreparedNormalTabQuery,
        controllers: ExtensionExistingExactTabControllerQuery,
        adapterStore: ExtensionBrowserAdapterStore,
        runtimePublicationEvidence: ExtensionRuntimePublicationEvidenceIssuer
    ) {
        self.runtimeLoadStatus = runtimeLoadStatus
        self.profileRuntime = profileRuntime
        self.preparedTabs = preparedTabs
        self.controllers = controllers
        self.adapterStore = adapterStore
        self.runtimePublicationEvidence = runtimePublicationEvidence
    }

    func validate(
        _ projection: ExtensionNormalWindowProjection,
        window: BrowserWindowState,
        selectedTab: Tab,
        publicationStage: ExtensionRuntimePublicationStage
    ) -> Bool {
        guard publicationStage.admits(runtimeLoadStatus),
              runtimePublicationEvidence.isCurrent(
                  projection.runtimePublication
              ),
              preparedTabs.containsPreparedTab(selectedTab),
              profileRuntime.controllersByProfile[projection.profileID]
                === projection.controller,
              controllers.existingController(for: selectedTab)
                === projection.controller,
              adapterStore.existingWindowAdapter(for: window.id)
                === projection.windowAdapter,
              adapterStore.tabAdapters[selectedTab.id]
                === projection.selectedTabAdapter
        else { return false }
        return true
    }
}
