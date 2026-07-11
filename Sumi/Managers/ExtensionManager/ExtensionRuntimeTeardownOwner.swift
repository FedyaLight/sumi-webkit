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

        manager.runtimeDiagnostics.trace(
            "runtimeTeardown start reason=\(reason) removeUIState=\(removeUIState) releaseController=\(releaseController)"
        )

        #if DEBUG
            manager.clearDebugState()
        #endif

        manager.runtimeSession.extensionLoadGeneration &+= 1
        manager.runtimeSession.runtimeInitializationTask?.cancel()
        manager.runtimeSession.runtimeInitializationTask = nil
        manager.loadedInitialDocumentRuntimePreparationOwner?
            .cancelContentScriptContextLoadTasks()
        manager.cancelInitialDocumentNativeMessagingWarmupTasks()
        manager.loadedInitialDocumentRuntimePreparationOwner?
            .cancelDeferredTabNotificationTasks()
        manager.cancelNativeMessagingBackgroundWakeTasks()
        manager.backgroundRuntimeStateOwner.cancelAllWakeTasks()
        manager.browserRuntimeBridgeOwner
            .closePublishedWindowsForRuntimeTeardown()

        let uiStateIDs = removeUIState ? manager.actionAnchorStore.extensionIDs : []
        let loadedIDs = manager.allLoadedExtensionIDs()
            .union(manager.runtimeSession.loadedExtensionManifests.keys)
            .union(manager.optionsWindows.extensionIDs)
            .union(manager.nativeMessagingPortRegistry.extensionIDs)
            .union(manager.errorObservationOwner.observedExtensionIDs)
            .union(uiStateIDs)

        for extensionId in loadedIDs {
            manager.tearDownExtensionRuntimeState(
                for: extensionId,
                removeUIState: removeUIState
            )
        }

        manager.errorObservationOwner.removeAllObservers()

        if removeUIState {
            for extensionId in manager.actionAnchorStore.extensionIDs {
                manager.actionAnchorStore.clearAnchors(for: extensionId)
            }
        }

        manager.optionsWindows.extensionIDs.forEach {
            manager.optionsWindows.closeWindow(for: $0)
        }
        manager.cancelNativeMessagingSessions(reason: reason)

        manager.profileRuntime.replaceContexts([:])
        manager.runtimeSession.loadedExtensionManifests.removeAll()
        manager.actionStatesByExtensionID.removeAll()
        manager.runtimeSession.cachedWebExtensionsByID.removeAll()
        manager.runtimeSession.cachedWebExtensionRuntimeSourceKeysByID.removeAll()
        manager.runtimeSession.lastExtensionLoadErrors.removeAll()
        manager.runtimeSession.extensionRuntimeResidencyState.removeAll()
        manager.backgroundRuntimeStateOwner.removeAll()
        manager.runtimeSession.runtimeMetricsByExtensionID.removeAll()
        manager.errorObservationOwner.removeAllLoggedErrorFingerprints()
        manager.recentExtensionTabRequests.removeAll()
        manager.permissionsOriginsCompatibilityPreludeInstallationOwner.clearInstallations()
        manager.controllerProvisioningOwner.removeAllExtensionPageUserContentControllers()
        manager.adapterStore.removeTabAndWindowAdapters()

        if releaseController {
            manager.browserConfiguration.webViewConfiguration.webExtensionController = nil
            for controller in manager.profileRuntime.controllersByProfile.values {
                controller.delegate = nil
            }
            manager.profileRuntime.replaceControllers([:])
            manager.profileRuntime.removeAllWebsiteDataStores()
            manager.runtimeSession.allowsRuntimeWithoutEnabledExtensions = false
            manager.runtimeSession.runtimeState = manager.isExtensionSupportAvailable ? .idle : .unavailable
            manager.extensionsLoaded = false
        }

        manager.runtimeDiagnostics.trace("runtimeTeardown complete reason=\(reason)")
    }
}
