import Foundation
import SwiftData
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func observeExtensionErrors(
        for extensionContext: WKWebExtensionContext,
        extensionId: String
    ) {
        removeExtensionErrorObserver(for: extensionId)
        guard Self.shouldObserveExtensionErrors else { return }

        let token = NotificationCenter.default.addObserver(
            forName: WKWebExtensionContext.errorsDidUpdateNotification,
            object: extensionContext,
            queue: .main
        ) { [weak self, weak extensionContext] _ in
            guard let self, let extensionContext else { return }
            Task { @MainActor [weak self, weak extensionContext] in
                guard let self, let extensionContext else { return }
                self.logExtensionErrorsIfNeeded(
                    for: extensionContext,
                    extensionId: extensionId,
                    reason: "update"
                )
            }
        }

        extensionErrorObserverTokens[extensionId] = token
        logExtensionErrorsIfNeeded(
            for: extensionContext,
            extensionId: extensionId,
            reason: "initial"
        )
    }

    func tearDownExtensionRuntimeState(
        for extensionId: String,
        removeUIState: Bool
    ) {
        browserBridgeContext?.closeAuxiliaryWindowSessions(
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

        for profileId in extensionContextsByProfile.keys {
            let wakeKey = backgroundScopedKey(extensionId: extensionId, profileId: profileId)
            backgroundRuntimeStateOwner.cancelAndRemoveRuntime(for: wakeKey)
        }
        cancelNativeMessagingBackgroundWakeTasks(forExtensionId: extensionId)
        clearActionSurfaceState(for: extensionId)
        unloadExtensionContextIfNeeded(for: extensionId)
        removeExtensionErrorObserver(for: extensionId)
        loadedExtensionManifests.removeValue(forKey: extensionId)
        cachedWebExtensionsByID.removeValue(forKey: extensionId)
        cachedWebExtensionRuntimeSourceKeysByID.removeValue(forKey: extensionId)
        lastExtensionLoadErrors = lastExtensionLoadErrors.filter {
            !$0.key.hasSuffix(":\(extensionId)")
        }
        extensionRuntimeResidencyState.remove(extensionId: extensionId)
        lastLoggedExtensionErrorFingerprints.removeValue(forKey: extensionId)
        closeOptionsWindow(for: extensionId)
        tearDownNativeMessageHandlers(for: extensionId)
        loadedNativeMessagingRelay?.clearLoopGuard(forExtensionId: extensionId)

        if removeUIState {
            clearActionAnchors(for: extensionId)
        }

        pruneRuntimeAdapters()
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
            .union(loadedExtensionManifests.keys)
            .union(optionsWindows.keys)
            .union(nativeMessagingPortRegistry.extensionIDs)

        for extensionId in loadedIDs {
            tearDownExtensionRuntimeState(for: extensionId, removeUIState: false)
        }

        extensionContextsByProfile.removeAll()
        loadedExtensionManifests.removeAll()
        actionStatesByExtensionID.removeAll()
        cachedWebExtensionsByID.removeAll()
        cachedWebExtensionRuntimeSourceKeysByID.removeAll()
        lastExtensionLoadErrors.removeAll()
        extensionRuntimeResidencyState.removeAll()
        backgroundRuntimeStateOwner.removeAll()
        requestedTabLifecycleOwner.removeAllRecentlyOpenedTabRequests()
        clearPermissionsOriginsCompatibilityInstallations()
        extensionPageUserContentControllersByProfile.removeAll()
        loadedInitialDocumentRuntimePreparationOwner?
            .cancelDeferredTabNotificationTasks()
        cancelInitialDocumentNativeMessagingWarmupTasks()
        cancelNativeMessagingBackgroundWakeTasks()
        cancelNativeMessagingSessions(reason: "resetLoadedExtensionRuntimeStateForReload")
        pruneRuntimeAdapters()
    }

    var hasLoadedUserExtensionRuntime: Bool {
        let loadedIDs = allLoadedExtensionIDs()
            .union(loadedExtensionManifests.keys)
            .union(cachedWebExtensionsByID.keys)
            .union(optionsWindows.keys)
            .union(nativeMessagingPortRegistry.extensionIDs)
            .union(extensionErrorObserverTokens.keys)

        if loadedIDs.isEmpty == false {
            return true
        }

        return hasEnabledInstalledExtensions
            && (extensionsLoaded
                || runtimeState == .loading
                || runtimeState == .ready
                || extensionControllersByProfile.isEmpty == false)
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

    func tabsAffectedByLoadedUserExtensionRuntime() -> [Tab] {
        guard hasLoadedUserExtensionRuntime else { return [] }

        let controllers = Array(extensionControllersByProfile.values)
        var affectedTabs: [Tab] = []
        var seenTabIds: Set<UUID> = []

        for tab in allKnownTabs() {
            guard seenTabIds.insert(tab.id).inserted else { continue }

            if tab.webExtensionContextOverride != nil
                || tab.webViewConfigurationOverride?.webExtensionController != nil {
                affectedTabs.append(tab)
                continue
            }

            let liveWebViews = liveWebViews(for: tab)
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

            extensionRuntimeTrace(
                "runtimeTeardown rebuildLiveWebViews reason=\(reason) \(extensionRuntimeTabDescription(tab))"
            )
            runtime.rebuildLiveWebViews(tab)
        }
    }

    func cancelNativeMessagingSessions(reason: String) {
        extensionRuntimeTrace(
            "nativeMessagingCancelSessions reason=\(reason) count=\(nativeMessagingPortRegistry.count)"
        )
        nativeMessagingPortRegistry.disconnectAll()
        loadedNativeMessagingRelay?.clearAllLoopGuardState()
    }

    func makeExtensionController(
        defaultDataStore: WKWebsiteDataStore,
        profileId: UUID
    ) -> WKWebExtensionController {
        let configuration = WKWebExtensionController.Configuration(
            identifier: extensionControllerIdentifier(for: profileId)
        )
        let runtimeWebConfiguration = browserConfiguration.webViewConfiguration
        let extensionPageConfiguration =
            makeExtensionPageBaseWebViewConfiguration(
                from: runtimeWebConfiguration,
                websiteDataStore: defaultDataStore
            )
        extensionPageUserContentControllersByProfile[profileId] =
            extensionPageConfiguration.userContentController
        configuration.webViewConfiguration = extensionPageConfiguration
        configuration.defaultWebsiteDataStore = defaultDataStore

        let controller = WKWebExtensionController(configuration: configuration)
        controller.delegate = self
        traceNativeMessagingContextBinding(
            phase: "controllerCreated",
            extensionId: nil,
            profileId: profileId,
            controller: controller,
            configuration: extensionPageConfiguration
        )

        if currentProfileId == profileId {
            runtimeWebConfiguration.webExtensionController = controller
        }
        runtimeWebConfiguration.defaultWebpagePreferences.allowsContentJavaScript = true

        return controller
    }

    private func makeExtensionPageBaseWebViewConfiguration(
        from source: WKWebViewConfiguration,
        websiteDataStore: WKWebsiteDataStore
    ) -> WKWebViewConfiguration {
        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            from: source,
            surface: .extensionOptions
        )
        configuration.websiteDataStore = websiteDataStore
        configuration.sumiIsNormalTabWebViewConfiguration = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        return configuration
    }

    func resolvedExtensionRuntimeWebsiteDataStore(
        profileId: UUID? = nil
    ) -> WKWebsiteDataStore? {
        let resolvedProfileId = resolvedProfileId(explicitProfileId: profileId)
        guard let resolvedProfileId else { return nil }
        if let store = extensionControllersByProfile[resolvedProfileId]?
            .configuration.defaultWebsiteDataStore {
            return store
        }
        return getExtensionDataStore(for: resolvedProfileId)
    }

    func scheduleControllerDelegateRebind(
        for controller: WKWebExtensionController
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak controller] in
            guard let self, let controller else { return }
            guard self.extensionControllersByProfile.values.contains(where: { $0 === controller }) else {
                return
            }
            controller.delegate = self
            self.traceNativeMessagingContextBinding(
                phase: "delegateRebound",
                extensionId: nil,
                profileId: self.profileId(for: controller),
                controller: controller
            )
        }
    }

    func verifyExtensionStorage(profileId: UUID?) {
        guard RuntimeDiagnostics.isVerboseEnabled else {
            return
        }
        guard let profileId,
              let dataStore = extensionControllersByProfile[profileId]?
            .configuration.defaultWebsiteDataStore
        else {
            return
        }
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            Self.logger.debug("Extension data store ready for profile \(profileId.uuidString, privacy: .public): \(records.count) records")
        }
    }

    func getExtensionDataStore(
        for profileId: UUID
    ) -> WKWebsiteDataStore {
        profileRuntimeOwner.websiteDataStore(
            for: profileId,
            runtime: runtime
        )
    }

    func canLateBindExtensionController(to webView: WKWebView) -> Bool {
        webView.configuration.webExtensionController == nil
            && ExtensionRuntimeWebViewBindingPolicy.canLateBindController(
                currentURL: webView.url
            )
    }

    private func removeExtensionErrorObserver(for extensionId: String) {
        guard let token = extensionErrorObserverTokens.removeValue(forKey: extensionId) else {
            return
        }

        NotificationCenter.default.removeObserver(token)
    }

    private func logExtensionErrorsIfNeeded(
        for extensionContext: WKWebExtensionContext,
        extensionId: String,
        reason: String
    ) {
        guard Self.shouldObserveExtensionErrors else { return }

        let updateStart = CFAbsoluteTimeGetCurrent()
        defer {
            recordRuntimeMetric(for: extensionId) {
                $0.errorUpdateDuration =
                    CFAbsoluteTimeGetCurrent() - updateStart
            }
        }

        let errors = extensionContext.errors
        let fingerprint = errors
            .map { error in
                let nsError = error as NSError
                return [
                    nsError.domain,
                    String(nsError.code),
                    nsError.localizedDescription,
                    Self.describeUserInfo(nsError.userInfo),
                ].joined(separator: "|")
            }
            .joined(separator: "\n")

        guard lastLoggedExtensionErrorFingerprints[extensionId] != fingerprint else {
            return
        }

        lastLoggedExtensionErrorFingerprints[extensionId] = fingerprint

        guard errors.isEmpty == false else {
            extensionRuntimeTrace(
                "Extension errors \(reason) for \(extensionId): none"
            )
            return
        }

        for error in errors {
            let nsError = error as NSError
            let userInfoDescription = Self.describeUserInfo(nsError.userInfo)
            Self.logger.error(
                "Extension error \(reason, privacy: .public) for \(extensionId, privacy: .public): domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) description=\(nsError.localizedDescription, privacy: .public) userInfo=\(userInfoDescription, privacy: .public)"
            )
        }
    }

    nonisolated private static func describeUserInfo(_ userInfo: [String: Any]) -> String {
        #if DEBUG || SUMI_DIAGNOSTICS
            guard userInfo.isEmpty == false else {
                return "{}"
            }

            if JSONSerialization.isValidJSONObject(userInfo),
               let data = try? JSONSerialization.data(withJSONObject: userInfo, options: [.sortedKeys]),
               let string = String(data: data, encoding: .utf8) {
                return string
            }

            let parts = userInfo.keys.sorted().map { key in
                "\(key)=\(String(describing: userInfo[key] ?? "nil"))"
            }
            return "{\(parts.joined(separator: ", "))}"
        #else
            _ = userInfo
            return "{}"
        #endif
    }

    func pruneNativeMessagePortHandlerEntries(
        forExtensionId extensionId: String,
        profileId: UUID? = nil
    ) {
        nativeMessagingPortRegistry.disconnect(extensionId: extensionId, profileId: profileId)
    }

    private func tearDownNativeMessageHandlers(for extensionId: String) {
        nativeMessagingPortRegistry.disconnect(extensionId: extensionId)
    }

    private func unloadExtensionContextIfNeeded(for extensionId: String) {
        for (profileId, contexts) in extensionContextsByProfile {
            guard let context = contexts[extensionId] else { continue }
            backgroundRuntimeStateOwner.removeRuntimeState(
                for: backgroundScopedKey(extensionId: extensionId, profileId: profileId)
            )
            removeExtensionContext(extensionId: extensionId, profileId: profileId)
            do {
                try extensionControllersByProfile[profileId]?.unload(context)
            } catch {
                extensionRuntimeTrace(
                    "Ignoring failed unload for extension \(extensionId) profile \(profileId.uuidString): \(error.localizedDescription)"
                )
            }
        }
    }
}
