//
//  ExtensionRuntimeStateResetOwner.swift
//  Sumi
//
//  Owns per-extension runtime state teardown and the full loaded-runtime
//  reset used before reloads: context unloads, cache/bookkeeping resets, and
//  live WebView rebuild sequencing after a user-extension runtime teardown.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeStateResetOwner {
    struct Dependencies {
        let profileRuntimeOwner: ExtensionProfileRuntimeOwner
        let runtimeSessionOwner: ExtensionRuntimeSessionOwner
        let backgroundRuntimeStateOwner: ExtensionBackgroundRuntimeStateOwner
        let requestedTabLifecycleOwner: ExtensionRequestedTabLifecycleOwner
        let nativeMessagingPortRegistry: ExtensionNativeMessagingPortRegistry
        let errorObservationOwner: ExtensionErrorObservationOwner
        let browserBridgeContext: @MainActor () -> (any ExtensionBrowserBridgeContext)?
        let runtime: @MainActor () -> ExtensionManagerRuntime
        let loadedNativeMessagingRelay: @MainActor () -> SumiNativeMessagingRelay?
        let cancelNativeMessagingBackgroundWakeTasks: @MainActor (String?) -> Void
        let cancelInitialDocumentTasks: @MainActor () -> Void
        let clearActionSurfaceState: @MainActor (String) -> Void
        let clearAllActionSurfaceStates: @MainActor () -> Void
        let closeOptionsWindow: @MainActor (String) -> Void
        let optionsWindowExtensionIDs: @MainActor () -> Set<String>
        let clearActionAnchors: @MainActor (String) -> Void
        let clearPermissionsOriginsCompatibilityInstallations: @MainActor () -> Void
        let removeAllExtensionPageUserContentControllers: @MainActor () -> Void
        let pruneRuntimeAdapters: @MainActor () -> Void
        let hasEnabledInstalledExtensions: @MainActor () -> Bool
        let extensionsLoaded: @MainActor () -> Bool
        let allKnownTabs: @MainActor () -> [Tab]
        let liveWebViews: @MainActor (Tab) -> [WKWebView]
        let tabDescription: @MainActor (Tab) -> String
        let trace: @MainActor (() -> String) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func tearDownExtensionRuntimeState(
        for extensionId: String,
        removeUIState: Bool
    ) {
        dependencies.browserBridgeContext()?.closeAuxiliaryWindowSessions(
            forExtensionId: extensionId,
            reason: .extensionDisable
        )

        let signpostState = PerformanceTrace.beginInterval(
            "ExtensionManager.tearDownExtensionRuntimeState"
        )
        defer {
            PerformanceTrace.endInterval(
                "ExtensionManager.tearDownExtensionRuntimeState",
                signpostState
            )
        }

        for profileId in dependencies.profileRuntimeOwner.contextsByProfile.keys {
            let wakeKey = ExtensionRuntimeResidencyState.scopedKey(
                extensionId: extensionId,
                profileId: profileId
            )
            dependencies.backgroundRuntimeStateOwner.cancelAndRemoveRuntime(for: wakeKey)
        }
        dependencies.cancelNativeMessagingBackgroundWakeTasks(extensionId)
        dependencies.clearActionSurfaceState(extensionId)
        unloadExtensionContextIfNeeded(for: extensionId)
        dependencies.errorObservationOwner.removeObserver(for: extensionId)
        dependencies.runtimeSessionOwner.loadedExtensionManifests
            .removeValue(forKey: extensionId)
        dependencies.runtimeSessionOwner.cachedWebExtensionsByID
            .removeValue(forKey: extensionId)
        dependencies.runtimeSessionOwner.cachedWebExtensionRuntimeSourceKeysByID
            .removeValue(forKey: extensionId)
        dependencies.runtimeSessionOwner.lastExtensionLoadErrors =
            dependencies.runtimeSessionOwner.lastExtensionLoadErrors.filter {
                !$0.key.hasSuffix(":\(extensionId)")
            }
        dependencies.runtimeSessionOwner.extensionRuntimeResidencyState
            .remove(extensionId: extensionId)
        dependencies.errorObservationOwner.removeLoggedErrorFingerprint(for: extensionId)
        dependencies.closeOptionsWindow(extensionId)
        dependencies.nativeMessagingPortRegistry.disconnect(extensionId: extensionId)
        dependencies.loadedNativeMessagingRelay()?.clearLoopGuard(forExtensionId: extensionId)

        if removeUIState {
            dependencies.clearActionAnchors(extensionId)
        }

        dependencies.pruneRuntimeAdapters()
    }

    func resetLoadedExtensionRuntimeStateForReload() {
        let signpostState = PerformanceTrace.beginInterval(
            "ExtensionManager.resetLoadedExtensionRuntimeStateForReload"
        )
        defer {
            PerformanceTrace.endInterval(
                "ExtensionManager.resetLoadedExtensionRuntimeStateForReload",
                signpostState
            )
        }

        let loadedIDs = allLoadedExtensionIDs()
            .union(dependencies.runtimeSessionOwner.loadedExtensionManifests.keys)
            .union(dependencies.optionsWindowExtensionIDs())
            .union(dependencies.nativeMessagingPortRegistry.extensionIDs)

        for extensionId in loadedIDs {
            tearDownExtensionRuntimeState(for: extensionId, removeUIState: false)
        }

        dependencies.profileRuntimeOwner.replaceContexts([:])
        dependencies.runtimeSessionOwner.loadedExtensionManifests.removeAll()
        dependencies.clearAllActionSurfaceStates()
        dependencies.runtimeSessionOwner.cachedWebExtensionsByID.removeAll()
        dependencies.runtimeSessionOwner.cachedWebExtensionRuntimeSourceKeysByID.removeAll()
        dependencies.runtimeSessionOwner.lastExtensionLoadErrors.removeAll()
        dependencies.runtimeSessionOwner.extensionRuntimeResidencyState.removeAll()
        dependencies.backgroundRuntimeStateOwner.removeAll()
        dependencies.requestedTabLifecycleOwner.removeAllRecentlyOpenedTabRequests()
        dependencies.clearPermissionsOriginsCompatibilityInstallations()
        dependencies.removeAllExtensionPageUserContentControllers()
        dependencies.cancelInitialDocumentTasks()
        dependencies.cancelNativeMessagingBackgroundWakeTasks(nil)
        cancelNativeMessagingSessions(reason: "resetLoadedExtensionRuntimeStateForReload")
        dependencies.pruneRuntimeAdapters()
    }

    var hasLoadedUserExtensionRuntime: Bool {
        let loadedIDs = allLoadedExtensionIDs()
            .union(dependencies.runtimeSessionOwner.loadedExtensionManifests.keys)
            .union(dependencies.runtimeSessionOwner.cachedWebExtensionsByID.keys)
            .union(dependencies.optionsWindowExtensionIDs())
            .union(dependencies.nativeMessagingPortRegistry.extensionIDs)
            .union(dependencies.errorObservationOwner.observedExtensionIDs)

        if loadedIDs.isEmpty == false {
            return true
        }

        let runtimeState = dependencies.runtimeSessionOwner.runtimeState
        return dependencies.hasEnabledInstalledExtensions()
            && (dependencies.extensionsLoaded()
                || runtimeState == .loading
                || runtimeState == .ready
                || dependencies.profileRuntimeOwner.controllersByProfile.isEmpty == false)
    }

    func tabsAffectedByLoadedUserExtensionRuntime() -> [Tab] {
        guard hasLoadedUserExtensionRuntime else { return [] }

        let controllers = Array(dependencies.profileRuntimeOwner.controllersByProfile.values)
        var affectedTabs: [Tab] = []
        var seenTabIds: Set<UUID> = []

        for tab in dependencies.allKnownTabs() {
            guard seenTabIds.insert(tab.id).inserted else { continue }

            if tab.webExtensionContextOverride != nil
                || tab.webViewConfigurationOverride?.webExtensionController != nil {
                affectedTabs.append(tab)
                continue
            }

            let liveWebViews = dependencies.liveWebViews(tab)
            if tab.isEphemeral == false,
               liveWebViews.isEmpty == false {
                affectedTabs.append(tab)
                continue
            }

            let hasAttachedController = liveWebViews.contains { webView in
                guard let controller = webView.configuration.webExtensionController else {
                    return false
                }
                guard controllers.isEmpty == false else { return true }
                return controllers.contains { $0 === controller }
            }

            if hasAttachedController {
                affectedTabs.append(tab)
            }
        }

        return affectedTabs
    }

    func rebuildLiveWebViewsAfterUserExtensionRuntimeTeardown(
        _ tabs: [Tab],
        reason: String
    ) {
        guard tabs.isEmpty == false else { return }

        var seenTabIds: Set<UUID> = []
        for tab in tabs {
            guard seenTabIds.insert(tab.id).inserted else { continue }

            tab.webExtensionContextOverride = nil
            tab.webViewConfigurationOverride = nil
            tab.extensionPageRuntimeOwner.resetDocumentBindingForContentScriptRebind()
            tab.extensionPageRuntimeOwner.clearOpenNotificationGeneration()

            dependencies.trace {
                "runtimeTeardown rebuildLiveWebViews reason=\(reason) \(self.dependencies.tabDescription(tab))"
            }
            dependencies.runtime().rebuildLiveWebViews(tab)
        }
    }

    func cancelNativeMessagingSessions(reason: String) {
        dependencies.trace {
            "nativeMessagingCancelSessions reason=\(reason) count=\(self.dependencies.nativeMessagingPortRegistry.count)"
        }
        dependencies.nativeMessagingPortRegistry.disconnectAll()
        dependencies.loadedNativeMessagingRelay()?.clearAllLoopGuardState()
    }

    private func allLoadedExtensionIDs() -> Set<String> {
        var identifiers: Set<String> = []
        for contexts in dependencies.profileRuntimeOwner.contextsByProfile.values {
            identifiers.formUnion(contexts.keys)
        }
        return identifiers
    }

    private func unloadExtensionContextIfNeeded(for extensionId: String) {
        for (profileId, contexts) in dependencies.profileRuntimeOwner.contextsByProfile {
            guard let context = contexts[extensionId] else { continue }
            dependencies.backgroundRuntimeStateOwner.removeRuntimeState(
                for: ExtensionRuntimeResidencyState.scopedKey(
                    extensionId: extensionId,
                    profileId: profileId
                )
            )
            _ = dependencies.profileRuntimeOwner.removeContext(
                extensionId: extensionId,
                profileId: profileId
            )
            do {
                try dependencies.profileRuntimeOwner.controller(for: profileId)?.unload(context)
            } catch {
                dependencies.trace {
                    "Ignoring failed unload for extension \(extensionId) profile \(profileId.uuidString): \(error.localizedDescription)"
                }
            }
        }
    }
}

@available(macOS 15.5, *)
extension ExtensionRuntimeStateResetOwner.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            profileRuntimeOwner: manager.profileRuntimeOwner,
            runtimeSessionOwner: manager.runtimeSessionOwner,
            backgroundRuntimeStateOwner: manager.backgroundRuntimeStateOwner,
            requestedTabLifecycleOwner: manager.requestedTabLifecycleOwner,
            nativeMessagingPortRegistry: manager.nativeMessagingPortRegistry,
            errorObservationOwner: manager.errorObservationOwner,
            browserBridgeContext: { [weak manager] in
                manager?.browserBridgeContext
            },
            runtime: { [weak manager] in
                manager?.runtime ?? .inactive
            },
            loadedNativeMessagingRelay: { [weak manager] in
                manager?.loadedNativeMessagingRelay
            },
            cancelNativeMessagingBackgroundWakeTasks: { [weak manager] extensionId in
                if let extensionId {
                    manager?.cancelNativeMessagingBackgroundWakeTasks(
                        forExtensionId: extensionId
                    )
                } else {
                    manager?.cancelNativeMessagingBackgroundWakeTasks()
                }
            },
            cancelInitialDocumentTasks: { [weak manager] in
                manager?.loadedInitialDocumentRuntimePreparationOwner?
                    .cancelDeferredTabNotificationTasks()
                manager?.cancelInitialDocumentNativeMessagingWarmupTasks()
            },
            clearActionSurfaceState: { [weak manager] extensionId in
                manager?.clearActionSurfaceState(for: extensionId)
            },
            clearAllActionSurfaceStates: { [weak manager] in
                manager?.actionStatesByExtensionID.removeAll()
            },
            closeOptionsWindow: { [weak manager] extensionId in
                manager?.closeOptionsWindow(for: extensionId)
            },
            optionsWindowExtensionIDs: { [weak manager] in
                manager.map { Set($0.optionsWindows.keys) } ?? []
            },
            clearActionAnchors: { [weak manager] extensionId in
                manager?.clearActionAnchors(for: extensionId)
            },
            clearPermissionsOriginsCompatibilityInstallations: { [weak manager] in
                manager?.clearPermissionsOriginsCompatibilityInstallations()
            },
            removeAllExtensionPageUserContentControllers: { [weak manager] in
                manager?.controllerProvisioningOwner
                    .removeAllExtensionPageUserContentControllers()
            },
            pruneRuntimeAdapters: { [weak manager] in
                manager?.pruneRuntimeAdapters()
            },
            hasEnabledInstalledExtensions: { [weak manager] in
                manager?.hasEnabledInstalledExtensions ?? false
            },
            extensionsLoaded: { [weak manager] in
                manager?.extensionsLoaded ?? false
            },
            allKnownTabs: { [weak manager] in
                manager?.allKnownTabs() ?? []
            },
            liveWebViews: { [weak manager] tab in
                manager?.liveWebViews(for: tab) ?? []
            },
            tabDescription: { [weak manager] tab in
                manager?.extensionRuntimeTabDescription(tab) ?? "tab=\(tab.id.uuidString.prefix(8))"
            },
            trace: { [weak manager] message in
                manager?.extensionRuntimeTrace(message())
            }
        )
    }
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func tearDownExtensionRuntimeState(
        for extensionId: String,
        removeUIState: Bool
    ) {
        runtimeStateResetOwner.tearDownExtensionRuntimeState(
            for: extensionId,
            removeUIState: removeUIState
        )
    }

    func resetLoadedExtensionRuntimeStateForReload() {
        runtimeStateResetOwner.resetLoadedExtensionRuntimeStateForReload()
    }

    var hasLoadedUserExtensionRuntime: Bool {
        runtimeStateResetOwner.hasLoadedUserExtensionRuntime
    }

    func tabsAffectedByLoadedUserExtensionRuntime() -> [Tab] {
        runtimeStateResetOwner.tabsAffectedByLoadedUserExtensionRuntime()
    }

    func rebuildLiveWebViewsAfterUserExtensionRuntimeTeardown(
        _ tabs: [Tab],
        reason: String
    ) {
        runtimeStateResetOwner.rebuildLiveWebViewsAfterUserExtensionRuntimeTeardown(
            tabs,
            reason: reason
        )
    }

    func cancelNativeMessagingSessions(reason: String) {
        runtimeStateResetOwner.cancelNativeMessagingSessions(reason: reason)
    }

    func tearDownExtensionRuntime(
        reason: String,
        removeUIState: Bool,
        releaseController: Bool
    ) {
        runtimeTeardownOwner.tearDownRuntime(
            manager: self,
            reason: reason,
            removeUIState: removeUIState,
            releaseController: releaseController
        )
    }

    func pruneNativeMessagePortHandlerEntries(
        forExtensionId extensionId: String,
        profileId: UUID? = nil
    ) {
        nativeMessagingPortRegistry.disconnect(extensionId: extensionId, profileId: profileId)
    }

    func observeExtensionErrors(
        for extensionContext: WKWebExtensionContext,
        extensionId: String
    ) {
        errorObservationOwner.observeExtensionErrors(
            for: extensionContext,
            extensionId: extensionId
        )
    }
}
