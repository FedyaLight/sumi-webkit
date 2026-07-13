import Foundation

/// Clears terminal in-memory runtime bookkeeping after every WebKit context
/// has been retired. It does not unload contexts or release controllers.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeBookkeepingReset {
    private let runtimeCatalog: ExtensionRuntimeCatalog
    private let runtimeResidency: ExtensionRuntimeResidencyAuthority
    private let runtimeMetrics: ExtensionRuntimeMetricsAuthority
    private let sourceCache: WebExtensionRuntimeSourceCache
    private let backgroundRuntimeState: ExtensionBackgroundRuntimeStateOwner
    private let errorObservation: ExtensionContextErrorObservation
    private let recentTabRequests: ExtensionRecentTabRequestHistory
    private let permissionPreludes:
        ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner
    private let controllerProvisioning: ExtensionControllerProvisioningOwner
    private let adapterStore: ExtensionBrowserAdapterStore
    private let optionsWindows: ExtensionOptionsWindowService
    private let actionAnchors: ExtensionActionAnchorStore
    private let actionPopupAnchors: ExtensionActionPopupAnchorStore
    private let actionPopupInvocations: ExtensionActionPopupInvocationLedger

    init(
        runtimeCatalog: ExtensionRuntimeCatalog,
        runtimeResidency: ExtensionRuntimeResidencyAuthority,
        runtimeMetrics: ExtensionRuntimeMetricsAuthority,
        sourceCache: WebExtensionRuntimeSourceCache,
        backgroundRuntimeState: ExtensionBackgroundRuntimeStateOwner,
        errorObservation: ExtensionContextErrorObservation,
        recentTabRequests: ExtensionRecentTabRequestHistory,
        permissionPreludes:
            ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner,
        controllerProvisioning: ExtensionControllerProvisioningOwner,
        adapterStore: ExtensionBrowserAdapterStore,
        optionsWindows: ExtensionOptionsWindowService,
        actionAnchors: ExtensionActionAnchorStore,
        actionPopupAnchors: ExtensionActionPopupAnchorStore,
        actionPopupInvocations: ExtensionActionPopupInvocationLedger
    ) {
        self.runtimeCatalog = runtimeCatalog
        self.runtimeResidency = runtimeResidency
        self.runtimeMetrics = runtimeMetrics
        self.sourceCache = sourceCache
        self.backgroundRuntimeState = backgroundRuntimeState
        self.errorObservation = errorObservation
        self.recentTabRequests = recentTabRequests
        self.permissionPreludes = permissionPreludes
        self.controllerProvisioning = controllerProvisioning
        self.adapterStore = adapterStore
        self.optionsWindows = optionsWindows
        self.actionAnchors = actionAnchors
        self.actionPopupAnchors = actionPopupAnchors
        self.actionPopupInvocations = actionPopupInvocations
    }

    func reset() {
        errorObservation.removeAllObservations()
        errorObservation.removeAllLoggedErrorFingerprints()
        optionsWindows.closeAllWindows()
        for extensionID in actionAnchors.extensionIDs {
            actionAnchors.clearAnchors(for: extensionID)
        }
        actionPopupAnchors.removeAll()
        actionPopupInvocations.removeAll()

        runtimeCatalog.reset()
        sourceCache.removeAll()
        runtimeResidency.reset()
        runtimeMetrics.reset()
        backgroundRuntimeState.removeAll()
        recentTabRequests.removeAll()
        permissionPreludes.clearInstallations()
        controllerProvisioning.removeAllExtensionPageUserContentControllers()
        adapterStore.removeTabAndWindowAdapters()
    }
}
