import AppKit
import Foundation
import SwiftData
import UserScript
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
    weak var browserManager: BrowserManager?

    init(
        moduleRegistry: SumiModuleRegistry = .shared,
        context: ModelContext? = nil,
        browserConfiguration: BrowserConfiguration? = nil,
        initialProfileProvider: @escaping @MainActor () -> Profile? = { nil },
        // Explicit injection seam for focused tests; production constructs lazily only when enabled.
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

    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager
        cachedManager?.attach(browserManager: browserManager)
    }

    func setEnabled(_ isEnabled: Bool) {
        moduleRegistry.setEnabled(isEnabled, for: .extensions)
        if isEnabled == false {
            tearDownLoadedRuntime(reason: "SumiExtensionsModule.setEnabled(false)")
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
        surfaceStore.bind(manager)
        return manager
    }

    func normalTabUserScripts() -> [UserScript] {
        managerIfEnabled()?.normalTabUserScripts() ?? []
    }

    func prepareWebViewConfigurationForExtensionRuntime(
        _ configuration: WKWebViewConfiguration,
        reason: String
    ) {
        managerIfEnabled()?.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            reason: reason
        )
    }

    func prepareWebViewForExtensionRuntime(
        _ webView: WKWebView,
        currentURL: URL?,
        reason: String
    ) {
        managerIfEnabled()?.prepareWebViewForExtensionRuntime(
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

    func discoverSafariExtensions() async -> [SafariExtensionInfo] {
        guard let manager = managerIfEnabled() else { return [] }
        return await manager.discoverSafariExtensions()
    }

    func installSafariExtension(
        _ info: SafariExtensionInfo,
        completionHandler: @escaping (Result<InstalledExtension, ExtensionError>) -> Void
    ) {
        guard let manager = managerIfEnabled() else {
            completionHandler(.failure(.unsupportedOS))
            return
        }
        manager.installSafariExtension(info, completionHandler: completionHandler)
    }

    func enableExtension(_ extensionId: String) async throws -> InstalledExtension {
        guard let manager = managerIfEnabled() else {
            throw ExtensionError.unsupportedOS
        }
        return try await manager.enableExtension(extensionId)
    }

    func disableExtension(_ extensionId: String) async throws {
        guard let manager = managerIfEnabled() else { return }
        try await manager.disableExtension(extensionId)
    }

    func uninstallExtension(_ extensionId: String) async throws {
        guard let manager = managerIfEnabled() else { return }
        try await manager.uninstallExtension(extensionId)
    }

    func showExtensionInstallDialog() {
        managerIfEnabled()?.showExtensionInstallDialog()
    }

    func orderedPinnedToolbarSlots(
        enabledExtensions: [InstalledExtension],
        sumiScriptsManagerEnabled: Bool
    ) -> [PinnedToolbarSlot] {
        managerIfLoadedAndEnabled()?.orderedPinnedToolbarSlots(
            enabledExtensions: enabledExtensions,
            sumiScriptsManagerEnabled: sumiScriptsManagerEnabled
        ) ?? []
    }

    func isPinnedToToolbar(_ extensionId: String) -> Bool {
        managerIfLoadedAndEnabled()?.isPinnedToToolbar(extensionId) ?? false
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

    func stableAdapter(for tab: Tab) -> ExtensionTabAdapter? {
        managerIfLoadedAndEnabled()?.stableAdapter(for: tab)
    }

    func setActionAnchorIfLoaded(for extensionId: String, anchorView: NSView) {
        managerIfLoadedAndEnabled()?.setActionAnchor(
            for: extensionId,
            anchorView: anchorView
        )
    }

    func cancelNativeMessagingSessionsIfLoaded(reason: String) {
        cachedManager?.cancelNativeMessagingSessions(reason: reason)
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
}
