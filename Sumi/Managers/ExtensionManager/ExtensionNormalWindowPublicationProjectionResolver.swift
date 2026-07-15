import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalWindowPublicationProjectionResolver {
    private let runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority
    private let profileRuntime: ExtensionProfileRuntime
    private let controllers: ExtensionExistingExactTabControllerQuery
    private let adapters: ExtensionAdapterCatalog
    private let runtimePublicationEvidence: ExtensionRuntimePublicationEvidenceIssuer
    private let preparedTabVisibility: ExtensionPreparedTabVisibility

    init(
        runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority,
        profileRuntime: ExtensionProfileRuntime,
        controllers: ExtensionExistingExactTabControllerQuery,
        adapters: ExtensionAdapterCatalog,
        runtimePublicationEvidence: ExtensionRuntimePublicationEvidenceIssuer,
        preparedTabVisibility: ExtensionPreparedTabVisibility
    ) {
        self.runtimeLoadStatus = runtimeLoadStatus
        self.profileRuntime = profileRuntime
        self.controllers = controllers
        self.adapters = adapters
        self.runtimePublicationEvidence = runtimePublicationEvidence
        self.preparedTabVisibility = preparedTabVisibility
    }

    func resolve(
        _ selection: ExtensionNormalWindowSelection,
        publicationStage: ExtensionRuntimePublicationStage
    ) -> ExtensionNormalWindowProjection? {
        guard publicationStage.admits(runtimeLoadStatus),
              let controller = profileRuntime.controllersByProfile[
                  selection.profileID
              ],
              controllers.existingController(for: selection.tab) === controller,
              let tabAdapter = adapters.stableAdapter(for: selection.tab),
              let windowAdapter = adapters.windowAdapter(
                  for: selection.window.id,
                  preparedTabVisibility: preparedTabVisibility
              ),
              windowAdapter.represents(selection.window)
        else { return nil }
        return ExtensionNormalWindowProjection(
            windowIdentity: ObjectIdentifier(selection.window),
            selectedTabIdentity: ObjectIdentifier(selection.tab),
            selectedTabID: selection.tabID,
            profileID: selection.profileID,
            runtimePublication: runtimePublicationEvidence.issue(),
            controller: controller,
            windowAdapter: windowAdapter,
            selectedTabAdapter: tabAdapter
        )
    }
}
