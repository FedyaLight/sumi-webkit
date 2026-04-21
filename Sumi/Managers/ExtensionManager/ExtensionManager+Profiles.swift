import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager

        guard let controller = extensionController else { return }
        extensionRuntimeTrace(
            "attach browserManager controller=\(extensionRuntimeControllerDescription(controller)) windows=\(browserManager.windowRegistry?.allWindows.count ?? 0) tabs=\(browserManager.tabManager.allTabs().count)"
        )
        updateExistingWebViewsWithController(controller)
        registerExistingWindowStateIfAttached()

        if browserManager.windowRegistry?.activeWindow == nil,
           let currentProfile = browserManager.currentProfile
        {
            switchProfile(profileId: currentProfile.id)
        }
    }

    func notifyWindowOpened(_ windowState: BrowserWindowState) {
        guard let controller = extensionController,
              let adapter = windowAdapter(for: windowState.id) else {
            return
        }
        controller.didOpenWindow(adapter)
    }

    func notifyWindowClosed(_ windowId: UUID) {
        windowAdapters.removeValue(forKey: windowId)
    }

    func notifyWindowFocused(_ windowState: BrowserWindowState) {
        guard let controller = extensionController,
              let adapter = windowAdapter(for: windowState.id) else {
            return
        }
        controller.didFocusWindow(adapter)

        if windowState.isIncognito, let profile = windowState.ephemeralProfile {
            switchProfile(profileId: profile.id)
        } else if let profileId = windowState.currentProfileId,
                  let profile = browserManager?.profileManager.profiles.first(where: { $0.id == profileId })
        {
            switchProfile(profileId: profile.id)
        } else if let currentProfile = browserManager?.currentProfile {
            switchProfile(profileId: currentProfile.id)
        }
    }

    func switchProfile(_ profile: Profile) {
        switchProfile(profileId: profile.id)
    }

    func switchProfile(profileId: UUID, dataStore: WKWebsiteDataStore) {
        switchProfile(profileId: profileId)
    }

    func switchProfile(profileId: UUID) {
        guard let extensionController else { return }
        let store = getExtensionDataStore(for: profileId)
        if currentProfileId == profileId,
           extensionController.configuration.defaultWebsiteDataStore?.identifier == store.identifier
        {
            return
        }

        let signpostState = PerformanceTrace.beginInterval("ExtensionManager.switchProfile")
        defer {
            PerformanceTrace.endInterval("ExtensionManager.switchProfile", signpostState)
        }

        extensionController.configuration.defaultWebsiteDataStore = store
        currentProfileId = profileId
        reloadPinnedToolbarExtensionsForCurrentProfile()
        verifyExtensionStorage(profileId: profileId)
    }

    func grantExtensionAccessToURL(_ url: URL) {
        for (_, extensionContext) in extensionContexts {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: url)
        }
    }

    @discardableResult
    func notifyTabOpened(_ tab: Tab) -> Bool {
        guard let controller = extensionController,
              let adapter = stableAdapter(for: tab) else { return false }
        extensionRuntimeTrace(
            "didOpenTab start generation=\(extensionLoadGeneration) notifyGeneration=\(tabOpenNotificationGeneration) controller=\(extensionRuntimeControllerDescription(controller)) \(extensionRuntimeTabDescription(tab)) adapter=\(extensionRuntimeObjectDescription(adapter))"
        )
        controller.didOpenTab(adapter)
        #if DEBUG
            testHooks.didOpenTab?(tab.id)
        #endif
        extensionRuntimeTrace(
            "didOpenTab complete generation=\(extensionLoadGeneration) notifyGeneration=\(tabOpenNotificationGeneration) \(extensionRuntimeTabDescription(tab))"
        )
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
        guard let controller = extensionController,
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
        guard let controller = extensionController,
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

        guard let controller = extensionController,
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

        if let browserManager,
           let activeWindow = browserManager.windowRegistry?.activeWindow,
           let currentTab = browserManager.currentTab(for: activeWindow),
           isTabEligibleForCurrentExtensionRuntime(currentTab)
        {
            notifyTabActivated(newTab: currentTab, previous: nil)
        }

        extensionRuntimeTrace(
            "resyncOpenTabsAfterGenerationBump complete reason=\(reason) generation=\(tabOpenNotificationGeneration)"
        )
    }

    func registerExistingWindowStateIfAttached() {
        guard let browserManager else { return }

        let windows = browserManager.windowRegistry?.allWindows ?? []
        extensionRuntimeTrace(
            "registerExistingWindowState start generation=\(extensionLoadGeneration) notifyGeneration=\(tabOpenNotificationGeneration) windows=\(windows.count) controller=\(extensionRuntimeControllerDescription(extensionController))"
        )

        for windowState in windows {
            notifyWindowOpened(windowState)
        }

        if let activeWindow = browserManager.windowRegistry?.activeWindow {
            notifyWindowFocused(activeWindow)
        }

        extensionRuntimeTrace(
            "registerExistingWindowState complete generation=\(extensionLoadGeneration) notifyGeneration=\(tabOpenNotificationGeneration) windows=\(windows.count)"
        )
    }

    func prepareExtensionContextForRuntime(
        _ extensionContext: WKWebExtensionContext,
        extensionId: String,
        manifest: [String: Any]? = nil
    ) {
        let resolvedManifest =
            manifest
            ?? loadedExtensionManifests[extensionId]
            ?? extensionContext.webExtension.manifest
        extensionContext.unsupportedAPIs = Self.safariOnlyRuntimeUnsupportedAPIs(
            for: resolvedManifest
        )

        guard let configuration = extensionContext.webViewConfiguration else {
            let fallbackConfiguration = browserConfiguration.webViewConfiguration
            if fallbackConfiguration.webExtensionController == nil,
               let extensionController
            {
                fallbackConfiguration.webExtensionController = extensionController
            }

            fallbackConfiguration.defaultWebpagePreferences.allowsContentJavaScript = true
            return
        }

        if configuration.webExtensionController == nil,
           let extensionController
        {
            configuration.webExtensionController = extensionController
        }

        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    }

    func scheduleWebKitExtensionStorageCleanupDryRun(activeExtensionIDs: Set<String>) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        let currentIdentifier = stableControllerIdentifier().uuidString.uppercased()
        guard let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }

        let rootURL = libraryDir
            .appendingPathComponent("WebKit", isDirectory: true)
            .appendingPathComponent(SumiAppIdentity.runtimeBundleIdentifier, isDirectory: true)
            .appendingPathComponent("WebExtensions", isDirectory: true)

        let activeIDs = activeExtensionIDs
        let staleCutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let logger = Self.logger

        DispatchQueue.global(qos: .utility).async {
            let fileManager = FileManager.default
            let controllerDirectories = (try? fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for controllerDirectory in controllerDirectories {
                let controllerIdentifier = controllerDirectory.lastPathComponent.uppercased()
                guard UUID(uuidString: controllerIdentifier) != nil,
                      controllerIdentifier != currentIdentifier else {
                    continue
                }
                guard (try? controllerDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                    continue
                }

                let values = try? controllerDirectory.resourceValues(forKeys: [.contentModificationDateKey])
                guard (values?.contentModificationDate ?? .distantPast) < staleCutoff else {
                    continue
                }

                let extensionDirectories = (try? fileManager.contentsOfDirectory(
                    at: controllerDirectory,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                let storedExtensionIDs = Set(extensionDirectories.compactMap { extensionDirectory in
                    ((try? extensionDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true)
                        ? extensionDirectory.lastPathComponent
                        : nil
                })

                if storedExtensionIDs.isDisjoint(with: activeIDs) {
                    logger.info(
                        "Dry-run stale WebKit extension storage cleanup would remove \(controllerDirectory.path, privacy: .public)"
                    )
                } else {
                    logger.debug(
                        "Keeping stale WebKit extension storage \(controllerDirectory.path, privacy: .public) because it contains active extension IDs"
                    )
                }
            }
        }
    }

    func observeExtensionErrors(
        for extensionContext: WKWebExtensionContext,
        extensionId: String
    ) {
        removeExtensionErrorObserver(for: extensionId)

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
        let signpostState = PerformanceTrace.beginInterval(
            "ExtensionManager.tearDownExtensionRuntimeState"
        )
        defer {
            PerformanceTrace.endInterval(
                "ExtensionManager.tearDownExtensionRuntimeState",
                signpostState
            )
        }

        backgroundWakeTasks[extensionId]?.cancel()
        backgroundWakeTasks.removeValue(forKey: extensionId)
        backgroundRuntimeStateByExtensionID.removeValue(forKey: extensionId)
        unloadExtensionContextIfNeeded(for: extensionId)
        removeExtensionErrorObserver(for: extensionId)
        loadedExtensionManifests.removeValue(forKey: extensionId)
        removeExternallyConnectablePageBridge(for: extensionId)
        lastLoggedExtensionErrorFingerprints.removeValue(forKey: extensionId)
        closeOptionsWindow(for: extensionId)
        tearDownNativeMessageHandlers(for: extensionId)

        if removeUIState {
            clearActionAnchors(for: extensionId)
        }
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

        let loadedIDs = Set(extensionContexts.keys)
            .union(loadedExtensionManifests.keys)
            .union(optionsWindows.keys)
            .union(nativeMessagePortExtensionIDs.values)

        for extensionId in loadedIDs {
            tearDownExtensionRuntimeState(for: extensionId, removeUIState: false)
        }

        extensionContexts.removeAll()
        loadedExtensionManifests.removeAll()
        backgroundWakeTasks.values.forEach { $0.cancel() }
        backgroundWakeTasks.removeAll()
        backgroundRuntimeStateByExtensionID.removeAll()
        recentExtensionTabOpenRequestDatesByURL.removeAll()
        nativeMessagePortHandlers.removeAll()
        nativeMessagePortExtensionIDs.removeAll()
        externallyConnectablePolicies.removeAll()
        clearExternallyConnectablePendingRequests()
        clearExternallyConnectableNativePorts()
    }

    func validateExpectedExtensionLoadGeneration(_ expectedGeneration: UInt64?) throws {
        guard let expectedGeneration else { return }
        guard extensionLoadGeneration == expectedGeneration else {
            throw CancellationError()
        }
    }

    func setupExtensionController(using initialProfile: Profile?) {
        let signpostState = PerformanceTrace.beginInterval("ExtensionManager.setupExtensionController")
        defer {
            PerformanceTrace.endInterval(
                "ExtensionManager.setupExtensionController",
                signpostState
            )
        }

        let defaultDataStore =
            initialProfile.map { getExtensionDataStore(for: $0.id) }
            ?? WKWebsiteDataStore(forIdentifier: stableControllerIdentifier())
        let controller = makeExtensionController(defaultDataStore: defaultDataStore)
        extensionRuntimeTrace(
            "setupExtensionController controller=\(extensionRuntimeControllerDescription(controller)) profile=\(initialProfile?.id.uuidString ?? "nil")"
        )
        extensionController = controller
        currentProfileId = initialProfile?.id
        scheduleControllerDelegateRebind(for: controller)
        updateExistingWebViewsWithController(controller)
        verifyExtensionStorage(profileId: initialProfile?.id)
    }

    private func stableControllerIdentifier() -> UUID {
        controllerIdentifier
    }

    private func makeExtensionController(
        defaultDataStore: WKWebsiteDataStore
    ) -> WKWebExtensionController {
        let configuration = WKWebExtensionController.Configuration(
            identifier: stableControllerIdentifier()
        )
        let runtimeWebConfiguration = browserConfiguration.webViewConfiguration
        configuration.webViewConfiguration = runtimeWebConfiguration
        configuration.defaultWebsiteDataStore = defaultDataStore

        let controller = WKWebExtensionController(configuration: configuration)
        controller.delegate = self

        runtimeWebConfiguration.webExtensionController = controller
        runtimeWebConfiguration.defaultWebpagePreferences.allowsContentJavaScript = true

        return controller
    }

    private func scheduleControllerDelegateRebind(
        for controller: WKWebExtensionController
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak controller] in
            guard let self, let controller else { return }
            guard self.extensionController === controller else { return }
            controller.delegate = self
        }
    }

    private func verifyExtensionStorage(profileId: UUID?) {
        guard RuntimeDiagnostics.isVerboseEnabled else {
            return
        }
        guard let dataStore = extensionController?.configuration.defaultWebsiteDataStore else {
            return
        }
        dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            Self.logger.debug("Extension data store ready for profile \(profileId?.uuidString ?? "none", privacy: .public): \(records.count) records")
        }
    }

    private func getExtensionDataStore(
        for profileId: UUID
    ) -> WKWebsiteDataStore {
        if let store = profileExtensionStores[profileId] {
            return store
        }

        let signpostState = PerformanceTrace.beginInterval("ExtensionManager.getExtensionDataStore")
        defer {
            PerformanceTrace.endInterval("ExtensionManager.getExtensionDataStore", signpostState)
        }

        let store = WKWebsiteDataStore(forIdentifier: profileId)
        profileExtensionStores[profileId] = store
        return store
    }

    private func updateExistingWebViewsWithController(
        _ controller: WKWebExtensionController
    ) {
        guard browserManager != nil else { return }
        for tab in allKnownTabs() {
            for webView in liveWebViews(for: tab) {
                let existingController = webView.configuration.webExtensionController
                let canLateBind = canLateBindExtensionController(to: webView)
                let willAssign = existingController == nil && canLateBind
                extensionRuntimeTrace(
                    "updateExistingWebViewsWithController webView=\(extensionRuntimeWebViewDescription(webView)) configuration=\(extensionRuntimeConfigurationDescription(webView.configuration)) userContentController=\(extensionRuntimeUserContentControllerDescription(webView.configuration.userContentController)) existingController=\(extensionRuntimeControllerDescription(existingController)) targetController=\(extensionRuntimeControllerDescription(controller)) canLateBind=\(canLateBind) willAssign=\(willAssign) \(extensionRuntimeTabDescription(tab))"
                )
                if willAssign {
                    webView.configuration.webExtensionController = controller
                    webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = true
                } else if existingController == nil {
                    extensionRuntimeTrace(
                        "updateExistingWebViewsWithController skipped lateBindExistingWebView webView=\(extensionRuntimeWebViewDescription(webView)) currentURL=\(webView.url?.absoluteString ?? "nil") \(extensionRuntimeTabDescription(tab))"
                    )
                }
            }
        }
    }

    private func canLateBindExtensionController(to webView: WKWebView) -> Bool {
        guard webView.configuration.webExtensionController == nil else {
            return false
        }

        guard let currentURL = webView.url else {
            return true
        }

        let normalizedURL = currentURL.absoluteString.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return normalizedURL.isEmpty || normalizedURL == "about:blank"
    }

    private func allKnownTabs() -> [Tab] {
        guard let browserManager else { return [] }

        var tabs = browserManager.tabManager.allTabs()
        for windowState in browserManager.windowRegistry?.allWindows ?? [] {
            tabs.append(contentsOf: windowState.ephemeralTabs)
        }

        return tabs
    }

    private func liveWebViews(for tab: Tab) -> [WKWebView] {
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
    }

    func isTabEligibleForCurrentExtensionRuntime(_ tab: Tab) -> Bool {
        isTabEligibleForExtensionRuntime(
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
            Self.logger.debug(
                "Extension errors \(reason, privacy: .public) for \(extensionId, privacy: .public): none"
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
    }

    private func tearDownNativeMessageHandlers(for extensionId: String) {
        let handlerIDs = nativeMessagePortExtensionIDs.compactMap { entry in
            entry.value == extensionId ? entry.key : nil
        }

        for handlerID in handlerIDs {
            nativeMessagePortHandlers[handlerID]?.disconnect()
            nativeMessagePortHandlers.removeValue(forKey: handlerID)
            nativeMessagePortExtensionIDs.removeValue(forKey: handlerID)
        }
    }

    private func unloadExtensionContextIfNeeded(for extensionId: String) {
        backgroundRuntimeStateByExtensionID.removeValue(forKey: extensionId)
        guard let context = extensionContexts.removeValue(forKey: extensionId) else {
            return
        }

        do {
            try extensionController?.unload(context)
        } catch {
            Self.logger.debug(
                "Ignoring failed unload for extension \(extensionId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
