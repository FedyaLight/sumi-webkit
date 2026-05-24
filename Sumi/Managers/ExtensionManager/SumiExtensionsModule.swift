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
    private let chromeMV3EmptyControllerOwnerFactory: @MainActor (
        ChromeMV3ControllerCreationGateDecision,
        WKWebsiteDataStore,
        UUID
    ) -> ChromeMV3EmptyControllerOwner?

    let surfaceStore: BrowserExtensionSurfaceStore

    private var cachedManager: ExtensionManager?
    private var cachedChromeMV3EmptyControllerOwner:
        ChromeMV3EmptyControllerOwner?
    weak var browserManager: BrowserManager?
    #if DEBUG
        var chromeMV3InternalNormalTabConfigurationAttachmentAllowed = false
    #endif

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
        chromeMV3EmptyControllerOwnerFactory: @escaping @MainActor (
            ChromeMV3ControllerCreationGateDecision,
            WKWebsiteDataStore,
            UUID
        ) -> ChromeMV3EmptyControllerOwner? = {
            ChromeMV3EmptyControllerFactory.makeOwner(
                gateDecision: $0,
                defaultWebsiteDataStore: $1,
                controllerIdentifier: $2
            )
        },
        surfaceStore: BrowserExtensionSurfaceStore? = nil
    ) {
        self.moduleRegistry = moduleRegistry
        self.context = context
        self.browserConfiguration = browserConfiguration ?? .shared
        self.initialProfileProvider = initialProfileProvider
        self.managerFactory = managerFactory
        self.chromeMV3EmptyControllerOwnerFactory =
            chromeMV3EmptyControllerOwnerFactory
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
            tearDownChromeMV3EmptyControllerOwner()
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

    func chromeMV3ProfileHostIfEnabled(
        candidateRewrittenVariants: [ChromeMV3RewrittenVariantCandidate] = []
    ) -> ChromeMV3ProfileHost? {
        guard isEnabled else { return nil }

        return makeChromeMV3ProfileHost(
            candidateRewrittenVariants: candidateRewrittenVariants
        ).host
    }

    func chromeMV3InventoryDiagnosticsIfEnabled(
        rootURL: URL
    ) -> ChromeMV3ProfileHostDiagnostics? {
        guard isEnabled else { return nil }

        let inventory = ChromeMV3CandidateInventoryReader()
            .readInventory(rootURL: rootURL)
        let candidates = inventory.candidates.map(\.profileHostCandidate)
        return chromeMV3ProfileHostIfEnabled(
            candidateRewrittenVariants: candidates
        )?.diagnostics(candidateInventory: inventory)
    }

    func chromeMV3ControllerCreationGateDecisionIfEnabled(
        explicitControllerCreationAllowed: Bool,
        requestedContextLoading: Bool = false,
        requestedNormalTabAttachment: Bool = false,
        candidateRewrittenVariants: [ChromeMV3RewrittenVariantCandidate] = []
    ) -> ChromeMV3ControllerCreationGateDecision? {
        guard isEnabled else { return nil }

        let host = makeChromeMV3ProfileHost(
            candidateRewrittenVariants: candidateRewrittenVariants
        ).host
        return host.controllerCreationGateDecision(
            extensionsModuleEnabled: true,
            explicitControllerCreationAllowed: explicitControllerCreationAllowed,
            requestedContextLoading: requestedContextLoading,
            requestedNormalTabAttachment: requestedNormalTabAttachment
        )
    }

    @discardableResult
    func createChromeMV3EmptyControllerOwnerIfEnabled(
        explicitControllerCreationAllowed: Bool,
        candidateRewrittenVariants: [ChromeMV3RewrittenVariantCandidate] = []
    ) -> ChromeMV3EmptyControllerOwner? {
        guard isEnabled else { return nil }

        let profileHost = makeChromeMV3ProfileHost(
            candidateRewrittenVariants: candidateRewrittenVariants
        )
        let decision = profileHost.host.controllerCreationGateDecision(
            extensionsModuleEnabled: true,
            explicitControllerCreationAllowed: explicitControllerCreationAllowed
        )

        guard decision.canCreateControllerNow else {
            return nil
        }

        if let cachedChromeMV3EmptyControllerOwner {
            return cachedChromeMV3EmptyControllerOwner
        }

        guard let profile = profileHost.profile else {
            return nil
        }

        let owner = chromeMV3EmptyControllerOwnerFactory(
            decision,
            profile.dataStore,
            profile.id
        )
        cachedChromeMV3EmptyControllerOwner = owner
        return owner
    }

    func chromeMV3EmptyControllerDiagnosticsIfEnabled(
        explicitControllerCreationAllowed: Bool,
        candidateRewrittenVariants: [ChromeMV3RewrittenVariantCandidate] = []
    ) -> ChromeMV3EmptyControllerDiagnostics? {
        guard isEnabled else { return nil }

        if let cachedChromeMV3EmptyControllerOwner {
            return cachedChromeMV3EmptyControllerOwner.diagnostics()
        }

        guard let decision = chromeMV3ControllerCreationGateDecisionIfEnabled(
            explicitControllerCreationAllowed: explicitControllerCreationAllowed,
            candidateRewrittenVariants: candidateRewrittenVariants
        ) else {
            return nil
        }

        return ChromeMV3EmptyControllerDiagnostics.notCreated(
            gateDecision: decision
        )
    }

    func chromeMV3ControllerDataStoreIdentityDiagnosticsIfEnabled(
        explicitControllerCreationAllowed: Bool,
        candidateRewrittenVariants: [ChromeMV3RewrittenVariantCandidate] = []
    ) -> ChromeMV3ControllerDataStoreIdentityDiagnostics? {
        guard isEnabled else { return nil }

        if let cachedChromeMV3EmptyControllerOwner {
            return cachedChromeMV3EmptyControllerOwner.diagnostics()
                .dataStoreIdentityPolicy
        }

        guard let decision = chromeMV3ControllerCreationGateDecisionIfEnabled(
            explicitControllerCreationAllowed: explicitControllerCreationAllowed,
            candidateRewrittenVariants: candidateRewrittenVariants
        ) else {
            return nil
        }

        return ChromeMV3ControllerDataStoreIdentityPolicy.evaluate(
            profileIdentifier: decision.input.profileIdentifier,
            dataStoreIdentity: decision.input.profileDataStoreIdentity,
            controllerCreated: false
        )
    }

    func chromeMV3ControllerAttachmentPreflightIfEnabled(
        surface: ChromeMV3WebViewSurface,
        runtimePreflight: ChromeMV3RuntimePreflightResult? = nil,
        explicitControllerCreationAllowed: Bool = false,
        candidateRewrittenVariants: [ChromeMV3RewrittenVariantCandidate] = []
    ) -> ChromeMV3ControllerAttachmentPreflight? {
        guard isEnabled else { return nil }

        let profileHost = makeChromeMV3ProfileHost(
            candidateRewrittenVariants: candidateRewrittenVariants
        ).host
        let eligibility = ChromeMV3WebViewEligibilityPolicy.evaluate(
            surface: surface,
            extensionModuleEnabled: profileHost.isActive,
            profileHostActive: profileHost.isActive
        )
        let controllerDiagnostics =
            chromeMV3EmptyControllerDiagnosticsIfEnabled(
                explicitControllerCreationAllowed:
                    explicitControllerCreationAllowed,
                candidateRewrittenVariants: candidateRewrittenVariants
            )

        return ChromeMV3ControllerAttachmentPreflightEvaluator.evaluate(
            surface: surface,
            eligibility: eligibility,
            controllerDiagnostics: controllerDiagnostics,
            runtimePreflight: runtimePreflight,
            moduleState: profileHost.moduleState
        )
    }

    #if DEBUG
        @available(macOS 15.5, *)
        func chromeMV3NormalTabConfigurationAttachmentRequestIfEnabled(
            explicitInternalNormalTabAttachmentAllowed: Bool,
            surface: ChromeMV3WebViewSurface = .normalTab,
            requestedContextLoading: Bool = false,
            canLoadContextNow: Bool = false,
            runtimeLoadable: Bool = false,
            candidateRewrittenVariants: [ChromeMV3RewrittenVariantCandidate] = []
        ) -> ChromeMV3NormalTabConfigurationAttachmentRequest? {
            guard isEnabled else { return nil }

            let profileHost = makeChromeMV3ProfileHost(
                candidateRewrittenVariants: candidateRewrittenVariants
            ).host
            return ChromeMV3NormalTabConfigurationAttachmentRequest(
                owner: cachedChromeMV3EmptyControllerOwner,
                extensionsModuleEnabled: true,
                profileHostEnabled: profileHost.isActive,
                explicitInternalNormalTabAttachmentAllowed:
                    explicitInternalNormalTabAttachmentAllowed,
                surface: surface,
                requestedContextLoading: requestedContextLoading,
                canLoadContextNow: canLoadContextNow,
                runtimeLoadable: runtimeLoadable
            )
        }

        @available(macOS 15.5, *)
        func chromeMV3NormalTabConfigurationAttachmentRequestForLiveNormalTabIfEnabled(
            surface: ChromeMV3WebViewSurface
        ) -> ChromeMV3NormalTabConfigurationAttachmentRequest? {
            chromeMV3NormalTabConfigurationAttachmentRequestIfEnabled(
                explicitInternalNormalTabAttachmentAllowed:
                    chromeMV3InternalNormalTabConfigurationAttachmentAllowed,
                surface: surface
            )
        }
    #endif

    @discardableResult
    func tearDownChromeMV3EmptyControllerOwnerIfEnabled(
        trigger: ChromeMV3EmptyControllerTeardownTrigger
    ) -> ChromeMV3EmptyControllerDiagnostics? {
        guard isEnabled else { return nil }
        guard let cachedChromeMV3EmptyControllerOwner else {
            guard let decision =
                chromeMV3ControllerCreationGateDecisionIfEnabled(
                    explicitControllerCreationAllowed: false
                )
            else {
                return nil
            }
            return ChromeMV3EmptyControllerDiagnostics.notCreated(
                gateDecision: decision
            )
        }

        let diagnostics = cachedChromeMV3EmptyControllerOwner.tearDown(
            trigger: trigger
        )
        self.cachedChromeMV3EmptyControllerOwner = nil
        return diagnostics
    }

    func normalTabUserScripts() -> [SumiUserScript] {
        managerIfNeededForNormalTabRuntime()?.normalTabUserScripts() ?? []
    }

    func prepareWebViewConfigurationForExtensionRuntime(
        _ configuration: WKWebViewConfiguration,
        reason: String
    ) {
        managerIfNeededForNormalTabRuntime()?.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
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

    func closeAllOptionsWindowsIfLoaded() {
        cachedManager?.closeAllOptionsWindows()
    }

    private func managerIfNeededForNormalTabRuntime() -> ExtensionManager? {
        guard isEnabled else { return nil }

        if let cachedManager {
            return cachedManager.hasEnabledInstalledExtensions ? cachedManager : nil
        }

        guard hasEnabledPersistedExtensions() else { return nil }
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

    private func tearDownChromeMV3EmptyControllerOwner() {
        cachedChromeMV3EmptyControllerOwner?.tearDown(trigger: .moduleDisable)
        cachedChromeMV3EmptyControllerOwner = nil
    }

    private func makeChromeMV3ProfileHost(
        candidateRewrittenVariants: [ChromeMV3RewrittenVariantCandidate]
    ) -> (host: ChromeMV3ProfileHost, profile: Profile?) {
        let profile = browserManager?.currentProfile ?? initialProfileProvider()
        let profileIdentifier = profile?.id.uuidString
            ?? ChromeMV3ProfileHost.unresolvedProfileIdentifier
        let dataStoreIdentity: ChromeMV3ProfileDataStoreIdentity
        if let profile {
            dataStoreIdentity = profile.isEphemeral
                ? .ephemeralProfileIdentifier(profile.id.uuidString)
                : .profileIdentifier(profile.id.uuidString)
        } else {
            dataStoreIdentity = .unresolved
        }

        return (
            ChromeMV3ProfileHost(
                profileIdentifier: profileIdentifier,
                extensionsEnabled: true,
                profileDataStoreIdentity: dataStoreIdentity,
                candidateRewrittenVariants: candidateRewrittenVariants
            ),
            profile
        )
    }
}
