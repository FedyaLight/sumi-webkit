//
//  Tab.swift
//  Sumi
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import AppKit
import Combine
import Foundation
import SwiftUI
import WebKit

enum SumiLiveInstanceRole {
    case none
    case liveEssentialInstance
    case livePinnedLauncherInstance
}

extension Notification.Name {
    static let sumiTabLifecycleDidChange = Notification.Name("SumiTabLifecycleDidChange")
    static let sumiTabNavigationStateDidChange = Notification.Name("SumiTabNavigationStateDidChange")
}

@MainActor
public class Tab: NSObject, Identifiable, ObservableObject, WKDownloadDelegate {
    public let id: UUID
    var url: URL
    @Published var name: String
    @Published var favicon: SwiftUI.Image
    /// True while the tab shows the SF Symbol ``globe`` fallback (no bitmap favicon yet / resolver miss).
    @Published var faviconIsTemplateGlobePlaceholder: Bool = false
    var spaceId: UUID?
    var index: Int
    var profileId: UUID?
    // If true, this tab is created to host a popup window; do not perform initial load.
    var isPopupHost: Bool = false

    // Track the current click modifiers so Glance can respond to the configured trigger.
    var clickModifierFlags: NSEvent.ModifierFlags = []
    private let navigationRuntime = TabNavigationRuntime()
    let mediaRuntime = TabMediaRuntime()
    private let webViewRuntime = TabWebViewRuntime()

    // MARK: - Pin State
    var isPinned: Bool = false  // Global pinned (essentials)
    var isSpacePinned: Bool = false  // Space-level pinned
    var folderId: UUID?  // Folder membership for tabs within spacepinned area
    var shortcutPinId: UUID?
    var shortcutPinRole: ShortcutPinRole?
    var isShortcutLiveInstance: Bool = false
    
    // MARK: - Ephemeral State
    /// Whether this tab belongs to an ephemeral/incognito session
    var isEphemeral: Bool {
        return resolveProfile()?.isEphemeral ?? false
    }

    // MARK: - Loading State
    enum LoadingState: Equatable {
        case idle
        case didStartProvisionalNavigation
        case didCommit
        case didFinish
        case didFail(Error)
        case didFailProvisionalNavigation(Error)

        static func == (lhs: LoadingState, rhs: LoadingState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                 (.didStartProvisionalNavigation, .didStartProvisionalNavigation),
                 (.didCommit, .didCommit),
                 (.didFinish, .didFinish):
                return true
            case (.didFail, .didFail),
                 (.didFailProvisionalNavigation, .didFailProvisionalNavigation):
                // Compare error descriptions for equality
                return lhs.description == rhs.description
            default:
                return false
            }
        }

        var isLoading: Bool {
            switch self {
            case .idle, .didFinish, .didFail, .didFailProvisionalNavigation:
                return false
            case .didStartProvisionalNavigation, .didCommit:
                return true
            }
        }

        var description: String {
            switch self {
            case .idle:
                return "Idle"
            case .didStartProvisionalNavigation:
                return "Loading started"
            case .didCommit:
                return "Content loading"
            case .didFinish:
                return "Loading finished"
            case .didFail(let error):
                return "Loading failed: \(error.localizedDescription)"
            case .didFailProvisionalNavigation(let error):
                return "Connection failed: \(error.localizedDescription)"
            }
        }
    }

    var loadingState: LoadingState {
        get { navigationRuntime.loadingState }
        set { navigationRuntime.loadingState = newValue }
    }

    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false

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

    var pendingMainFrameNavigationTask: Task<Void, Never>? {
        get { navigationRuntime.pendingMainFrameNavigationTask }
        set { navigationRuntime.pendingMainFrameNavigationTask = newValue }
    }
    var pendingMainFrameNavigationToken: UUID? {
        get { navigationRuntime.pendingMainFrameNavigationToken }
        set { navigationRuntime.pendingMainFrameNavigationToken = newValue }
    }
    var pendingMainFrameNavigationKind: TabMainFrameNavigationKind? {
        get { navigationRuntime.pendingMainFrameNavigationKind }
        set { navigationRuntime.pendingMainFrameNavigationKind = newValue }
    }
    var pendingBackForwardNavigationContext: TabBackForwardNavigationContext? {
        get { navigationRuntime.pendingBackForwardNavigationContext }
        set { navigationRuntime.pendingBackForwardNavigationContext = newValue }
    }
    var pendingBackForwardSettleTask: Task<Void, Never>? {
        get { navigationRuntime.pendingBackForwardSettleTask }
        set { navigationRuntime.pendingBackForwardSettleTask = newValue }
    }
    var isFreezingNavigationStateDuringBackForwardGesture: Bool {
        get { navigationRuntime.isFreezingNavigationStateDuringBackForwardGesture }
        set { navigationRuntime.isFreezingNavigationStateDuringBackForwardGesture = newValue }
    }
    var lastMediaActivityAt: Date {
        get { mediaRuntime.lastMediaActivityAt }
        set { mediaRuntime.lastMediaActivityAt = newValue }
    }
    var isActivelyPlayingMedia: Bool {
        audioState.isPlayingAudio
    }

    // MARK: - Tab State
    var isUnloaded: Bool {
        return _webView == nil
    }

    /// True when the tab row should show the “web content unloaded” affordance (dimmed favicon + badge).
    /// Sumi-only tabs (settings UI, empty new-tab surface) never host a primary-frame WKWebView for that UI, so they must not look “unloaded”.
    var showsWebViewUnloadedIndicator: Bool {
        if representsSumiSettingsSurface || representsSumiEmptySurface {
            return false
        }
        return isUnloaded
    }

    var _webView: WKWebView? {
        get { webViewRuntime.webView }
        set { webViewRuntime.webView = newValue }
    }
    var _existingWebView: WKWebView? {
        get { webViewRuntime.existingWebView }
        set { webViewRuntime.existingWebView = newValue }
    }
    var webViewConfigurationOverride: WKWebViewConfiguration? {
        get { webViewRuntime.webViewConfigurationOverride }
        set { webViewRuntime.webViewConfigurationOverride = newValue }
    }
    var pendingContextMenuCapture: WebContextMenuCapture? {
        get { webViewRuntime.pendingContextMenuCapture }
        set { webViewRuntime.pendingContextMenuCapture = newValue }
    }
    var didNotifyOpenToExtensions: Bool {
        get { webViewRuntime.extensionRuntimeState.didReportOpenForGeneration != 0 }
        set {
            if newValue == false {
                webViewRuntime.extensionRuntimeState.didReportOpenForGeneration = 0
            }
        }
    }
    var lastExtensionOpenNotificationGeneration: UInt64 {
        get { webViewRuntime.extensionRuntimeState.didReportOpenForGeneration }
        set { webViewRuntime.extensionRuntimeState.didReportOpenForGeneration = newValue }
    }
    var extensionRuntimeControllerGeneration: UInt64 {
        get { webViewRuntime.extensionRuntimeState.controllerGeneration }
        set { webViewRuntime.extensionRuntimeState.controllerGeneration = newValue }
    }
    var extensionRuntimeDocumentSequence: UInt64 {
        get { webViewRuntime.extensionRuntimeState.documentSequence }
        set { webViewRuntime.extensionRuntimeState.documentSequence = newValue }
    }
    var extensionRuntimeCommittedMainDocumentURL: URL? {
        get { webViewRuntime.extensionRuntimeState.committedMainDocumentURL }
        set { webViewRuntime.extensionRuntimeState.committedMainDocumentURL = newValue }
    }
    var extensionRuntimeLastReportedURL: URL? {
        get { webViewRuntime.extensionRuntimeState.lastReportedURL }
        set { webViewRuntime.extensionRuntimeState.lastReportedURL = newValue }
    }
    var extensionRuntimeLastReportedLoadingComplete: Bool? {
        get { webViewRuntime.extensionRuntimeState.lastReportedLoadingComplete }
        set { webViewRuntime.extensionRuntimeState.lastReportedLoadingComplete = newValue }
    }
    var extensionRuntimeLastReportedTitle: String? {
        get { webViewRuntime.extensionRuntimeState.lastReportedTitle }
        set { webViewRuntime.extensionRuntimeState.lastReportedTitle = newValue }
    }
    var extensionRuntimeEligibleGeneration: UInt64 {
        get { webViewRuntime.extensionRuntimeState.eligibleGeneration }
        set { webViewRuntime.extensionRuntimeState.eligibleGeneration = newValue }
    }
    
    // MARK: - WebView Ownership Tracking (Memory Optimization)
    /// The window ID that currently "owns" the primary WebView for this tab
    /// If nil, no window is displaying this tab yet
    var primaryWindowId: UUID? {
        get { webViewRuntime.primaryWindowId }
        set { webViewRuntime.primaryWindowId = newValue }
    }
    
    weak var browserManager: BrowserManager?
    weak var sumiSettings: SumiSettingsService?

    // MARK: - Link Hover Callback
    var onLinkHover: ((String?) -> Void)? = nil
    var onCommandHover: ((String?) -> Void)? = nil

    private var navigationStateObservedWebViews: NSHashTable<AnyObject> {
        navigationRuntime.observedWebViews
    }
    private var titleObservations: [ObjectIdentifier: NSKeyValueObservation] {
        get { navigationRuntime.titleObservations }
        set { navigationRuntime.titleObservations = newValue }
    }

    func prepareExtensionRuntimeGeneration(_ generation: UInt64) {
        guard extensionRuntimeControllerGeneration != generation else { return }
        extensionRuntimeControllerGeneration = generation
        extensionRuntimeLastReportedURL = nil
        extensionRuntimeLastReportedLoadingComplete = nil
        extensionRuntimeLastReportedTitle = nil
        lastExtensionOpenNotificationGeneration = 0
        extensionRuntimeEligibleGeneration = 0
    }

    func noteCommittedMainDocumentNavigation(to url: URL) {
        extensionRuntimeDocumentSequence &+= 1
        extensionRuntimeCommittedMainDocumentURL = url
    }

    var isCurrentTab: Bool {
        guard let browserManager else { return false }
        if let windowState = browserManager.windowState(containing: self) {
            return browserManager.currentTab(for: windowState)?.id == id
        }
        if let activeWindow = browserManager.windowRegistry?.activeWindow {
            return browserManager.currentTab(for: activeWindow)?.id == id
        }
        return false
    }

    var isActiveInSpace: Bool {
        guard let spaceId = self.spaceId,
            let browserManager = self.browserManager,
            let space = browserManager.tabManager.spaces.first(where: { $0.id == spaceId })
        else {
            return isCurrentTab  // Fallback to current tab for pinned tabs or if no space
        }
        return space.activeTabId == id
    }

    var isLoading: Bool {
        return loadingState.isLoading
    }

    var representsSumiEmptySurface: Bool {
        !isPopupHost && SumiSurface.isEmptyNewTabURL(url)
    }

    var representsSumiSettingsSurface: Bool {
        !isPopupHost && SumiSurface.isSettingsSurfaceURL(url)
    }

    /// Sidebar / split tab row: tint template SF Symbol favicons like `NavButtonStyle` (`tokens.primaryText`).
    /// Covers empty tab, settings, and the ordinary ``globe`` placeholder until a bitmap favicon loads.
    var usesChromeThemedTemplateFavicon: Bool {
        !isPopupHost
            && (representsSumiEmptySurface || representsSumiSettingsSurface || faviconIsTemplateGlobePlaceholder)
    }

    // MARK: - Initializers
    init(
        id: UUID = UUID(),
        url: URL = SumiSurface.emptyTabURL,
        name: String = "New Tab",
        favicon: String = "globe",
        spaceId: UUID? = nil,
        index: Int = 0,
        browserManager: BrowserManager? = nil,
        existingWebView: WKWebView? = nil,
        skipFaviconFetch: Bool = false
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.favicon = Image(systemName: favicon)
        self.faviconIsTemplateGlobePlaceholder = (favicon == "globe")
        self.spaceId = spaceId
        self.index = index
        self.browserManager = browserManager
        super.init()
        self._existingWebView = existingWebView

        if skipFaviconFetch {
            applyCachedFaviconOrPlaceholder(for: url)
        } else {
            Task { @MainActor in
                await fetchAndSetFavicon(for: url)
            }
        }
    }

    func bindToShortcutPin(_ pin: ShortcutPin) {
        shortcutPinId = pin.id
        shortcutPinRole = pin.role
        isShortcutLiveInstance = true
    }

    func clearShortcutBinding() {
        shortcutPinId = nil
        shortcutPinRole = nil
        isShortcutLiveInstance = false
    }

    var sumiLiveInstanceRole: SumiLiveInstanceRole {
        guard isShortcutLiveInstance else { return .none }
        switch shortcutPinRole {
        case .essential:
            return .liveEssentialInstance
        case .spacePinned:
            return .livePinnedLauncherInstance
        case .none:
            return .none
        }
    }

    public init(
        id: UUID = UUID(),
        url: URL = SumiSurface.emptyTabURL,
        name: String = "New Tab",
        favicon: String = "globe",
        spaceId: UUID? = nil,
        index: Int = 0,
        skipFaviconFetch: Bool = false
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.favicon = Image(systemName: favicon)
        self.faviconIsTemplateGlobePlaceholder = (favicon == "globe")
        self.spaceId = spaceId
        self.index = index
        self.browserManager = nil
        super.init()

        if skipFaviconFetch {
            applyCachedFaviconOrPlaceholder(for: url)
        } else {
            Task { @MainActor in
                await fetchAndSetFavicon(for: url)
            }
        }
    }

    // MARK: - Tab Actions
    func closeTab() {
        RuntimeDiagnostics.emit("Closing tab: \(self.name)")

        // MEMORY LEAK FIX: Use comprehensive cleanup instead of scattered cleanup
        performComprehensiveWebViewCleanup()

        // 11. RESET ALL STATE
        resetPlaybackActivity()
        applyAudioState(.unmuted(isPlayingAudio: false))
        loadingState = .idle

        // 13. CLEANUP ZOOM DATA
        browserManager?.cleanupZoomForTab(self.id)

        // 14. FORCE COMPOSITOR UPDATE
        // Note: This is called during tab loading, so we use the global current tab
        // The compositor will handle window-specific visibility in its update methods
        browserManager?.compositorManager.updateTabVisibility(
            currentTabId: browserManager?.tabManager.currentTab?.id)

        if let webView = _webView {
            removeNavigationStateObservers(from: webView)
        }

        // 15. REMOVE FROM TAB MANAGER
        browserManager?.tabManager.removeTab(self.id)

        // Cancel any pending observations
        profileAwaitCancellable?.cancel()
        profileAwaitCancellable = nil
        cancelPendingMainFrameNavigation()

        RuntimeDiagnostics.debug("Tab close completed.", category: "Tab")
    }

    deinit {
        // AnyCancellable cancels on deallocation, so deinit does not need to reach into
        // main-actor runtime buckets just to tear down deferred observers.
        RuntimeDiagnostics.debug("Tab deinit cleanup completed.", category: "Tab")
    }

    func loadURL(_ newURL: URL) {
        self.url = newURL
        loadingState = .didStartProvisionalNavigation

        guard _webView != nil else {
            setupWebView()
            return
        }

        resetPlaybackActivity()
        // The muted part of audioState is preserved to maintain the user's mute preference.

        if newURL.isFileURL {
            // Grant read access to the containing directory for local resources
            let directoryURL = newURL.deletingLastPathComponent()
            if let webView = _webView {
                if #available(macOS 15.5, *) {
                    performMainFrameNavigationAfterHydrationIfNeeded(
                        on: webView,
                        url: newURL
                    ) { resolvedWebView in
                        resolvedWebView.loadFileURL(
                            newURL,
                            allowingReadAccessTo: directoryURL
                        )
                    }
                } else {
                    performMainFrameNavigation(
                        on: webView,
                        url: newURL
                    ) { resolvedWebView in
                        resolvedWebView.loadFileURL(
                            newURL,
                            allowingReadAccessTo: directoryURL
                        )
                    }
                }
            }
        } else {
            // Regular URL loading. Extension scheme pages can misbehave with `returnCacheDataElseLoad`
            // (stale/empty document on first open, e.g. Tampermonkey options after install).
            var request = URLRequest(url: newURL)
            let scheme = newURL.scheme?.lowercased() ?? ""
            if scheme == "webkit-extension" || scheme == "safari-web-extension" {
                request.cachePolicy = .reloadIgnoringLocalCacheData
            } else {
                request.cachePolicy = .returnCacheDataElseLoad
            }
            request.timeoutInterval = 30.0
            if let webView = _webView {
                if #available(macOS 15.5, *) {
                    performMainFrameNavigationAfterHydrationIfNeeded(
                        on: webView,
                        url: newURL
                    ) { resolvedWebView in
                        resolvedWebView.load(request)
                    }
                } else {
                    performMainFrameNavigation(
                        on: webView,
                        url: newURL
                    ) { resolvedWebView in
                        resolvedWebView.load(request)
                    }
                }
            }
        }

        Task { @MainActor in
            await fetchAndSetFavicon(for: newURL)
        }
    }

    func loadURL(_ urlString: String) {
        guard let newURL = URL(string: urlString) else {
            RuntimeDiagnostics.emit("Invalid URL: \(urlString)")
            return
        }
        loadURL(newURL)
    }

    /// Navigate to a new URL with proper search engine normalization
    func navigateToURL(_ input: String) {
        let settings = sumiSettings ?? browserManager?.sumiSettings
        let template = settings?.resolvedSearchEngineTemplate ?? SearchProvider.google.queryTemplate
        let normalizedUrl = normalizeURL(input, queryTemplate: template)

        guard let validURL = URL(string: normalizedUrl) else {
            RuntimeDiagnostics.emit("Invalid URL after normalization: \(input) -> \(normalizedUrl)")
            return
        }

        loadURL(validURL)
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

    func authoritativeMediaWebView(
        using browserManager: BrowserManager,
        in windowState: BrowserWindowState
    ) -> WKWebView? {
        browserManager.getWebView(for: id, in: windowState.id)
            ?? assignedWebView
            ?? existingWebView
    }

    func unloadWebView() {
        guard let webView = _webView else {
            SumiNativeNowPlayingController.shared.handleTabUnloaded(id)
            SumiNativeNowPlayingController.shared.scheduleRefresh(delayNanoseconds: 0)
            return
        }

        cleanupCloneWebView(webView)
        _webView = nil

        resetPlaybackActivity()

        // Reset loading state
        loadingState = .idle

        SumiNativeNowPlayingController.shared.handleTabUnloaded(id)
        SumiNativeNowPlayingController.shared.scheduleRefresh(delayNanoseconds: 0)
    }

    func loadWebViewIfNeeded() {
        if _webView == nil {
            setupWebView()
        }
    }

    func toggleMute() {
        setMuted(!audioState.isMuted)
    }

    func setMuted(_ muted: Bool) {
        if let webView = _webView {
            _ = webView.sumiSetAudioMuted(muted)
        } else {
            RuntimeDiagnostics.emit("🔇 [Tab] Mute state queued at \(muted); base webView not loaded yet")
        }

        browserManager?.setMuteState(
            muted, for: id, originatingWindowId: browserManager?.windowRegistry?.activeWindow?.id)

        applyAudioState(audioState.withMuted(muted))
    }

    // MARK: - Navigation State Observation

    /// Set up KVO observers for navigation state properties
    func setupNavigationStateObservers(for webView: WKWebView) {
        if !navigationStateObservedWebViews.contains(webView) {
            webView.addObserver(
                self, forKeyPath: "canGoBack", options: [.new], context: nil)
            webView.addObserver(
                self, forKeyPath: "canGoForward", options: [.new], context: nil)
            titleObservations[ObjectIdentifier(webView)] = webView.observe(\.title) { [weak self] webView, _ in
                Task { @MainActor [weak self, weak webView] in
                    guard let self, let webView else { return }
                    guard self.titleObservations[ObjectIdentifier(webView)] != nil else { return }
                    self.updateTitle(from: webView)
                }
            }
            // NOTE: URL observer removed - it was firing during setup and overwriting
            // restored URLs. URL updates are handled by didCommit/didFinish delegates.
            navigationStateObservedWebViews.add(webView)
        }
    }

    /// Remove KVO observers for navigation state properties
    func removeNavigationStateObservers(from webView: WKWebView) {
        if navigationStateObservedWebViews.contains(webView) {
            webView.removeObserver(self, forKeyPath: "canGoBack")
            webView.removeObserver(self, forKeyPath: "canGoForward")
            titleObservations.removeValue(forKey: ObjectIdentifier(webView))?.invalidate()
            // NOTE: URL observer removed - see setupNavigationStateObservers
            navigationStateObservedWebViews.remove(webView)
        }
    }

    /// MEMORY LEAK FIX: Comprehensive WebView cleanup to prevent memory leaks
    func cleanupCloneWebView(_ webView: WKWebView) {
        if browserManager?.webViewCoordinator?.deferProtectedWebViewMutation(
            webView,
            reason: "Tab.cleanupCloneWebView",
            operation: { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.cleanupCloneWebView(webView)
            }
        ) == true {
            return
        }

        browserManager?.extensionManager.releaseExternallyConnectableRuntime(
            for: webView,
            reason: "WebView cleanup"
        )
        browserManager?.sumiScriptsManager.cleanupWebView(
            controller: webView.configuration.userContentController,
            webViewId: id
        )

        // 1. Stop all loading and media
        webView.stopLoading()

        // 2. Kill all media and JavaScript execution
        let killScript = """
            (() => {
                try {
                    // Kill all media
                    document.querySelectorAll('video, audio').forEach(el => {
                        el.pause();
                        el.currentTime = 0;
                        el.src = '';
                        el.load();
                    });

                    // Kill all WebAudio contexts
                    if (window.AudioContext || window.webkitAudioContext) {
                        if (window.__SumiAudioContexts) {
                            window.__SumiAudioContexts.forEach(ctx => ctx.close());
                            delete window.__SumiAudioContexts;
                        }
                    }

                    // Kill all timers
                    const maxId = setTimeout(() => {}, 0);
                    for (let i = 0; i < maxId; i++) {
                        clearTimeout(i);
                        clearInterval(i);
                    }
                } catch (e) {
                    console.log('Cleanup script error:', e);
                }
            })();
            """
        webView.evaluateJavaScript(killScript) { _, error in
            if let error = error {
                RuntimeDiagnostics.emit("⚠️ [Tab] Cleanup script error: \(error.localizedDescription)")
            }
        }

        // 3. Remove ALL message handlers comprehensively
        let controller = webView.configuration.userContentController
        for handlerName in coreScriptMessageHandlerNames(for: id) {
            controller.removeScriptMessageHandler(forName: handlerName)
        }

        // 4. MEMORY LEAK FIX: Detach contextMenuBridge before clearing delegates
        // This breaks the retain cycle: WKWebView → contextMenuBridge → userContentController → WKWebView
        if let focusableWebView = webView as? FocusableWKWebView {
            focusableWebView.contextMenuBridge?.detach()
            focusableWebView.contextMenuBridge = nil
        }

        unbindAudioState(from: webView)
        removeNavigationStateObservers(from: webView)

        // 6. Clear all delegates
        webView.navigationDelegate = nil
        webView.uiDelegate = nil

        // 7. Remove from view hierarchy
        webView.removeFromSuperview()

        // 7. Force remove from compositor
        browserManager?.webViewCoordinator?.removeWebViewFromContainers(webView)
    }

    /// MEMORY LEAK FIX: Comprehensive cleanup for the main tab WebView
    public func performComprehensiveWebViewCleanup() {
        guard let webView = _webView else { return }

        RuntimeDiagnostics.debug("Performing comprehensive WebView cleanup for '\(name)'.", category: "Tab")

        // Use the same comprehensive cleanup as clone WebViews
        cleanupCloneWebView(webView)

        // Additional cleanup for main WebView
        _webView = nil

        RuntimeDiagnostics.debug("Completed WebView cleanup for '\(name)'.", category: "Tab")
    }

    public override func observeValue(
        forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == "canGoBack" || keyPath == "canGoForward" {
            // Real-time navigation state updates from KVO observers
            updateNavigationState()
        } else if keyPath == "URL" {
            // URL observer disabled - was causing restored URLs to be overwritten
            // URL updates are handled by didCommit/didFinish navigation delegates
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    func activate() {
        browserManager?.tabManager.setActiveTab(self)
    }

    func updateTitle(from webView: WKWebView) {
        let trimmedTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedTitle, !trimmedTitle.isEmpty else { return }

        if name != trimmedTitle {
            name = trimmedTitle
            if pendingMainFrameNavigationKind != .backForward {
                browserManager?.tabManager.scheduleRuntimeStatePersistence(for: self)
            }
            browserManager?.extensionManager.notifyTabPropertiesChanged(
                self,
                properties: [.title]
            )
        }

        if let currentItem = webView.backForwardList.currentItem,
           currentItem.url == (webView.url ?? url),
           !webView.isLoading {
            currentItem.tabTitle = trimmedTitle
        }
    }

    @discardableResult
    func applyTitleCandidate(
        _ candidateTitle: String?,
        url candidateURL: URL?,
        source: TabTitleUpdateSource,
        isLoading explicitLoadingState: Bool? = nil
    ) -> Bool {
        _ = candidateURL
        _ = source
        _ = explicitLoadingState
        let trimmedTitle = candidateTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let resolvedTitle = trimmedTitle, !resolvedTitle.isEmpty else {
            return false
        }
        return acceptResolvedDisplayTitle(resolvedTitle, url: url)
    }

    @discardableResult
    func acceptResolvedDisplayTitle(_ title: String, url candidateURL: URL? = nil) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }
        _ = candidateURL
        guard trimmedTitle != name else { return false }
        name = trimmedTitle
        if pendingMainFrameNavigationKind != .backForward {
            browserManager?.tabManager.scheduleRuntimeStatePersistence(for: self)
        }
        browserManager?.extensionManager.notifyTabPropertiesChanged(
            self,
            properties: [.title]
        )
        return true
    }

    func resetPlaybackActivity() {
        applyAudioState(audioState.withPlayingAudio(false))
        lastMediaActivityAt = .distantPast
    }

}

// MARK: - Hashable & Equatable
extension Tab {
    public static func == (lhs: Tab, rhs: Tab) -> Bool {
        return lhs.id == rhs.id
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? Tab else { return false }
        return self.id == other.id
    }

    public override var hash: Int {
        return id.hashValue
    }
}

extension Tab {
    func deliverContextMenuCapture(_ capture: WebContextMenuCapture?) {
        pendingContextMenuCapture = capture
        if let webView = _webView as? FocusableWKWebView {
            webView.contextMenuCaptureDidUpdate(capture)
        }
    }
}

// MARK: - NSColor Extension
extension NSColor {
    convenience init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }

        guard hexString.count == 6 else { return nil }

        var rgbValue: UInt64 = 0
        guard Scanner(string: hexString).scanHexInt64(&rgbValue) else { return nil }

        let red = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgbValue & 0x0000FF) / 255.0

        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}
