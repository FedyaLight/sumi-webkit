import AppKit
import Foundation
import SwiftData
import WebKit

@MainActor
struct SumiExtensionsModuleRuntime {
    typealias CurrentProfileProvider = @MainActor () -> Profile?
    typealias ManagerAttacher = @MainActor (_ manager: ExtensionManager) -> Void
    typealias LiveTabsProvider = @MainActor () -> [Tab]
    typealias StructuralRevisionInvalidator = @MainActor () -> Void

    let currentProfile: CurrentProfileProvider
    let attachManager: ManagerAttacher
    let liveTabs: LiveTabsProvider
    let invalidateTabStructuralRevision: StructuralRevisionInvalidator

    static let inactive = SumiExtensionsModuleRuntime(
        currentProfile: { nil },
        attachManager: { _ in /* No-op. */ },
        liveTabs: { [] },
        invalidateTabStructuralRevision: { /* No-op. */ }
    )
}

@MainActor
final class SumiExtensionsModule {
    static let shared = SumiExtensionsModule()

    private let moduleRegistry: SumiModuleRegistry
    private let context: ModelContext?
    private let browserConfiguration: BrowserConfiguration
    private let initialProfileProvider: @MainActor () -> Profile?
    private let safariExtensionImportStore: any SafariExtensionImportStoring & SafariExtensionImportRecordProviding
    private let managerFactory: @MainActor (
        ModelContext,
        Profile?,
        BrowserConfiguration,
        SumiModuleRegistry
    ) -> ExtensionManager

    let surfaceStore: BrowserExtensionSurfaceStore

    private var cachedManager: ExtensionManager?
    private var pendingActionAnchors: [String: [WeakAnchor]] = [:]
    private let safariContentBlockerRuntimeOwner: SafariContentBlockerRuntimeOwner
    private var runtime = SumiExtensionsModuleRuntime.inactive

    init(
        moduleRegistry: SumiModuleRegistry = .shared,
        context: ModelContext? = nil,
        browserConfiguration: BrowserConfiguration? = nil,
        initialProfileProvider: @escaping @MainActor () -> Profile? = { nil },
        safariExtensionImportStore: any SafariExtensionImportStoring & SafariExtensionImportRecordProviding = SafariExtensionImportStore.shared,
        managerFactory: @escaping @MainActor (
            ModelContext,
            Profile?,
            BrowserConfiguration,
            SumiModuleRegistry
        ) -> ExtensionManager = {
            ExtensionManager(
                context: $0,
                initialProfile: $1,
                browserConfiguration: $2,
                moduleRegistry: $3
            )
        },
        surfaceStore: BrowserExtensionSurfaceStore? = nil
    ) {
        self.moduleRegistry = moduleRegistry
        self.context = context
        self.browserConfiguration = browserConfiguration ?? .shared
        self.initialProfileProvider = initialProfileProvider
        self.safariExtensionImportStore = safariExtensionImportStore
        self.managerFactory = managerFactory
        self.surfaceStore = surfaceStore ?? BrowserExtensionSurfaceStore(
            extensionManager: nil
        )
        self.safariContentBlockerRuntimeOwner = SafariContentBlockerRuntimeOwner(
            context: context,
            defaults: moduleRegistry.userDefaults,
            isModuleEnabled: {
                moduleRegistry.isEnabled(.extensions)
            }
        )
    }

    var isEnabled: Bool {
        moduleRegistry.isEnabled(.extensions)
    }

    var hasLoadedRuntime: Bool {
        cachedManager != nil
    }

    var hasLoadedWebExtensionController: Bool {
        cachedManager?.extensionController != nil
    }

    func attach(runtime: SumiExtensionsModuleRuntime) {
        self.runtime = runtime
        if let cachedManager {
            runtime.attachManager(cachedManager)
        }
        ensureActionMetadataLoadedIfNeeded()
    }

    func setEnabled(_ isEnabled: Bool) {
        let wasEnabled = self.isEnabled
        moduleRegistry.setEnabled(isEnabled, for: .extensions)
        if isEnabled == false {
            tearDownLoadedRuntime(reason: "SumiExtensionsModule.setEnabled(false)")
            safariContentBlockerRuntimeOwner.clearRuntime()
            pendingActionAnchors.removeAll()
        }
        if wasEnabled != isEnabled {
            markSafariContentBlockerReloadRequiredForLiveTabs()
        }
    }

    func managerIfLoadedAndEnabled() -> ExtensionManager? {
        guard isEnabled else { return nil }
        return cachedManager
    }

    func managerIfEnabled() -> ExtensionManager? {
        guard isEnabled else { return nil }

        if let cachedManager {
            transferPendingActionAnchors(to: cachedManager)
            surfaceStore.bind(cachedManager)
            return cachedManager
        }

        guard let context else { return nil }

        let manager = managerFactory(
            context,
            runtime.currentProfile() ?? initialProfileProvider(),
            browserConfiguration,
            moduleRegistry
        )
        cachedManager = manager
        runtime.attachManager(manager)
        transferPendingActionAnchors(to: manager)
        surfaceStore.bind(manager)
        return manager
    }

    @discardableResult
    func ensureActionMetadataLoadedIfNeeded() -> Bool {
        guard isEnabled, context != nil else { return false }

        if cachedManager != nil {
            return true
        }

        guard hasEnabledPersistedExtensions() else {
            return false
        }

        return managerIfEnabled() != nil
    }

    func normalTabUserScripts() -> [SumiUserScript] {
        managerIfNeededForNormalTabRuntime()?.normalTabUserScripts() ?? []
    }

    func prepareWebViewConfigForExtensionRuntime(
        _ configuration: WKWebViewConfiguration,
        profileId: UUID? = nil,
        reason: String
    ) {
        managerIfNeededForNormalTabRuntime()?.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profileId,
            reason: reason
        )
    }

    func prepareWebViewForExtensionRuntime(
        _ webView: WKWebView,
        currentURL: URL?,
        reason: String
    ) {
        managerIfNeededForNormalTabRuntime()?.prepareWebViewForExtensionRuntime(
            webView,
            currentURL: currentURL,
            reason: reason
        )
    }

    @discardableResult
    func prepareExtensionPageNavigationIfLoaded(
        _ tab: Tab,
        targetURL: URL,
        reason: String
    ) -> Bool {
        managerIfLoadedAndEnabled()?.prepareExtensionPageNavigation(
            tab,
            targetURL: targetURL,
            reason: reason
        ) ?? false
    }

    func registerTabWithExtensionRuntimeIfLoaded(
        _ tab: Tab,
        reason: String
    ) {
        managerIfLoadedAndEnabled()?.registerTabWithExtensionRuntime(
            tab,
            reason: reason
        )
    }

    func reconcileExtensionRuntimeOnUserGestureIfNeeded(
        _ tab: Tab,
        reason: String
    ) {
        managerIfLoadedAndEnabled()?.reconcileExtensionRuntimeOnUserGestureIfNeeded(
            tab,
            reason: reason
        )
    }

    func notifyWindowOpenedIfLoaded(_ windowState: BrowserWindowState) {
        managerIfLoadedAndEnabled()?.notifyWindowOpened(windowState)
    }

    func notifyWindowClosedIfLoaded(_ windowId: UUID) {
        managerIfLoadedAndEnabled()?.notifyWindowClosed(windowId)
    }

    func notifyWindowFocusedIfLoaded(_ windowState: BrowserWindowState) {
        managerIfLoadedAndEnabled()?.notifyWindowFocused(windowState)
    }

    func switchProfileIfLoaded(_ profile: Profile) {
        managerIfLoadedAndEnabled()?.switchProfile(profile)
    }

    func notifyTabActivatedIfLoaded(newTab: Tab, previous: Tab?) {
        managerIfLoadedAndEnabled()?.notifyTabActivated(
            newTab: newTab,
            previous: previous
        )
    }

    func notifyTabClosedIfLoaded(_ tab: Tab) {
        managerIfLoadedAndEnabled()?.notifyTabClosed(tab)
    }

    func notifyTabPropertiesChangedIfLoaded(
        _ tab: Tab,
        properties: WKWebExtension.TabChangedProperties
    ) {
        managerIfLoadedAndEnabled()?.notifyTabPropertiesChanged(
            tab,
            properties: properties
        )
    }

    /// Safari parity: dispatches a keyboard event to loaded extension
    /// commands after Sumi's own shortcuts declined it. Returns true when an
    /// extension command consumed the event.
    func performExtensionKeyboardCommandIfLoaded(for event: NSEvent) -> Bool {
        managerIfLoadedAndEnabled()?.performExtensionKeyboardCommand(for: event) ?? false
    }

    /// Safari parity: extension-provided context-menu items for a page tab.
    /// Fetch immediately before showing the menu; items must not be cached.
    func pageContextMenuItemsIfLoaded(for tab: Tab) -> [NSMenuItem] {
        managerIfLoadedAndEnabled()?.pageContextMenuItems(for: tab) ?? []
    }

    func markTabEligibleAfterCommittedNavigationIfLoaded(
        _ tab: Tab,
        reason: String
    ) {
        managerIfLoadedAndEnabled()?.markTabEligibleAfterCommittedNavigation(
            tab,
            reason: reason
        )
    }

    func prepareExtensionRuntimeBeforeCommittedMainFrameNavigationIfLoaded(
        _ tab: Tab,
        destinationURL: URL,
        reason: String
    ) {
        managerIfLoadedAndEnabled()?.prepareExtensionRuntimeBeforeCommittedMainFrameNavigation(
            tab,
            destinationURL: destinationURL,
            reason: reason
        )
    }

    func ensureContentScriptContextsLoadedIfNeeded(profileId: UUID) async {
        guard isEnabled else { return }
        await managerIfNeededForNormalTabRuntime()?
            .ensureContentScriptContextsLoaded(for: profileId)
    }

    func ensureInitialExtensionContextsIfNeeded(profileId: UUID) async {
        guard isEnabled else { return }
        await managerIfNeededForNormalTabRuntime()?
            .ensureInitialExtensionContextsLoaded(for: profileId)
    }

    func needsInitialDocumentExtensionContextLoadIfNeeded(profileId: UUID) -> Bool {
        guard isEnabled else { return false }
        return managerIfNeededForNormalTabRuntime()?
            .profileNeedsInitialDocumentExtensionContextLoad(profileId: profileId)
            ?? false
    }

    func consumeRecentlyOpenedExtensionTabRequestIfLoaded(for url: URL) -> Bool {
        managerIfLoadedAndEnabled()?.requestedTabLifecycleOwner.consumeRecentlyOpenedTabRequest(
            for: url
        ) ?? false
    }

    func recordRecentlyOpenedExtensionTabRequestIfLoaded(for url: URL?) {
        managerIfLoadedAndEnabled()?.requestedTabLifecycleOwner.recordRecentlyOpenedTabRequest(for: url)
    }

    func registerExtensionCreatedTabWithExtensionRuntimeIfLoaded(
        _ tab: Tab,
        reason: String
    ) {
        managerIfLoadedAndEnabled()?.registerExtensionCreatedTabWithExtensionRuntime(
            tab,
            reason: reason
        )
    }

    func enableExtension(_ extensionId: String) async throws -> InstalledExtension {
        guard let manager = managerIfEnabled() else {
            throw ExtensionError.unsupportedOS
        }
        let enabled = try await manager.enableExtension(extensionId)
        _ = safariExtensionCompatibilityReport()
        return enabled
    }

    func disableExtension(_ extensionId: String) async throws {
        guard let manager = managerIfEnabled() else { return }
        try await manager.disableExtension(extensionId)
    }

    func uninstallExtension(_ extensionId: String) async throws {
        guard let manager = managerIfEnabled() else { return }
        safariExtensionImportStore.removeImportedRecord(
            forInstalledExtensionId: extensionId
        )
        try await manager.uninstallExtension(extensionId)
    }

    func enableSafariAppExtension(
        from candidate: DiscoveredSafariExtensionCandidate
    ) async throws -> InstalledExtension {
        guard candidate.bundleKind == .webExtension else {
            throw ExtensionError.installationFailed(
                "Only Safari Web Extensions can be enabled in the WebExtension runtime."
            )
        }
        guard let manager = managerIfEnabled() else {
            throw ExtensionError.unsupportedOS
        }

        let installed = try await manager.performInstallation(
            from: candidate.appexURL,
            enableOnInstall: true
        )
        safariExtensionImportStore.markImported(
            candidate: candidate,
            installedExtensionId: installed.id
        )
        return installed
    }

    func refreshDiscoveredSafariWebExtensionCandidates(
        _ candidates: [DiscoveredSafariExtensionCandidate]
    ) {
        safariExtensionImportStore.refreshDiscoveredCandidates(
            candidates.filter { $0.bundleKind == .webExtension }
        )
    }

    func safariExtensionImportRecordsForDiagnostics() -> any SafariExtensionImportRecordProviding {
        safariExtensionImportStore
    }

    func installedSafariContentBlockers() -> [InstalledSafariContentBlockerRecord] {
        safariContentBlockerRuntimeOwner.installedContentBlockers()
    }

    func safariContentBlockerRecord(
        forBundleIdentifier bundleIdentifier: String
    ) -> InstalledSafariContentBlockerRecord? {
        safariContentBlockerRuntimeOwner.contentBlockerRecord(
            forBundleIdentifier: bundleIdentifier
        )
    }

    func enableSafariContentBlocker(
        from candidate: DiscoveredSafariExtensionCandidate
    ) async throws -> InstalledSafariContentBlockerRecord {
        let record = try await safariContentBlockerRuntimeOwner.enableContentBlocker(from: candidate)
        markSafariContentBlockerReloadRequiredForLiveTabs()
        return record
    }

    func setSafariContentBlockerEnabled(
        _ enabled: Bool,
        bundleIdentifier: String
    ) async throws -> InstalledSafariContentBlockerRecord? {
        let record = try await safariContentBlockerRuntimeOwner.setContentBlockerEnabled(
            enabled,
            bundleIdentifier: bundleIdentifier
        )
        markSafariContentBlockerReloadRequiredForLiveTabs()
        return record
    }

    func enabledSafariContentBlockingServices(
        for url: URL?,
        profileId: UUID?
    ) -> [SumiContentBlockingService] {
        safariContentBlockerRuntimeOwner.enabledContentBlockingServices(
            for: url,
            profileId: profileId
        )
    }

    func safariContentBlockerAttachmentState(
        for url: URL?
    ) -> SumiSafariContentBlockerAttachmentState {
        safariContentBlockerRuntimeOwner.attachmentState(for: url)
    }

    func safariContentBlockerSiteState(
        for url: URL?
    ) -> SumiSafariContentBlockerSiteState {
        safariContentBlockerRuntimeOwner.siteState(for: url)
    }

    func safariContentBlockerAttachedRuleListIdentifiers() -> [String] {
        safariContentBlockerRuntimeOwner.attachedRuleListIdentifiers()
    }

    private func markSafariContentBlockerReloadRequiredForLiveTabs() {
        runtime.liveTabs().forEach {
            $0.updateSafariContentBlockerReloadRequirementForCurrentSite()
        }
    }

    private func markSafariContentBlockerReloadRequiredForLiveTabs(
        afterChangingPolicyFor url: URL?
    ) {
        runtime.liveTabs().forEach {
            $0.markSafariContentBlockerReloadRequiredIfNeeded(
                afterChangingPolicyFor: url
            )
        }
    }

    func setSafariContentBlockerSiteOverride(
        _ override: SumiSafariContentBlockerSiteOverride,
        for url: URL?
    ) {
        safariContentBlockerRuntimeOwner.setSiteOverride(override, for: url)
        markSafariContentBlockerReloadRequiredForLiveTabs(afterChangingPolicyFor: url)
    }

    func orderedPinnedToolbarSlots(
        enabledExtensions: [InstalledExtension],
        sumiScriptsManagerEnabled: Bool
    ) -> [PinnedToolbarSlot] {
        orderedPinnedToolbarSlots(
            enabledExtensions: enabledExtensions,
            sumiScriptsManagerEnabled: sumiScriptsManagerEnabled,
            profileId: nil
        )
    }

    func orderedPinnedToolbarSlots(
        enabledExtensions: [InstalledExtension],
        sumiScriptsManagerEnabled: Bool,
        profileId: UUID?
    ) -> [PinnedToolbarSlot] {
        guard let manager = managerIfLoadedAndEnabled() else { return [] }
        return manager.orderedPinnedToolbarSlots(
            enabledExtensions: enabledExtensions,
            sumiScriptsManagerEnabled: sumiScriptsManagerEnabled,
            profileId: profileId ?? manager.currentProfileId
        )
    }

    func isPinnedToToolbar(_ extensionId: String) -> Bool {
        managerIfLoadedAndEnabled()?.isPinnedToToolbar(extensionId) ?? false
    }

    func pinToToolbar(_ extensionId: String) {
        managerIfEnabled()?.pinToToolbar(extensionId)
        runtime.invalidateTabStructuralRevision()
    }

    func unpinFromToolbar(_ extensionId: String) {
        managerIfEnabled()?.unpinFromToolbar(extensionId)
        runtime.invalidateTabStructuralRevision()
    }

    func siteAccessPolicy(
        extensionId: String,
        profileId: UUID? = nil
    ) -> SafariExtensionSiteAccessPolicy? {
        guard let manager = managerIfEnabled() else { return nil }
        let resolvedProfileId =
            profileId
            ?? manager.currentProfileId
            ?? runtime.currentProfile()?.id
        guard let resolvedProfileId else { return nil }
        return manager.siteAccessPolicy(
            extensionId: extensionId,
            profileId: resolvedProfileId
        )
    }

    func setDefaultSiteAccess(
        _ access: SafariExtensionSiteAccessLevel,
        extensionId: String,
        profileId: UUID? = nil
    ) {
        guard let manager = managerIfEnabled() else { return }
        let resolvedProfileId =
            profileId
            ?? manager.currentProfileId
            ?? runtime.currentProfile()?.id
        guard let resolvedProfileId else { return }
        manager.setDefaultSiteAccess(
            access,
            extensionId: extensionId,
            profileId: resolvedProfileId
        )
    }

    func setPrivateBrowsingAccess(
        _ isAllowed: Bool,
        extensionId: String,
        profileId: UUID? = nil
    ) {
        guard let manager = managerIfEnabled() else { return }
        let resolvedProfileId =
            profileId
            ?? manager.currentProfileId
            ?? runtime.currentProfile()?.id
        guard let resolvedProfileId else { return }
        manager.setPrivateBrowsingAccess(
            isAllowed,
            extensionId: extensionId,
            profileId: resolvedProfileId
        )
    }

    func setConfiguredSiteAccess(
        _ access: SafariExtensionSiteAccessLevel,
        extensionId: String,
        profileId: UUID? = nil,
        matchPatternString: String
    ) {
        guard let manager = managerIfEnabled() else { return }
        let resolvedProfileId =
            profileId
            ?? manager.currentProfileId
            ?? runtime.currentProfile()?.id
        guard let resolvedProfileId else { return }
        manager.setConfiguredSiteAccess(
            access,
            extensionId: extensionId,
            profileId: resolvedProfileId,
            matchPatternString: matchPatternString
        )
    }

    @discardableResult
    func requestExtensionRuntime(
        reason: ExtensionManager.ExtensionRuntimeRequestReason
    ) -> WKWebExtensionController? {
        managerIfEnabled()?.requestExtensionRuntime(reason: reason)
    }

    func getExtensionContext(
        for extensionId: String
    ) -> WKWebExtensionContext? {
        managerIfLoadedAndEnabled()?.getExtensionContext(for: extensionId)
    }

    func openOptionsPage(
        extensionId: String,
        profileId: UUID? = nil
    ) async {
        guard let manager = managerIfEnabled() else { return }
        let resolvedProfileId =
            profileId
            ?? manager.currentProfileId
            ?? runtime.currentProfile()?.id
        guard let resolvedProfileId else {
            return
        }
        let context: WKWebExtensionContext?
        do {
            context = try await manager.ensureExtensionLoaded(
                extensionId: extensionId,
                profileId: resolvedProfileId
            )
        } catch {
            RuntimeDiagnostics.debug(category: "Extensions") {
                "Unable to load extension context for options page \(extensionId): \(error.localizedDescription)"
            }
            return
        }
        guard let context else {
            RuntimeDiagnostics.debug(category: "Extensions") {
                "Extension context was unavailable for options page \(extensionId)"
            }
            return
        }

        await withCheckedContinuation { continuation in
            manager.presentOptionsPageWindow(for: context) { error in
                if let error {
                    RuntimeDiagnostics.debug(category: "Extensions") {
                        "Unable to open extension options for \(extensionId): \(error.localizedDescription)"
                    }
                }
                continuation.resume()
            }
        }
    }

    func openActionPopupFromURLHub(
        extensionId: String,
        currentTab: Tab?
    ) async -> BrowserExtensionActionPopupRequestResult {
        guard isEnabled else {
            return .blocked(
                .moduleDisabled,
                message: "The Extensions module is disabled."
            )
        }
        guard let manager = managerIfEnabled() else {
            return .blocked(
                .runtimeUnavailable,
                message: "Sumi could not create the local extension manager for this action popup."
            )
        }
        transferPendingActionAnchors(to: manager)
        return await manager.openActionPopupFromURLHub(
            extensionId: extensionId,
            currentTab: currentTab
        )
    }

    func stableAdapter(for tab: Tab) -> ExtensionTabAdapter? {
        managerIfLoadedAndEnabled()?.adapterResolutionOwner.stableAdapter(for: tab)
    }

    func setActionAnchorIfLoaded(for extensionId: String, anchorView: NSView) {
        storePendingActionAnchor(for: extensionId, anchorView: anchorView)
        managerIfLoadedAndEnabled()?.actionAnchorStore.setAnchor(
            for: extensionId,
            anchorView: anchorView
        )
    }

    @discardableResult
    func captureActionPopupAnchor(
        extensionId: String,
        windowId: UUID,
        profileId: UUID?
    ) -> UUID {
        managerIfEnabled()?.actionPopupAnchorResolutionOwner.captureActionPopupAnchor(
            extensionId: extensionId,
            windowId: windowId,
            profileId: profileId
        ) ?? UUID()
    }

    func cancelNativeMessagingSessionsIfLoaded(reason: String) {
        cachedManager?.cancelNativeMessagingSessions(reason: reason)
    }

    func closeAllOptionsWindowsIfLoaded() {
        cachedManager?.optionsWindowOwner.closeAllWindows()
    }

    private func storePendingActionAnchor(
        for extensionId: String,
        anchorView: NSView
    ) {
        var anchors = pendingActionAnchors[extensionId] ?? []
        anchors.removeAll { $0.view == nil || $0.view === anchorView }
        anchors.append(WeakAnchor(view: anchorView, window: anchorView.window))
        pendingActionAnchors[extensionId] = Array(anchors.suffix(8))
    }

    private func transferPendingActionAnchors(to manager: ExtensionManager) {
        for (extensionId, anchors) in pendingActionAnchors {
            for anchor in anchors {
                guard let view = anchor.view else { continue }
                manager.actionAnchorStore.setAnchor(for: extensionId, anchorView: view)
            }
        }
    }

    /// Boots the profile-scoped `WKWebExtensionController` for normal-tab WebViews when
    /// persisted extensions are enabled. Does not require extension contexts to be loaded.
    private func managerIfNeededForNormalTabRuntime() -> ExtensionManager? {
        guard isEnabled, hasEnabledPersistedExtensions() else { return nil }
        return managerIfEnabled()
    }

    private func hasEnabledPersistedExtensions() -> Bool {
        guard let context else { return false }
        // Runs on the hot normal-tab WebView provisioning path (eager extension-controller
        // provisioning), so push the `isEnabled` filter into the store and count rather than
        // materializing every ExtensionEntity and scanning in memory.
        let descriptor = FetchDescriptor<ExtensionEntity>(
            predicate: #Predicate { $0.isEnabled }
        )
        do {
            return try context.fetchCount(descriptor) > 0
        } catch {
            RuntimeDiagnostics.debug(category: "Extensions") {
                "Could not count enabled persisted extensions: \(error.localizedDescription)"
            }
            return false
        }
    }

    #if DEBUG
        func drainSafariContentBlockerRuntimeForTests(cancel: Bool = false) async {
            await safariContentBlockerRuntimeOwner.drainRuntimeForTests(cancel: cancel)
        }
    #endif

    private func tearDownLoadedRuntime(reason: String) {
        guard let cachedManager else {
            surfaceStore.bind(nil)
            return
        }

        let tabsToRebuild = cachedManager.tabsAffectedByLoadedUserExtensionRuntime()
        cachedManager.tearDownExtensionRuntime(
            reason: reason,
            removeUIState: true,
            releaseController: true
        )
        surfaceStore.bind(nil)
        cachedManager.rebuildLiveWebViewsAfterUserExtensionRuntimeTeardown(
            tabsToRebuild,
            reason: reason
        )
        self.cachedManager = nil
    }

    #if DEBUG
    /// Prints the acceptance matrix to stdout (Extensions menu, DEBUG builds).
    func printSafariExtensionAcceptanceCheckToConsole() {
        guard isEnabled else {
            print("SafariExtensionAcceptanceMatrix: skipped — Extensions module is disabled")
            return
        }

        let matrix = safariExtensionAcceptanceMatrix()
        let json: String
        do {
            json = try SafariExtensionDiagnosticJSON.prettyPrintedString(matrix)
        } catch {
            print("SafariExtensionAcceptanceMatrix: encode failed: \(error.localizedDescription)")
            return
        }

        print("SafariExtensionAcceptanceMatrix:\n\(json)")
        SafariExtensionAcceptanceMatrixBuilder.logIfDiagnosticsEnabled(matrix)
    }
    #endif
}
