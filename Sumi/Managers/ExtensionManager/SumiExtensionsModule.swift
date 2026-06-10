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
    }

    func setEnabled(_ isEnabled: Bool) {
        moduleRegistry.setEnabled(isEnabled, for: .extensions)
        if isEnabled == false {
            tearDownLoadedRuntime(reason: "SumiExtensionsModule.setEnabled(false)")
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

    func releaseExternallyConnectableRuntimeIfLoaded(
        for webView: WKWebView,
        reason: String
    ) {
        cachedManager?.releaseExternallyConnectableRuntime(
            for: webView,
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

    func consumeRecentlyOpenedExtensionTabRequestIfLoaded(for url: URL) -> Bool {
        managerIfLoadedAndEnabled()?.consumeRecentlyOpenedExtensionTabRequest(
            for: url
        ) ?? false
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

    func importSafariAppExtension(
        from candidate: DiscoveredSafariExtensionCandidate
    ) async throws -> InstalledExtension {
        guard let manager = managerIfEnabled() else {
            throw ExtensionError.unsupportedOS
        }

        let installed = try await manager.performInstallation(
            from: candidate.appexURL,
            enableOnInstall: false
        )
        SafariExtensionImportStore.shared.markImported(
            candidate: candidate,
            installedExtensionId: installed.id
        )

        do {
            return try await manager.enableExtension(installed.id)
        } catch {
            try? await manager.disableExtension(installed.id)
            throw ExtensionError.importSucceededEnableFailed(
                "\(installed.name) was imported but could not be enabled: \(error.localizedDescription)"
            )
        }
    }

    func orderedPinnedToolbarSlots(
        enabledExtensions: [InstalledExtension],
        sumiScriptsManagerEnabled: Bool
    ) -> [PinnedToolbarSlot] {
        if let manager = managerIfLoadedAndEnabled() {
            return manager.orderedPinnedToolbarSlots(
                enabledExtensions: enabledExtensions,
                sumiScriptsManagerEnabled: sumiScriptsManagerEnabled
            )
        }

        var slots: [PinnedToolbarSlot] = []
        if sumiScriptsManagerEnabled {
            slots.append(.sumiScriptsManager)
        }
        slots.append(
            contentsOf: enabledExtensions
                .filter(\.isEnabled)
                .filter(\.hasAction)
                .map { .webExtension($0) }
        )
        return slots
    }

    func isPinnedToToolbar(_ extensionId: String) -> Bool {
        managerIfLoadedAndEnabled()?.isPinnedToToolbar(extensionId) ?? true
    }

    func pinToToolbar(_ extensionId: String) {
        managerIfEnabled()?.pinToToolbar(extensionId)
    }

    func unpinFromToolbar(_ extensionId: String) {
        managerIfEnabled()?.unpinFromToolbar(extensionId)
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

    private func tearDownLoadedRuntime(reason: String) {
        guard let cachedManager else {
            surfaceStore.bind(nil)
            return
        }

        cachedManager.tearDownExtensionRuntime(
            reason: reason,
            removeUIState: true,
            releaseController: true
        )
        self.cachedManager = nil
        surfaceStore.bind(nil)
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
