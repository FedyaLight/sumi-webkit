import Foundation

/// Private lifetime storage only. No consumer accepts this aggregate as a
/// capability; construction distributes its exact leaf roles.
@available(macOS 15.5, *)
@MainActor
struct ExtensionAttachedBrowserRuntime {
    let browserIdentity: ObjectIdentifier
    let bridge: BrowserExtensionBridgeComposition
    let controller: ExtensionControllerRuntimeComposition
    let adapters: ExtensionAdapterCatalog
    let normalTabs: ExtensionAttachedNormalTabRuntime
    let publications: ExtensionAttachedPublicationRuntime
    let requestedTabs: ExtensionRequestedBrowserRuntimeServices
    let optionsComposer: ExtensionOptionsWindowCallbackComposer
    let profileQuery: ExtensionBrowserProfileQuery
    let websiteDataAdmission: ExtensionWebsiteDataMutationAdmission
    let browserRoutes: ExtensionControllerBrowserRouteInstaller
}

#if DEBUG
    /// Immutable white-box snapshot for tests that need already-distributed
    /// browser roles. The attachment lifetime and retirement authority are
    /// intentionally absent, so tests cannot recover the production aggregate.
    @MainActor
    struct ExtensionAttachedBrowserRuntimeInspection {
        let bridge: BrowserExtensionBridgeComposition
        let controller: ExtensionControllerRuntimeComposition
        let adapters: ExtensionAdapterCatalog
        let normalTabs: ExtensionAttachedNormalTabRuntime
        let publications: ExtensionAttachedPublicationRuntime
        let requestedTabs: ExtensionRequestedBrowserRuntimeServices
        let optionsComposer: ExtensionOptionsWindowCallbackComposer
        let profileQuery: ExtensionBrowserProfileQuery

        init(_ runtime: ExtensionAttachedBrowserRuntime) {
            bridge = runtime.bridge
            controller = runtime.controller
            adapters = runtime.adapters
            normalTabs = runtime.normalTabs
            publications = runtime.publications
            requestedTabs = runtime.requestedTabs
            optionsComposer = runtime.optionsComposer
            profileQuery = runtime.profileQuery
        }
    }
#endif

/// Browser-bound services for WebKit-created tabs, windows, navigation and
/// menu reads. This is composition lifetime storage, never a forwarded API.
@available(macOS 15.5, *)
@MainActor
struct ExtensionRequestedBrowserRuntimeServices {
    let targetResolver: ExtensionRequestedTabTargetResolver
    let createdTabRegistrar: ExtensionCreatedTabRuntimeRegistrar
    let initialTabPreparer: ExtensionInitialTabPublicationPreparer
    let contextPreloader: ExtensionRequestedTabContextPreloader
    let opening: ExtensionRequestedTabOpeningService
    let openingCallbacks: ExtensionControllerOpeningCallbackRuntime
    let auxiliaryIntegration: AuxiliaryWindowExtensionIntegration
    let windowRouter: ExtensionWindowRequestRouter
    let windowVisibility: ExtensionWindowVisibilityResolver
    let pageResolution: ExtensionPageResolutionOwner
    let pageContextMenu: ExtensionPageContextMenuItemsOwner
    let pageNavigation: ExtensionPageNavigationPreparationOwner
}
