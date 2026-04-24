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

extension Notification.Name {
    static let sumiTabLifecycleDidChange = Notification.Name("SumiTabLifecycleDidChange")
    static let sumiTabNavigationStateDidChange = Notification.Name("SumiTabNavigationStateDidChange")
}

enum SumiWebViewShutdown {
    @MainActor
    static func perform(
        on webView: WKWebView,
        tabId: UUID,
        browserManager: BrowserManager?,
        additionalTabCleanup: (() -> Void)? = nil
    ) {
        webView.stopLoading()
        stopNativeMedia(on: webView)

        browserManager?.extensionManager.releaseExternallyConnectableRuntime(
            for: webView,
            reason: "WebView cleanup"
        )
        browserManager?.sumiScriptsManager.cleanupWebView(
            controller: webView.configuration.userContentController,
            webViewId: tabId
        )

        let controller = webView.configuration.userContentController
        for handlerName in Tab.coreScriptMessageHandlerNames(for: tabId) {
            controller.removeScriptMessageHandler(forName: handlerName)
        }

        additionalTabCleanup?()

        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        browserManager?.webViewCoordinator?.removeWebViewFromContainers(webView)
    }

    @MainActor
    private static func stopNativeMedia(on webView: WKWebView) {
        webView.pauseAllMediaPlayback(completionHandler: nil)
        webView.setAllMediaPlaybackSuspended(true, completionHandler: nil)
        webView.closeAllMediaPresentations(completionHandler: nil)

        if webView.cameraCaptureState != .none {
            webView.setCameraCaptureState(.none, completionHandler: nil)
        }
        if webView.microphoneCaptureState != .none {
            webView.setMicrophoneCaptureState(.none, completionHandler: nil)
        }
    }
}

@MainActor
public class Tab: NSObject, Identifiable, ObservableObject {
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
    var historyRecorder: HistoryTabRecorder {
        navigationRuntime.historyRecorder
    }
    var navigationDelegateBundles: NSMapTable<WKWebView, SumiTabNavigationDelegateBundle> {
        navigationRuntime.navigationDelegateBundles
    }
    var isFreezingNavigationStateDuringBackForwardGesture: Bool {
        get { navigationRuntime.isFreezingNavigationStateDuringBackForwardGesture }
        set { navigationRuntime.isFreezingNavigationStateDuringBackForwardGesture = newValue }
    }
    var lastMediaActivityAt: Date {
        get { mediaRuntime.lastMediaActivityAt }
        set { mediaRuntime.lastMediaActivityAt = newValue }
    }
    // MARK: - Tab State
    var isUnloaded: Bool {
        return _webView == nil
    }

    /// True when the tab row should show the “web content unloaded” affordance (dimmed favicon + badge).
    /// Sumi-native tabs (settings UI, empty new-tab surface) never host a primary-frame WKWebView for that UI, so they must not look “unloaded”.
    var showsWebViewUnloadedIndicator: Bool {
        requiresPrimaryWebView && isUnloaded
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
    var isSuspended: Bool {
        get { webViewRuntime.isSuspended }
        set { webViewRuntime.isSuspended = newValue }
    }
    var lastSuspendedURL: URL? {
        get { webViewRuntime.lastSuspendedURL }
        set { webViewRuntime.lastSuspendedURL = newValue }
    }
    var lastSelectedAt: Date? {
        get { webViewRuntime.lastSelectedAt }
        set { webViewRuntime.lastSelectedAt = newValue }
    }
    var isSuspensionRestoreInProgress: Bool {
        get { webViewRuntime.isSuspensionRestoreInProgress }
        set { webViewRuntime.isSuspensionRestoreInProgress = newValue }
    }
    var resolvedFaviconCacheKey: String? {
        get { webViewRuntime.resolvedFaviconCacheKey }
        set { webViewRuntime.resolvedFaviconCacheKey = newValue }
    }
    var faviconsTabExtension: FaviconsTabExtension? {
        get { webViewRuntime.faviconsTabExtension }
        set { webViewRuntime.faviconsTabExtension = newValue }
    }
    var faviconCancellables: Set<AnyCancellable> {
        get { webViewRuntime.faviconCancellables }
        set { webViewRuntime.faviconCancellables = newValue }
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

    var isLoading: Bool {
        return loadingState.isLoading
    }

    var representsSumiEmptySurface: Bool {
        !isPopupHost && SumiSurface.isEmptyNewTabURL(url)
    }

    var representsSumiSettingsSurface: Bool {
        !isPopupHost && SumiSurface.isSettingsSurfaceURL(url)
    }

    var representsSumiHistorySurface: Bool {
        !isPopupHost && SumiSurface.isHistorySurfaceURL(url)
    }

    var representsSumiBookmarksSurface: Bool {
        !isPopupHost && SumiSurface.isBookmarksSurfaceURL(url)
    }

    /// Native Sumi surfaces rendered outside WebKit.
    var representsSumiNativeSurface: Bool {
        representsSumiSettingsSurface || representsSumiHistorySurface || representsSumiBookmarksSurface
    }

    /// Internal Sumi surfaces that use chrome-template presentation.
    var representsSumiInternalSurface: Bool {
        representsSumiNativeSurface
    }

    var requiresPrimaryWebView: Bool {
        !representsSumiNativeSurface && !representsSumiEmptySurface
    }

    /// Sidebar / split tab row: tint template SF Symbol favicons like `NavButtonStyle` (`tokens.primaryText`).
    /// Covers empty tab, internal Sumi surfaces, and the ordinary ``globe`` placeholder until a bitmap favicon loads.
    var usesChromeThemedTemplateFavicon: Bool {
        !isPopupHost
            && (representsSumiEmptySurface || representsSumiInternalSurface || faviconIsTemplateGlobePlaceholder)
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
        existingWebView: WKWebView? = nil
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

        applyCachedFaviconOrPlaceholder(for: url)
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
        browserManager?.compositorManager.updateTabVisibility()

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
                        on: webView
                    ) { resolvedWebView in
                        resolvedWebView.loadFileURL(
                            newURL,
                            allowingReadAccessTo: directoryURL
                        )
                    }
                } else {
                    performMainFrameNavigation(
                        on: webView
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
                        on: webView
                    ) { resolvedWebView in
                        resolvedWebView.load(request)
                    }
                } else {
                    performMainFrameNavigation(
                        on: webView
                    ) { resolvedWebView in
                        resolvedWebView.load(request)
                    }
                }
            }
        }

        applyCachedFaviconOrPlaceholder(for: newURL)
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
        let removedTrackedWebViews = browserManager?.webViewCoordinator?.removeAllWebViews(for: self) ?? false

        guard removedTrackedWebViews || _webView != nil else {
            SumiNativeNowPlayingController.shared.handleTabUnloaded(id)
            SumiNativeNowPlayingController.shared.scheduleRefresh(delayNanoseconds: 0)
            return
        }

        if let webView = _webView {
            cleanupCloneWebView(webView)
        }
        _webView = nil

        resetPlaybackActivity()

        // Reset loading state
        loadingState = .idle

        SumiNativeNowPlayingController.shared.handleTabUnloaded(id)
        SumiNativeNowPlayingController.shared.scheduleRefresh(delayNanoseconds: 0)
    }

    func loadWebViewIfNeeded() {
        if _webView == nil {
            beginSuspendedRestoreIfNeeded()
            setupWebView()
            finishSuspendedRestoreIfNeeded()
        }
    }

    func noteSuspensionAccess(at date: Date = Date()) {
        lastSelectedAt = date
    }

    func markSuspended(at date: Date = Date()) {
        objectWillChange.send()
        isSuspended = true
        isSuspensionRestoreInProgress = false
        lastSuspendedURL = url
        if lastSelectedAt == nil {
            lastSelectedAt = date
        }
        resetPlaybackActivity()
        loadingState = .idle
        SumiNativeNowPlayingController.shared.handleTabUnloaded(id)
        SumiNativeNowPlayingController.shared.scheduleRefresh(delayNanoseconds: 0)
        NotificationCenter.default.post(
            name: .sumiTabLifecycleDidChange,
            object: self
        )
    }

    func beginSuspendedRestoreIfNeeded() {
        guard isSuspended, !isSuspensionRestoreInProgress else { return }
        isSuspensionRestoreInProgress = true
        PerformanceTrace.emitEvent("TabSuspension.restoreStart")
    }

    func finishSuspendedRestoreIfNeeded() {
        guard isSuspensionRestoreInProgress, _webView != nil else { return }
        objectWillChange.send()
        isSuspended = false
        isSuspensionRestoreInProgress = false
        PerformanceTrace.emitEvent("TabSuspension.restoreEnd")
        NotificationCenter.default.post(
            name: .sumiTabLifecycleDidChange,
            object: self
        )
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

        browserManager?.setMuteState(muted, for: id)

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
        if browserManager?.webViewCoordinator?.deferProtectedWebViewCleanup(
            webView,
            tabID: id,
            reason: "Tab.cleanupCloneWebView",
        ) == true {
            return
        }

        SumiWebViewShutdown.perform(
            on: webView,
            tabId: id,
            browserManager: browserManager
        ) { [weak self, weak webView] in
            guard let self, let webView else { return }
            self.unbindAudioState(from: webView)
            self.removeNavigationStateObservers(from: webView)
            self.removeNavigationDelegateBundle(for: webView)
        }
    }

    /// MEMORY LEAK FIX: Comprehensive cleanup for the main tab WebView
    public func performComprehensiveWebViewCleanup() {
        let removedTrackedWebViews = browserManager?.webViewCoordinator?.removeAllWebViews(for: self) ?? false
        guard removedTrackedWebViews || _webView != nil else { return }

        RuntimeDiagnostics.debug("Performing comprehensive WebView cleanup for '\(name)'.", category: "Tab")

        if let webView = _webView {
            cleanupCloneWebView(webView)
        }

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

        historyRecorder.updateTitle(trimmedTitle, tab: self)

        if let currentItem = webView.backForwardList.currentItem,
           currentItem.url == (webView.url ?? url),
           !webView.isLoading {
            currentItem.tabTitle = trimmedTitle
        }
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
        historyRecorder.updateTitle(trimmedTitle, tab: self)
        return true
    }

    func resolvedHistoryTitle(for candidateURL: URL) -> String {
        let webViewTitle = existingWebView?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let webViewTitle, !webViewTitle.isEmpty {
            return webViewTitle
        }

        let currentName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentName.isEmpty, !representsSumiEmptySurface {
            return currentName
        }

        return candidateURL.sumiSuggestedTitlePlaceholder ?? candidateURL.absoluteString
    }

    func resetPlaybackActivity() {
        applyAudioState(audioState.withPlayingAudio(false))
        lastMediaActivityAt = .distantPast
    }

}

// MARK: - Hashable & Equatable
extension Tab {
    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? Tab else { return false }
        return self.id == other.id
    }

    public override var hash: Int {
        return id.hashValue
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
