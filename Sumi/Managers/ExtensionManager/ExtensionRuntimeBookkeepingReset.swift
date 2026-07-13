import Foundation

/// Clears terminal in-memory runtime bookkeeping after every WebKit context
/// has been retired. It does not unload contexts or release controllers.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeBookkeepingReset {
    private let runtimeSession: ExtensionRuntimeSession
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

    init(
        runtimeSession: ExtensionRuntimeSession,
        sourceCache: WebExtensionRuntimeSourceCache,
        backgroundRuntimeState: ExtensionBackgroundRuntimeStateOwner,
        errorObservation: ExtensionContextErrorObservation,
        recentTabRequests: ExtensionRecentTabRequestHistory,
        permissionPreludes:
            ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner,
        controllerProvisioning: ExtensionControllerProvisioningOwner,
        adapterStore: ExtensionBrowserAdapterStore,
        optionsWindows: ExtensionOptionsWindowService,
        actionAnchors: ExtensionActionAnchorStore
    ) {
        self.runtimeSession = runtimeSession
        self.sourceCache = sourceCache
        self.backgroundRuntimeState = backgroundRuntimeState
        self.errorObservation = errorObservation
        self.recentTabRequests = recentTabRequests
        self.permissionPreludes = permissionPreludes
        self.controllerProvisioning = controllerProvisioning
        self.adapterStore = adapterStore
        self.optionsWindows = optionsWindows
        self.actionAnchors = actionAnchors
    }

    func reset() {
        errorObservation.removeAllObservations()
        errorObservation.removeAllLoggedErrorFingerprints()
        optionsWindows.closeAllWindows()
        for extensionID in actionAnchors.extensionIDs {
            actionAnchors.clearAnchors(for: extensionID)
        }

        runtimeSession.loadedExtensionManifests.removeAll()
        sourceCache.removeAll()
        runtimeSession.lastExtensionLoadErrors.removeAll()
        runtimeSession.extensionRuntimeResidencyState.removeAll()
        runtimeSession.runtimeMetricsByExtensionID.removeAll()
        backgroundRuntimeState.removeAll()
        recentTabRequests.removeAll()
        permissionPreludes.clearInstallations()
        controllerProvisioning.removeAllExtensionPageUserContentControllers()
        adapterStore.removeTabAndWindowAdapters()
    }
}
