import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalTabPreparationLifetime {
    private let configurationPreparation: ExtensionWebViewConfigurationPreparation
    private let deferredRuntimeOwners: ExtensionDeferredRuntimeOwnerStore
    private let recentTabRequests: ExtensionRecentTabRequestHistory
    private let requestedTabLoadResolver: ExtensionRequestedTabLoadResolver
    private let adapterStore: ExtensionBrowserAdapterStore

    init(
        configurationPreparation: ExtensionWebViewConfigurationPreparation,
        deferredRuntimeOwners: ExtensionDeferredRuntimeOwnerStore,
        recentTabRequests: ExtensionRecentTabRequestHistory,
        requestedTabLoadResolver: ExtensionRequestedTabLoadResolver,
        adapterStore: ExtensionBrowserAdapterStore
    ) {
        self.configurationPreparation = configurationPreparation
        self.deferredRuntimeOwners = deferredRuntimeOwners
        self.recentTabRequests = recentTabRequests
        self.requestedTabLoadResolver = requestedTabLoadResolver
        self.adapterStore = adapterStore
    }
}
