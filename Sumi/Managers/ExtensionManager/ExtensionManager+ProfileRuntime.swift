import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    var extensionController: WKWebExtensionController? {
        guard let currentProfileId else { return nil }
        return profileRuntimeState.controller(for: currentProfileId)
    }

    var extensionContexts: [String: WKWebExtensionContext] {
        guard let currentProfileId else { return [:] }
        return profileRuntimeState.contexts(for: currentProfileId)
    }

    func extensionContexts(for profileId: UUID) -> [String: WKWebExtensionContext] {
        profileRuntimeState.contexts(for: profileId)
    }

    func setExtensionContext(
        _ context: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID
    ) {
        let generation = profileRuntimeState.setContext(
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
        profileRuntimeState.contextBindingGeneration(for: profileId)
    }

    func bumpExtensionContextBindingGeneration(
        for profileId: UUID,
        reason: String
    ) {
        let next = profileRuntimeState.bumpContextBindingGeneration(for: profileId)
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
        guard let removed = profileRuntimeState.removeContext(
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
        profileRuntimeState.allLoadedExtensionIDs()
    }

    func profileId(for extensionContext: WKWebExtensionContext) -> UUID? {
        profileRuntimeState.profileId(for: extensionContext)
    }

    func profileId(for controller: WKWebExtensionController) -> UUID? {
        profileRuntimeState.profileId(for: controller)
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

    func rememberPrivateExtensionRuntimeProfileIfNeeded(_ profile: Profile) {
        profileWebsiteDataStoreCache.rememberPrivateRuntimeProfileIfNeeded(profile)
    }

    func isPrivateExtensionRuntimeProfile(_ profileId: UUID?) -> Bool {
        profileWebsiteDataStoreCache.isPrivateRuntimeProfile(profileId)
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

    func extensionsModuleEnabledForRuntimeBoundary() -> Bool {
        guard let browserManager else { return true }
        return browserManager.extensionsModule.isEnabled
    }

    @discardableResult
    func ensureExtensionController(for profileId: UUID) -> WKWebExtensionController {
        if let existing = profileRuntimeState.controller(for: profileId) {
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
        profileRuntimeState.setController(controller, for: profileId)
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
        let resolvedProfileId =
            profileId ?? currentProfileId ?? browserManager?.currentProfile?.id
        guard let resolvedProfileId else { return nil }
        return extensionContexts(for: resolvedProfileId)[extensionId]
    }

    func missingEnabledExtensionIDs(for profileId: UUID) -> [String] {
        extensionRuntimeReadinessContext(for: profileId).missingEnabledExtensionIDs
    }

    func isProfileExtensionRuntimeReady(for profileId: UUID) -> Bool {
        extensionRuntimeReadinessContext(for: profileId).isProfileReady
    }

    func isExtensionRuntimeReady(
        extensionId: String,
        profileId: UUID
    ) -> Bool {
        extensionRuntimeReadinessContext(for: profileId)
            .isExtensionReady(extensionID: extensionId)
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
        ExtensionRuntimeReadinessContext(
            hasEnabledExtensionDemand: hasEnabledInstalledExtensions,
            enabledExtensionIDs: Set(enabledPersistedExtensionEntities().map(\.id)),
            loadedExtensionStatesByID: extensionContexts(for: profileId)
                .mapValues(\.isLoaded),
            controllerExists: extensionControllersByProfile[profileId] != nil,
            globalRuntimeReady: runtimeState == .ready
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
        profileRuntimeState.countLoadedExtensionContexts()
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

    func profileHasLoadedContentScriptContexts(profileId: UUID) -> Bool {
        guard extensionsModuleEnabledForRuntimeBoundary() else { return true }

        let contentScriptEntities = enabledPersistedExtensionEntities().filter {
            $0.isEnabled && $0.hasContentScripts
        }
        guard contentScriptEntities.isEmpty == false else { return true }

        return contentScriptEntities.allSatisfy { entity in
            guard let context = getExtensionContext(for: entity.id, profileId: profileId) else {
                return false
            }
            return context.isLoaded
        }
    }

    func profileNeedsContentScriptContextLoad(profileId: UUID) -> Bool {
        profileHasLoadedContentScriptContexts(profileId: profileId) == false
    }

    func profileNeedsInitialDocumentExtensionContextLoad(profileId: UUID) -> Bool {
        return profileNeedsContentScriptContextLoad(profileId: profileId)
            || profileNeedsInitialDocumentNativeMessagingWarmup(profileId: profileId)
    }

    func ensureContentScriptContextsLoaded(for profileId: UUID) async {
        guard extensionsModuleEnabledForRuntimeBoundary() else { return }
        guard profileNeedsContentScriptContextLoad(profileId: profileId) else { return }

        if let existingTask = contentScriptContextLoadTasksByProfile[profileId] {
            await existingTask.value
            return
        }

        let task = Self.detachedMainActorRuntimeTask { [weak self] in
            guard let self else { return }
            defer { self.contentScriptContextLoadTasksByProfile.removeValue(forKey: profileId) }
            guard Task.isCancelled == false else { return }

            for entity in self.enabledPersistedExtensionEntities()
                where entity.isEnabled && entity.hasContentScripts
            {
                guard Task.isCancelled == false else { return }
                do {
                    _ = try await self.ensureExtensionLoaded(
                        extensionId: entity.id,
                        profileId: profileId
                    )
                } catch {
                    self.logExtensionLoadFailure(
                        error,
                        extensionId: entity.id,
                        profileId: profileId,
                        operation: "preload content-script context"
                    )
                }
            }
        }
        contentScriptContextLoadTasksByProfile[profileId] = task
        await task.value
    }

    /// Prepares extension contexts needed by the first normal-tab document.
    ///
    /// Manifest content scripts are still loaded lazily, but extensions that combine
    /// `content_scripts`, background content, and the required `nativeMessaging`
    /// permission need their background page/service worker ready before the first
    /// content-script message. Chrome/Firefox route native messaging through that
    /// background context, and WebKit exposes `loadBackgroundContent` for the same
    /// app-owned preflight without opening the action popup.
    func ensureInitialDocumentExtensionContextsLoaded(for profileId: UUID) async {
        guard extensionsModuleEnabledForRuntimeBoundary() else { return }
        await ensureContentScriptContextsLoaded(for: profileId)
        await ensureInitialDocumentNativeMessagingBackgroundsLoaded(for: profileId)
    }

    private func ensureInitialDocumentNativeMessagingBackgroundsLoaded(
        for profileId: UUID
    ) async {
        guard extensionsModuleEnabledForRuntimeBoundary() else { return }
        guard profileNeedsInitialDocumentNativeMessagingWarmup(profileId: profileId)
        else { return }

        if let existingTask =
            initialDocumentNativeMessagingWarmupTasksByProfile[profileId]
        {
            await existingTask.value
            return
        }

        let task = Self.detachedMainActorRuntimeTask { [weak self] in
            guard let self else { return }
            defer {
                self.initialDocumentNativeMessagingWarmupTasksByProfile
                    .removeValue(forKey: profileId)
            }
            guard Task.isCancelled == false else { return }

            for entity in self.initialDocumentNativeMessagingWarmupEntities(
                profileId: profileId
            ) {
                guard Task.isCancelled == false else { return }
                do {
                    guard let extensionContext = try await self.ensureExtensionLoaded(
                        extensionId: entity.id,
                        profileId: profileId
                    ) else {
                        continue
                    }
                    _ = try await self.ensureBackgroundAvailableIfRequired(
                        for: extensionContext.webExtension,
                        context: extensionContext,
                        reason: .nativeMessaging
                    )
                } catch {
                    self.logExtensionLoadFailure(
                        error,
                        extensionId: entity.id,
                        profileId: profileId,
                        operation: "warm initial-document native messaging runtime"
                    )
                }
            }
        }
        initialDocumentNativeMessagingWarmupTasksByProfile[profileId] = task
        await task.value
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
        initialDocumentNativeMessagingWarmupEntities(profileId: profileId).contains {
            backgroundRuntimeState(for: $0.id, profileId: profileId) != .loaded
        }
    }

    private func initialDocumentNativeMessagingWarmupEntities(
        profileId: UUID
    ) -> [ExtensionEntity] {
        guard extensionsModuleEnabledForRuntimeBoundary() else { return [] }

        return enabledPersistedExtensionEntities().filter { entity in
            entity.isEnabled
                && entity.hasContentScripts
                && entity.hasBackground
                && extensionDeclaresNativeMessaging(entity)
                && backgroundRuntimeState(for: entity.id, profileId: profileId) != .loaded
        }
    }

    private func extensionDeclaresNativeMessaging(_ entity: ExtensionEntity) -> Bool {
        let manifest =
            loadedExtensionManifests[entity.id]
            ?? installedExtensions.first(where: { $0.id == entity.id })?.manifest
            ?? InstalledExtensionRecord(from: entity)?.manifest
            ?? [:]
        let permissions = Self.manifestStringArray(from: manifest["permissions"])
        return permissions.contains("nativeMessaging")
    }

    private nonisolated static func manifestStringArray(from value: Any?) -> [String] {
        value as? [String] ?? []
    }

    @discardableResult
    func scheduleDeferredTabNotificationAfterContextLoad(
        _ tab: Tab,
        profileId: UUID,
        reason: String = #function
    ) -> Task<Void, Never> {
        let tabId = tab.id
        let scheduledGeneration = extensionLoadGeneration
        let token = UUID()
        let task = Self.detachedMainActorRuntimeTask { [weak self] in
            guard let self else { return }
            defer {
                if self.deferredTabNotificationTasksByTabID[tabId]?.token == token {
                    self.deferredTabNotificationTasksByTabID.removeValue(forKey: tabId)
                }
            }

            guard Task.isCancelled == false,
                  self.extensionLoadGeneration == scheduledGeneration
            else { return }

            await self.ensureInitialDocumentExtensionContextsLoaded(for: profileId)

            guard Task.isCancelled == false,
                  self.extensionLoadGeneration == scheduledGeneration
            else { return }

            guard let resolvedTab = self.browserManager?.tabManager.tab(for: tabId) else { return }
            self.reconcileTabAfterContentScriptContextsLoaded(
                resolvedTab,
                reason: "\(reason).afterContextLoad"
            )
        }
        deferredTabNotificationTasksByTabID[tabId]?.task.cancel()
        deferredTabNotificationTasksByTabID[tabId] = (token, task)
        return task
    }

    func deferredTabNotificationTask(for tabId: UUID) -> Task<Void, Never>? {
        deferredTabNotificationTasksByTabID[tabId]?.task
    }

    private nonisolated static func detachedMainActorRuntimeTask(
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
        if tab.lastExtensionOpenNotificationGeneration == tabOpenNotificationGeneration,
           tab.extensionRuntimeOpenNotifiedDocumentSequence == tab.extensionRuntimeDocumentSequence,
           tab.extensionRuntimeOpenNotifiedWithLoadedContexts == true
        {
            return
        }

        if tab.extensionRuntimeDocumentSequence > 0,
           tabNeedsExtensionContentScriptRebind(tab)
        {
            ensureExtensionControllerAttachedForTab(tab, reason: reason)
            return
        }

        tab.lastExtensionOpenNotificationGeneration = 0
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
        if let webView = tab.assignedWebView ?? tab.existingWebView {
            return webView
        }

        if let browserManager,
           let windowState = browserManager.windowState(containing: tab)
           ?? tab.primaryWindowId.flatMap({ browserManager.windowRegistry?.windows[$0] })
        {
            if let webView = browserManager.getWebView(
                for: tab.id,
                in: windowState.id
            ) {
                return webView
            }
        }

        return nil
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
            || extensionRuntimeAllowsWithoutEnabledExtensions
        {
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
               webViewNeedsExtensionRuntimeRebuild(webView, for: tab)
            {
                needsRebuild = true
                break
            }
        }

        if needsRebuild,
           let coordinator = browserManager?.webViewCoordinator
        {
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
            tab.resetExtensionRuntimeDocumentBindingForContentScriptRebind()
            coordinator.rebuildLiveWebViews(for: tab)
            // WebKit only injects manifest content scripts when the controller is on the
            // configuration before navigation; allow `notifyTabOpenedIfNeeded` to run again.
            tab.lastExtensionOpenNotificationGeneration = 0
        }
    }

    func webViewNeedsExtensionRuntimeRebuild(
        _ webView: WKWebView,
        for tab: Tab
    ) -> Bool {
        if webView.configuration.webExtensionController == nil,
           canLateBindExtensionController(to: webView) == false
        {
            return true
        }

        guard let profileId = resolvedProfileId(for: tab),
              let expectedController = extensionControllersByProfile[profileId],
              let existingController = webView.configuration.webExtensionController,
              existingController !== expectedController
        else {
            return false
        }

        return true
    }

    func updateWebViewsForProfile(
        _ profileId: UUID,
        allowWhenExtensionsNotLoaded: Bool = false
    ) {
        guard extensionControllersByProfile[profileId] != nil else { return }
        guard browserManager != nil else { return }

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
           hasOriginalAppex == false
        {
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
