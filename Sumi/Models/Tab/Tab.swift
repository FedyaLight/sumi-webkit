//
//  Tab.swift
//  Sumi
//
//

import AppKit
import Combine
import Foundation
import SumiDomain
import WebKit
import SumiWebRuntime

@MainActor
public class Tab: NSObject, Identifiable, ObservableObject {
    public typealias LoadingState = TabLoadingState
    public let id: UUID
    public var url: URL
    @Published var name: String
    /// Model-neutral favicon representation; the UI layer maps this to `SwiftUI.Image`
    /// (see `Sumi/Components/TabFaviconPresentation+Image.swift`).
    @Published var faviconPresentation: TabFaviconPresentation
    /// True while the tab shows the SF Symbol ``globe`` fallback (no bitmap favicon yet / resolver miss).
    @Published var faviconIsTemplateGlobePlaceholder: Bool = false
    private let placementStateOwner = TabPlacementStateOwner()
    private let surfaceStateOwner = TabSurfaceStateOwner()
    var spaceId: UUID? {
        get { placementStateOwner.spaceId }
        set { placementStateOwner.spaceId = newValue }
    }
    var index: Int {
        get { placementStateOwner.index }
        set { placementStateOwner.index = newValue }
    }
    var profileId: UUID?
    // If true, this tab is created to host a popup window; do not perform initial load.
    var isPopupHost: Bool {
        get { surfaceStateOwner.isPopupHost }
        set { surfaceStateOwner.isPopupHost = newValue }
    }
    // If true, this tab hosts content in a compact auxiliary mini-window (not in sidebar).
    var isAuxiliaryMiniWindow: Bool {
        get { surfaceStateOwner.isAuxiliaryMiniWindow }
        set { surfaceStateOwner.isAuxiliaryMiniWindow = newValue }
    }

    // Track the current click modifiers for native popup/link routing fallback.
    var clickModifierFlags: NSEvent.ModifierFlags {
        get { webViewInteractionStateOwner.clickModifierFlags }
        set { webViewInteractionStateOwner.clickModifierFlags = newValue }
    }
    let stateChangeEmitter = TabStateChangeEmitter()
    let navigationRuntime = TabNavigationRuntime()
    let mediaRuntime = TabMediaRuntime()
    let popupUserActivationTracker = SumiPopupUserActivationTracker()
    let faviconRuntime = TabFaviconRuntime()
    let profileResolutionOwner = TabProfileResolutionOwner()
    let extensionPageRuntimeOwner = TabExtensionPageRuntimeOwner()
    lazy var webViewOwnershipOwner = TabWebViewOwnershipOwner(tabId: id)
    private let webViewRuntime = TabWebViewRuntime()
    let webViewConfigurationOwner = TabWebViewConfigurationOwner()
    let normalWebViewSetupOwner = TabNormalWebViewSetupOwner()
    let webViewProvisioningOwner = TabWebViewProvisioningOwner()
    lazy var normalWebViewRuntimeContextOwner = TabNormalWebViewRuntimeContextOwner(tab: self)
    private let closeLifecycleOwner = TabCloseLifecycleOwner()
    let webViewReplacementContextOwner =
        TabWebViewReplacementContextOwner()
    let navigationCommandOwner = TabNavigationCommandOwner()
    lazy var profileWebViewCreationGate = TabProfileWebViewCreationGate(
        tab: self,
        currentProfileUpdates: { [weak self] in
            self?.browserRuntime.currentProfileUpdates()
        }
    )
    lazy var ownedWebViewPreparationOwner = TabOwnedWebViewPreparationOwner(
        dependencies: .live(tab: self)
    )
    let suspensionStateOwner = TabSuspensionStateOwner()
    private let webViewInteractionStateOwner = TabWebViewInteractionStateOwner()
    lazy var permissionSurfaceOwner = TabPermissionSurfaceOwner(context: .live(tab: self))
    lazy var webKitUIDelegateOwner = TabWebKitUIDelegateOwner(tab: self)
    lazy var webKitPermissionUIDelegateOwner = TabWebKitPermissionUIDelegateOwner(tab: self)
    lazy var scriptMessageRuntimeOwner = TabScriptMessageRuntimeOwner(tab: self)
    private var browserRuntime = TabBrowserRuntime.inactive
    /// Web-page context-menu / bookmark / download UI actions, delegated to whatever owns
    /// the active browser runtime. Callers invoke this directly instead of routing through
    /// per-action forwarders on `Tab` (see `SumiWebPageMenuController`, `SumiWebNotificationUserScript`).
    private(set) var browserActionService = TabBrowserActionService.inactive
    private let dependencyStateOwner: TabDependencyStateOwner

    // MARK: - Pin State
    var isPinned: Bool {
        get { placementStateOwner.isPinned }
        set { placementStateOwner.isPinned = newValue }
    }
    var isSpacePinned: Bool {
        get { placementStateOwner.isSpacePinned }
        set { placementStateOwner.isSpacePinned = newValue }
    }
    var folderId: UUID? {
        get { placementStateOwner.folderId }
        set { placementStateOwner.folderId = newValue }
    }
    var shortcutPinId: UUID? {
        get { placementStateOwner.shortcutPinId }
        set { placementStateOwner.shortcutPinId = newValue }
    }
    var shortcutPinRole: ShortcutPinRole? {
        get { placementStateOwner.shortcutPinRole }
        set { placementStateOwner.shortcutPinRole = newValue }
    }
    var isShortcutLiveInstance: Bool {
        get { placementStateOwner.isShortcutLiveInstance }
        set { placementStateOwner.isShortcutLiveInstance = newValue }
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
            if !newValue.isLoading {
                self.estimatedProgress = 1.0
            }
            guard oldIsLoading != newValue.isLoading else { return }
            stateChangeEmitter.postLoadingStateDidChange(for: self)
        }
    }

    func beginLoadingPresentationIfNeeded() {
        guard !loadingState.isLoading else { return }
        estimatedProgress = 0.05
        loadingState = .didStartProvisionalNavigation
    }

    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false

    /// Owns page-load progress. Kept off `Tab`'s own `@Published` graph so its
    /// high-frequency ticks don't invalidate sidebar rows that observe the whole
    /// `Tab`; only the chrome loading bar subscribes to it. See ``TabLoadingProgress``.
    let loadingProgress = TabLoadingProgress()
    var estimatedProgress: Double {
        get { loadingProgress.estimatedProgress }
        set { loadingProgress.estimatedProgress = newValue }
    }

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

    var profileAwaitCancellable: AnyCancellable? {
        get { webViewRuntime.profileAwaitCancellable }
        set { webViewRuntime.profileAwaitCancellable = newValue }
    }
    var findInPage: FindInPageTabExtension {
        webViewRuntime.findInPage
    }

    // MARK: - Tab State
    var isUnloaded: Bool {
        resolvedCurrentWebView() == nil
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
    var reloadPolicyStateOwner: TabReloadPolicyStateOwner {
        webViewRuntime.reloadPolicyStateOwner
    }

    // MARK: - WebView Ownership Tracking (Memory Optimization)
    // Primary window id is session/registry SoT via routing mutators
    // (`assignPrimaryWebView` / `notePrimaryAssignment`). Use
    // `resolvedPrimaryWindowId()` for Tab-internal reads.
    var lastWebViewInteractionEvent: NSEvent? {
        get { webViewInteractionStateOwner.lastWebViewInteractionEvent }
        set { webViewInteractionStateOwner.lastWebViewInteractionEvent = newValue }
    }
    var webViewInteractionCancellables: [ObjectIdentifier: AnyCancellable] {
        get { webViewInteractionStateOwner.webViewInteractionCancellables }
        set { webViewInteractionStateOwner.webViewInteractionCancellables = newValue }
    }

    var hasBrowserRuntime: Bool {
        browserActionService.hasBrowserRuntime()
    }

    func makeWebViewConfigurationContext() -> TabWebViewConfigurationContext {
        browserRuntime.webViewConfigurationContext()
    }

    func attachBrowserRuntime(_ runtime: TabBrowserRuntime) {
        browserRuntime = runtime
        browserActionService = runtime.browserActionService
        navigationRuntime.webViewRouting = runtime.webViewRoutingRuntime
        navigationRuntime.persistenceCallbacks = runtime.persistenceRuntimeCallbacks
        mediaRuntime.callbacks = runtime.mediaRuntimeCallbacks
        navigationRuntime.navigationCommandRuntime = runtime.navigationCommandRuntime
        navigationRuntime.profileResolutionRuntime = runtime.profileResolutionRuntime
        navigationRuntime.reloadPolicyRuntime = runtime.reloadPolicyRuntime
        navigationRuntime.historySwipeRuntime = runtime.historySwipeRuntime
        navigationRuntime.historyRecordingRuntime = runtime.historyRecordingRuntime
        navigationRuntime.findInPageRuntime = runtime.findInPageRuntime
        navigationRuntime.extensionPropertiesRuntime = runtime.extensionPropertiesRuntime
        navigationRuntime.closeLifecycleRuntime = runtime.closeLifecycleRuntime
        navigationRuntime.lifecycleNavigationRuntime = runtime.lifecycleNavigationRuntime
        navigationRuntime.permissionRuntime = runtime.permissionRuntime
        navigationRuntime.webViewCleanupRuntime = runtime.webViewCleanupRuntime
        navigationRuntime.normalWebViewExtensionRuntime = runtime.normalWebViewExtensionRuntime
        navigationRuntime.scriptMessageRuntime = runtime.scriptMessageRuntime
        navigationRuntime.navigationDelegateRuntime = runtime.navigationDelegateRuntime
        navigationRuntime.faviconExtensionRuntime = runtime.faviconExtensionRuntime
        navigationRuntime.popupHandlingRuntime = runtime.popupHandlingRuntime
        navigationRuntime.installNavigationRuntime = runtime.installNavigationRuntime
        navigationRuntime.webKitUIRuntime = runtime.webKitUIRuntime
        navigationRuntime.webViewReplacementRuntime =
            runtime.webViewReplacementRuntime
        // Promote Tab-local pre-runtime session notes into the coordinator store.
        // adoptLocalSession clears the local slot when the coordinator is bound.
        navigationRuntime.webViewRouting.adoptLocalWebViewSession(
            webViewOwnershipOwner.localSession,
            id
        )
        dependencyStateOwner.attachDataServicesProvider { [weak self] in
            self?.browserRuntime.dataServices()
        }
        sumiSettings = runtime.settings()
    }

    func attachBrowserActionService(_ service: TabBrowserActionService) {
        browserActionService = service
    }

    var sumiSettings: SumiSettingsService? {
        get { dependencyStateOwner.sumiSettings }
        set { dependencyStateOwner.sumiSettings = newValue }
    }

    var faviconService: any BrowserFaviconServicing {
        dependencyStateOwner.faviconService
    }

    var faviconImageService: any BrowserFaviconImageServicing {
        dependencyStateOwner.faviconImageService
    }

    var visitedLinkStore: any BrowserVisitedLinkStoreManaging {
        dependencyStateOwner.visitedLinkStore
    }

    // MARK: - Link Hover Callback
    var onLinkHover: ((String?) -> Void)? {
        get { webViewInteractionStateOwner.onLinkHover }
        set { webViewInteractionStateOwner.onLinkHover = newValue }
    }
    var lastHoveredLinkURL: URL? {
        get { webViewInteractionStateOwner.lastHoveredLinkURL }
        set { webViewInteractionStateOwner.lastHoveredLinkURL = newValue }
    }
    var lastWebPageContextMenuTarget: SumiWebPageContextMenuTargetSnapshot? {
        get { webViewInteractionStateOwner.lastWebPageContextMenuTarget }
        set { webViewInteractionStateOwner.lastWebPageContextMenuTarget = newValue }
    }
    var lastGlanceMouseDownOrigin: SumiGlanceOriginSnapshot? {
        get { webViewInteractionStateOwner.lastGlanceMouseDownOrigin }
        set { webViewInteractionStateOwner.lastGlanceMouseDownOrigin = newValue }
    }

    private var navigationStateController: TabNavigationStateController {
        navigationRuntime.navigationStateController
    }

    func recordPopupUserActivation(_ event: NSEvent, kind: String) {
        recordWebViewInteraction(event)
        popupUserActivationTracker.record(event: event, kind: kind)
    }

    func recordWebViewInteraction(_ interactionEvent: SumiWebViewInteractionEvent) {
        switch interactionEvent {
        case .mouseDown(let event),
             .middleMouseDown(let event),
             .keyDown(let event):
            recordWebViewInteraction(event)
            browserActionService.reconcileExtensionRuntimeOnUserGesture(
                self,
                "Tab.recordWebViewInteraction"
            )
        case .scrollWheel:
            break
        }
    }

    func recordWebViewInteraction(_ event: NSEvent) {
        webViewInteractionStateOwner.recordInteraction(event)
    }

    func clearWebViewInteractionEvent() {
        webViewInteractionStateOwner.clearInteractionEvent()
    }

    func recentWebViewInteractionModifierFlags(maxAge: TimeInterval = 1.0) -> NSEvent.ModifierFlags? {
        webViewInteractionStateOwner.recentInteractionModifierFlags(maxAge: maxAge)
    }

    func recentWebViewMouseDownModifierFlags(maxAge: TimeInterval = 1.0) -> NSEvent.ModifierFlags? {
        webViewInteractionStateOwner.recentMouseDownModifierFlags(maxAge: maxAge)
    }

    func recordGlanceMouseDownOriginIfNeeded(_ event: NSEvent) {
        webViewInteractionStateOwner.recordGlanceMouseDownOriginIfNeeded(event)
    }

    func recentGlanceMouseDownOriginRect(maxAge: TimeInterval = 1.5) -> CGRect? {
        webViewInteractionStateOwner.recentGlanceMouseDownOriginRect(maxAge: maxAge)
    }

    var isCurrentTab: Bool {
        browserActionService.isCurrentTab(self)
    }

    var isLoading: Bool {
        loadingState.isLoading
    }

    var representsSumiEmptySurface: Bool {
        surfaceStateOwner.representsSumiEmptySurface(for: url)
    }

    var representsSumiSettingsSurface: Bool {
        surfaceStateOwner.representsSumiSettingsSurface(for: url)
    }

    var representsSumiHistorySurface: Bool {
        surfaceStateOwner.representsSumiHistorySurface(for: url)
    }

    var representsSumiBookmarksSurface: Bool {
        surfaceStateOwner.representsSumiBookmarksSurface(for: url)
    }

    /// Native Sumi surfaces rendered outside WebKit.
    var representsSumiNativeSurface: Bool {
        surfaceStateOwner.representsSumiNativeSurface(for: url)
    }

    /// Internal Sumi surfaces that use chrome-template presentation.
    var representsSumiInternalSurface: Bool {
        surfaceStateOwner.representsSumiInternalSurface(for: url)
    }

    public var requiresPrimaryWebView: Bool {
        surfaceStateOwner.requiresPrimaryWebView(for: url)
    }

    /// Sidebar / split tab row: tint template SF Symbol favicons like `NavButtonStyle` (`tokens.primaryText`).
    /// Covers empty tab, internal Sumi surfaces, and the ordinary ``globe`` placeholder until a bitmap favicon loads.
    var usesChromeThemedTemplateFavicon: Bool {
        surfaceStateOwner.usesChromeThemedTemplateFavicon(
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
        loadsCachedFaviconOnInit: Bool = true,
        faviconService: any BrowserFaviconServicing = TabDependencyIsolationDefaults.faviconService,
        faviconImageService: any BrowserFaviconImageServicing = TabDependencyIsolationDefaults.faviconImageService,
        visitedLinkStore: any BrowserVisitedLinkStoreManaging = TabDependencyIsolationDefaults.visitedLinkStore
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.faviconPresentation = .systemSymbol(favicon)
        self.faviconIsTemplateGlobePlaceholder = (favicon == "globe")
        self.dependencyStateOwner = TabDependencyStateOwner(
            faviconService: faviconService,
            faviconImageService: faviconImageService,
            visitedLinkStore: visitedLinkStore
        )
        super.init()
        self.spaceId = spaceId
        self.index = index
        navigationStateController.delegate = self
        parkExistingWebView(existingWebView)

        applyCachedFaviconOrPlaceholder(
            for: url,
            allowCacheLookup: loadsCachedFaviconOnInit
        )
    }

    func parkExistingWebView(_ webView: WKWebView?) {
        // Coordinator session when runtime is attached; local session is always
        // a write-through cache for pre-attach and Tab-accessor fallback.
        navigationRuntime.webViewRouting.noteParkedWebView(webView, id)
        webViewOwnershipOwner.parkExistingWebView(webView)
    }

    func clearParkedExistingWebView() {
        navigationRuntime.webViewRouting.noteParkedWebView(nil, id)
        webViewOwnershipOwner.clearParkedExistingWebView()
    }

    func adoptParkedWebViewAsCurrent(_ webView: WKWebView) {
        navigationRuntime.webViewRouting.noteUntrackedWebView(webView, id)
        webViewOwnershipOwner.adoptParkedWebViewAsCurrent(webView)
    }

    func replaceUntrackedWebView(_ webView: WKWebView) {
        navigationRuntime.webViewRouting.noteUntrackedWebView(webView, id)
        webViewOwnershipOwner.replaceUntrackedWebView(webView)
    }

    func assignPrimaryWebView(_ webView: WKWebView, windowId: UUID) {
        navigationRuntime.webViewRouting.notePrimaryAssignment(windowId, webView, id)
        webViewOwnershipOwner.assignPrimaryWebView(webView, windowId: windowId)
    }

    public func clearCurrentWebViewOwnership() {
        navigationRuntime.webViewRouting.clearPrimaryAssignment(id)
        navigationRuntime.webViewRouting.noteUntrackedWebView(nil, id)
        webViewOwnershipOwner.clearCurrentWebViewOwnership()
    }

    public func clearAllWebViewOwnership() {
        navigationRuntime.webViewRouting.clearWebViewSession(id)
        webViewOwnershipOwner.clearAllWebViewOwnership()
    }

    @discardableResult
    func clearCurrentWebViewOwnershipIfIdentical(to webView: WKWebView) -> Bool {
        guard resolvedCurrentWebView() === webView else { return false }
        clearCurrentWebViewOwnership()
        return true
    }

    func bindToShortcutPin(_ pin: ShortcutPin) {
        placementStateOwner.bindToShortcutPin(id: pin.id, role: pin.role)
    }

    func clearShortcutBinding() {
        placementStateOwner.clearShortcutBinding()
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

    func loadWebViewIfNeeded() {
        if !hasCurrentWebView {
            suspensionStateOwner.beginRestoreIfNeeded()
            _ = ensureUntrackedNormalWebView(reason: "Tab.loadWebViewIfNeeded")
            finishSuspendedRestoreIfNeeded()
        }
    }

    func publishNavigationStateChangeIfNeeded(_ didChange: Bool) {
        guard didChange else { return }
        stateChangeEmitter.publishNavigationStateDidChange(for: self)
    }

    func markSuspended(at date: Date = Date()) {
        suspensionStateOwner.markSuspended(tab: self, at: date)
    }

    func finishSuspendedRestoreIfNeeded() {
        suspensionStateOwner.finishRestoreIfNeeded(tab: self, hasWebView: hasCurrentWebView)
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

    func activate() {
        browserActionService.activate(self)
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
