import AppKit
import Foundation
import SwiftData
import WebKit

@MainActor
final class SumiExtensionsModule {
    static let shared = SumiExtensionsModule()

    private let moduleRegistry: SumiModuleRegistry
    private let context: ModelContext?
    private let browserConfiguration: BrowserConfiguration
    private let initialProfileProvider: @MainActor () -> Profile?
    private let managerFactory: @MainActor (
        ModelContext,
        Profile?,
        BrowserConfiguration
    ) -> ExtensionManager

    let surfaceStore: BrowserExtensionSurfaceStore

    private var cachedManager: ExtensionManager?
    private var pendingActionAnchors: [String: [WeakAnchor]] = [:]
    private var safariContentBlockerService: SumiContentBlockingService?
    private var safariContentBlockerServiceCacheKey: String?
    private var safariContentBlockerSiteOverrides: [String: SumiSafariContentBlockerSiteOverride]
    weak var browserManager: BrowserManager?

    init(
        moduleRegistry: SumiModuleRegistry = .shared,
        context: ModelContext? = nil,
        browserConfiguration: BrowserConfiguration? = nil,
        initialProfileProvider: @escaping @MainActor () -> Profile? = { nil },
        managerFactory: @escaping @MainActor (
            ModelContext,
            Profile?,
            BrowserConfiguration
        ) -> ExtensionManager = {
            ExtensionManager(
                context: $0,
                initialProfile: $1,
                browserConfiguration: $2
            )
        },
        surfaceStore: BrowserExtensionSurfaceStore? = nil
    ) {
        self.moduleRegistry = moduleRegistry
        self.context = context
        self.browserConfiguration = browserConfiguration ?? .shared
        self.initialProfileProvider = initialProfileProvider
        self.managerFactory = managerFactory
        self.surfaceStore = surfaceStore ?? BrowserExtensionSurfaceStore(
            extensionManager: nil
        )
        self.safariContentBlockerSiteOverrides = Self.loadSafariContentBlockerSiteOverrides(
            from: moduleRegistry.userDefaults
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

    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager
        cachedManager?.attach(browserManager: browserManager)
        ensureActionSurfaceMetadataLoadedIfNeeded()
    }

    func setEnabled(_ isEnabled: Bool) {
        moduleRegistry.setEnabled(isEnabled, for: .extensions)
        if isEnabled == false {
            tearDownLoadedRuntime(reason: "SumiExtensionsModule.setEnabled(false)")
            clearSafariContentBlockerRuntime()
            pendingActionAnchors.removeAll()
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
            browserManager?.currentProfile ?? initialProfileProvider(),
            browserConfiguration
        )
        cachedManager = manager
        if let browserManager {
            manager.attach(browserManager: browserManager)
        }
        transferPendingActionAnchors(to: manager)
        surfaceStore.bind(manager)
        return manager
    }

    @discardableResult
    func ensureActionSurfaceMetadataLoadedIfNeeded() -> Bool {
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

    func prepareWebViewConfigurationForExtensionRuntime(
        _ configuration: WKWebViewConfiguration,
        profileId: UUID? = nil,
        reason: String
    ) {
        managerIfNeededForNormalTabRuntime()?.prepareWebViewConfigurationForExtensionRuntime(
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

    func ensureInitialDocumentExtensionContextsLoadedIfNeeded(profileId: UUID) async {
        guard isEnabled else { return }
        await managerIfNeededForNormalTabRuntime()?
            .ensureInitialDocumentExtensionContextsLoaded(for: profileId)
    }

    func needsInitialDocumentExtensionContextLoadIfNeeded(profileId: UUID) -> Bool {
        guard isEnabled else { return false }
        return managerIfNeededForNormalTabRuntime()?
            .profileNeedsInitialDocumentExtensionContextLoad(profileId: profileId)
            ?? false
    }

    func consumeRecentlyOpenedExtensionTabRequestIfLoaded(for url: URL) -> Bool {
        managerIfLoadedAndEnabled()?.consumeRecentlyOpenedExtensionTabRequest(
            for: url
        ) ?? false
    }

    func recordRecentlyOpenedExtensionTabRequestIfLoaded(for url: URL?) {
        managerIfLoadedAndEnabled()?.recordRecentlyOpenedExtensionTabRequest(for: url)
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
        SafariExtensionImportStore.shared.removeImportedRecord(
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
        SafariExtensionImportStore.shared.markImported(
            candidate: candidate,
            installedExtensionId: installed.id
        )
        return installed
    }

    func installedSafariContentBlockers() -> [InstalledSafariContentBlockerRecord] {
        guard let context else { return [] }
        do {
            return try context.fetch(FetchDescriptor<SafariContentBlockerEntity>())
                .map(InstalledSafariContentBlockerRecord.init)
                .sorted {
                    if $0.containingAppName == $1.containingAppName {
                        return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                    }
                    return $0.containingAppName.localizedCaseInsensitiveCompare($1.containingAppName) == .orderedAscending
                }
        } catch {
            return []
        }
    }

    func safariContentBlockerRecord(
        forBundleIdentifier bundleIdentifier: String
    ) -> InstalledSafariContentBlockerRecord? {
        installedSafariContentBlockers().first {
            $0.extensionBundleIdentifier == bundleIdentifier
        }
    }

    func enableSafariContentBlocker(
        from candidate: DiscoveredSafariExtensionCandidate
    ) async throws -> InstalledSafariContentBlockerRecord {
        guard candidate.bundleKind == .contentBlocker else {
            throw ExtensionError.installationFailed(
                "Only Safari Content Blocker bundles can be enabled as content blockers."
            )
        }
        guard isEnabled, let context else {
            throw ExtensionError.unsupportedOS
        }

        let locatedRules: SafariContentBlockerLocatedRules
        do {
            locatedRules = try SafariContentBlockerRuleLocator.locateRules(in: candidate)
        } catch let error as SafariContentBlockerRuleLocatorError {
            _ = try upsertSafariContentBlockerEntity(
                from: candidate,
                resourceFingerprint: SafariContentBlockerRuleLocator.resourceFingerprint(
                    appexURL: candidate.appexURL
                ),
                isEnabled: false,
                compileStatus: error.persistedCompileStatus,
                lastError: error.localizedDescription,
                ruleListCount: 0,
                ignoredEmptyRuleListCount: 0
            )
            try context.save()
            clearSafariContentBlockerRuntime()
            throw ExtensionError.installationFailed(error.localizedDescription)
        }

        let validationService = SumiContentBlockingService(policy: .disabled)
        do {
            let preparedUpdate = try await validationService.prepareRuleListUpdate(
                ruleLists: locatedRules.definitions,
                retainEncodedRuleListsInPreparedPolicy: false
            )
            validationService.commitPreparedContentBlockingUpdate(preparedUpdate)
        } catch {
            _ = try upsertSafariContentBlockerEntity(
                from: candidate,
                resourceFingerprint: locatedRules.resourceFingerprint,
                isEnabled: false,
                compileStatus: .compileFailed,
                lastError: error.localizedDescription,
                ruleListCount: locatedRules.definitions.count,
                ignoredEmptyRuleListCount: locatedRules.ignoredEmptyRuleListCount
            )
            try context.save()
            clearSafariContentBlockerRuntime()
            throw ExtensionError.installationFailed(error.localizedDescription)
        }

        let entity = try upsertSafariContentBlockerEntity(
            from: candidate,
            resourceFingerprint: locatedRules.resourceFingerprint,
            isEnabled: true,
            compileStatus: .available,
            lastError: nil,
            ruleListCount: locatedRules.definitions.count,
            ignoredEmptyRuleListCount: locatedRules.ignoredEmptyRuleListCount
        )
        try context.save()
        clearSafariContentBlockerRuntime()
        return InstalledSafariContentBlockerRecord(entity: entity)
    }

    func setSafariContentBlockerEnabled(
        _ enabled: Bool,
        bundleIdentifier: String
    ) async throws -> InstalledSafariContentBlockerRecord? {
        guard let context else { return nil }
        guard let entity = try safariContentBlockerEntity(
            forBundleIdentifier: bundleIdentifier
        ) else {
            return nil
        }
        if enabled {
            let candidate = DiscoveredSafariExtensionCandidate(
                extensionBundleIdentifier: entity.extensionBundleIdentifier,
                displayName: entity.displayName,
                version: entity.version,
                extensionPointIdentifier: SafariExtensionScanner.safariContentBlockerExtensionPointIdentifier,
                bundleKind: .contentBlocker,
                runtimeStatus: .contentBlockerImportable,
                containingAppName: entity.containingAppName,
                containingAppBundleIdentifier: entity.containingAppBundleIdentifier,
                containingAppURL: URL(fileURLWithPath: entity.containingAppPath, isDirectory: true),
                appexURL: URL(fileURLWithPath: entity.appexPath, isDirectory: true),
                manifestURL: nil,
                isReadable: true
            )
            return try await enableSafariContentBlocker(from: candidate)
        }

        entity.isEnabled = false
        entity.lastUpdateDate = Date()
        try context.save()
        clearSafariContentBlockerRuntime()
        return InstalledSafariContentBlockerRecord(entity: entity)
    }

    func enabledSafariContentBlockingServices(
        for url: URL?,
        profileId: UUID?
    ) -> [SumiContentBlockingService] {
        _ = profileId
        guard isEnabled,
              safariContentBlockerAttachmentState(for: url).isEnabled,
              let context
        else { return [] }

        let enabledRecords = installedSafariContentBlockers()
            .filter { $0.isEnabled && $0.compileStatus == .available }
        guard enabledRecords.isEmpty == false else { return [] }

        var definitions: [SumiContentRuleListDefinition] = []
        var cacheParts: [String] = []
        for record in enabledRecords {
            let appexURL = URL(fileURLWithPath: record.appexPath, isDirectory: true)
            do {
                let located = try SafariContentBlockerRuleLocator.locateRules(
                    appexURL: appexURL,
                    extensionBundleIdentifier: record.extensionBundleIdentifier,
                    displayName: record.displayName
                )
                definitions.append(contentsOf: located.definitions)
                cacheParts.append("\(record.id):\(located.resourceFingerprint):\(located.definitions.count)")
                if located.resourceFingerprint != record.resourceFingerprint,
                   let entity = try? safariContentBlockerEntity(
                       forBundleIdentifier: record.extensionBundleIdentifier
                   )
                {
                    entity.resourceFingerprint = located.resourceFingerprint
                    entity.ruleListCount = located.definitions.count
                    entity.ignoredEmptyRuleListCount = located.ignoredEmptyRuleListCount
                    entity.lastUpdateDate = Date()
                    try? context.save()
                }
            } catch {
                continue
            }
        }

        guard definitions.isEmpty == false else { return [] }
        let cacheKey = cacheParts.sorted().joined(separator: "|")
        if let safariContentBlockerService,
           safariContentBlockerServiceCacheKey == cacheKey
        {
            return [safariContentBlockerService]
        }

        let service = SumiContentBlockingService(
            policy: .enabled(ruleLists: definitions)
        )
        safariContentBlockerService = service
        safariContentBlockerServiceCacheKey = cacheKey
        return [service]
    }

    func safariContentBlockerAttachmentState(
        for url: URL?
    ) -> SumiSafariContentBlockerAttachmentState {
        let siteHost = Self.normalizedSiteHost(for: url)
        guard isEnabled else {
            return .disabled(siteHost: siteHost)
        }

        let enabledRecords = installedSafariContentBlockers()
            .filter { $0.isEnabled && $0.compileStatus == .available }
        guard enabledRecords.isEmpty == false,
              let siteHost
        else {
            return .disabled(siteHost: siteHost)
        }
        let siteOverride = safariContentBlockerSiteOverrides[siteHost] ?? .inherit
        return SumiSafariContentBlockerAttachmentState(
            siteHost: siteHost,
            isEnabledForSite: siteOverride != .disabled,
            enabledContentBlockerIds: enabledRecords.map(\.id).sorted()
        )
    }

    func safariContentBlockerSiteState(
        for url: URL?
    ) -> SumiSafariContentBlockerSiteState {
        let siteHost = Self.normalizedSiteHost(for: url)
        let siteOverride = siteHost.flatMap { safariContentBlockerSiteOverrides[$0] } ?? .inherit
        guard isEnabled else {
            return SumiSafariContentBlockerSiteState(
                siteHost: siteHost,
                isGloballyAvailable: false,
                isEnabledForSite: siteOverride != .disabled,
                enabledContentBlockerCount: 0
            )
        }

        let enabledRecords = installedSafariContentBlockers()
            .filter { $0.isEnabled && $0.compileStatus == .available }
        return SumiSafariContentBlockerSiteState(
            siteHost: siteHost,
            isGloballyAvailable: !enabledRecords.isEmpty,
            isEnabledForSite: siteOverride != .disabled,
            enabledContentBlockerCount: enabledRecords.count
        )
    }

    func safariContentBlockerAttachedRuleListIdentifiers() -> [String] {
        safariContentBlockerService?.latestRuleListIdentifiers ?? []
    }

    func setSafariContentBlockerSiteOverride(
        _ override: SumiSafariContentBlockerSiteOverride,
        for url: URL?
    ) {
        guard let host = Self.normalizedSiteHost(for: url) else { return }
        var updated = safariContentBlockerSiteOverrides
        if override == .inherit {
            updated.removeValue(forKey: host)
        } else {
            updated[host] = override
        }
        guard updated != safariContentBlockerSiteOverrides else { return }
        safariContentBlockerSiteOverrides = updated
        Self.persistSafariContentBlockerSiteOverrides(
            updated,
            to: moduleRegistry.userDefaults
        )
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
        browserManager?.tabStructuralRevision &+= 1
    }

    func unpinFromToolbar(_ extensionId: String) {
        managerIfEnabled()?.unpinFromToolbar(extensionId)
        browserManager?.tabStructuralRevision &+= 1
    }

    func siteAccessPolicy(
        extensionId: String,
        profileId: UUID? = nil
    ) -> SafariExtensionSiteAccessPolicy? {
        guard let manager = managerIfEnabled() else { return nil }
        let resolvedProfileId =
            profileId
            ?? manager.currentProfileId
            ?? browserManager?.currentProfile?.id
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
            ?? browserManager?.currentProfile?.id
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
            ?? browserManager?.currentProfile?.id
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
            ?? browserManager?.currentProfile?.id
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
            ?? browserManager?.currentProfile?.id
        guard let resolvedProfileId,
              let context = try? await manager.ensureExtensionLoaded(
                  extensionId: extensionId,
                  profileId: resolvedProfileId
              )
        else {
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
        managerIfLoadedAndEnabled()?.stableAdapter(for: tab)
    }

    func setActionAnchorIfLoaded(for extensionId: String, anchorView: NSView) {
        storePendingActionAnchor(for: extensionId, anchorView: anchorView)
        managerIfLoadedAndEnabled()?.setActionAnchor(
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
        managerIfEnabled()?.captureActionPopupAnchor(
            extensionId: extensionId,
            windowId: windowId,
            profileId: profileId
        ) ?? UUID()
    }

    func cancelNativeMessagingSessionsIfLoaded(reason: String) {
        cachedManager?.cancelNativeMessagingSessions(reason: reason)
    }

    func closeAllOptionsWindowsIfLoaded() {
        cachedManager?.closeAllOptionsWindows()
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
                manager.setActionAnchor(for: extensionId, anchorView: view)
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
        do {
            return try context.fetch(FetchDescriptor<ExtensionEntity>())
                .contains { $0.isEnabled }
        } catch {
            return false
        }
    }

    private func safariContentBlockerEntity(
        forBundleIdentifier bundleIdentifier: String
    ) throws -> SafariContentBlockerEntity? {
        guard let context else { return nil }
        return try context.fetch(FetchDescriptor<SafariContentBlockerEntity>())
            .first { $0.extensionBundleIdentifier == bundleIdentifier }
    }

    private func upsertSafariContentBlockerEntity(
        from candidate: DiscoveredSafariExtensionCandidate,
        resourceFingerprint: String,
        isEnabled: Bool,
        compileStatus: SafariContentBlockerCompileStatus,
        lastError: String?,
        ruleListCount: Int,
        ignoredEmptyRuleListCount: Int
    ) throws -> SafariContentBlockerEntity {
        guard let context else {
            throw ExtensionError.unsupportedOS
        }

        if let existing = try safariContentBlockerEntity(
            forBundleIdentifier: candidate.extensionBundleIdentifier
        ) {
            existing.displayName = candidate.displayName
            existing.version = candidate.version
            existing.containingAppName = candidate.containingAppName
            existing.containingAppBundleIdentifier = candidate.containingAppBundleIdentifier
            existing.appexPath = candidate.appexURL.path
            existing.containingAppPath = candidate.containingAppURL.path
            existing.resourceFingerprint = resourceFingerprint
            existing.isEnabled = isEnabled
            existing.lastUpdateDate = Date()
            existing.compileStatus = compileStatus
            existing.lastError = lastError
            existing.ruleListCount = ruleListCount
            existing.ignoredEmptyRuleListCount = ignoredEmptyRuleListCount
            return existing
        }

        let entity = SafariContentBlockerEntity(
            id: candidate.extensionBundleIdentifier,
            extensionBundleIdentifier: candidate.extensionBundleIdentifier,
            displayName: candidate.displayName,
            version: candidate.version,
            containingAppName: candidate.containingAppName,
            containingAppBundleIdentifier: candidate.containingAppBundleIdentifier,
            appexPath: candidate.appexURL.path,
            containingAppPath: candidate.containingAppURL.path,
            resourceFingerprint: resourceFingerprint,
            isEnabled: isEnabled,
            compileStatus: compileStatus,
            lastError: lastError,
            ruleListCount: ruleListCount,
            ignoredEmptyRuleListCount: ignoredEmptyRuleListCount
        )
        context.insert(entity)
        return entity
    }

    private func clearSafariContentBlockerRuntime() {
        safariContentBlockerService = nil
        safariContentBlockerServiceCacheKey = nil
    }

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

    private static let safariContentBlockerSiteOverridesDefaultsKey =
        "\(SumiAppIdentity.bundleIdentifier).extensions.safariContentBlocker.siteOverrides.v1"

    private static func normalizedSiteHost(for url: URL?) -> String? {
        SumiSiteNormalizer().normalizedHost(for: url)
    }

    private static func loadSafariContentBlockerSiteOverrides(
        from defaults: UserDefaults
    ) -> [String: SumiSafariContentBlockerSiteOverride] {
        guard let data = defaults.data(forKey: safariContentBlockerSiteOverridesDefaultsKey),
              let raw = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return raw.reduce(into: [:]) { result, entry in
            guard let override = SumiSafariContentBlockerSiteOverride(rawValue: entry.value),
                  override != .inherit
            else { return }
            result[entry.key] = override
        }
    }

    private static func persistSafariContentBlockerSiteOverrides(
        _ overrides: [String: SumiSafariContentBlockerSiteOverride],
        to defaults: UserDefaults
    ) {
        let raw = overrides.mapValues(\.rawValue)
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: safariContentBlockerSiteOverridesDefaultsKey)
        }
    }

    #if DEBUG
    /// Prints the acceptance matrix to stdout (Extensions menu, DEBUG builds).
    func printSafariExtensionAcceptanceCheckToConsole() {
        guard isEnabled else {
            print("SafariExtensionAcceptanceMatrix: skipped — Extensions module is disabled")
            return
        }

        let matrix = safariExtensionAcceptanceMatrix()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let data = try? encoder.encode(matrix),
              let json = String(data: data, encoding: .utf8)
        else {
            print("SafariExtensionAcceptanceMatrix: encode failed")
            return
        }

        print("SafariExtensionAcceptanceMatrix:\n\(json)")
        SafariExtensionAcceptanceMatrixBuilder.logIfDiagnosticsEnabled(matrix)
    }
    #endif
}

private extension SafariContentBlockerRuleLocatorError {
    var persistedCompileStatus: SafariContentBlockerCompileStatus {
        switch self {
        case .resourcesDirectoryMissing, .staticRulesUnavailable:
            return .rulesUnavailable
        case .invalidJSON, .invalidRuleListShape:
            return .compileFailed
        }
    }
}
