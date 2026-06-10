import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    var extensionController: WKWebExtensionController? {
        guard let currentProfileId else { return nil }
        return extensionControllersByProfile[currentProfileId]
    }

    var extensionContexts: [String: WKWebExtensionContext] {
        guard let currentProfileId else { return [:] }
        return extensionContextsByProfile[currentProfileId] ?? [:]
    }

    func extensionContexts(for profileId: UUID) -> [String: WKWebExtensionContext] {
        extensionContextsByProfile[profileId] ?? [:]
    }

    func setExtensionContext(
        _ context: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID
    ) {
        var contexts = extensionContextsByProfile[profileId] ?? [:]
        contexts[extensionId] = context
        extensionContextsByProfile[profileId] = contexts
    }

    @discardableResult
    func removeExtensionContext(
        extensionId: String,
        profileId: UUID
    ) -> WKWebExtensionContext? {
        guard var contexts = extensionContextsByProfile[profileId] else {
            return nil
        }
        let removed = contexts.removeValue(forKey: extensionId)
        if contexts.isEmpty {
            extensionContextsByProfile.removeValue(forKey: profileId)
        } else {
            extensionContextsByProfile[profileId] = contexts
        }
        return removed
    }

    func allLoadedExtensionIDs() -> Set<String> {
        Set(extensionContextsByProfile.values.flatMap(\.keys))
    }

    func profileId(for extensionContext: WKWebExtensionContext) -> UUID? {
        for (profileId, contexts) in extensionContextsByProfile {
            if contexts.values.contains(where: { $0 === extensionContext }) {
                return profileId
            }
        }
        return nil
    }

    func profileId(for controller: WKWebExtensionController) -> UUID? {
        extensionControllersByProfile.first(where: { $0.value === controller })?.key
    }

    func resolvedProfileId(for tab: Tab?) -> UUID? {
        guard let tab else { return currentProfileId }
        if let profileId = tab.profileId {
            return profileId
        }
        if let profile = tab.resolveProfile() {
            return profile.id
        }
        if let windowId = tab.primaryWindowId,
           let windowState = browserManager?.windowRegistry?.windows[windowId]
        {
            return resolvedProfileId(for: windowState)
        }
        return currentProfileId ?? browserManager?.currentProfile?.id
    }

    func resolvedProfileId(for windowState: BrowserWindowState) -> UUID? {
        if windowState.isIncognito, let profile = windowState.ephemeralProfile {
            return profile.id
        }
        if let profileId = windowState.currentProfileId {
            return profileId
        }
        return browserManager?.currentProfile?.id
    }

    func windowMatchesProfile(
        _ windowState: BrowserWindowState,
        profileId: UUID
    ) -> Bool {
        resolvedProfileId(for: windowState) == profileId
    }

    func extensionControllerIdentifier(for profileId: UUID) -> UUID {
        var uuid = profileId.uuid
        uuid.15 ^= 0xA5
        return UUID(uuid: uuid)
    }

    @discardableResult
    func ensureExtensionController(for profileId: UUID) -> WKWebExtensionController {
        if let existing = extensionControllersByProfile[profileId] {
            return existing
        }

        let signpostState = PerformanceTrace.beginInterval(
            "ExtensionManager.setupExtensionController"
        )
        defer {
            PerformanceTrace.endInterval(
                "ExtensionManager.setupExtensionController",
                signpostState
            )
        }

        let defaultDataStore = getExtensionDataStore(for: profileId)
        let controller = makeExtensionController(
            defaultDataStore: defaultDataStore,
            profileId: profileId
        )
        extensionControllersByProfile[profileId] = controller
        scheduleControllerDelegateRebind(for: controller)

        if currentProfileId == profileId {
            browserConfiguration.webViewConfiguration.webExtensionController = controller
        }

        extensionRuntimeTrace(
            "ensureExtensionController profile=\(profileId.uuidString) controller=\(extensionRuntimeControllerDescription(controller))"
        )
        updateWebViewsForProfile(profileId)
        verifyExtensionStorage(profileId: profileId)
        return controller
    }

    func extensionController(for tab: Tab) -> WKWebExtensionController? {
        guard let profileId = resolvedProfileId(for: tab) else { return nil }
        if let controller = extensionControllersByProfile[profileId] {
            return controller
        }
        guard hasEnabledInstalledExtensions else { return nil }
        return ensureExtensionController(for: profileId)
    }

    func getExtensionContext(
        for extensionId: String,
        profileId: UUID? = nil
    ) -> WKWebExtensionContext? {
        let resolvedProfileId =
            profileId ?? currentProfileId ?? browserManager?.currentProfile?.id
        guard let resolvedProfileId else { return nil }
        return extensionContexts(for: resolvedProfileId)[extensionId]
    }

    func missingEnabledExtensionIDs(for profileId: UUID) -> [String] {
        let enabledIDs = Set(enabledPersistedExtensionEntities().map(\.id))
        let loadedIDs = Set(extensionContexts(for: profileId).keys)
        return Array(enabledIDs.subtracting(loadedIDs)).sorted()
    }

    func isProfileExtensionRuntimeReady(for profileId: UUID) -> Bool {
        guard hasEnabledInstalledExtensions else { return true }
        return missingEnabledExtensionIDs(for: profileId).isEmpty
    }

    func isExtensionRuntimeReady(
        extensionId: String,
        profileId: UUID
    ) -> Bool {
        guard let context = getExtensionContext(for: extensionId, profileId: profileId) else {
            return false
        }
        return context.isLoaded
    }

    func markExtensionRuntimeReadyIfProfileContextsLoaded(for profileId: UUID) {
        guard extensionControllersByProfile[profileId] != nil else { return }
        extensionsLoaded = true
        if isProfileExtensionRuntimeReady(for: profileId) {
            runtimeState = .ready
        } else if runtimeState != .failed {
            runtimeState = .ready
        }
        extensionRuntimeTrace(
            "markExtensionRuntimeReady profile=\(profileId.uuidString) loadedContexts=\(extensionContexts(for: profileId).count) allEnabledLoaded=\(isProfileExtensionRuntimeReady(for: profileId))"
        )
    }

    func recordExtensionLoadError(
        _ error: Error,
        extensionId: String,
        profileId: UUID
    ) {
        lastExtensionLoadErrors[
            backgroundScopedKey(extensionId: extensionId, profileId: profileId)
        ] = error
    }

    func clearExtensionLoadError(extensionId: String, profileId: UUID) {
        lastExtensionLoadErrors.removeValue(
            forKey: backgroundScopedKey(extensionId: extensionId, profileId: profileId)
        )
    }

    func lastExtensionLoadError(
        extensionId: String,
        profileId: UUID
    ) -> Error? {
        lastExtensionLoadErrors[
            backgroundScopedKey(extensionId: extensionId, profileId: profileId)
        ]
    }

    func countLoadedExtensionContexts() -> Int {
        extensionContextsByProfile.values.reduce(0) { $0 + $1.count }
    }

    func touchLiveExtensionContext(extensionId: String, profileId: UUID) {
        let key = backgroundScopedKey(extensionId: extensionId, profileId: profileId)
        liveExtensionContextOrder.removeAll { $0 == key }
        liveExtensionContextOrder.append(key)
    }

    func enforceBoundedLiveExtensionContexts(
        keepingProfileId: UUID,
        keepingExtensionId: String
    ) {
        let keepKey = backgroundScopedKey(
            extensionId: keepingExtensionId,
            profileId: keepingProfileId
        )
        touchLiveExtensionContext(
            extensionId: keepingExtensionId,
            profileId: keepingProfileId
        )

        while countLoadedExtensionContexts() > Self.maxLiveExtensionContexts,
              let evictionKey = liveExtensionContextOrder.first(where: { $0 != keepKey })
        {
            guard let parsed = parseBackgroundScopedKey(evictionKey) else {
                liveExtensionContextOrder.removeAll { $0 == evictionKey }
                continue
            }
            unloadExtensionContextIfLoaded(
                extensionId: parsed.extensionId,
                profileId: parsed.profileId
            )
        }
    }

    func unloadExtensionContextsForInactiveProfiles(keepingProfileId: UUID) {
        for profileId in Array(extensionContextsByProfile.keys)
        where profileId != keepingProfileId
        {
            for extensionId in Array(extensionContexts(for: profileId).keys) {
                unloadExtensionContextIfLoaded(
                    extensionId: extensionId,
                    profileId: profileId
                )
            }
        }
    }

    func unloadExtensionContextIfLoaded(
        extensionId: String,
        profileId: UUID
    ) {
        guard let context = getExtensionContext(for: extensionId, profileId: profileId) else {
            return
        }

        let wakeKey = backgroundScopedKey(extensionId: extensionId, profileId: profileId)
        backgroundWakeTasks[wakeKey]?.cancel()
        backgroundWakeTasks.removeValue(forKey: wakeKey)
        backgroundRuntimeStateByExtensionID.removeValue(forKey: wakeKey)
        liveExtensionContextOrder.removeAll { $0 == wakeKey }

        removeExtensionContext(extensionId: extensionId, profileId: profileId)
        if let controller = extensionControllersByProfile[profileId] {
            do {
                try controller.unload(context)
            } catch {
                extensionRuntimeTrace(
                    "Ignoring failed unload for extension \(extensionId) profile \(profileId.uuidString): \(error.localizedDescription)"
                )
            }
        }

        extensionRuntimeTrace(
            "unloadExtensionContext extensionId=\(extensionId) profileId=\(profileId.uuidString) remainingContexts=\(countLoadedExtensionContexts())"
        )
    }

    private func parseBackgroundScopedKey(
        _ key: String
    ) -> (profileId: UUID, extensionId: String)? {
        let parts = key.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let profileId = UUID(uuidString: String(parts[0]))
        else {
            return nil
        }
        return (profileId, String(parts[1]))
    }

    @discardableResult
    func ensureExtensionLoaded(
        extensionId: String,
        profileId: UUID
    ) async throws -> WKWebExtensionContext? {
        guard isExtensionSupportAvailable else { return nil }

        _ = ensureExtensionController(for: profileId)

        if let context = getExtensionContext(for: extensionId, profileId: profileId),
           context.isLoaded
        {
            touchLiveExtensionContext(extensionId: extensionId, profileId: profileId)
            enforceBoundedLiveExtensionContexts(
                keepingProfileId: profileId,
                keepingExtensionId: extensionId
            )
            return context
        }

        guard let entity = try extensionEntity(for: extensionId),
              entity.isEnabled
        else {
            return nil
        }

        _ = try await loadEnabledExtension(
            from: entity,
            profileId: profileId,
            expectedLoadGeneration: extensionLoadGeneration
        )
        touchLiveExtensionContext(extensionId: extensionId, profileId: profileId)
        enforceBoundedLiveExtensionContexts(
            keepingProfileId: profileId,
            keepingExtensionId: extensionId
        )
        return getExtensionContext(for: extensionId, profileId: profileId)
    }

    /// Loads every enabled extension for a profile. Prefer `ensureExtensionLoaded` for lazy paths.
    func ensureEnabledExtensionsLoaded(for profileId: UUID) async {
        guard isExtensionSupportAvailable else { return }

        _ = ensureExtensionController(for: profileId)
        let enabledEntities = enabledPersistedExtensionEntities()
        guard enabledEntities.isEmpty == false else { return }

        for entity in enabledEntities {
            guard getExtensionContext(for: entity.id, profileId: profileId) == nil else {
                continue
            }

            do {
                _ = try await loadEnabledExtension(
                    from: entity,
                    profileId: profileId,
                    expectedLoadGeneration: extensionLoadGeneration
                )
            } catch {
                Self.logger.error(
                    "Failed to load enabled extension \(entity.name, privacy: .public) for profile \(profileId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        markExtensionRuntimeReadyIfProfileContextsLoaded(for: profileId)
    }

    func updateWebViewsForProfile(_ profileId: UUID) {
        guard let controller = extensionControllersByProfile[profileId] else { return }
        guard browserManager != nil else { return }

        for tab in allKnownTabs() {
            guard resolvedProfileId(for: tab) == profileId else { continue }
            for webView in liveWebViews(for: tab) {
                let existingController = webView.configuration.webExtensionController
                let canLateBind = canLateBindExtensionController(to: webView)
                let willAssign = existingController == nil && canLateBind
                extensionRuntimeTrace(
                    "updateWebViewsForProfile webView=\(extensionRuntimeWebViewDescription(webView)) profile=\(profileId.uuidString) existingController=\(extensionRuntimeControllerDescription(existingController)) targetController=\(extensionRuntimeControllerDescription(controller)) canLateBind=\(canLateBind) willAssign=\(willAssign) \(extensionRuntimeTabDescription(tab))"
                )
                if willAssign {
                    webView.configuration.webExtensionController = controller
                    webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = true
                }
            }
        }
    }

    func refreshActionSurfaceStateForCurrentProfile() {
        guard let profileId = currentProfileId else { return }
        for (extensionId, context) in extensionContexts(for: profileId) {
            publishActionSurfaceStateForLoadedContext(context)
            _ = extensionId
        }
    }

    func backgroundScopedKey(
        extensionId: String,
        profileId: UUID
    ) -> String {
        "\(profileId.uuidString):\(extensionId)"
    }

    func classifyActionPopupRuntimeFailure(
        extensionId: String,
        profileId: UUID,
        installedExtension: InstalledExtension? = nil
    ) -> ExtensionActionPopupRuntimeFailureBucket {
        let installed =
            installedExtension
            ?? installedExtensions.first(where: { $0.id == extensionId })

        guard extensionControllersByProfile[profileId] != nil else {
            return .profileRuntimeNotFound
        }

        guard let installed else {
            return .deletedImportRecordStale
        }

        let packageExists = FileManager.default.fileExists(
            atPath: installed.packagePath
        )
        if packageExists == false {
            return .copiedResourcesMissing
        }

        let hasOriginalAppex =
            SafariAppExtensionResources.installedAppexBundleURL(
                sourceKind: installed.sourceKind,
                sourceBundlePath: installed.sourceBundlePath
            ) != nil
        if installed.sourceKind == .safariAppExtension,
           hasOriginalAppex == false,
           packageExists == false
        {
            return .originalAppExtensionBundleMissing
        }

        if let loadError = lastExtensionLoadError(
            extensionId: extensionId,
            profileId: profileId
        ) {
            let nsError = loadError as NSError
            if nsError.domain == WKWebExtension.errorDomain {
                return .webExtensionCreationFailed
            }
            if loadError is ExtensionError {
                return .manifestValidationPolicyWrongForSourceKind
            }
        }

        let context = getExtensionContext(for: extensionId, profileId: profileId)
        if let context,
           let currentProfileId,
           currentProfileId != profileId,
           self.profileId(for: context) != profileId
        {
            return .wrongProfileRuntimeLookup
        }

        if context == nil {
            if let loadError = lastExtensionLoadError(
                extensionId: extensionId,
                profileId: profileId
            ) {
                _ = loadError
                return .webExtensionCreationFailed
            }
            return .profileContextNotCreated
        }

        if context?.isLoaded == false {
            return .profileContextNotLoaded
        }

        if runtimeState == .failed {
            return .globalRuntimeLoadFailed
        }

        if runtimeState != .ready {
            return .globalRuntimeUnavailable
        }

        return .enabledStateWithoutRuntime
    }

    func actionPopupRuntimeDiagnosticLines(
        extensionId: String,
        profileId: UUID,
        installedExtension: InstalledExtension,
        failureBucket: ExtensionActionPopupRuntimeFailureBucket,
        lastLoadError: Error? = nil
    ) -> [String] {
        let context = getExtensionContext(for: extensionId, profileId: profileId)
        let controller = extensionControllersByProfile[profileId]
        let hasOriginalAppex =
            SafariAppExtensionResources.installedAppexBundleURL(
                sourceKind: installedExtension.sourceKind,
                sourceBundlePath: installedExtension.sourceBundlePath
            ) != nil
        let packageExists = FileManager.default.fileExists(
            atPath: installedExtension.packagePath
        )

        var lines = [
            "failureBucket=\(failureBucket.rawValue)",
            "extensionId=\(extensionId)",
            "displayName=\(installedExtension.name)",
            "profileId=\(profileId.uuidString)",
            "sourceKind=\(installedExtension.sourceKind.rawValue)",
            "hasOriginalAppex=\(hasOriginalAppex)",
            "copiedResourcesPresent=\(packageExists)",
            "controllerExists=\(controller != nil)",
            "contextExists=\(context != nil)",
            "contextLoaded=\(context?.isLoaded ?? false)",
            "runtimeState=\(runtimeState.rawValue)",
            "missingEnabledExtensionIDs=\(missingEnabledExtensionIDs(for: profileId).joined(separator: ","))",
        ]

        if let lastLoadError {
            let nsError = lastLoadError as NSError
            lines.append("lastErrorDomain=\(nsError.domain)")
            lines.append("lastErrorCode=\(nsError.code)")
            lines.append("lastErrorDescription=\(nsError.localizedDescription)")
        } else if let recordedError = lastExtensionLoadError(
            extensionId: extensionId,
            profileId: profileId
        ) {
            let nsError = recordedError as NSError
            lines.append("lastErrorDomain=\(nsError.domain)")
            lines.append("lastErrorCode=\(nsError.code)")
            lines.append("lastErrorDescription=\(nsError.localizedDescription)")
        } else if let context, context.errors.isEmpty == false, let error = context.errors.first {
            let nsError = error as NSError
            lines.append("webKitErrorDomain=\(nsError.domain)")
            lines.append("webKitErrorCode=\(nsError.code)")
            lines.append("webKitErrorDescription=\(nsError.localizedDescription)")
        }

        return lines
    }
}
