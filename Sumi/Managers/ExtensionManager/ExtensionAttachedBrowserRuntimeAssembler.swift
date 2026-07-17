import Foundation

/// Small directional coordinator for the six bounded attachment factories.
/// It does not own browser state, install delegate routes, or publish a
/// runtime; those transitions remain separate fail-closed authorities.
@available(macOS 15.5, *)
@MainActor
final class ExtensionAttachedBrowserRuntimeAssembler {
    struct Result {
        let runtime: ExtensionAttachedBrowserRuntime
        let controller: ExtensionControllerRuntimeComposition
        let requestedTabs: ExtensionRequestedBrowserRuntimeServices
        let optionsComposer: ExtensionOptionsWindowCallbackComposer
    }

    private let controllers: ExtensionAttachedControllerRuntimeFactory
    private let windows: ExtensionWindowPublicationFactory
    private let normalTabs: ExtensionAttachedNormalTabRuntimeFactory
    private let publicationTransactions: ExtensionPublicationTransactionFactory
    private let requestedTabCore: ExtensionRequestedTabCoreFactory
    private let requestedTabSurfaces:
        ExtensionRequestedTabBrowserSurfaceFactory

    init(
        controllers: ExtensionAttachedControllerRuntimeFactory,
        windows: ExtensionWindowPublicationFactory,
        normalTabs: ExtensionAttachedNormalTabRuntimeFactory,
        publicationTransactions: ExtensionPublicationTransactionFactory,
        requestedTabCore: ExtensionRequestedTabCoreFactory,
        requestedTabSurfaces: ExtensionRequestedTabBrowserSurfaceFactory
    ) {
        self.controllers = controllers
        self.windows = windows
        self.normalTabs = normalTabs
        self.publicationTransactions = publicationTransactions
        self.requestedTabCore = requestedTabCore
        self.requestedTabSurfaces = requestedTabSurfaces
    }

    func assemble(
        browserIdentity: ObjectIdentifier,
        bridge: BrowserExtensionBridgeComposition,
        browserRoutes: ExtensionControllerBrowserRouteInstaller
    ) -> Result {
        let controller = controllers.assemble(bridge: bridge)
        let windowPublication = windows.assemble(
            bridge: bridge,
            controller: controller
        )
        let normalTabRuntime = normalTabs.assemble(
            bridge: bridge,
            controller: controller,
            publication: windowPublication
        )
        let publicationRuntime = publicationTransactions.assemble(
            bridge: bridge,
            controller: controller,
            windows: windowPublication,
            normalTabs: normalTabRuntime
        )
        let requestedCore = requestedTabCore.assemble(
            bridge: bridge,
            controller: controller,
            windows: windowPublication,
            normalTabs: normalTabRuntime,
            windowCreation: bridge.requestedWindows
        )
        let requestedSurface = requestedTabSurfaces.assemble(
            bridge: bridge,
            controller: controller,
            windows: windowPublication,
            normalTabs: normalTabRuntime,
            core: requestedCore
        )
        let runtime = ExtensionAttachedBrowserRuntime(
            browserIdentity: browserIdentity,
            bridge: bridge,
            controller: controller,
            adapters: windowPublication.adapters,
            normalTabs: normalTabRuntime,
            publications: publicationRuntime,
            requestedTabs: requestedSurface.services,
            optionsComposer: requestedSurface.optionsComposer,
            profileQuery: bridge.profiles,
            websiteDataAdmission: bridge.websiteDataAdmission,
            browserRoutes: browserRoutes
        )
        return Result(
            runtime: runtime,
            controller: controller,
            requestedTabs: requestedSurface.services,
            optionsComposer: requestedSurface.optionsComposer
        )
    }
}
