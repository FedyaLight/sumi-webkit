import Foundation

/// Coordinates the two cohesive requested-tab surface assemblies without
/// retaining any browser or extension-runtime leaf itself.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRequestedTabBrowserSurfaceFactory {
    private let pages: ExtensionRequestedTabPageSurfaceFactory
    private let callbacks: ExtensionRequestedTabCallbackSurfaceFactory

    init(
        profileRuntime: ExtensionProfileRuntime,
        installedExtensions: InstalledExtensionCollection,
        controllerProvisioning: ExtensionControllerProvisioningOwner,
        configurationPreparation: ExtensionWebViewConfigurationPreparation,
        callbackAdmission: ExtensionControllerCallbackAdmission,
        browserConfiguration: BrowserConfiguration,
        deferredRuntimeOwners: ExtensionDeferredRuntimeOwnerStore,
        loadResolver: ExtensionRequestedTabLoadResolver,
        recentRequests: ExtensionRecentTabRequestHistory
    ) {
        pages = ExtensionRequestedTabPageSurfaceFactory(
            profileRuntime: profileRuntime,
            installedExtensions: installedExtensions,
            controllerProvisioning: controllerProvisioning
        )
        callbacks = ExtensionRequestedTabCallbackSurfaceFactory(
            profileRuntime: profileRuntime,
            installedExtensions: installedExtensions,
            configurationPreparation: configurationPreparation,
            callbackAdmission: callbackAdmission,
            browserConfiguration: browserConfiguration,
            deferredRuntimeOwners: deferredRuntimeOwners,
            loadResolver: loadResolver,
            recentRequests: recentRequests
        )
    }

    func assemble(
        bridge: BrowserExtensionBridgeComposition,
        controller: ExtensionControllerRuntimeComposition,
        windows: ExtensionWindowPublicationAssembly,
        normalTabs: ExtensionAttachedNormalTabRuntime,
        core: ExtensionRequestedTabCoreAssembly
    ) -> (
        services: ExtensionRequestedBrowserRuntimeServices,
        optionsComposer: ExtensionOptionsWindowCallbackComposer
    ) {
        let pageRoles = pages.assemble(
            bridge: bridge,
            controller: controller,
            windows: windows
        )
        let callbackRoles = callbacks.assemble(
            bridge: bridge,
            controller: controller,
            windows: windows,
            core: core,
            pageResolution: pageRoles.resolution
        )
        return (
            ExtensionRequestedBrowserRuntimeServices(
                targetResolver: core.targetResolver,
                createdTabRegistrar: core.createdTabRegistrar,
                initialTabPreparer: core.initialTabPreparer,
                contextPreloader: core.contextPreloader,
                opening: core.opening,
                openingCallbacks: callbackRoles.opening,
                auxiliaryIntegration: callbackRoles.auxiliaryIntegration,
                windowRouter: core.windowRouter,
                windowVisibility: callbackRoles.visibility,
                pageResolution: pageRoles.resolution,
                pageContextMenu: pageRoles.contextMenu,
                pageNavigation: pageRoles.navigation
            ),
            callbackRoles.options
        )
    }
}
