import Foundation
import SwiftData
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager
        browserBridgeContext = browserManager

        if browserManager.windowRegistry?.activeWindow == nil,
           let currentProfile = browserManager.currentProfile
        {
            switchProfile(profileId: currentProfile.id)
        }

        if let controller = extensionController {
            extensionRuntimeTrace(
                "attach browserManager controller=\(extensionRuntimeControllerDescription(controller)) windows=\(browserManager.windowRegistry?.allWindows.count ?? 0) tabs=\(browserManager.tabManager.allTabs().count)"
            )
            if let profileId = currentProfileId {
                updateWebViewsForProfile(profileId)
            }
            registerExistingWindowStateIfAttached()
        }
    }

    func notifyWindowOpened(_ windowState: BrowserWindowState) {
        guard let profileId = resolvedProfileId(for: windowState),
              let controller = extensionControllersByProfile[profileId],
              let adapter = windowAdapter(for: windowState.id) else {
            return
        }
        controller.didOpenWindow(adapter)
    }

    func notifyWindowClosed(_ windowId: UUID) {
        windowAdapters.removeValue(forKey: windowId)
    }

    func notifyAuxiliaryWindowOpened(_ session: AuxiliaryWindowSession) {
        guard let adapter = session.miniWindowAdapter,
              let extensionContext = auxiliaryOwnerExtensionContext(for: session)
        else {
            return
        }

        extensionContext.didOpenWindow(adapter)
        if session.shouldActivateApp {
            browserBridgeContext?.recordAuxiliaryWindowSessionFocus(session.id)
            extensionContext.didFocusWindow(adapter)
        }
    }

    func notifyAuxiliaryWindowFocused(_ session: AuxiliaryWindowSession) {
        guard let adapter = session.miniWindowAdapter,
              let extensionContext = auxiliaryOwnerExtensionContext(for: session)
        else {
            return
        }

        guard extensionContext.openWindows.contains(where: { window in
            (window as? ExtensionMiniWindowAdapter)?.sessionId == session.id
        }) else {
            return
        }
        if (extensionContext.focusedWindow as? ExtensionMiniWindowAdapter)?.sessionId == session.id {
            return
        }

        extensionContext.didFocusWindow(adapter)
    }

    func notifyAuxiliaryWindowClosed(_ session: AuxiliaryWindowSession) {
        guard let adapter = session.miniWindowAdapter,
              let extensionContext = auxiliaryOwnerExtensionContext(for: session)
        else {
            miniWindowAdapters.removeValue(forKey: session.id)
            return
        }

        extensionContext.didCloseWindow(adapter)
        if let activeWindow = browserBridgeContext?.activeExtensionWindowState,
           let profileId = resolvedProfileId(for: session.tab),
           windowMatchesProfile(activeWindow, profileId: profileId),
           let focusedAdapter = windowAdapter(for: activeWindow.id)
        {
            extensionContext.didFocusWindow(focusedAdapter)
        } else {
            extensionContext.didFocusWindow(nil)
        }

        miniWindowAdapters.removeValue(forKey: session.id)
    }

    private func auxiliaryOwnerExtensionContext(
        for session: AuxiliaryWindowSession
    ) -> WKWebExtensionContext? {
        if let context = session.tab.webExtensionContextOverride {
            return context
        }

        guard let ownerExtensionID = session.ownerExtensionID,
              let profileId = resolvedProfileId(for: session.tab)
        else {
            return nil
        }

        return extensionContexts(for: profileId)[ownerExtensionID]
    }

    func notifyWindowFocused(_ windowState: BrowserWindowState) {
        if let keyWindow = NSApp.keyWindow,
           let auxiliarySession = browserBridgeContext?.auxiliaryWindowSession(for: keyWindow)
        {
            browserBridgeContext?.focusAuxiliaryWindowSession(auxiliarySession.id)
            return
        }

        if windowState.isIncognito, let profile = windowState.ephemeralProfile {
            switchProfile(profileId: profile.id)
        } else if let profileId = windowState.currentProfileId,
                  let profile = browserManager?.profileManager.profiles.first(where: { $0.id == profileId })
        {
            switchProfile(profileId: profile.id)
        } else if let currentProfile = browserManager?.currentProfile {
            switchProfile(profileId: currentProfile.id)
        }

        guard let profileId = resolvedProfileId(for: windowState),
              let controller = extensionControllersByProfile[profileId],
              let adapter = windowAdapter(for: windowState.id) else {
            return
        }
        controller.didFocusWindow(adapter)
    }

    func switchProfile(_ profile: Profile) {
        switchProfile(profileId: profile.id)
    }

    func switchProfile(profileId: UUID) {
        let signpostState = PerformanceTrace.beginInterval("ExtensionManager.switchProfile")
        defer {
            PerformanceTrace.endInterval("ExtensionManager.switchProfile", signpostState)
        }

        let runtimeInitialized = profileRuntimeOwner.activateProfile(
            profileId,
            hasExtensionDemand: hasEnabledInstalledExtensions,
            runtimeIsReadyOrLoading: runtimeState == .ready || runtimeState == .loading
        )
        clearActionPopupAnchors(notMatching: profileId)
        reloadPinnedToolbarExtensionsForCurrentProfile()

        guard isExtensionSupportAvailable else { return }

        guard runtimeInitialized else { return }

        let controller = ensureExtensionController(for: profileId)
        browserConfiguration.webViewConfiguration.webExtensionController = controller
        unloadExtensionContextsForInactiveProfiles(keepingProfileId: profileId)

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.updateWebViewsForProfile(profileId)
            self.refreshActionSurfaceStateForCurrentProfile()
        }
    }

    @discardableResult
    func notifyTabOpened(_ tab: Tab) -> Bool {
        func deferOpen(_ reason: String) -> Bool {
            #if DEBUG
                testHooks.didDeferOpenTab?(tab.id, reason)
            #endif
            return false
        }

        guard let controller = extensionController(for: tab),
              let adapter = stableAdapter(for: tab)
        else {
            SafariExtensionAutofillFillDiagnostics.recordContentScriptInjection(
                injected: false,
                extensionId: nil,
                reason: "notifyTabOpenedMissingAdapterOrController",
                pageURL: tab.url
            )
            return deferOpen("missingAdapterOrController")
        }

        guard let profileId = resolvedProfileId(for: tab) else {
            SafariExtensionAutofillFillDiagnostics.recordContentScriptInjection(
                injected: false,
                extensionId: nil,
                reason: "notifyTabOpenedMissingProfile",
                pageURL: tab.url
            )
            return deferOpen("missingProfile")
        }

        let contextsReady = profileNeedsInitialDocumentExtensionContextLoad(
            profileId: profileId
        ) == false
        guard contextsReady else {
            SafariExtensionAutofillFillDiagnostics.recordContentScriptInjection(
                injected: false,
                extensionId: nil,
                reason: "notifyTabOpenedInitialDocumentContextsNotLoaded",
                pageURL: tab.url
            )
            scheduleDeferredTabNotificationAfterContextLoad(
                tab,
                profileId: profileId,
                reason: "notifyTabOpened"
            )
            return deferOpen("initialDocumentContextsNotLoaded")
        }

        guard tabHasUsableWebViewForExtensionOpenNotification(
            tab,
            controller: controller,
            profileId: profileId,
            deferOpen: deferOpen
        ) else {
            SafariExtensionAutofillFillDiagnostics.recordContentScriptInjection(
                injected: false,
                extensionId: nil,
                reason: "notifyTabOpenedMissingUsableWebView",
                pageURL: tab.url
            )
            extensionRuntimeTrace(
                "didOpenTab deferred because=missingUsableWebView generation=\(extensionLoadGeneration) notifyGeneration=\(tabOpenNotificationGeneration) controller=\(extensionRuntimeControllerDescription(controller)) \(extensionRuntimeTabDescription(tab))"
            )
            return false
        }

        extensionRuntimeTrace(
            "didOpenTab start generation=\(extensionLoadGeneration) notifyGeneration=\(tabOpenNotificationGeneration) controller=\(extensionRuntimeControllerDescription(controller)) \(extensionRuntimeTabDescription(tab)) adapter=\(extensionRuntimeObjectDescription(adapter))"
        )
        tab.extensionRuntimeOpenNotifiedDocumentSequence = tab.extensionRuntimeDocumentSequence
        tab.extensionRuntimeOpenNotifiedExtensionContextBindingGeneration =
            extensionContextBindingGeneration(for: profileId)
        tab.extensionRuntimeOpenNotifiedWithLoadedContexts = true
        controller.didOpenTab(adapter)
        #if DEBUG
            testHooks.didOpenTab?(tab.id)
        #endif
        SafariExtensionAutofillFillDiagnostics.recordContentScriptInjection(
            injected: true,
            extensionId: nil,
            reason: "didOpenTab",
            pageURL: tab.url
        )
        extensionRuntimeTrace(
            "didOpenTab complete generation=\(extensionLoadGeneration) notifyGeneration=\(tabOpenNotificationGeneration) \(extensionRuntimeTabDescription(tab))"
        )
        return true
    }

    private func tabHasUsableWebViewForExtensionOpenNotification(
        _ tab: Tab,
        controller: WKWebExtensionController,
        profileId: UUID,
        deferOpen: (String) -> Bool
    ) -> Bool {
        guard let webView = resolvedLiveWebView(for: tab) else {
            extensionRuntimeTrace(
                "didOpenTab deferred because=noLiveWebView profile=\(profileId.uuidString) \(extensionRuntimeTabDescription(tab))"
            )
            _ = deferOpen("noLiveWebView")
            return false
        }

        guard attachExtensionControllerIfNeeded(to: webView, for: tab) else {
            extensionRuntimeTrace(
                "didOpenTab deferred because=controllerAttachFailed webView=\(extensionRuntimeWebViewDescription(webView)) profile=\(profileId.uuidString) \(extensionRuntimeTabDescription(tab))"
            )
            _ = deferOpen("controllerAttachFailed")
            return false
        }

        guard webView.configuration.webExtensionController === controller else {
            extensionRuntimeTrace(
                "didOpenTab deferred because=controllerMismatch webView=\(extensionRuntimeWebViewDescription(webView)) profile=\(profileId.uuidString) \(extensionRuntimeTabDescription(tab))"
            )
            _ = deferOpen("controllerMismatch")
            return false
        }

        return true
    }

    func notifyTabOpenedIfNeeded(_ tab: Tab, reason: String = #function) {
        let generation = tabOpenNotificationGeneration
        tab.prepareExtensionRuntimeGeneration(generation)

        guard extensionsLoaded else {
            extensionRuntimeTrace(
                "notifyTabOpenedIfNeeded skip reason=\(reason) because=extensionsNotLoaded generation=\(extensionLoadGeneration) notifyGeneration=\(tabOpenNotificationGeneration) lastNotified=\(tab.lastExtensionOpenNotificationGeneration) \(extensionRuntimeTabDescription(tab))"
            )
            return
        }

        guard isTabEligibleForExtensionRuntime(tab, generation: generation) else {
            extensionRuntimeTrace(
                "notifyTabOpenedIfNeeded skip reason=\(reason) because=tabNotEligible generation=\(generation) eligibleGeneration=\(tab.extensionRuntimeEligibleGeneration) \(extensionRuntimeTabDescription(tab))"
            )
            return
        }

        guard tab.lastExtensionOpenNotificationGeneration != generation else {
            extensionRuntimeTrace(
                "notifyTabOpenedIfNeeded skip reason=\(reason) because=alreadyNotified generation=\(generation) \(extensionRuntimeTabDescription(tab))"
            )
            return
        }

        extensionRuntimeTrace(
            "notifyTabOpenedIfNeeded proceed reason=\(reason) generation=\(generation) lastNotified=\(tab.lastExtensionOpenNotificationGeneration) \(extensionRuntimeTabDescription(tab))"
        )
        guard notifyTabOpened(tab) else {
            SafariExtensionAutofillFillDiagnostics.recordContentScriptInjection(
                injected: false,
                extensionId: nil,
                reason: "notifyTabOpenedIfNeeded:\(reason)",
                pageURL: tab.url
            )
            extensionRuntimeTrace(
                "notifyTabOpenedIfNeeded aborted reason=\(reason) because=notifyFailed generation=\(generation) \(extensionRuntimeTabDescription(tab))"
            )
            return
        }

        tab.didNotifyOpenToExtensions = true
        tab.lastExtensionOpenNotificationGeneration = generation
        extensionRuntimeTrace(
            "notifyTabOpenedIfNeeded marked reason=\(reason) generation=\(generation) \(extensionRuntimeTabDescription(tab))"
        )
    }

    func notifyTabActivated(newTab: Tab, previous: Tab?) {
        guard isTabEligibleForExtensionRuntime(
            newTab,
            generation: tabOpenNotificationGeneration
        ) else {
            return
        }
        guard let controller = extensionController(for: newTab),
              let newAdapter = stableAdapter(for: newTab) else { return }
        let previousAdapter = previous.flatMap { tab in
            isTabEligibleForExtensionRuntime(tab, generation: tabOpenNotificationGeneration)
                ? stableAdapter(for: tab)
                : nil
        }
        controller.didActivateTab(newAdapter, previousActiveTab: previousAdapter)
        controller.didSelectTabs([newAdapter])
        if let previousAdapter {
            controller.didDeselectTabs([previousAdapter])
        }
    }

    func notifyTabClosed(_ tab: Tab) {
        guard let controller = extensionController(for: tab),
              let adapter = stableAdapter(for: tab) else { return }
        controller.didCloseTab(adapter, windowIsClosing: false)
        tabAdapters.removeValue(forKey: tab.id)
    }

    func notifyTabPropertiesChanged(
        _ tab: Tab,
        properties: WKWebExtension.TabChangedProperties
    ) {
        let generation = tabOpenNotificationGeneration
        tab.prepareExtensionRuntimeGeneration(generation)

        guard isTabEligibleForExtensionRuntime(tab, generation: generation) else {
            extensionRuntimeTrace(
                "notifyTabPropertiesChanged skip because=tabNotEligible requested=\(properties.rawValue) generation=\(generation) eligibleGeneration=\(tab.extensionRuntimeEligibleGeneration) \(extensionRuntimeTabDescription(tab))"
            )
            return
        }

        let coalescedProperties = coalescedTabChangedProperties(
            for: tab,
            requestedProperties: properties
        )
        guard coalescedProperties.isEmpty == false else {
            extensionRuntimeTrace(
                "notifyTabPropertiesChanged skip because=noDiff requested=\(properties.rawValue) \(extensionRuntimeTabDescription(tab))"
            )
            return
        }

        guard let controller = extensionController(for: tab),
              let adapter = stableAdapter(for: tab) else { return }
        controller.didChangeTabProperties(coalescedProperties, for: adapter)
        #if DEBUG
            testHooks.didChangeTabProperties?(tab.id, coalescedProperties)
        #endif
    }

    /// Call immediately after `tabOpenNotificationGeneration` is incremented so WebKit never
    /// observes a window whose `tabs(for:)` can list adapters while `activeTab(for:)` is `nil`
    /// only because tabs have not yet been reconciled to the new generation.
    ///
    /// - Parameter allowWhenExtensionsNotLoaded: Use during `performInstallation` so tabs re-bind
    ///   after `load(extensionContext:)` even before `loadInstalledExtensions` sets `extensionsLoaded`.
    /// Re-binds open tabs and late-assigns the extension controller after a context load
    /// so WebKit can inject content scripts on already-open normal tabs.
    func reconcileOpenTabsAfterExtensionContextLoad(
        reason: String,
        allowWhenExtensionsNotLoaded: Bool = false,
        profileId: UUID? = nil
    ) {
        tabOpenNotificationGeneration &+= 1
        var profileIds = Set(extensionControllersByProfile.keys)
        if let profileId {
            profileIds.insert(profileId)
        }
        if let currentProfileId {
            profileIds.insert(currentProfileId)
        }
        // Attach or rebuild WebViews before `didOpenTab` so WebKit can inject manifest
        // content scripts (including CSS) on already-open normal tabs.
        for resolvedProfileId in profileIds {
            updateWebViewsForProfile(
                resolvedProfileId,
                allowWhenExtensionsNotLoaded: allowWhenExtensionsNotLoaded
            )
        }
        resyncOpenTabsWithExtensionRuntimeAfterGenerationBump(
            reason: reason,
            allowWhenExtensionsNotLoaded: allowWhenExtensionsNotLoaded
        )
        registerExistingWindowStateIfAttached()
    }

    func resyncOpenTabsWithExtensionRuntimeAfterGenerationBump(
        reason: String,
        allowWhenExtensionsNotLoaded: Bool = false
    ) {
        guard extensionsLoaded || allowWhenExtensionsNotLoaded else { return }

        let tabs = allKnownTabs()
        extensionRuntimeTrace(
            "resyncOpenTabsAfterGenerationBump start reason=\(reason) generation=\(tabOpenNotificationGeneration) tabs=\(tabs.count) allowWhenNotLoaded=\(allowWhenExtensionsNotLoaded)"
        )

        for tab in tabs {
            registerTabWithExtensionRuntime(
                tab,
                reason: reason,
                allowWhenExtensionsNotLoaded: allowWhenExtensionsNotLoaded
            )
        }

        if let browserContext = browserBridgeContext,
           let activeWindow = browserContext.activeExtensionWindowState,
           let currentTab = browserContext.currentExtensionTab(in: activeWindow),
           isTabEligibleForCurrentExtensionRuntime(currentTab)
        {
            notifyTabActivated(newTab: currentTab, previous: nil)
        }

        extensionRuntimeTrace(
            "resyncOpenTabsAfterGenerationBump complete reason=\(reason) generation=\(tabOpenNotificationGeneration)"
        )
    }

    func registerExistingWindowStateIfAttached() {
        guard let browserContext = browserBridgeContext else { return }

        let windows = browserContext.allExtensionWindowStates
        extensionRuntimeTrace(
            "registerExistingWindowState start generation=\(extensionLoadGeneration) notifyGeneration=\(tabOpenNotificationGeneration) windows=\(windows.count) controller=\(extensionRuntimeControllerDescription(extensionController))"
        )

        for windowState in windows {
            notifyWindowOpened(windowState)
        }

        if let activeWindow = browserContext.activeExtensionWindowState {
            notifyWindowFocused(activeWindow)
        }

        extensionRuntimeTrace(
            "registerExistingWindowState complete generation=\(extensionLoadGeneration) notifyGeneration=\(tabOpenNotificationGeneration) windows=\(windows.count)"
        )
    }

    func prepareExtensionContextForRuntime(
        _ extensionContext: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID,
        manifest: [String: Any]? = nil
    ) {
        let resolvedManifest =
            manifest
            ?? loadedExtensionManifests[extensionId]
            ?? extensionContext.webExtension.manifest
        installCapabilityOwner.prepareExtensionContextForRuntime(
            extensionContext,
            extensionId: extensionId,
            profileId: profileId,
            manifest: resolvedManifest
        )

        _ = extensionControllersByProfile[profileId]
            ?? ensureExtensionController(for: profileId)
    }

    var hasEnabledInstalledExtensions: Bool {
        installedExtensions.contains { $0.isEnabled }
    }

    @discardableResult
    func requestExtensionRuntime(
        reason: ExtensionRuntimeRequestReason,
        forceReload: Bool = false,
        allowWithoutEnabledExtensions: Bool = false,
        profileId: UUID? = nil
    ) -> WKWebExtensionController? {
        PerformanceTrace.emitEvent("ExtensionManager.lazyRuntimeRequested")

        guard isExtensionSupportAvailable else {
            runtimeState = .unavailable
            extensionsLoaded = true
            return nil
        }

        let hasDemand = hasEnabledInstalledExtensions || allowWithoutEnabledExtensions
        guard hasDemand else {
            extensionsLoaded = true
            return nil
        }

        if allowWithoutEnabledExtensions {
            extensionRuntimeAllowsWithoutEnabledExtensions = true
        }

        let resolvedProfileId = profileRuntimeOwner.resolvedProfileId(
            explicitProfileId: profileId,
            browserManager: browserManager
        )
        let controller: WKWebExtensionController
        if let resolvedProfileId {
            controller = ensureExtensionController(for: resolvedProfileId)
        } else {
            controller = ensureExtensionController(reason: reason)
        }

        if runtimeState == .loading, forceReload == false {
            return controller
        }

        if runtimeState == .ready, forceReload == false {
            if let profileId = resolvedProfileId ?? currentProfileId {
                updateWebViewsForProfile(profileId)
            }
            return controller
        }

        startExtensionRuntimeLoad(
            reason: reason,
            forceReload: forceReload,
            allowWithoutEnabledExtensions: allowWithoutEnabledExtensions,
            profileId: resolvedProfileId
        )
        return controller
    }

    @discardableResult
    func requestExtensionRuntimeAndWait(
        reason: ExtensionRuntimeRequestReason,
        forceReload: Bool = false,
        allowWithoutEnabledExtensions: Bool = false,
        profileId: UUID? = nil,
        extensionId: String? = nil
    ) async -> Bool {
        let resolvedProfileId = profileRuntimeOwner.resolvedProfileId(
            explicitProfileId: profileId,
            browserManager: browserManager
        )

        if forceReload == false,
           let resolvedProfileId,
           extensionRuntimeReadinessContext(for: resolvedProfileId)
            .canUseExistingRuntime(extensionID: extensionId)
        {
            markExtensionRuntimeReadyIfProfileContextsLoaded(for: resolvedProfileId)
            return true
        }

        guard requestExtensionRuntime(
            reason: reason,
            forceReload: forceReload,
            allowWithoutEnabledExtensions: allowWithoutEnabledExtensions,
            profileId: resolvedProfileId
        ) != nil else {
            return false
        }

        if let runtimeInitializationTask {
            await runtimeInitializationTask.value
        }

        if let resolvedProfileId,
           extensionRuntimeReadinessContext(for: resolvedProfileId)
            .isReadyAfterRuntimeRequest(extensionID: extensionId)
        {
            markExtensionRuntimeReadyIfProfileContextsLoaded(for: resolvedProfileId)
            return true
        }

        if let resolvedProfileId,
           extensionRuntimeReadinessContext(for: resolvedProfileId)
            .allowsReadyControllerFallback(extensionID: extensionId)
        {
            return true
        }

        return false
    }

    private func ensureExtensionController(
        reason: ExtensionRuntimeRequestReason
    ) -> WKWebExtensionController {
        let profileId =
            currentProfileId
            ?? profileRuntimeOwner.currentProfile(in: browserManager)?.id
            ?? browserManager?.currentProfile?.id
            ?? UUID()
        let controller = ensureExtensionController(for: profileId)
        extensionRuntimeTrace(
            "runtime controller initialized reason=\(reason.rawValue) profile=\(profileId.uuidString) controller=\(extensionRuntimeControllerDescription(controller))"
        )
        return controller
    }

    private func startExtensionRuntimeLoad(
        reason: ExtensionRuntimeRequestReason,
        forceReload: Bool,
        allowWithoutEnabledExtensions: Bool,
        profileId: UUID?
    ) {
        runtimeInitializationTask?.cancel()
        runtimeInitializationTask = nil

        let resolvedProfileId = profileRuntimeOwner.resolvedProfileId(
            explicitProfileId: profileId,
            browserManager: browserManager
        )

        if forceReload {
            resetLoadedExtensionRuntimeStateForReload()
            cachedWebExtensionsByID.removeAll()
            cachedWebExtensionRuntimeSourceKeysByID.removeAll()
            lastExtensionLoadErrors.removeAll()
            extensionRuntimeResidencyState.removeAll()
        }

        let hasDemand =
            enabledPersistedExtensionEntities().isEmpty == false
            || allowWithoutEnabledExtensions
        guard hasDemand else {
            extensionsLoaded = true
            runtimeState = .idle
            return
        }

        guard let resolvedProfileId else {
            extensionsLoaded = true
            runtimeState = .idle
            return
        }

        runtimeState = .loading
        _ = ensureExtensionController(for: resolvedProfileId)
        extensionsLoaded = true
        runtimeState = .ready
        markExtensionRuntimeReadyIfProfileContextsLoaded(for: resolvedProfileId)
        extensionRuntimeTrace(
            "lazyRuntime controller-only reason=\(reason.rawValue) profileId=\(resolvedProfileId.uuidString) loadedContexts=\(countLoadedExtensionContexts()) forceReload=\(forceReload)"
        )
    }

    func enabledPersistedExtensionEntities() -> [ExtensionEntity] {
        do {
            return try context.fetch(FetchDescriptor<ExtensionEntity>())
                .filter(\.isEnabled)
        } catch {
            Self.logger.error("Failed to fetch enabled extensions: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

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
            .union(nativeMessagePortExtensionIDs.values)

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
            .union(nativeMessagePortExtensionIDs.values)
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
        let signpostState = PerformanceTrace.beginInterval(
            "ExtensionManager.runtimeTeardown"
        )
        defer {
            PerformanceTrace.endInterval(
                "ExtensionManager.runtimeTeardown",
                signpostState
            )
        }

        extensionRuntimeTrace(
            "runtimeTeardown start reason=\(reason) removeUIState=\(removeUIState) releaseController=\(releaseController)"
        )

        #if DEBUG
            clearDebugState()
        #endif

        extensionLoadGeneration &+= 1
        runtimeInitializationTask?.cancel()
        runtimeInitializationTask = nil
        loadedInitialDocumentRuntimePreparationOwner?
            .cancelContentScriptContextLoadTasks()
        cancelInitialDocumentNativeMessagingWarmupTasks()
        loadedInitialDocumentRuntimePreparationOwner?
            .cancelDeferredTabNotificationTasks()
        cancelNativeMessagingBackgroundWakeTasks()
        backgroundRuntimeStateOwner.cancelAllWakeTasks()

        let uiStateIDs = removeUIState ? Array(actionAnchors.keys) : []
        let loadedIDs = allLoadedExtensionIDs()
            .union(loadedExtensionManifests.keys)
            .union(optionsWindows.keys)
            .union(nativeMessagePortExtensionIDs.values)
            .union(extensionErrorObserverTokens.keys)
            .union(uiStateIDs)

        for extensionId in loadedIDs {
            tearDownExtensionRuntimeState(
                for: extensionId,
                removeUIState: removeUIState
            )
        }

        for (_, token) in extensionErrorObserverTokens {
            NotificationCenter.default.removeObserver(token)
        }
        extensionErrorObserverTokens.removeAll()

        if removeUIState {
            for extensionId in Array(actionAnchors.keys) {
                clearActionAnchors(for: extensionId)
            }
        }

        Array(optionsWindows.keys).forEach { closeOptionsWindow(for: $0) }
        cancelNativeMessagingSessions(reason: reason)

        extensionContextsByProfile.removeAll()
        loadedExtensionManifests.removeAll()
        actionStatesByExtensionID.removeAll()
        cachedWebExtensionsByID.removeAll()
        cachedWebExtensionRuntimeSourceKeysByID.removeAll()
        lastExtensionLoadErrors.removeAll()
        extensionRuntimeResidencyState.removeAll()
        backgroundRuntimeStateOwner.removeAll()
        runtimeMetricsByExtensionID.removeAll()
        lastLoggedExtensionErrorFingerprints.removeAll()
        requestedTabLifecycleOwner.removeAllRecentlyOpenedTabRequests()
        clearPermissionsOriginsCompatibilityInstallations()
        extensionPageUserContentControllersByProfile.removeAll()
        tabAdapters.removeAll()
        windowAdapters.removeAll()

        if releaseController {
            browserConfiguration.webViewConfiguration.webExtensionController = nil
            for controller in extensionControllersByProfile.values {
                controller.delegate = nil
            }
            extensionControllersByProfile.removeAll()
            profileRuntimeOwner.removeAllWebsiteDataStores()
            extensionRuntimeAllowsWithoutEnabledExtensions = false
            runtimeState = isExtensionSupportAvailable ? .idle : .unavailable
            extensionsLoaded = false
        }

        extensionRuntimeTrace("runtimeTeardown complete reason=\(reason)")
    }

    func tabsAffectedByLoadedUserExtensionRuntime() -> [Tab] {
        guard hasLoadedUserExtensionRuntime else { return [] }

        let controllers = Array(extensionControllersByProfile.values)
        var affectedTabs: [Tab] = []
        var seenTabIds: Set<UUID> = []

        for tab in allKnownTabs() {
            guard seenTabIds.insert(tab.id).inserted else { continue }

            if tab.webExtensionContextOverride != nil
                || tab.webViewConfigurationOverride?.webExtensionController != nil
            {
                affectedTabs.append(tab)
                continue
            }

            let liveWebViews = liveWebViews(for: tab)
            if tab.isEphemeral == false,
               liveWebViews.isEmpty == false
            {
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
            tab.resetExtensionRuntimeDocumentBindingForContentScriptRebind()
            tab.lastExtensionOpenNotificationGeneration = 0

            extensionRuntimeTrace(
                "runtimeTeardown rebuildLiveWebViews reason=\(reason) \(extensionRuntimeTabDescription(tab))"
            )
            browserManager?.webViewCoordinator?.rebuildLiveWebViews(for: tab)
        }
    }

    func cancelNativeMessagingSessions(reason: String) {
        extensionRuntimeTrace(
            "nativeMessagingCancelSessions reason=\(reason) count=\(nativeMessagePortHandlers.count)"
        )
        if nativeMessagePortHandlers.isEmpty == false {
            nativeMessagePortHandlers.values.forEach { $0.disconnect() }
            nativeMessagePortHandlers.removeAll()
            nativeMessagePortExtensionIDs.removeAll()
            nativeMessagePortProfileIDs.removeAll()
        }
        loadedNativeMessagingRelay?.clearAllLoopGuardState()
    }

    private func pruneRuntimeAdapters() {
        if let browserManager {
            let liveTabIDs = Set(
                browserManager.tabManager.allTabs().map(\.id)
                    + (browserManager.windowRegistry?.allWindows ?? [])
                    .flatMap(\.ephemeralTabs)
                    .map(\.id)
            )
            tabAdapters = tabAdapters.filter { liveTabIDs.contains($0.key) }

            let liveWindowIDs = Set(
                browserManager.windowRegistry?.windows.keys.map { $0 } ?? []
            )
            windowAdapters = windowAdapters.filter { liveWindowIDs.contains($0.key) }
        } else {
            tabAdapters.removeAll()
            windowAdapters.removeAll()
        }
    }

    func validateExpectedExtensionLoadGeneration(_ expectedGeneration: UInt64?) throws {
        guard let expectedGeneration else { return }
        guard extensionLoadGeneration == expectedGeneration else {
            throw CancellationError()
        }
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
        let resolvedProfileId = profileRuntimeOwner.resolvedProfileId(
            explicitProfileId: profileId,
            browserManager: browserManager
        )
        guard let resolvedProfileId else { return nil }
        if let store = extensionControllersByProfile[resolvedProfileId]?
            .configuration.defaultWebsiteDataStore
        {
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
            browserManager: browserManager
        )
    }

    func canLateBindExtensionController(to webView: WKWebView) -> Bool {
        webView.configuration.webExtensionController == nil
            && ExtensionRuntimeWebViewBindingPolicy.canLateBindController(
                currentURL: webView.url
            )
    }

    /// WebKit injects manifest `content_scripts` (including CSS) only when `didOpenTab`
    /// precedes the committed document. A controller on the configuration alone is not enough.
    func tabNeedsExtensionContentScriptRebind(_ tab: Tab) -> Bool {
        let documentSequence = tab.extensionRuntimeDocumentSequence
        guard documentSequence > 0 else { return false }
        guard let committedURL = tab.extensionRuntimeCommittedMainDocumentURL,
              isExtensionInjectableCommittedURL(committedURL)
        else {
            return false
        }

        if tab.extensionRuntimeOpenNotifiedWithLoadedContexts == false {
            return true
        }

        if let openBinding = tab.extensionRuntimeOpenNotifiedExtensionContextBindingGeneration,
           let profileId = resolvedProfileId(for: tab),
           openBinding != extensionContextBindingGeneration(for: profileId)
        {
            return true
        }

        for webView in liveWebViews(for: tab) where webViewNeedsExtensionRuntimeRebuild(webView, for: tab) {
            return true
        }

        guard let openNotifiedDocumentSequence = tab.extensionRuntimeOpenNotifiedDocumentSequence else {
            return true
        }

        return openNotifiedDocumentSequence != documentSequence - 1
    }

    /// Re-binds extension runtime when the user interacts with a page whose committed
    /// document never received a pre-commit `didOpenTab` notification.
    func reconcileExtensionRuntimeOnUserGestureIfNeeded(
        _ tab: Tab,
        reason: String = #function
    ) {
        guard extensionsLoaded else { return }
        guard tab.isEphemeral == false else { return }
        guard tabNeedsExtensionContentScriptRebind(tab) else { return }
        registerTabWithExtensionRuntime(
            tab,
            reason: reason
        )
    }

    /// Delivers a fresh `didCloseTab`/`didOpenTab` pair before the next main-frame document
    /// commits so WebKit injects manifest `content_scripts` (including CSS) on reload and other
    /// regular navigations. Generation-based deduplication alone is insufficient because WebKit
    /// ignores a second `didOpenTab` on an already-open tab adapter until `didCloseTab` runs.
    func prepareExtensionRuntimeBeforeCommittedMainFrameNavigation(
        _ tab: Tab,
        destinationURL: URL,
        reason: String = #function
    ) {
        guard extensionsLoaded else {
            extensionRuntimeTrace(
                "prepareExtensionRuntimeBeforeCommittedMainFrameNavigation skip reason=\(reason) because=extensionsNotLoaded \(extensionRuntimeTabDescription(tab))"
            )
            return
        }
        guard tab.isEphemeral == false else { return }
        guard isExtensionInjectableCommittedURL(destinationURL) else { return }
        if tab.extensionRuntimeDocumentSequence == 0,
           tab.extensionRuntimeOpenNotifiedDocumentSequence == 0,
           tab.extensionRuntimeOpenNotifiedWithLoadedContexts == true
        {
            return
        }

        tab.lastExtensionOpenNotificationGeneration = 0
        extensionRuntimeTrace(
            "prepareExtensionRuntimeBeforeCommittedMainFrameNavigation proceed reason=\(reason) destination=\(destinationURL.absoluteString) documentSequence=\(tab.extensionRuntimeDocumentSequence) \(extensionRuntimeTabDescription(tab))"
        )
        rebindExtensionTabBeforeCommittedNavigation(
            tab,
            reason: reason
        )
    }

    /// Re-binds a live tab to WebKit immediately before a committed navigation so manifest
    /// `content_scripts` can inject on the incoming document.
    func rebindExtensionTabBeforeCommittedNavigation(
        _ tab: Tab,
        reason: String = #function
    ) {
        ensureExtensionControllerAttachedForTab(tab, reason: reason)

        if let profileId = resolvedProfileId(for: tab),
           profileNeedsInitialDocumentExtensionContextLoad(
               profileId: profileId
           )
        {
            scheduleDeferredTabNotificationAfterContextLoad(
                tab,
                profileId: profileId,
                reason: reason
            )
            return
        }

        let shouldCycleTabLifecycle =
            tab.extensionRuntimeOpenNotifiedDocumentSequence != nil
            || tab.extensionRuntimeDocumentSequence > 0
            || tabNeedsExtensionContentScriptRebind(tab)

        if shouldCycleTabLifecycle,
           let controller = extensionController(for: tab),
           let adapter = stableAdapter(for: tab)
        {
            extensionRuntimeTrace(
                "rebindExtensionTabBeforeCommittedNavigation didCloseTab reason=\(reason) \(extensionRuntimeTabDescription(tab))"
            )
            controller.didCloseTab(adapter, windowIsClosing: false)
            #if DEBUG
                testHooks.didCloseTab?(tab.id)
            #endif
            tab.lastExtensionOpenNotificationGeneration = 0
        }

        registerTabWithExtensionRuntime(
            tab,
            reason: reason
        )
    }

    private func isExtensionInjectableCommittedURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "about" {
            return false
        }
        return scheme == "http" || scheme == "https" || scheme == "file"
    }

    func allKnownTabs() -> [Tab] {
        guard let browserManager else { return [] }

        var tabs = browserManager.tabManager.allTabs()
        for windowState in browserManager.windowRegistry?.allWindows ?? [] {
            tabs.append(contentsOf: windowState.ephemeralTabs)
        }

        return tabs
    }

    func liveWebViews(for tab: Tab) -> [WKWebView] {
        var webViews = [tab.assignedWebView, tab.existingWebView].compactMap { $0 }

        if let browserManager,
           let coordinator = browserManager.webViewCoordinator
        {
            webViews.append(contentsOf: coordinator.getAllWebViews(for: tab.id))
        }

        var uniqueWebViews: [WKWebView] = []
        var seen: Set<ObjectIdentifier> = []
        for webView in webViews {
            let identifier = ObjectIdentifier(webView)
            guard seen.insert(identifier).inserted else { continue }
            uniqueWebViews.append(webView)
        }

        return uniqueWebViews
    }

    private func resolvedLiveURL(for tab: Tab) -> URL? {
        for webView in liveWebViews(for: tab) {
            if let url = webView.url {
                return url
            }
        }

        return tab.url
    }

    func registerTabWithExtensionRuntime(
        _ tab: Tab,
        reason: String = #function,
        allowWhenExtensionsNotLoaded: Bool = false
    ) {
        let generation = tabOpenNotificationGeneration
        tab.prepareExtensionRuntimeGeneration(generation)

        guard extensionsLoaded || allowWhenExtensionsNotLoaded else {
            extensionRuntimeTrace(
                "registerTabWithExtensionRuntime skip reason=\(reason) because=extensionsNotLoaded generation=\(generation) \(extensionRuntimeTabDescription(tab))"
            )
            return
        }

        tab.extensionRuntimeEligibleGeneration = generation
        ensureExtensionControllerAttachedForTab(
            tab,
            reason: reason,
            allowWhenExtensionsNotLoaded: allowWhenExtensionsNotLoaded
        )
        notifyTabOpenedIfNeeded(tab, reason: reason)
    }

    func markTabEligibleAfterCommittedNavigation(
        _ tab: Tab,
        reason: String = #function
    ) {
        let generation = tabOpenNotificationGeneration
        tab.prepareExtensionRuntimeGeneration(generation)

        guard extensionsLoaded else {
            extensionRuntimeTrace(
                "markTabEligibleAfterCommittedNavigation skip reason=\(reason) because=extensionsNotLoaded generation=\(generation) \(extensionRuntimeTabDescription(tab))"
            )
            return
        }

        tab.extensionRuntimeEligibleGeneration = generation
        ensureExtensionControllerAttachedForTab(tab, reason: reason)
        notifyTabOpenedIfNeeded(tab, reason: reason)
    }

    func isTabEligibleForCurrentExtensionRuntime(_ tab: Tab) -> Bool {
        guard tab.isEphemeral == false else { return false }
        return isTabEligibleForExtensionRuntime(
            tab,
            generation: tabOpenNotificationGeneration
        )
    }

    private func coalescedTabChangedProperties(
        for tab: Tab,
        requestedProperties: WKWebExtension.TabChangedProperties
    ) -> WKWebExtension.TabChangedProperties {
        var changedProperties: WKWebExtension.TabChangedProperties = []

        if requestedProperties.contains(.URL) {
            let resolvedURL = resolvedLiveURL(for: tab)
            if resolvedURL?.absoluteString != tab.extensionRuntimeLastReportedURL?.absoluteString {
                changedProperties.insert(.URL)
                tab.extensionRuntimeLastReportedURL = resolvedURL
            }
        }

        if requestedProperties.contains(.loading) {
            let isLoadingComplete = !tab.isLoading
            if tab.extensionRuntimeLastReportedLoadingComplete != isLoadingComplete {
                changedProperties.insert(.loading)
                tab.extensionRuntimeLastReportedLoadingComplete = isLoadingComplete
            }
        }

        if requestedProperties.contains(.title) {
            let title = tab.name.isEmpty ? nil : tab.name
            if tab.extensionRuntimeLastReportedTitle != title {
                changedProperties.insert(.title)
                tab.extensionRuntimeLastReportedTitle = title
            }
        }

        return changedProperties
    }

    private func isTabEligibleForExtensionRuntime(
        _ tab: Tab,
        generation: UInt64
    ) -> Bool {
        tab.extensionRuntimeEligibleGeneration == generation
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
               let string = String(data: data, encoding: .utf8)
            {
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
        let handlerIDs = nativeMessagePortExtensionIDs.compactMap { entry -> ObjectIdentifier? in
            guard entry.value == extensionId else { return nil }
            if let profileId, nativeMessagePortProfileIDs[entry.key] != profileId {
                return nil
            }
            return entry.key
        }

        for handlerID in handlerIDs {
            nativeMessagePortHandlers[handlerID]?.disconnect()
            nativeMessagePortHandlers.removeValue(forKey: handlerID)
            nativeMessagePortExtensionIDs.removeValue(forKey: handlerID)
            nativeMessagePortProfileIDs.removeValue(forKey: handlerID)
        }
    }

    private func tearDownNativeMessageHandlers(for extensionId: String) {
        let handlerIDs = nativeMessagePortExtensionIDs.compactMap { entry in
            entry.value == extensionId ? entry.key : nil
        }

        for handlerID in handlerIDs {
            nativeMessagePortHandlers[handlerID]?.disconnect()
            nativeMessagePortHandlers.removeValue(forKey: handlerID)
            nativeMessagePortExtensionIDs.removeValue(forKey: handlerID)
            nativeMessagePortProfileIDs.removeValue(forKey: handlerID)
        }
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
