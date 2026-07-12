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
        let profileRuntime: ExtensionProfileRuntime
        let runtimeSession: ExtensionRuntimeSession
        let backgroundRuntimeStateOwner: ExtensionBackgroundRuntimeStateOwner
        let recentTabRequests: ExtensionRecentTabRequestHistory
        let nativeMessagingPortRegistry: ExtensionNativeMessagingPortRegistry
        let errorObservationOwner: ExtensionErrorObservationOwner
        let auxiliaryWindows:
            @MainActor () -> (any ExtensionAuxiliaryWindowControl)?
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
        dependencies.auxiliaryWindows()?.closeAuxiliaryWindowSessions(
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

        for profileId in dependencies.profileRuntime.contextsByProfile.keys {
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
        dependencies.runtimeSession.loadedExtensionManifests
            .removeValue(forKey: extensionId)
        dependencies.runtimeSession.cachedWebExtensionsByID
            .removeValue(forKey: extensionId)
        dependencies.runtimeSession.cachedWebExtensionRuntimeSourceKeysByID
            .removeValue(forKey: extensionId)
        dependencies.runtimeSession.lastExtensionLoadErrors =
            dependencies.runtimeSession.lastExtensionLoadErrors.filter {
                !$0.key.hasSuffix(":\(extensionId)")
            }
        dependencies.runtimeSession.extensionRuntimeResidencyState
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
            .union(dependencies.runtimeSession.loadedExtensionManifests.keys)
            .union(dependencies.optionsWindowExtensionIDs())
            .union(dependencies.nativeMessagingPortRegistry.extensionIDs)

        for extensionId in loadedIDs {
            tearDownExtensionRuntimeState(for: extensionId, removeUIState: false)
        }

        dependencies.profileRuntime.replaceContexts([:])
        dependencies.runtimeSession.loadedExtensionManifests.removeAll()
        dependencies.clearAllActionSurfaceStates()
        dependencies.runtimeSession.cachedWebExtensionsByID.removeAll()
        dependencies.runtimeSession.cachedWebExtensionRuntimeSourceKeysByID.removeAll()
        dependencies.runtimeSession.lastExtensionLoadErrors.removeAll()
        dependencies.runtimeSession.extensionRuntimeResidencyState.removeAll()
        dependencies.backgroundRuntimeStateOwner.removeAll()
        dependencies.recentTabRequests.removeAll()
        dependencies.clearPermissionsOriginsCompatibilityInstallations()
        dependencies.removeAllExtensionPageUserContentControllers()
        dependencies.cancelInitialDocumentTasks()
        dependencies.cancelNativeMessagingBackgroundWakeTasks(nil)
        cancelNativeMessagingSessions(reason: "resetLoadedExtensionRuntimeStateForReload")
        dependencies.pruneRuntimeAdapters()
    }

    var hasLoadedUserExtensionRuntime: Bool {
        let loadedIDs = allLoadedExtensionIDs()
            .union(dependencies.runtimeSession.loadedExtensionManifests.keys)
            .union(dependencies.runtimeSession.cachedWebExtensionsByID.keys)
            .union(dependencies.optionsWindowExtensionIDs())
            .union(dependencies.nativeMessagingPortRegistry.extensionIDs)
            .union(dependencies.errorObservationOwner.observedExtensionIDs)

        if loadedIDs.isEmpty == false {
            return true
        }

        let runtimeState = dependencies.runtimeSession.runtimeState
        return dependencies.hasEnabledInstalledExtensions()
            && (dependencies.extensionsLoaded()
                || runtimeState == .loading
                || runtimeState == .ready
                || dependencies.profileRuntime.controllersByProfile.isEmpty == false)
    }

    func tabsAffectedByLoadedUserExtensionRuntime() -> [Tab] {
        guard hasLoadedUserExtensionRuntime else { return [] }

        let controllers = Array(dependencies.profileRuntime.controllersByProfile.values)
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
        for contexts in dependencies.profileRuntime.contextsByProfile.values {
            identifiers.formUnion(contexts.keys)
        }
        return identifiers
    }

    private func unloadExtensionContextIfNeeded(for extensionId: String) {
        for (profileId, contexts) in dependencies.profileRuntime.contextsByProfile {
            guard let context = contexts[extensionId] else { continue }
            dependencies.backgroundRuntimeStateOwner.removeRuntimeState(
                for: ExtensionRuntimeResidencyState.scopedKey(
                    extensionId: extensionId,
                    profileId: profileId
                )
            )
            _ = dependencies.profileRuntime.removeContext(
                extensionId: extensionId,
                profileId: profileId
            )
            do {
                try dependencies.profileRuntime.controller(for: profileId)?.unload(context)
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
            profileRuntime: manager.profileRuntime,
            runtimeSession: manager.runtimeSession,
            backgroundRuntimeStateOwner: manager.backgroundRuntimeStateOwner,
            recentTabRequests: manager.recentExtensionTabRequests,
            nativeMessagingPortRegistry: manager.nativeMessagingPortRegistry,
            errorObservationOwner: manager.errorObservationOwner,
            auxiliaryWindows: { [weak manager] in
                manager?.extensionAuxiliaryWindows
            },
            runtime: { [weak manager] in
                manager?.runtime ?? .inactive
            },
            loadedNativeMessagingRelay: { [weak manager] in
                manager?.loadedNativeMessagingRelayOwner?.loadedRelay
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
                manager?.actionSurfacePublisher.clearActionSurfaceState(for: extensionId)
            },
            clearAllActionSurfaceStates: { [weak manager] in
                manager?.actionStatesByExtensionID.removeAll()
            },
            closeOptionsWindow: { [weak manager] extensionId in
                manager?.optionsWindows.closeWindow(for: extensionId)
            },
            optionsWindowExtensionIDs: { [weak manager] in
                manager?.optionsWindows.extensionIDs ?? []
            },
            clearActionAnchors: { [weak manager] extensionId in
                manager?.actionAnchorStore.clearAnchors(for: extensionId)
            },
            clearPermissionsOriginsCompatibilityInstallations: { [weak manager] in
                manager?.permissionsOriginsCompatibilityPreludeInstallationOwner
                    .clearInstallations()
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
                manager?.runtimeDiagnostics.tabDescription(tab, manager: manager) ?? "tab=\(tab.id.uuidString.prefix(8))"
            },
            trace: { [weak manager] message in
                manager?.runtimeDiagnostics.trace(message())
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
