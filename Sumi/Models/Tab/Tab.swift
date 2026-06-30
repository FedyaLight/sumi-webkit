//
//  Tab.swift
//  Sumi
//
//

import AppKit
import Combine
import Foundation
import SwiftUI
import WebKit

@MainActor
public class Tab: NSObject, Identifiable, ObservableObject {
    public let id: UUID
    var url: URL
    @Published var name: String
    @Published var favicon: SwiftUI.Image
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
    private let navigationRuntime = TabNavigationRuntime()
    let mediaRuntime = TabMediaRuntime()
    let popupUserActivationTracker = SumiPopupUserActivationTracker()
    let faviconRuntime = TabFaviconRuntime()
    let profileResolutionOwner = TabProfileResolutionOwner()
    let extensionPageRuntimeOwner = TabExtensionPageRuntimeOwner()
    private let webViewOwnershipOwner = TabWebViewOwnershipOwner()
    private let webViewRuntime = TabWebViewRuntime()
    let webViewConfigurationOwner = TabWebViewConfigurationOwner()
    let normalWebViewSetupOwner = TabNormalWebViewSetupOwner()
    let webViewProvisioningOwner = TabWebViewProvisioningOwner()
    lazy var normalWebViewRuntimeContextOwner = TabNormalWebViewRuntimeContextOwner(tab: self)
    private let closeLifecycleOwner = TabCloseLifecycleOwner()
    let configurationPolicyWebViewReplacementContextOwner =
        TabConfigurationPolicyWebViewReplacementContextOwner()
    let navigationCommandOwner = TabNavigationCommandOwner()
    lazy var profileWebViewCreationGate = TabProfileWebViewCreationGate(
        dependencies: .live(
            tab: self,
            currentProfileUpdates: { [weak self] in
                self?.browserManager?.$currentProfile.eraseToAnyPublisher()
            }
        )
    )
    lazy var ownedWebViewPreparationOwner = TabOwnedWebViewPreparationOwner(
        dependencies: .live(tab: self)
    )
    private let suspensionStateOwner = TabSuspensionStateOwner()
    private let webViewInteractionStateOwner = TabWebViewInteractionStateOwner()
    lazy var permissionSurfaceOwner = TabPermissionSurfaceOwner(context: .live(tab: self))
    lazy var webKitUIDelegateOwner = TabWebKitUIDelegateOwner(tab: self)
    lazy var webKitPermissionUIDelegateOwner = TabWebKitPermissionUIDelegateOwner(tab: self)
    lazy var scriptMessageRuntimeOwner = TabScriptMessageRuntimeOwner(tab: self)
    private weak var browserManagerStorage: BrowserManager?
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
    var isEphemeral: Bool {
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
    @Published var estimatedProgress: Double = 0.0

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

    var navigationTransactionOwner: TabNavigationTransactionOwner {
        navigationRuntime.navigationTransactionOwner
    }
    var pendingMainFrameNavigationKind: TabMainFrameNavigationKind? {
        get { navigationTransactionOwner.pendingMainFrameNavigationKind }
        set { navigationTransactionOwner.pendingMainFrameNavigationKind = newValue }
    }
    var historyRecorder: HistoryTabRecorder {
        navigationRuntime.historyRecorder
    }
    var titleUpdateOwner: TabTitleUpdateOwner {
        navigationRuntime.titleUpdateOwner
    }
    var navigationDelegateBundles: NSMapTable<WKWebView, SumiTabNavigationDelegateBundle> {
        navigationRuntime.navigationDelegateBundles
    }
    var webViewRoutingRuntime: TabWebViewRoutingRuntime {
        get { navigationRuntime.webViewRouting }
        set { navigationRuntime.webViewRouting = newValue }
    }
    var persistenceRuntimeCallbacks: TabRuntimePersistenceCallbacks {
        get { navigationRuntime.persistenceCallbacks }
        set { navigationRuntime.persistenceCallbacks = newValue }
    }
    var historySwipeRuntime: TabHistorySwipeRuntime {
        get { navigationRuntime.historySwipeRuntime }
        set { navigationRuntime.historySwipeRuntime = newValue }
    }
    var historyRecordingRuntime: TabHistoryRecordingRuntime {
        get { navigationRuntime.historyRecordingRuntime }
        set { navigationRuntime.historyRecordingRuntime = newValue }
    }
    var findInPageRuntime: TabFindInPageRuntime {
        get { navigationRuntime.findInPageRuntime }
        set { navigationRuntime.findInPageRuntime = newValue }
    }
    var extensionPropertiesRuntime: TabExtensionPropertiesRuntime {
        get { navigationRuntime.extensionPropertiesRuntime }
        set { navigationRuntime.extensionPropertiesRuntime = newValue }
    }
    var closeLifecycleRuntime: TabCloseLifecycleRuntime {
        get { navigationRuntime.closeLifecycleRuntime }
        set { navigationRuntime.closeLifecycleRuntime = newValue }
    }
    var lifecycleNavigationRuntime: TabLifecycleNavigationRuntime {
        get { navigationRuntime.lifecycleNavigationRuntime }
        set { navigationRuntime.lifecycleNavigationRuntime = newValue }
    }
    var permissionRuntime: TabPermissionRuntime {
        get { navigationRuntime.permissionRuntime }
        set { navigationRuntime.permissionRuntime = newValue }
    }
    var webViewCleanupRuntime: TabWebViewCleanupRuntime {
        get { navigationRuntime.webViewCleanupRuntime }
        set { navigationRuntime.webViewCleanupRuntime = newValue }
    }
    var normalWebViewExtensionRuntime: TabNormalWebViewExtensionRuntime {
        get { navigationRuntime.normalWebViewExtensionRuntime }
        set { navigationRuntime.normalWebViewExtensionRuntime = newValue }
    }
    var scriptMessageRuntime: TabScriptMessageRuntime {
        get { navigationRuntime.scriptMessageRuntime }
        set { navigationRuntime.scriptMessageRuntime = newValue }
    }
    var navigationDelegateRuntime: TabNavigationDelegateRuntime {
        get { navigationRuntime.navigationDelegateRuntime }
        set { navigationRuntime.navigationDelegateRuntime = newValue }
    }
    var faviconExtensionRuntime: TabFaviconExtensionRuntime {
        get { navigationRuntime.faviconExtensionRuntime }
        set { navigationRuntime.faviconExtensionRuntime = newValue }
    }
    var popupHandlingRuntime: TabPopupHandlingRuntime {
        get { navigationRuntime.popupHandlingRuntime }
        set { navigationRuntime.popupHandlingRuntime = newValue }
    }
    var webKitUIRuntime: TabWebKitUIRuntime {
        get { navigationRuntime.webKitUIRuntime }
        set { navigationRuntime.webKitUIRuntime = newValue }
    }
    var installNavigationRuntime: TabInstallNavigationRuntime {
        get { navigationRuntime.installNavigationRuntime }
        set { navigationRuntime.installNavigationRuntime = newValue }
    }
    var configurationPolicyWebViewReplacementRuntime: TabConfigurationPolicyWebViewReplacementRuntime {
        get { navigationRuntime.configurationPolicyWebViewReplacementRuntime }
        set { navigationRuntime.configurationPolicyWebViewReplacementRuntime = newValue }
    }
    var navigationCommandRuntime: TabNavigationCommandRuntime {
        get { navigationRuntime.navigationCommandRuntime }
        set { navigationRuntime.navigationCommandRuntime = newValue }
    }
    var profileResolutionRuntime: TabProfileResolutionRuntime {
        get { navigationRuntime.profileResolutionRuntime }
        set { navigationRuntime.profileResolutionRuntime = newValue }
    }
    var reloadPolicyRuntime: TabReloadPolicyRuntime {
        get { navigationRuntime.reloadPolicyRuntime }
        set { navigationRuntime.reloadPolicyRuntime = newValue }
    }
    var isFreezingNavigationStateDuringBackForwardGesture: Bool {
        get { navigationTransactionOwner.isFreezingNavigationStateDuringBackForwardGesture }
        set { navigationTransactionOwner.isFreezingNavigationStateDuringBackForwardGesture = newValue }
    }
    var lastMediaActivityAt: Date {
        get { mediaRuntime.lastMediaActivityAt }
        set { mediaRuntime.lastMediaActivityAt = newValue }
    }
    var mediaRuntimeCallbacks: TabMediaRuntimeCallbacks {
        get { mediaRuntime.callbacks }
        set { mediaRuntime.callbacks = newValue }
    }
    // MARK: - Tab State
    var isUnloaded: Bool {
        webViewOwnershipOwner.isUnloaded
    }

    /// True when the tab row should show the web-content-unloaded favicon affordance.
    /// Sumi-native tabs (settings UI, empty new-tab surface) never host a primary-frame WKWebView for that UI, so they must not look “unloaded”.
    var showsWebViewUnloadedIndicator: Bool {
        requiresPrimaryWebView && isUnloaded
    }

    var _webView: WKWebView? {
        get { webViewOwnershipOwner.webView }
        set { webViewOwnershipOwner.setCurrentWebViewForLegacyBridge(newValue) }
    }
    var _existingWebView: WKWebView? {
        get { webViewOwnershipOwner.existingWebView }
        set { webViewOwnershipOwner.setExistingWebViewForLegacyBridge(newValue) }
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

    var safariContentBlockerAppliedAttachmentState: SumiSafariContentBlockerAttachmentState? {
        get { reloadPolicyStateOwner.safariContentBlockerAppliedAttachmentState }
        set { reloadPolicyStateOwner.safariContentBlockerAppliedAttachmentState = newValue }
    }
    var protectionAppliedAttachmentState: SumiProtectionAttachmentState? {
        get { reloadPolicyStateOwner.protectionAppliedAttachmentState }
        set { reloadPolicyStateOwner.protectionAppliedAttachmentState = newValue }
    }
    var safariContentBlockerReloadRequirement: SumiSafariContentBlockerReloadRequirement? {
        get { reloadPolicyStateOwner.safariContentBlockerReloadRequirement }
        set { reloadPolicyStateOwner.safariContentBlockerReloadRequirement = newValue }
    }
    var isSafariContentBlockerReloadRequired: Bool {
        reloadPolicyStateOwner.isSafariContentBlockerReloadRequired
    }
    var protectionReloadRequirement: SumiProtectionReloadRequirement? {
        get { reloadPolicyStateOwner.protectionReloadRequirement }
        set { reloadPolicyStateOwner.protectionReloadRequirement = newValue }
    }
    var isProtectionReloadRequired: Bool {
        reloadPolicyStateOwner.isProtectionReloadRequired
    }
    var didManualReloadRebuildProtectionWebView: Bool {
        get { reloadPolicyStateOwner.didManualReloadRebuildProtectionWebView }
        set { reloadPolicyStateOwner.didManualReloadRebuildProtectionWebView = newValue }
    }
    var appliedProtectionAfterManualReload: Bool {
        get { reloadPolicyStateOwner.appliedProtectionAfterManualReload }
        set { reloadPolicyStateOwner.appliedProtectionAfterManualReload = newValue }
    }
    var lastProtectionWebViewRebuildDuration: TimeInterval? {
        get { reloadPolicyStateOwner.lastProtectionWebViewRebuildDuration }
        set { reloadPolicyStateOwner.lastProtectionWebViewRebuildDuration = newValue }
    }
    var lastProtectionURLHubSummaryDuration: TimeInterval? {
        get { reloadPolicyStateOwner.lastProtectionURLHubSummaryDuration }
        set { reloadPolicyStateOwner.lastProtectionURLHubSummaryDuration = newValue }
    }
    var autoplayReloadRequirement: SumiAutoplayReloadRequirement? {
        get { reloadPolicyStateOwner.autoplayReloadRequirement }
        set { reloadPolicyStateOwner.autoplayReloadRequirement = newValue }
    }
    var isAutoplayReloadRequired: Bool {
        reloadPolicyStateOwner.isAutoplayReloadRequired
    }
    // MARK: - WebView Ownership Tracking (Memory Optimization)
    /// The window ID that currently "owns" the primary WebView for this tab
    /// If nil, no window is displaying this tab yet
    var primaryWindowId: UUID? {
        get { webViewOwnershipOwner.primaryWindowId }
        set { webViewOwnershipOwner.setPrimaryWindowIdForLegacyBridge(newValue) }
    }
    var isSuspended: Bool {
        get { suspensionStateOwner.isSuspended }
        set { suspensionStateOwner.isSuspended = newValue }
    }
    var lastSuspendedURL: URL? {
        get { suspensionStateOwner.lastSuspendedURL }
        set { suspensionStateOwner.lastSuspendedURL = newValue }
    }
    var lastSelectedAt: Date? {
        get { suspensionStateOwner.lastSelectedAt }
        set { suspensionStateOwner.lastSelectedAt = newValue }
    }
    var pageSuspensionVeto: TabPageSuspensionVeto {
        get { suspensionStateOwner.pageSuspensionVeto }
        set { suspensionStateOwner.pageSuspensionVeto = newValue }
    }
    var hasPictureInPictureVideo: Bool {
        get { suspensionStateOwner.hasPictureInPictureVideo }
        set { suspensionStateOwner.hasPictureInPictureVideo = newValue }
    }
    var isDisplayingPDFDocument: Bool {
        get { suspensionStateOwner.isDisplayingPDFDocument }
        set { suspensionStateOwner.isDisplayingPDFDocument = newValue }
    }
    var isSuspensionRestoreInProgress: Bool {
        get { suspensionStateOwner.isRestoreInProgress }
        set { suspensionStateOwner.isRestoreInProgress = newValue }
    }
    var lastWebViewInteractionEvent: NSEvent? {
        get { webViewInteractionStateOwner.lastWebViewInteractionEvent }
        set { webViewInteractionStateOwner.lastWebViewInteractionEvent = newValue }
    }
    var webViewInteractionCancellables: [ObjectIdentifier: AnyCancellable] {
        get { webViewInteractionStateOwner.webViewInteractionCancellables }
        set { webViewInteractionStateOwner.webViewInteractionCancellables = newValue }
    }

    var browserManager: BrowserManager? {
        get { browserManagerStorage }
        set {
            browserManagerStorage = newValue
            if let newValue {
                let browserManager = newValue
                webViewRoutingRuntime = .live(webViewRoutingService: newValue.webViewRoutingService)
                persistenceRuntimeCallbacks = .live(tabManager: newValue.tabManager)
                mediaRuntimeCallbacks = .live(
                    nowPlayingController: newValue.nativeNowPlayingController,
                    backgroundMediaOptimizationService: newValue.backgroundMediaOptimizationService
                )
                navigationCommandRuntime = .live(settings: { [weak browserManager] in
                    browserManager?.sumiSettings
                })
                profileResolutionRuntime = .live(browserManager: newValue)
                reloadPolicyRuntime = .live(
                    extensionsModule: { [weak browserManager] in
                        browserManager?.extensionsModule
                    },
                    protectionCoordinator: { [weak browserManager] in
                        browserManager?.protectionCoordinator
                    },
                    runtimePermissionController: { [weak browserManager] in
                        browserManager?.runtimePermissionController
                    }
                )
                historySwipeRuntime = .live(
                    webViewCoordinator: { [weak browserManager] in
                        browserManager?.webViewCoordinator
                    },
                    cancelWindowMutationsAfterHistorySwipe: { [weak browserManager] windowId in
                        browserManager?.cancelWindowMutationsAfterHistorySwipe(in: windowId)
                    },
                    flushWindowMutationsAfterHistorySwipe: { [weak browserManager] windowId in
                        browserManager?.flushWindowMutationsAfterHistorySwipe(in: windowId)
                    }
                )
                historyRecordingRuntime = .live(
                    historyManager: { [weak browserManager] in
                        browserManager?.historyManager
                    },
                    currentProfileId: { [weak browserManager] in
                        browserManager?.currentProfile?.id
                    }
                )
                findInPageRuntime = .live(
                    activeWindowId: { [weak browserManager] in
                        browserManager?.windowRegistry?.activeWindow?.id
                    },
                    webView: { [weak browserManager] tabId, windowId in
                        browserManager?.getWebView(for: tabId, in: windowId)
                    }
                )
                extensionPropertiesRuntime = .live(extensionsModule: { [weak browserManager] in
                    browserManager?.extensionsModule
                })
                closeLifecycleRuntime = .live(
                    cleanupZoomForTab: { [weak browserManager] tabId in
                        browserManager?.cleanupZoomForTab(tabId)
                    },
                    updateTabVisibility: { [weak browserManager] in
                        browserManager?.compositorManager.updateTabVisibility()
                    },
                    removeTab: { [weak browserManager] tabId in
                        browserManager?.tabManager.removeTab(tabId)
                    }
                )
                lifecycleNavigationRuntime = .live(
                    tabSuspensionService: { [weak browserManager] in
                        browserManager?.tabSuspensionService
                    },
                    extensionsModule: { [weak browserManager] in
                        browserManager?.extensionsModule
                    },
                    loadZoomForTab: { [weak browserManager] tabId in
                        browserManager?.loadZoomForTab(tabId)
                    },
                    adBlockingModule: { [weak browserManager] in
                        browserManager?.adBlockingModule
                    },
                    enforceSiteDataPolicyAfterNavigation: { [weak browserManager] tab in
                        browserManager?.enforceSiteDataPolicyAfterNavigation(for: tab)
                    },
                    authenticationManager: { [weak browserManager] in
                        browserManager?.authenticationManager
                    },
                    webViewCoordinator: { [weak browserManager] in
                        browserManager?.webViewCoordinator
                    }
                )
                permissionRuntime = .live(
                    permissionBridges: { [weak browserManager] in
                        browserManager?.permissionBridges
                    },
                    handlePermissionLifecycleEvent: { [weak browserManager] event in
                        browserManager?.permissionLifecycleController.handle(event)
                    },
                    isActiveGlancePreviewSurface: { [weak browserManager] tabId, webView in
                        guard let browserManager,
                              let session = browserManager.glanceManager.currentSession,
                              session.previewTab.id == tabId,
                              session.previewTab.existingWebView === webView,
                              let windowState = browserManager.windowRegistry?.windows[session.windowId],
                              browserManager.glanceManager.activeSession(for: windowState)?.id == session.id
                        else {
                            return false
                        }
                        return true
                    }
                )
                webViewCleanupRuntime = .live(
                    userscriptsModule: { [weak browserManager] in
                        browserManager?.userscriptsModule
                    },
                    webViewCoordinator: { [weak browserManager] in
                        browserManager?.webViewCoordinator
                    }
                )
                normalWebViewExtensionRuntime = .live(
                    extensionsModule: { [weak browserManager] in
                        browserManager?.extensionsModule
                    },
                    windowState: { [weak browserManager] windowId in
                        browserManager?.windowRegistry?.windows[windowId]
                    },
                    currentTab: { [weak browserManager] windowState in
                        browserManager?.currentTab(for: windowState)
                    }
                )
                scriptMessageRuntime = .live(glanceManager: browserManager.glanceManager)
                navigationDelegateRuntime = .live(
                    externalSchemePermissionBridge: { [weak browserManager] in
                        browserManager?.externalSchemePermissionBridge
                    },
                    downloadManager: { [weak browserManager] in
                        browserManager?.downloadManager
                    }
                )
                faviconExtensionRuntime = .live(
                    extensionsModule: { [weak browserManager] in
                        browserManager?.extensionsModule
                    },
                    extensionSurfaceStore: { [weak browserManager] in
                        browserManager?.extensionSurfaceStore
                    }
                )
                popupHandlingRuntime = .live(browserManager: browserManager)
                installNavigationRuntime = .live(userscriptsModule: { [weak browserManager] in
                    browserManager?.userscriptsModule
                })
                webKitUIRuntime = .live(
                    handleWebViewDidClose: { [weak browserManager] webView in
                        browserManager?.handleWebViewDidClose(webView) == true
                    },
                    saveDownloadedData: { [weak browserManager] data, suggestedFilename, mimeType, originatingURL in
                        browserManager?.downloadManager.saveDownloadedData(
                            data,
                            suggestedFilename: suggestedFilename,
                            mimeType: mimeType,
                            originatingURL: originatingURL
                        )
                    }
                )
                configurationPolicyWebViewReplacementRuntime = .live(
                    webViewCoordinator: { [weak browserManager] in
                        browserManager?.webViewCoordinator
                    },
                    windowState: { [weak browserManager] windowId in
                        browserManager?.windowRegistry?.windows[windowId]
                    },
                    refreshCompositor: { [weak browserManager] windowState in
                        browserManager?.refreshCompositor(for: windowState)
                    }
                )
            } else {
                webViewRoutingRuntime = .inactive
                persistenceRuntimeCallbacks = .inactive
                mediaRuntimeCallbacks = .inactive
                historySwipeRuntime = .inactive
                historyRecordingRuntime = .inactive
                findInPageRuntime = .inactive
                extensionPropertiesRuntime = .inactive
                closeLifecycleRuntime = .inactive
                lifecycleNavigationRuntime = .inactive
                permissionRuntime = .inactive
                webViewCleanupRuntime = .inactive
                normalWebViewExtensionRuntime = .inactive
                scriptMessageRuntime = .inactive
                navigationDelegateRuntime = .inactive
                faviconExtensionRuntime = .inactive
                popupHandlingRuntime = .inactive
                webKitUIRuntime = .inactive
                installNavigationRuntime = .inactive
                configurationPolicyWebViewReplacementRuntime = .inactive
                navigationCommandRuntime = .inactive
                profileResolutionRuntime = .inactive
                reloadPolicyRuntime = .empty
            }
            dependencyStateOwner.attachDataServicesProvider { [weak self] in
                guard let dataServices = self?.browserManagerStorage?.dataServices else { return nil }
                return TabDependencyDataServices(
                    faviconService: dataServices.faviconService,
                    faviconImageService: dataServices.faviconImageService,
                    visitedLinkStore: dataServices.visitedLinkStore
                )
            }
        }
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
            browserManager?.extensionsModule.reconcileExtensionRuntimeOnUserGestureIfNeeded(
                self,
                reason: "Tab.recordWebViewInteraction"
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

    var requiresPrimaryWebView: Bool {
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
        browserManager: BrowserManager? = nil,
        existingWebView: WKWebView? = nil,
        loadsCachedFaviconOnInit: Bool = true,
        faviconService: any BrowserFaviconServicing = BrowserManagerDataServices.productionFaviconService,
        faviconImageService: any BrowserFaviconImageServicing = BrowserManagerDataServices.productionFaviconImageService,
        visitedLinkStore: any BrowserVisitedLinkStoreManaging = BrowserManagerDataServices.productionVisitedLinkStore
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.favicon = Image(systemName: favicon)
        self.faviconIsTemplateGlobePlaceholder = (favicon == "globe")
        self.dependencyStateOwner = TabDependencyStateOwner(
            faviconService: faviconService,
            faviconImageService: faviconImageService,
            visitedLinkStore: visitedLinkStore
        )
        super.init()
        self.browserManager = browserManager
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
        webViewOwnershipOwner.parkExistingWebView(webView)
    }

    func clearParkedExistingWebView() {
        webViewOwnershipOwner.clearParkedExistingWebView()
    }

    func adoptParkedWebViewAsCurrent(_ webView: WKWebView) {
        webViewOwnershipOwner.adoptParkedWebViewAsCurrent(webView)
    }

    func replaceUntrackedWebView(_ webView: WKWebView) {
        webViewOwnershipOwner.replaceUntrackedWebView(webView)
    }

    func assignPrimaryWebView(_ webView: WKWebView, windowId: UUID) {
        webViewOwnershipOwner.assignPrimaryWebView(webView, windowId: windowId)
    }

    func clearCurrentWebViewOwnership() {
        webViewOwnershipOwner.clearCurrentWebViewOwnership()
    }

    func clearAllWebViewOwnership() {
        webViewOwnershipOwner.clearAllWebViewOwnership()
    }

    @discardableResult
    func clearCurrentWebViewOwnershipIfIdentical(to webView: WKWebView) -> Bool {
        webViewOwnershipOwner.clearCurrentWebViewOwnershipIfIdentical(to: webView)
    }

    func bindToShortcutPin(_ pin: ShortcutPin) {
        placementStateOwner.bindToShortcutPin(pin)
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
            beginSuspendedRestoreIfNeeded()
            setupWebView()
            finishSuspendedRestoreIfNeeded()
        }
    }

    func noteSuspensionAccess(at date: Date = Date()) {
        suspensionStateOwner.noteAccess(at: date)
    }

    func resetPageSuspensionRuntimeState() {
        suspensionStateOwner.resetRuntimeState()
    }

    func publishNavigationStateChangeIfNeeded(_ didChange: Bool) {
        guard didChange else { return }
        stateChangeEmitter.publishNavigationStateDidChange(for: self)
    }

    func markSuspended(at date: Date = Date()) {
        suspensionStateOwner.markSuspended(tab: self, at: date)
    }

    func beginSuspendedRestoreIfNeeded() {
        suspensionStateOwner.beginRestoreIfNeeded()
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
        browserManager?.tabManager.setActiveTab(self)
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
