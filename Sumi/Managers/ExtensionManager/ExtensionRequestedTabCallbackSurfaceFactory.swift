import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionRequestedTabCallbackSurfaceRoles {
    let opening: ExtensionControllerOpeningCallbackRuntime
    let auxiliaryIntegration: AuxiliaryWindowExtensionIntegration
    let options: ExtensionOptionsWindowCallbackComposer
    let visibility: ExtensionWindowVisibilityResolver
}

/// Creates callback, auxiliary-window, options, and visibility roles.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRequestedTabCallbackSurfaceFactory {
    private let profileRuntime: ExtensionProfileRuntime
    private let installedExtensions: InstalledExtensionCollection
    private let configurationPreparation: ExtensionWebViewConfigurationPreparation
    private let callbackAdmission: ExtensionControllerCallbackAdmission
    private let browserConfiguration: BrowserConfiguration
    private let deferredRuntimeOwners: ExtensionDeferredRuntimeOwnerStore
    private let loadResolver: ExtensionRequestedTabLoadResolver
    private let recentRequests: ExtensionRecentTabRequestHistory

    init(
        profileRuntime: ExtensionProfileRuntime,
        installedExtensions: InstalledExtensionCollection,
        configurationPreparation: ExtensionWebViewConfigurationPreparation,
        callbackAdmission: ExtensionControllerCallbackAdmission,
        browserConfiguration: BrowserConfiguration,
        deferredRuntimeOwners: ExtensionDeferredRuntimeOwnerStore,
        loadResolver: ExtensionRequestedTabLoadResolver,
        recentRequests: ExtensionRecentTabRequestHistory
    ) {
        self.profileRuntime = profileRuntime
        self.installedExtensions = installedExtensions
        self.configurationPreparation = configurationPreparation
        self.callbackAdmission = callbackAdmission
        self.browserConfiguration = browserConfiguration
        self.deferredRuntimeOwners = deferredRuntimeOwners
        self.loadResolver = loadResolver
        self.recentRequests = recentRequests
    }

    func assemble(
        bridge: BrowserExtensionBridgeComposition,
        controller: ExtensionControllerRuntimeComposition,
        windows: ExtensionWindowPublicationAssembly,
        core: ExtensionRequestedTabCoreAssembly,
        pageResolution: ExtensionPageResolutionOwner
    ) -> ExtensionRequestedTabCallbackSurfaceRoles {
        let auxiliaryEvents = ExtensionAuxiliaryWindowEventRouter(
            gate: windows.tabs.gate,
            lifecycle: windows.windows.auxiliary,
            control: bridge.auxiliaryWindows,
            windows: bridge.windows
        )
        let auxiliaryIntegration = AuxiliaryWindowExtensionIntegration(
            installedExtensions: { [installedExtensions] in
                installedExtensions.records
            },
            events: auxiliaryEvents,
            resolveExtensionID: {
                [pageResolution]
                context,
                openerTab,
                sourceURL,
                explicitExtensionID in
                pageResolution.ownerExtensionID(
                    extensionContext: context,
                    openerTab: openerTab,
                    extensionOwnedSourceURL: sourceURL,
                    explicitExtensionID: explicitExtensionID
                )
            },
            makeMiniWindowAdapter: {
                [adapters = windows.adapters]
                sessionID,
                tab,
                window,
                isPrivate,
                shouldActivate in
                adapters.miniWindowAdapter(
                    for: sessionID,
                    tab: tab,
                    window: window,
                    isPrivate: isPrivate,
                    shouldActivateApp: shouldActivate
                )
            }
        )
        let auxiliaryRuntime = ExtensionAuxiliaryWindowCallbackRuntime(
            contextLoading:
                deferredRuntimeOwners.initialDocumentRuntimePreparationOwner,
            loadResolver: loadResolver,
            contextPreloader: core.contextPreloader,
            recentRequests: recentRequests,
            configurationPreparation: configurationPreparation,
            integration: auxiliaryIntegration
        )
        let opening = ExtensionControllerOpeningCallbackRuntime(
            admission: callbackAdmission,
            contextPreloader: core.contextPreloader,
            tabOpening: core.opening,
            adapterResolver: windows.adapters,
            windowRouter: core.windowRouter,
            windowQuery: bridge.windows,
            windowPresentation: bridge.presentation,
            auxiliaryRuntime: auxiliaryRuntime
        )
        let options = ExtensionOptionsWindowCallbackComposer(
            admission: callbackAdmission,
            profiles: bridge.profiles,
            profileRuntime: profileRuntime,
            installedExtensions: installedExtensions,
            browserConfiguration: browserConfiguration,
            configurationPreparation: configurationPreparation,
            websiteDataAdmission: bridge.websiteDataAdmission
        )
        let visibility = ExtensionWindowVisibilityResolver(
            windowQuery: { bridge.windows },
            auxiliaryWindows: { bridge.auxiliaryWindows },
            profileIdForContext: { [profileRuntime] context in
                profileRuntime.profileId(for: context)
            },
            extensionIDForContext: { [profileRuntime] context in
                profileRuntime.extensionId(for: context)
            },
            publishedWindowAdapter: {
                [publications = windows.windows.query]
                window,
                profileID in
                publications.publishedWindowAdapter(
                    for: window,
                    profileID: profileID
                )
            },
            miniWindowAdapters: {
                [publications = windows.windows.query]
                extensionID,
                profileID in
                publications.publishedAuxiliaryWindowAdapters(
                    ownerExtensionID: extensionID,
                    profileID: profileID
                )
            }
        )
        return ExtensionRequestedTabCallbackSurfaceRoles(
            opening: opening,
            auxiliaryIntegration: auxiliaryIntegration,
            options: options,
            visibility: visibility
        )
    }
}
