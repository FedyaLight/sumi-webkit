//
//  Tab.swift
//  Sumi
//
//

import AppKit
import Combine
import Foundation
import Navigation
import SumiDomain
import SumiWebRuntime
import WebKit

@MainActor
public class Tab: NSObject, Identifiable, ObservableObject {
    public typealias LoadingState = TabLoadingState
    public let id: UUID
    /// Presentation/persistence URL. Navigation authority is advanced only by
    /// explicit commands or exact WebKit lifecycle identities, never by an
    /// incidental model assignment.
    @Published public var url: URL
    @Published var name: String
    /// Model-neutral favicon representation; the UI layer maps this to `SwiftUI.Image`
    /// (see `Sumi/Components/TabFaviconPresentation+Image.swift`).
    @Published var faviconPresentation: TabFaviconPresentation
    /// True while the tab shows the SF Symbol ``globe`` fallback (no bitmap favicon yet / resolver miss).
    @Published var faviconIsTemplateGlobePlaceholder: Bool = false
    private var placementState = TabPlacementState()
    private var surfaceState = TabSurfaceState()
    var spaceId: UUID? {
        get { placementState.spaceId }
        set { placementState.spaceId = newValue }
    }
    var index: Int {
        get { placementState.index }
        set { placementState.index = newValue }
    }
    let profileAssignment = TabProfileAssignmentStateMachine()
    var profileId: UUID? {
        get { profileAssignment.currentProfileID }
        set { _ = profileAssignment.replaceCurrentProfileID(newValue) }
    }
    // If true, this tab is created to host a popup window; do not perform initial load.
    var isPopupHost: Bool {
        get { surfaceState.isPopupHost }
        set { surfaceState.isPopupHost = newValue }
    }
    // If true, this tab hosts content in a compact auxiliary mini-window (not in sidebar).
    var isAuxiliaryMiniWindow: Bool {
        get { surfaceState.isAuxiliaryMiniWindow }
        set { surfaceState.isAuxiliaryMiniWindow = newValue }
    }

    let stateChangeEmitter = TabStateChangeEmitter()
    let navigationRuntime = TabNavigationRuntime()
    let mediaRuntime = TabMediaRuntime()
    private var retainedFaviconRuntime: TabFaviconRuntime?
    var faviconRuntime: TabFaviconRuntime {
        if let retainedFaviconRuntime {
            return retainedFaviconRuntime
        }
        let runtime = TabFaviconRuntime()
        retainedFaviconRuntime = runtime
        return runtime
    }
    var hasMaterializedFaviconRuntime: Bool {
        retainedFaviconRuntime != nil
    }
    let profileResolutionOwner = TabProfileResolutionOwner()
    let extensionPageRuntimeOwner = TabExtensionPageRuntimeOwner()
    public let webViewSession: WebViewSessionHandle
    private let mainFrameRuntimeTransaction: TabMainFrameRuntimeTransaction
    let mainFrameLoads: any TabMainFrameLoads
    let mainFrameSubmission: any TabMainFrameSubmissionSettlement
    /// Read by recovery routing as a fail-closed marker status. Recovery
    /// admission itself is callback-local in the lifecycle responder.
    let webContentRecoveryMarkers: any TabWebContentRecoveryMarkerQuery
    let webContentRecoveryAdmission: any TabWebContentRecoveryAdmission
    let webViewRebuildEpoch = TabWebViewRebuildEpoch()
    let committedDocumentRuntime: TabCommittedDocumentRuntime
    let webViewConfigurationOwner = TabWebViewConfigurationOwner()
    var cachedNormalTabCoreUserScripts: [SumiPageScript]?
    var cachedNormalTabCoreUserScriptsGPCEnabled: Bool?
    var cachedNormalTabCoreUserScriptsMemoryMode: SumiMemoryMode?
    let normalWebViewSetup = TabNormalWebViewSetupService()
    let webViewProvisioningOwner = TabWebViewProvisioningOwner()
    let webViewRetirementLedger = TabWebViewRetirementLedger()
    private let closeLifecycleOwner = TabCloseLifecycleOwner()
    let navigationCommandOwner = TabNavigationCommandOwner()
    lazy var profileWebViewCreationGate = TabProfileWebViewCreationGate(
        tab: self,
        currentProfileUpdates: { [weak self] in
            self?.browserRuntimeReference.runtime.currentProfileUpdates()
        }
    )
    lazy var ownedWebViewPreparationOwner = TabOwnedWebViewPreparationOwner(
        dependencies: .live(tab: self)
    )
    var suspensionState = TabSuspensionState()
    var lastSelectedAt: Date?
    lazy var permissionSurfaceOwner = TabPermissionSurfaceOwner(context: .live(tab: self))
    lazy var webKitUIDelegateOwner = TabWebKitUIDelegateOwner(tab: self)
    lazy var webKitPermissionUIDelegateOwner = TabWebKitPermissionUIDelegateOwner(tab: self)
    private var browserRuntimeReference = TabBrowserRuntimeReference(.inactive)
    private var browserRuntimeAttached = false
    var linkPresentationCommands: TabLinkPresentationCommands {
        browserRuntimeReference.runtime.linkPresentationCommands
    }
    var webPageMenuCommands: TabWebPageMenuCommands {
        browserRuntimeReference.runtime.webPageMenuCommands
    }
    private let dependencyStateOwner: TabDependencyStateOwner

    // MARK: - Pin State
    var isPinned: Bool {
        get { placementState.isPinned }
        set { placementState.isPinned = newValue }
    }
    var isSpacePinned: Bool {
        get { placementState.isSpacePinned }
        set { placementState.isSpacePinned = newValue }
    }
    var folderId: UUID? {
        get { placementState.folderId }
        set { placementState.folderId = newValue }
    }
    var shortcutPinId: UUID? {
        get { placementState.shortcutPinId }
        set { placementState.shortcutPinId = newValue }
    }
    var shortcutPinRole: ShortcutPinRole? {
        get { placementState.shortcutPinRole }
        set { placementState.shortcutPinRole = newValue }
    }
    var isShortcutLiveInstance: Bool {
        get { placementState.isShortcutLiveInstance }
        set { placementState.isShortcutLiveInstance = newValue }
    }

    // MARK: - Ephemeral State
    /// Whether this tab belongs to an ephemeral/incognito session
    public var isEphemeral: Bool {
        resolveProfile()?.isEphemeral ?? false
    }

    var loadingState: LoadingState {
        get { navigationRuntime.loadingState }
        set {
            guard navigationRuntime.loadingState != newValue else { return }
            let oldIsLoading = navigationRuntime.loadingState.isLoading
            objectWillChange.send()
            navigationRuntime.loadingState = newValue
            guard oldIsLoading != newValue.isLoading else { return }
            stateChangeEmitter.postLoadingStateDidChange(for: self)
        }
    }

    func beginLoadingPresentationIfNeeded() {
        guard !loadingState.isLoading else { return }
        loadingState = .didStartProvisionalNavigation
    }

    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false

    /// Typed browser-owned failure surface for a durable page whose persisted
    /// destination cannot be admitted. This must never be represented as an
    /// empty `about:blank` page.
    var isRestoreFailure = false
    var restoreFailureDestination: URL?
    var restoreFailureRawDestination: String?

    // Restored navigation state from undo/session restoration (applied when web view is created)
    var restoredCanGoBack: Bool? {
        get { navigationRuntime.restoredCanGoBack }
        set { navigationRuntime.restoredCanGoBack = newValue }
    }
    var restoredCanGoForward: Bool? {
        get { navigationRuntime.restoredCanGoForward }
        set { navigationRuntime.restoredCanGoForward = newValue }
    }

    // MARK: - Audio State
    @Published var audioState: SumiWebViewAudioState = .unmuted(isPlayingAudio: false)
    // MARK: - Rename State
    @Published var isRenaming: Bool = false
    @Published var editingName: String = ""

    var profileAwaitCancellable: AnyCancellable?
    let findInPage = FindInPageTabExtension()

    // MARK: - Tab State
    private(set) var websiteDataMutationPresentation: (
        sessionID: UUID,
        destination: URL
    )?

    var isUnloaded: Bool {
        resolvedCurrentWebView() == nil
    }

    func beginWebsiteDataMutationPresentation(
        sessionID: UUID,
        destination: URL
    ) {
        if let current = websiteDataMutationPresentation,
           current.sessionID == sessionID {
            return
        }
        websiteDataMutationPresentation = (sessionID, destination)
        publishPagePresentationChangeForOwnedWebViews()
    }

    func endWebsiteDataMutationPresentation(sessionID: UUID) {
        guard websiteDataMutationPresentation?.sessionID == sessionID else {
            return
        }
        websiteDataMutationPresentation = nil
        publishPagePresentationChangeForOwnedWebViews()
    }

    private func publishPagePresentationChangeForOwnedWebViews() {
        objectWillChange.send()
        for webView in webViewSession.allKnownWebViews {
            navigationRuntime.webViewRouting.pagePresentationDidChange(id, webView)
        }
    }

    /// True when the tab row should show the web-content-unloaded favicon affordance.
    /// Sumi-native tabs (settings UI, empty new-tab surface) never host a primary-frame WKWebView for that UI, so they must not look “unloaded”.
    var showsWebViewUnloadedIndicator: Bool {
        requiresPrimaryWebView && isUnloaded
    }

    var webViewConfigurationOverride: WKWebViewConfiguration? {
        get { webViewConfigurationOwner.webViewConfigurationOverride }
        set { webViewConfigurationOwner.webViewConfigurationOverride = newValue }
    }
    var webExtensionContextOverride: WKWebExtensionContext? {
        get { webViewConfigurationOwner.webExtensionContextOverride }
        set { webViewConfigurationOwner.webExtensionContextOverride = newValue }
    }
    let configurationPolicyLedger = TabConfigurationPolicyLedger()
    lazy var configurationPolicyTransaction =
        TabConfigurationPolicyTransaction(
            policyLedger: configurationPolicyLedger,
            webViewSession: webViewSession
        )
    lazy var safariContentBlockerReloadState =
        SafariContentBlockerReloadState(
            policyLedger: configurationPolicyLedger
        )
    lazy var protectionReloadState = ProtectionReloadState(
        policyLedger: configurationPolicyLedger
    )
    let autoplayReloadState = AutoplayReloadState()
    let configurationPolicyRebuildService =
        TabConfigurationPolicyRebuildService()

    func makeMainFrameLifecycleResponder() -> SumiTabLifecycleNavigationResponder {
        SumiTabLifecycleNavigationResponder(
            tab: self,
            submission: mainFrameRuntimeTransaction,
            lifecycle: mainFrameRuntimeTransaction,
            promotion: mainFrameRuntimeTransaction,
            recovery: mainFrameRuntimeTransaction
        )
    }

    func makeAuthenticationNavigationResponder()
        -> SumiTabAuthenticationNavigationResponder {
        SumiTabAuthenticationNavigationResponder(tab: self)
    }

    @discardableResult
    func beginMainFrameNavigationIntent(to targetURL: URL) -> TabMainFrameNavigationIntent {
        let blankAdmission = targetURL.isSumiBlankDocumentURL
            ? BlankDocumentAdmission(
                id: UUID(),
                source: .explicitUserCommand
            )
            : nil
        let intent = mainFrameRuntimeTransaction.beginExplicitIntent(
            to: targetURL,
            blankAdmission: blankAdmission
        )
        for webView in webViewSession.allKnownWebViews {
            guard let host = webView.sumiReaderPresentationHost,
                  host.tabID == id,
                  host.webView === webView else {
                continue
            }
            host.dismissReader()
        }
        return intent
    }

    @discardableResult
    func webViewDidLeaveNavigationRuntime(
        _ webView: WKWebView
    ) -> TabMainFrameRuntimeDepartureResult {
        let preferredWebView = resolvedCurrentWebView().flatMap {
            $0 === webView ? nil : $0
        }
        return webViewsDidLeaveNavigationRuntime(
            [webView],
            preferredAuthorityWebView: preferredWebView
        )
    }

    /// Retires a complete physical generation before any member is destroyed.
    /// Authority is reduced and replayed once after the whole set has departed.
    @discardableResult
    func webViewsDidLeaveNavigationRuntime(
        _ webViews: [WKWebView],
        preferredAuthorityWebView: WKWebView?
    ) -> TabMainFrameRuntimeDepartureResult {
        var seen: Set<ObjectIdentifier> = []
        let departingWebViews = webViews.filter {
            seen.insert(ObjectIdentifier($0)).inserted
        }
        departingWebViews.forEach {
            navigationRuntime.webViewRouting.cancelWebContentProcessRecovery($0)
            navigationDelegateBundle(for: $0)?.cancelPendingNavigationDecisions()
        }
        let result = mainFrameRuntimeTransaction.webViewsDidLeaveRuntime(
            departingWebViews,
            preferredAuthorityWebView: preferredAuthorityWebView
        )
        departingWebViews.forEach {
            unbindAudioState(from: $0)
            removeNavigationStateObservers(from: $0)
            removeNavigationDelegateBundle(for: $0)
        }
        if let continuation = result.continuation {
            TabMainFrameLifecycleReducer.replayIfNeeded(
                continuation,
                tab: self,
                promotion: mainFrameRuntimeTransaction
            )
        }
        return result
    }

    func abortMainFrameNavigation(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        rollsBackWhenUnreplaced: Bool = true
    ) -> TabMainFrameNavigationAbortResult {
        let result = mainFrameRuntimeTransaction.abortNavigation(
            from: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            survivingCommittedURL: webView.committedURL,
            rollsBackWhenUnreplaced: rollsBackWhenUnreplaced
        )
        if case .authoritativeRollback(let rollbackURL) = result {
            _ = webViewRebuildEpoch.advance()
            url = rollbackURL
        }
        return result
    }

    func beginMainFrameLifecycle(
        from webView: WKWebView,
        navigationID: ObjectIdentifier?,
        navigationLifetime: AnyObject,
        targetURL: URL?,
        blankAdmission: BlankDocumentAdmission? = nil,
        allowsUserInitiatedSupersession: Bool,
        continuationKind: TabMainFrameContinuationKind?
    ) -> TabMainFrameLifecycleRole {
        let acceptance = mainFrameRuntimeTransaction.beginLifecycle(
            from: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            targetURL: targetURL,
            blankAdmission: blankAdmission,
            allowsUserInitiatedSupersession: allowsUserInitiatedSupersession,
            continuationKind: continuationKind
        )
        if acceptance.beganNewIntent {
            _ = webViewRebuildEpoch.advance()
        }
        return acceptance.role
    }

    @discardableResult
    func applyPromotedAuthorityURL(
        _ targetURL: URL,
        matching continuation: TabMainFrameAuthorityContinuation
    ) -> Bool {
        guard continuation.hasCommittedDocument else { return false }
        guard mainFrameRuntimeTransaction.acceptPromotedAuthorityTarget(
            targetURL,
            matching: continuation
        ) else { return false }
        url = targetURL
        return true
    }

    @discardableResult
    func applyAcceptedMainFrameLifecycleURL(
        _ targetURL: URL,
        from webView: WKWebView,
        navigationID: ObjectIdentifier?
    ) -> Bool {
        guard mainFrameRuntimeTransaction.acceptLifecycleTarget(
            targetURL,
            from: webView,
            navigationID: navigationID
        ) else { return false }
        url = targetURL
        return true
    }

    func cancelMainFrameNavigationIntent() {
        _ = mainFrameRuntimeTransaction.rollbackToDurableDocument()
    }

    func rollbackMainFrameNavigationAfterFailedSubmission(
        on webView: WKWebView?,
        matching intent: TabMainFrameNavigationIntent? = nil
    ) {
        if let intent, mainFrameLoads.isCurrent(intent) == false {
            return
        }
        var survivingWebViews = webViewSession.allKnownWebViews
        if let webView,
           survivingWebViews.contains(where: { $0 === webView }) == false {
            survivingWebViews.append(webView)
        }
        let rollback = mainFrameRuntimeTransaction.rollbackAfterFailedSubmission(
            survivingWebViews: survivingWebViews
        )
        let rollbackURL = rollback.targetURL
        _ = webViewRebuildEpoch.advance()
        url = rollbackURL
        if loadingState.isLoading {
            loadingState = .idle
        }
        applyCachedFaviconOrPlaceholder(for: rollbackURL)
        refreshFaviconExtensionCache()
        if let navigationStateSource = rollback.navigationStateSource {
            updateNavigationState(from: navigationStateSource)
        } else if let webView,
                  let committedURL = webView.committedURL,
                  WebRuntimeNavigationIdentity(committedURL)
                    == WebRuntimeNavigationIdentity(rollbackURL) {
            updateNavigationState(from: webView)
        } else {
            updateNavigationState()
        }
        stateChangeEmitter.postNavigationStateDidChange(for: self)
        navigationRuntime.persistenceCallbacks.scheduleRuntimeStatePersistence(self)
        navigationRuntime.extensionPropertiesRuntime.notifyTabPropertiesChanged(
            self,
            [.URL, .loading]
        )
    }

    var hasBrowserRuntime: Bool {
        browserRuntimeAttached
    }

    func makeWebViewConfigurationContext() -> TabWebViewConfigurationContext {
        browserRuntimeReference.runtime.webViewConfigurationContext()
    }

    func attachBrowserRuntime(_ runtime: TabBrowserRuntime) {
        attachBrowserRuntime(TabBrowserRuntimeReference(runtime))
    }

    func attachBrowserRuntime(_ runtimeReference: TabBrowserRuntimeReference) {
        browserRuntimeReference = runtimeReference
        browserRuntimeAttached = true
        let runtime = runtimeReference.runtime
        navigationRuntime.attach(browserRuntime: runtimeReference)
        mediaRuntime.attach(browserRuntime: runtimeReference)
        normalWebViewSetup.attach(
            to: self,
            installation: runtime.untrackedWebViewInstallation
        )
        navigationRuntime.webViewRouting.bindWebViewSession(webViewSession)
        sumiSettings = runtime.settings()
    }

    var sumiSettings: SumiSettingsService? {
        get { dependencyStateOwner.sumiSettings }
        set { dependencyStateOwner.sumiSettings = newValue }
    }

    var faviconService: any BrowserFaviconServicing {
        dependencyStateOwner.faviconService
    }

    var faviconCapabilities: BrowserFaviconCapabilities {
        dependencyStateOwner.faviconCapabilities
    }

    var visitedLinkStore: any BrowserVisitedLinkStoreManaging {
        dependencyStateOwner.visitedLinkStore
    }

    private var navigationStateController: TabNavigationStateController {
        navigationRuntime.navigationStateController
    }

    var isLoading: Bool {
        loadingState.isLoading
    }

    var representsSumiEmptySurface: Bool {
        !isRestoreFailure && surfaceState.representsSumiEmptySurface(for: url)
    }

    var representsSumiHistorySurface: Bool {
        surfaceState.representsSumiHistorySurface(for: url)
    }

    var representsSumiBookmarksSurface: Bool {
        surfaceState.representsSumiBookmarksSurface(for: url)
    }

    /// Native Sumi surfaces rendered outside WebKit.
    var representsSumiNativeSurface: Bool {
        surfaceState.representsSumiNativeSurface(for: url)
    }

    /// Internal Sumi surfaces that use chrome-template presentation.
    var representsSumiInternalSurface: Bool {
        surfaceState.representsSumiInternalSurface(for: url)
    }

    public var requiresPrimaryWebView: Bool {
        !isRestoreFailure && surfaceState.requiresPrimaryWebView(for: url)
    }

    /// Sidebar / split tab row: tint template SF Symbol favicons like `NavButtonStyle` (`tokens.primaryText`).
    /// Covers empty tab, internal Sumi surfaces, and the ordinary ``globe`` placeholder until a bitmap favicon loads.
    var usesChromeThemedTemplateFavicon: Bool {
        surfaceState.usesChromeThemedTemplateFavicon(
            for: url,
            faviconIsTemplateGlobePlaceholder: faviconIsTemplateGlobePlaceholder
        )
    }

    // MARK: - Initializers
    init(
        id: UUID = UUID(),
        url: URL = SumiSurface.emptyTabURL,
        name: String = "New Tab",
        favicon: String = "globe",
        spaceId: UUID? = nil,
        index: Int = 0,
        existingWebView: WKWebView? = nil,
        webViewSessions: WebViewSessionRepository? = nil,
        loadsCachedFaviconOnInit: Bool = true,
        faviconService: any BrowserFaviconServicing = TabDependencyIsolationDefaults.faviconService,
        faviconCapabilities: BrowserFaviconCapabilities = TabDependencyIsolationDefaults.faviconCapabilities,
        visitedLinkStore: any BrowserVisitedLinkStoreManaging = TabDependencyIsolationDefaults.visitedLinkStore,
        mainFrameRuntimeTransaction injectedMainFrameRuntimeTransaction:
            TabMainFrameRuntimeTransaction? = nil
    ) {
        self.id = id
        self.url = url
        let mainFrameRuntimeTransaction = injectedMainFrameRuntimeTransaction
            ?? TabMainFrameRuntimeTransaction(initialURL: url)
        precondition(
            mainFrameRuntimeTransaction.mainFrameLoads.currentIntent
                == TabMainFrameNavigationIntent(revision: 0, targetURL: url),
            "Tab requires a pristine main-frame transaction for its initial URL"
        )
        self.mainFrameRuntimeTransaction = mainFrameRuntimeTransaction
        self.mainFrameLoads = mainFrameRuntimeTransaction.mainFrameLoads
        self.mainFrameSubmission = mainFrameRuntimeTransaction
        self.webContentRecoveryMarkers = mainFrameRuntimeTransaction
        self.webContentRecoveryAdmission = mainFrameRuntimeTransaction
        self.committedDocumentRuntime =
            mainFrameRuntimeTransaction.committedDocumentRuntime
        self.name = name
        self.faviconPresentation = .systemSymbol(favicon)
        self.faviconIsTemplateGlobePlaceholder = (favicon == "globe")
        if let webViewSessions {
            self.webViewSession = WebViewSessionHandle(
                tabID: id,
                repository: webViewSessions
            )
        } else {
            self.webViewSession = WebViewSessionHandle(tabID: id)
        }
        self.dependencyStateOwner = TabDependencyStateOwner(
            faviconService: faviconService,
            faviconCapabilities: faviconCapabilities,
            visitedLinkStore: visitedLinkStore
        )
        super.init()
        committedDocumentRuntime.attachSuspensionEffects(self)
        self.spaceId = spaceId
        self.index = index
        navigationStateController.delegate = self
        parkExistingWebView(existingWebView)

        if loadsCachedFaviconOnInit {
            applyCachedFaviconOrPlaceholder(for: url)
        } else {
            applyFaviconPlaceholderWithoutCache(for: url)
        }
    }

    func parkExistingWebView(_ webView: WKWebView?) {
        webViewSession.park(webView)
    }

    func clearParkedExistingWebView() {
        webViewSession.clearParked()
    }

    public func clearCurrentWebViewOwnership() {
        webViewSession.clearUntracked()
    }

    public func clearAllWebViewOwnership() {
        webViewSession.clearDetachedOwnership()
    }

    @discardableResult
    func clearCurrentWebViewOwnershipIfIdentical(to webView: WKWebView) -> Bool {
        webViewSession.clearUntracked(ifIdenticalTo: webView)
    }

    func bindToShortcutPin(_ pin: ShortcutPin) {
        placementState.bindToShortcutPin(id: pin.id, role: pin.role)
    }

    func clearShortcutBinding() {
        placementState.clearShortcutBinding()
    }

    // MARK: - Tab Actions
    func closeTab() {
        closeLifecycleOwner.close(context: .live(tab: self))
    }

    deinit {
        // AnyCancellable cancels on deallocation, so deinit does not need to reach into
        // main-actor runtime buckets just to tear down deferred observers.
        RuntimeDiagnostics.debug("Tab deinit cleanup completed.", category: "Tab")
    }

    // MARK: - Rename Methods
    func startRenaming() {
        isRenaming = true
        editingName = name
    }

    func saveRename() {
        if !editingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        isRenaming = false
        editingName = ""
    }

    func cancelRename() {
        isRenaming = false
        editingName = ""
    }

    func loadWebViewIfNeeded(preferredViewportSize: CGSize? = nil) {
        if !hasCurrentWebView {
            beginSuspendedRestoreIfNeeded()
            let webView = ensureUntrackedNormalWebView(
                reason: "Tab.loadWebViewIfNeeded"
            )
            if let preferredViewportSize,
               preferredViewportSize.width > 0,
               preferredViewportSize.height > 0 {
                webView?.setFrameSize(preferredViewportSize)
            }
        }
    }

    func publishNavigationStateChangeIfNeeded(_ didChange: Bool) {
        guard didChange else { return }
        stateChangeEmitter.publishNavigationStateDidChange(for: self)
    }

    func noteAccess(at date: Date = Date()) {
        lastSelectedAt = date
    }

    func beginSuspendedRestoreIfNeeded() {
        suspensionState.beginRestoreIfNeeded(
            residenceGeneration: webViewSession.generation
        )
    }

    func markSuspended(
        sessionSnapshots: [PageSessionSnapshot] = [],
        at date: Date = Date()
    ) {
        objectWillChange.send()
        suspensionState.markSuspended(
            url: url,
            snapshots: sessionSnapshots
        )
        cachedNormalTabCoreUserScripts = nil
        cachedNormalTabCoreUserScriptsGPCEnabled = nil
        cachedNormalTabCoreUserScriptsMemoryMode = nil
        retainedFaviconRuntime = nil
        if lastSelectedAt == nil {
            lastSelectedAt = date
        }
        resetPlaybackActivity()
        loadingState = .idle
        stateChangeEmitter.postLifecycleDidChange(for: self)
    }

    @discardableResult
    func commitSuspendedRestoreIfMatching(
        webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> Bool {
        guard suspensionState.commit(
            webViewID: ObjectIdentifier(webView),
            navigationID: navigationID
        ) else { return false }
        objectWillChange.send()
        stateChangeEmitter.postLifecycleDidChange(for: self)
        return true
    }

    func cancelSuspendedRestoreIfNeeded() {
        guard suspensionState.isRestoreInProgress else { return }
        objectWillChange.send()
        suspensionState.cancelRestore()
        stateChangeEmitter.postLifecycleDidChange(for: self)
    }

    // MARK: - Navigation State Observation

    /// Set up KVO observers for navigation state properties
    func setupNavigationStateObservers(for webView: WKWebView) {
        navigationStateController.observe(webView)
    }

    /// Remove KVO observers for navigation state properties
    func removeNavigationStateObservers(from webView: WKWebView) {
        navigationStateController.remove(webView)
    }
}

// MARK: - Hashable & Equatable
extension Tab {
    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? Tab else { return false }
        return self.id == other.id
    }

    public override var hash: Int {
        id.hashValue
    }
}
