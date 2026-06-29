import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeTeardownOwner {
    func tearDownRuntime(
        manager: ExtensionManager,
        reason: String,
        removeUIState: Bool,
        releaseController: Bool
    ) {
        let signpostState = PerformanceTrace.beginInterval(
            "ExtensionManager.runtimeTeardown"
        )
        defer {
            PerformanceTrace.endInterval(
                "ExtensionManager.runtimeTeardown",
                signpostState
            )
        }

        manager.extensionRuntimeTrace(
            "runtimeTeardown start reason=\(reason) removeUIState=\(removeUIState) releaseController=\(releaseController)"
        )

        #if DEBUG
            manager.clearDebugState()
        #endif

        manager.extensionLoadGeneration &+= 1
        manager.runtimeInitializationTask?.cancel()
        manager.runtimeInitializationTask = nil
        manager.loadedInitialDocumentRuntimePreparationOwner?
            .cancelContentScriptContextLoadTasks()
        manager.cancelInitialDocumentNativeMessagingWarmupTasks()
        manager.loadedInitialDocumentRuntimePreparationOwner?
            .cancelDeferredTabNotificationTasks()
        manager.cancelNativeMessagingBackgroundWakeTasks()
        manager.backgroundRuntimeStateOwner.cancelAllWakeTasks()

        let uiStateIDs = removeUIState ? Array(manager.actionAnchors.keys) : []
        let loadedIDs = manager.allLoadedExtensionIDs()
            .union(manager.loadedExtensionManifests.keys)
            .union(manager.optionsWindows.keys)
            .union(manager.nativeMessagingPortRegistry.extensionIDs)
            .union(manager.extensionErrorObserverTokens.keys)
            .union(uiStateIDs)

        for extensionId in loadedIDs {
            manager.tearDownExtensionRuntimeState(
                for: extensionId,
                removeUIState: removeUIState
            )
        }

        for (_, token) in manager.extensionErrorObserverTokens {
            NotificationCenter.default.removeObserver(token)
        }
        manager.extensionErrorObserverTokens.removeAll()

        if removeUIState {
            for extensionId in Array(manager.actionAnchors.keys) {
                manager.clearActionAnchors(for: extensionId)
            }
        }

        Array(manager.optionsWindows.keys).forEach {
            manager.closeOptionsWindow(for: $0)
        }
        manager.cancelNativeMessagingSessions(reason: reason)

        manager.extensionContextsByProfile.removeAll()
        manager.loadedExtensionManifests.removeAll()
        manager.actionStatesByExtensionID.removeAll()
        manager.cachedWebExtensionsByID.removeAll()
        manager.cachedWebExtensionRuntimeSourceKeysByID.removeAll()
        manager.lastExtensionLoadErrors.removeAll()
        manager.extensionRuntimeResidencyState.removeAll()
        manager.backgroundRuntimeStateOwner.removeAll()
        manager.runtimeMetricsByExtensionID.removeAll()
        manager.lastLoggedExtensionErrorFingerprints.removeAll()
        manager.requestedTabLifecycleOwner.removeAllRecentlyOpenedTabRequests()
        manager.clearPermissionsOriginsCompatibilityInstallations()
        manager.extensionPageUserContentControllersByProfile.removeAll()
        manager.adapterStore.removeTabAndWindowAdapters()

        if releaseController {
            manager.browserConfiguration.webViewConfiguration.webExtensionController = nil
            for controller in manager.extensionControllersByProfile.values {
                controller.delegate = nil
            }
            manager.extensionControllersByProfile.removeAll()
            manager.profileRuntimeOwner.removeAllWebsiteDataStores()
            manager.extensionRuntimeAllowsWithoutEnabledExtensions = false
            manager.runtimeState = manager.isExtensionSupportAvailable ? .idle : .unavailable
            manager.extensionsLoaded = false
        }

        manager.extensionRuntimeTrace("runtimeTeardown complete reason=\(reason)")
    }
}
