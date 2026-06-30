import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    var extensionController: WKWebExtensionController? {
        profileRuntimeStateOwner.currentController
    }

    var extensionContexts: [String: WKWebExtensionContext] {
        profileRuntimeStateOwner.currentContexts
    }

    func extensionContexts(for profileId: UUID) -> [String: WKWebExtensionContext] {
        profileRuntimeStateOwner.contexts(for: profileId)
    }

    func setExtensionContext(
        _ context: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID
    ) {
        let generation = profileRuntimeOwner.setContext(
            context,
            extensionId: extensionId,
            profileId: profileId
        )
        traceExtensionContextBindingGeneration(
            profileId: profileId,
            generation: generation,
            reason: "setExtensionContext"
        )
    }

    func extensionContextBindingGeneration(for profileId: UUID) -> UInt64 {
        profileRuntimeOwner.contextBindingGeneration(for: profileId)
    }

    func bumpExtensionContextBindingGeneration(
        for profileId: UUID,
        reason: String
    ) {
        let next = profileRuntimeOwner.bumpContextBindingGeneration(for: profileId)
        traceExtensionContextBindingGeneration(
            profileId: profileId,
            generation: next,
            reason: reason
        )
    }

    private func traceExtensionContextBindingGeneration(
        profileId: UUID,
        generation: UInt64,
        reason: String
    ) {
        extensionRuntimeTrace(
            "extensionContextBindingGeneration profile=\(profileId.uuidString) generation=\(generation) reason=\(reason)"
        )
    }

    @discardableResult
    func removeExtensionContext(
        extensionId: String,
        profileId: UUID
    ) -> WKWebExtensionContext? {
        guard let removed = profileRuntimeOwner.removeContext(
            extensionId: extensionId,
            profileId: profileId
        ) else { return nil }
        traceExtensionContextBindingGeneration(
            profileId: profileId,
            generation: removed.generation,
            reason: "removeExtensionContext"
        )
        return removed.context
    }

    func allLoadedExtensionIDs() -> Set<String> {
        profileRuntimeStateOwner.allLoadedExtensionIDs()
    }

    func profileId(for extensionContext: WKWebExtensionContext) -> UUID? {
        profileRuntimeStateOwner.profileId(for: extensionContext)
    }

    func contextIdentity(
        for extensionContext: WKWebExtensionContext
    ) -> (extensionId: String, profileId: UUID)? {
        profileRuntimeStateOwner.contextIdentity(for: extensionContext)
    }

    func profileId(for controller: WKWebExtensionController) -> UUID? {
        profileRuntimeStateOwner.profileId(for: controller)
    }

    func resolvedProfileId(for tab: Tab?) -> UUID? {
        profileRuntimeOwner.resolvedProfileId(
            for: tab,
            runtime: runtime
        )
    }

    func resolvedProfileId(for windowState: BrowserWindowState) -> UUID? {
        profileRuntimeOwner.resolvedProfileId(
            for: windowState,
            runtime: runtime
        )
    }

    func resolvedProfileId(explicitProfileId: UUID?) -> UUID? {
        profileRuntimeOwner.resolvedProfileId(
            explicitProfileId: explicitProfileId,
            runtime: runtime
        )
    }

    var fallbackProfileId: UUID? {
        resolvedProfileId(explicitProfileId: nil)
    }

    func rememberPrivateExtensionRuntimeProfileIfNeeded(_ profile: Profile) {
        profileRuntimeOwner.rememberPrivateRuntimeProfileIfNeeded(profile)
    }

    func isPrivateExtensionRuntimeProfile(_ profileId: UUID?) -> Bool {
        profileRuntimeOwner.isPrivateRuntimeProfile(profileId)
    }

    func windowMatchesProfile(
        _ windowState: BrowserWindowState,
        profileId: UUID
    ) -> Bool {
        profileRuntimeOwner.windowMatchesProfile(
            windowState,
            profileId: profileId,
            runtime: runtime
        )
    }

    func extensionControllerIdentifier(for profileId: UUID) -> UUID {
        var uuid = profileId.uuid
        uuid.15 ^= 0xA5
        return UUID(uuid: uuid)
    }

    func extensionsModuleEnabledForRuntimeBoundary() -> Bool {
        runtime.extensionsModuleEnabled() ?? true
    }

    @discardableResult
    func ensureExtensionController(for profileId: UUID) -> WKWebExtensionController {
        if let existing = profileRuntimeOwner.controller(for: profileId) {
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
        profileRuntimeOwner.setController(controller, for: profileId)
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
        guard hasEnabledInstalledExtensions
            || extensionRuntimeAllowsWithoutEnabledExtensions
        else {
            return nil
        }
        return ensureExtensionController(for: profileId)
    }

    func getExtensionContext(
        for extensionId: String,
        profileId: UUID? = nil
    ) -> WKWebExtensionContext? {
        profileRuntimeStateOwner.context(for: extensionId, profileId: profileId)
    }

    func missingEnabledExtensionIDs(for profileId: UUID) -> [String] {
        profileRuntimeStateOwner.missingEnabledExtensionIDs(for: profileId)
    }

    func isProfileExtensionRuntimeReady(for profileId: UUID) -> Bool {
        profileRuntimeStateOwner.isProfileReady(for: profileId)
    }

    func isExtensionRuntimeReady(
        extensionId: String,
        profileId: UUID
    ) -> Bool {
        profileRuntimeStateOwner.isExtensionReady(
            extensionId: extensionId,
            profileId: profileId
        )
    }

    func markExtensionRuntimeReadyIfProfileContextsLoaded(for profileId: UUID) {
        guard extensionControllersByProfile[profileId] != nil else { return }
        let readiness = extensionRuntimeReadinessContext(for: profileId)
        extensionsLoaded = true
        if readiness.isProfileReady {
            runtimeState = .ready
        } else if runtimeState != .failed {
            runtimeState = .ready
        }
        extensionRuntimeTrace(
            "markExtensionRuntimeReady profile=\(profileId.uuidString) loadedContexts=\(extensionContexts(for: profileId).count) allEnabledLoaded=\(readiness.isProfileReady)"
        )
    }

    func extensionRuntimeReadinessContext(
        for profileId: UUID
    ) -> ExtensionRuntimeReadinessContext {
        profileRuntimeStateOwner.readinessContext(for: profileId)
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
        profileRuntimeStateOwner.countLoadedContexts()
    }

    func touchLiveExtensionContext(extensionId: String, profileId: UUID) {
        extensionRuntimeResidencyState.touch(
            extensionId: extensionId,
            profileId: profileId
        )
    }

    func enforceBoundedLiveExtensionContexts(
        keepingProfileId: UUID,
        keepingExtensionId: String
    ) {
        let evictionCandidates =
            extensionRuntimeResidencyState.touchAndEvictionCandidates(
                loadedContextCount: countLoadedExtensionContexts(),
                limit: Self.maxLiveExtensionContexts,
                keepingExtensionId: keepingExtensionId,
                keepingProfileId: keepingProfileId
            )

        for evictionCandidate in evictionCandidates {
            unloadExtensionContextIfLoaded(
                extensionId: evictionCandidate.extensionId,
                profileId: evictionCandidate.profileId
            )
        }
    }

    func unloadExtensionContextsForInactiveProfiles(keepingProfileId: UUID) {
        for identity in profileRuntimeOwner.inactiveLoadedContextIdentities(
            keepingProfileId: keepingProfileId
        ) {
            unloadExtensionContextIfLoaded(
                extensionId: identity.extensionId,
                profileId: identity.profileId
            )
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
        backgroundRuntimeStateOwner.cancelAndRemoveRuntime(for: wakeKey)
        extensionRuntimeResidencyState.remove(
            extensionId: extensionId,
            profileId: profileId
        )

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

    @discardableResult
    func ensureExtensionLoaded(
        extensionId: String,
        profileId: UUID
    ) async throws -> WKWebExtensionContext? {
        guard isExtensionSupportAvailable else { return nil }
        guard extensionsModuleEnabledForRuntimeBoundary() else {
            extensionRuntimeTrace(
                "ensureExtensionLoaded skip extensionId=\(extensionId) profileId=\(profileId.uuidString) because=extensionsModuleDisabled"
            )
            return nil
        }

        _ = ensureExtensionController(for: profileId)

        if let context = getExtensionContext(for: extensionId, profileId: profileId),
           context.isLoaded {
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

    func profileHasLoadedContentScriptContexts(profileId: UUID) -> Bool {
        initialDocumentRuntimePreparationOwner
            .profileHasLoadedContentScriptContexts(profileId: profileId)
    }

    func profileNeedsContentScriptContextLoad(profileId: UUID) -> Bool {
        initialDocumentRuntimePreparationOwner
            .profileNeedsContentScriptContextLoad(profileId: profileId)
    }

    func profileNeedsInitialDocumentExtensionContextLoad(profileId: UUID) -> Bool {
        initialDocumentRuntimePreparationOwner
            .profileNeedsInitialDocumentExtensionContextLoad(profileId: profileId)
    }

    func ensureContentScriptContextsLoaded(for profileId: UUID) async {
        await initialDocumentRuntimePreparationOwner
            .ensureContentScriptContextsLoaded(for: profileId)
    }

    func ensureInitialDocumentExtensionContextsLoaded(for profileId: UUID) async {
        await initialDocumentRuntimePreparationOwner
            .ensureInitialDocumentExtensionContextsLoaded(for: profileId)
    }

    func cancelInitialDocumentNativeMessagingWarmupTasks() {
        loadedInitialDocumentRuntimePreparationOwner?
            .cancelInitialDocumentNativeMessagingWarmupTasks()
    }

    func logExtensionLoadFailure(
        _ error: Error,
        extensionId: String,
        profileId: UUID,
        operation: String
    ) {
        Self.logger.error(
            "Failed to \(operation, privacy: .public) for extension \(extensionId, privacy: .public) profile \(profileId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )
    }

    func logBackgroundWakeFailure(
        _ error: Error,
        extensionContext: WKWebExtensionContext,
        reason: ExtensionBackgroundWakeReason,
        operation: String
    ) {
        let extensionId = extensionID(for: extensionContext) ?? "(unknown)"
        let profileId = profileId(for: extensionContext)?.uuidString ?? "(unknown)"
        Self.logger.error(
            "Failed to \(operation, privacy: .public) for extension \(extensionId, privacy: .public) profile \(profileId, privacy: .public) reason \(reason.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )
    }

    func profileNeedsInitialDocumentNativeMessagingWarmup(profileId: UUID) -> Bool {
        initialDocumentRuntimePreparationOwner
            .profileNeedsInitialDocumentNativeMessagingWarmup(profileId: profileId)
    }

    @discardableResult
    func scheduleDeferredTabNotificationAfterContextLoad(
        _ tab: Tab,
        profileId: UUID,
        reason: String = #function
    ) -> Task<Void, Never> {
        initialDocumentRuntimePreparationOwner
            .scheduleDeferredTabNotificationAfterContextLoad(
                tab,
                profileId: profileId,
                extensionLoadGeneration: extensionLoadGeneration,
                reason: reason
            )
    }

    func deferredTabNotificationTask(for tabId: UUID) -> Task<Void, Never>? {
        initialDocumentRuntimePreparationOwner.deferredTabNotificationTask(for: tabId)
    }

    nonisolated static func detachedMainActorRuntimeTask(
        _ operation: @escaping @MainActor @Sendable () async -> Void
    ) -> Task<Void, Never> {
        Task.detached {
            await operation()
        }
    }

    func reconcileTabAfterContentScriptContextsLoaded(
        _ tab: Tab,
        reason: String = #function
    ) {
        guard tab.isEphemeral == false else { return }
        if tab.extensionPageRuntimeOwner.hasOpenNotificationForCurrentDocumentWithLoadedContexts(
            generation: tabOpenNotificationGeneration
        ) {
            return
        }

        if tab.extensionPageRuntimeOwner.hasCommittedDocumentBinding(),
           tabNeedsExtensionContentScriptRebind(tab) {
            ensureExtensionControllerAttachedForTab(tab, reason: reason)
            return
        }

        tab.extensionPageRuntimeOwner.clearOpenNotificationGeneration()
        registerTabWithExtensionRuntime(tab, reason: reason)
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

    func tabMatchesExtensionContext(
        _ tab: Tab,
        extensionContext: WKWebExtensionContext
    ) -> Bool {
        guard tab.isEphemeral == false else { return false }
        guard let contextProfileId = profileId(for: extensionContext),
              let tabProfileId = resolvedProfileId(for: tab)
        else {
            return false
        }
        return contextProfileId == tabProfileId
    }

    func resolvedLiveWebView(for tab: Tab) -> WKWebView? {
        let windowId = runtime.windowStateContainingTab(tab)?.id ?? tab.primaryWindowId
        if let windowId,
           let webView = runtime.windowOwnedWebView(tab, windowId) {
            return webView
        }

        return ownedUntrackedCurrentWebView(for: tab)
    }

    func ownedUntrackedCurrentWebView(for tab: Tab) -> WKWebView? {
        guard tab.primaryWindowId == nil else { return nil }
        guard let webView = tab.currentWebView else { return nil }
        guard (webView as? FocusableWKWebView)?.owningTab === tab else { return nil }
        return webView
    }

    @discardableResult
    func attachExtensionControllerIfNeeded(
        to webView: WKWebView,
        for tab: Tab
    ) -> Bool {
        guard tab.isEphemeral == false else { return false }
        guard let profileId = resolvedProfileId(for: tab) else { return false }

        let expectedController: WKWebExtensionController
        if let existing = extensionControllersByProfile[profileId] {
            expectedController = existing
        } else if hasEnabledInstalledExtensions
            || extensionRuntimeAllowsWithoutEnabledExtensions {
            expectedController = ensureExtensionController(for: profileId)
        } else {
            return false
        }

        if let existingController = webView.configuration.webExtensionController {
            if existingController === expectedController {
                installPermissionsOriginsCompatibilityPreludes(
                    into: webView.configuration.userContentController,
                    profileId: profileId
                )
                return true
            }
            return false
        }

        guard canLateBindExtensionController(to: webView) else { return false }

        webView.configuration.webExtensionController = expectedController
        webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        installPermissionsOriginsCompatibilityPreludes(
            into: webView.configuration.userContentController,
            profileId: profileId
        )
        return true
    }

    func extensionWebView(
        for tab: Tab,
        extensionContext: WKWebExtensionContext
    ) -> WKWebView? {
        guard tabMatchesExtensionContext(tab, extensionContext: extensionContext),
              let webView = resolvedLiveWebView(for: tab)
        else {
            SafariExtensionAutofillFillDiagnostics.recordFrameResolution(
                resolved: false,
                extensionId: extensionID(for: extensionContext),
                reason: "extensionWebViewMissingLiveTarget"
            )
            return nil
        }

        guard attachExtensionControllerIfNeeded(to: webView, for: tab),
              let profileId = resolvedProfileId(for: tab),
              let expectedController = extensionControllersByProfile[profileId],
              webView.configuration.webExtensionController === expectedController
        else {
            SafariExtensionAutofillFillDiagnostics.recordFrameResolution(
                resolved: false,
                extensionId: extensionID(for: extensionContext),
                reason: "extensionWebViewControllerMismatch"
            )
            return nil
        }

        SafariExtensionAutofillFillDiagnostics.recordFrameResolution(
            resolved: true,
            extensionId: extensionID(for: extensionContext),
            reason: "extensionWebViewReady"
        )
        return webView
    }

    func ensureExtensionControllerAttachedForTab(
        _ tab: Tab,
        reason: String = #function,
        allowWhenExtensionsNotLoaded: Bool = false
    ) {
        guard tab.isEphemeral == false else { return }
        guard extensionsLoaded || allowWhenExtensionsNotLoaded else { return }
        guard resolvedProfileId(for: tab) != nil else { return }

        var needsRebuild = false
        for webView in liveWebViews(for: tab) {
            let attached = attachExtensionControllerIfNeeded(to: webView, for: tab)
            extensionRuntimeTrace(
                "ensureExtensionControllerAttachedForTab webView=\(extensionRuntimeWebViewDescription(webView)) attached=\(attached) \(extensionRuntimeTabDescription(tab))"
            )
            if attached == false,
               webViewNeedsExtensionRuntimeRebuild(webView, for: tab) {
                needsRebuild = true
                break
            }
        }

        if needsRebuild,
           runtime.browserRuntimeAvailable() {
            extensionRuntimeTrace(
                "ensureExtensionControllerAttachedForTab rebuild reason=\(reason) controllerMismatch=true contentScriptRebind=\(tabNeedsExtensionContentScriptRebind(tab)) \(extensionRuntimeTabDescription(tab))"
            )
            SafariExtensionPermissionLifecycleDiagnostics.logReloadRebuild(
                SafariExtensionReloadRebuildSnapshot(
                    triggerReason: reason,
                    profileBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(
                        resolvedProfileId(for: tab)
                    ),
                    tabBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(tab.id),
                    host: SafariExtensionPermissionLifecycleDiagnostics.host(from: tab.url),
                    userActionCaused: false,
                    action: .destructiveRebuild
                )
            )
            tab.extensionPageRuntimeOwner.resetDocumentBindingForContentScriptRebind()
            runtime.rebuildLiveWebViews(tab)
            // WebKit only injects manifest content scripts when the controller is on the
            // configuration before navigation; allow `notifyTabOpenedIfNeeded` to run again.
            tab.extensionPageRuntimeOwner.clearOpenNotificationGeneration()
        }
    }

    func webViewNeedsExtensionRuntimeRebuild(
        _ webView: WKWebView,
        for tab: Tab
    ) -> Bool {
        webViewNeedsExtensionRuntimeRebuild(
            currentController: webView.configuration.webExtensionController,
            currentURL: webView.url,
            for: tab
        )
    }

    func webViewNeedsExtensionRuntimeRebuild(
        currentController: WKWebExtensionController?,
        currentURL: URL?,
        for tab: Tab
    ) -> Bool {
        guard let profileId = resolvedProfileId(for: tab) else {
            return ExtensionRuntimeWebViewBindingPolicy.needsRuntimeRebuild(
                currentController: currentController,
                expectedController: nil,
                currentURL: currentURL
            )
        }

        if let currentController,
           let currentProfileId = self.profileId(for: currentController),
           currentProfileId != profileId {
            return true
        }

        let expectedController =
            extensionControllersByProfile[profileId]
            ?? extensionController(for: tab)
        return ExtensionRuntimeWebViewBindingPolicy.needsRuntimeRebuild(
            currentController: currentController,
            expectedController: expectedController,
            currentURL: currentURL
        )
    }

    func updateWebViewsForProfile(
        _ profileId: UUID,
        allowWhenExtensionsNotLoaded: Bool = false
    ) {
        guard extensionControllersByProfile[profileId] != nil else { return }
        guard runtime.browserRuntimeAvailable() else { return }

        for tab in allKnownTabs() {
            guard resolvedProfileId(for: tab) == profileId else { continue }
            guard tab.isEphemeral == false else { continue }
            ensureExtensionControllerAttachedForTab(
                tab,
                reason: "updateWebViewsForProfile",
                allowWhenExtensionsNotLoaded: allowWhenExtensionsNotLoaded
            )
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
        ExtensionRuntimeResidencyState.scopedKey(
            extensionId: extensionId,
            profileId: profileId
        )
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

        let hasOriginalAppex =
            SafariAppExtensionResources.installedAppexBundleURL(
                sourceKind: installed.sourceKind,
                sourceBundlePath: installed.sourceBundlePath
            ) != nil
        if installed.sourceKind == .safariAppExtension,
           hasOriginalAppex == false {
            return .originalAppExtensionBundleMissing
        }
        let resourcesRoot = try? extensionResourcesRoot(
            sourceKind: installed.sourceKind,
            packagePath: installed.packagePath,
            sourceBundlePath: installed.sourceBundlePath
        )
        let resourcesExist = resourcesRoot.map {
            FileManager.default.fileExists(atPath: $0.path)
        } ?? false
        if resourcesExist == false {
            return .sourceResourcesMissing
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

        let snapshot = profileRuntimeStateOwner.extensionSnapshot(
            extensionId: extensionId,
            profileId: profileId
        )
        let context = snapshot.context
        if let context,
           let currentProfileId,
           currentProfileId != profileId,
           self.profileId(for: context) != profileId {
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
        let snapshot = profileRuntimeStateOwner.extensionSnapshot(
            extensionId: extensionId,
            profileId: profileId
        )
        let context = snapshot.context
        let hasOriginalAppex =
            SafariAppExtensionResources.installedAppexBundleURL(
                sourceKind: installedExtension.sourceKind,
                sourceBundlePath: installedExtension.sourceBundlePath
            ) != nil
        let resourcesRoot = try? extensionResourcesRoot(
            sourceKind: installedExtension.sourceKind,
            packagePath: installedExtension.packagePath,
            sourceBundlePath: installedExtension.sourceBundlePath
        )
        let resourcesExist = resourcesRoot.map {
            FileManager.default.fileExists(atPath: $0.path)
        } ?? false

        var lines = [
            "failureBucket=\(failureBucket.rawValue)",
            "extensionId=\(extensionId)",
            "displayName=\(installedExtension.name)",
            "profileId=\(profileId.uuidString)",
            "sourceKind=\(installedExtension.sourceKind.rawValue)",
            "hasOriginalAppex=\(hasOriginalAppex)",
            "sourceResourcesPresent=\(resourcesExist)",
            "controllerExists=\(snapshot.controllerExists)",
            "contextExists=\(snapshot.contextExists)",
            "contextLoaded=\(snapshot.contextLoaded)",
            "runtimeState=\(runtimeState.rawValue)",
            "missingEnabledExtensionIDs=\(snapshot.missingEnabledExtensionIDs.joined(separator: ","))",
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
