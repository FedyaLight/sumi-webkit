import AppKit
import Combine
import Foundation
import ObjectiveC.runtime
import WebKit

@MainActor
struct TabBrowserRuntime {
    var webViewRoutingRuntime: TabWebViewRoutingRuntime
    var persistenceRuntimeCallbacks: TabRuntimePersistenceCallbacks
    var mediaRuntimeCallbacks: TabMediaRuntimeCallbacks
    var navigationCommandRuntime: TabNavigationCommandRuntime
    var profileResolutionRuntime: TabProfileResolutionRuntime
    var reloadPolicyRuntime: TabReloadPolicyRuntime
    var historySwipeRuntime: TabHistorySwipeRuntime
    var historyRecordingRuntime: TabHistoryRecordingRuntime
    var findInPageRuntime: TabFindInPageRuntime
    var extensionPropertiesRuntime: TabExtensionPropertiesRuntime
    var closeLifecycleRuntime: TabCloseLifecycleRuntime
    var lifecycleNavigationRuntime: TabLifecycleNavigationRuntime
    var permissionRuntime: TabPermissionRuntime
    var webViewCleanupRuntime: TabWebViewCleanupRuntime
    var normalWebViewExtensionRuntime: TabNormalWebViewExtensionRuntime
    var scriptMessageRuntime: TabScriptMessageRuntime
    var navigationDelegateRuntime: TabNavigationDelegateRuntime
    var faviconExtensionRuntime: TabFaviconExtensionRuntime
    var popupHandlingRuntime: TabPopupHandlingRuntime
    var installNavigationRuntime: TabInstallNavigationRuntime
    var webKitUIRuntime: TabWebKitUIRuntime
    var configurationPolicyWebViewReplacementRuntime: TabConfigurationPolicyWebViewReplacementRuntime
    var webViewConfigurationContext: () -> TabWebViewConfigurationContext
    var dataServices: () -> TabDependencyDataServices?
    var currentProfileUpdates: () -> AnyPublisher<Profile?, Never>?
    var settings: () -> SumiSettingsService?
    var hasBrowserRuntime: () -> Bool
    var webPageMenuAppearance: (Tab, NSAppearance?) -> NSAppearance?
    var canBookmark: (Tab) -> Bool
    var requestBookmarkEditorFromMenu: () -> Void
    var canStartContextMenuDownload: () -> Bool
    var startContextMenuDownload: (WKWebView, URLRequest) -> Void
    var openURLInForegroundTab: (URL, Tab) -> Void
    var openURLsInNewWindow: ([URL]) -> Void
    var notificationPermissionBridge: () -> SumiNotificationPermissionBridge?
    var shortcutLaunchURL: (UUID) -> URL?
    var reconcileExtensionRuntimeOnUserGesture: (Tab, String) -> Void
    var isCurrentTab: (Tab) -> Bool
    var activate: (Tab) -> Void

    static let inactive = Self(
        webViewRoutingRuntime: .inactive,
        persistenceRuntimeCallbacks: .inactive,
        mediaRuntimeCallbacks: .inactive,
        navigationCommandRuntime: .inactive,
        profileResolutionRuntime: .inactive,
        reloadPolicyRuntime: .empty,
        historySwipeRuntime: .inactive,
        historyRecordingRuntime: .inactive,
        findInPageRuntime: .inactive,
        extensionPropertiesRuntime: .inactive,
        closeLifecycleRuntime: .inactive,
        lifecycleNavigationRuntime: .inactive,
        permissionRuntime: .inactive,
        webViewCleanupRuntime: .inactive,
        normalWebViewExtensionRuntime: .inactive,
        scriptMessageRuntime: .inactive,
        navigationDelegateRuntime: .inactive,
        faviconExtensionRuntime: .inactive,
        popupHandlingRuntime: .inactive,
        installNavigationRuntime: .inactive,
        webKitUIRuntime: .inactive,
        configurationPolicyWebViewReplacementRuntime: .inactive,
        webViewConfigurationContext: { .empty },
        dataServices: { nil },
        currentProfileUpdates: { nil },
        settings: { nil },
        hasBrowserRuntime: { false },
        webPageMenuAppearance: { _, fallback in fallback },
        canBookmark: { _ in false },
        requestBookmarkEditorFromMenu: {},
        canStartContextMenuDownload: { false },
        startContextMenuDownload: { _, _ in },
        openURLInForegroundTab: { _, _ in },
        openURLsInNewWindow: { _ in },
        notificationPermissionBridge: { nil },
        shortcutLaunchURL: { _ in nil },
        reconcileExtensionRuntimeOnUserGesture: { _, _ in },
        isCurrentTab: { _ in false },
        activate: { _ in }
    )
}

@MainActor
struct TabWebViewRoutingRuntime {
    var syncTabAcrossWindows: (UUID, WKWebView?) -> Void
    var reloadTabAcrossWindows: (UUID) -> Void
    var setMuteState: (Bool, UUID) -> Void

    static let inactive = Self(
        syncTabAcrossWindows: { _, _ in },
        reloadTabAcrossWindows: { _ in },
        setMuteState: { _, _ in }
    )
}

@MainActor
struct TabRuntimePersistenceCallbacks {
    var updateNavigationState: (Tab) -> Void
    var scheduleRuntimeStatePersistence: (Tab) -> Void

    static let inactive = Self(
        updateNavigationState: { _ in },
        scheduleRuntimeStatePersistence: { _ in }
    )
}

@MainActor
struct TabMediaRuntimeCallbacks {
    var scheduleNowPlayingRefresh: (UInt64) -> Void
    var scheduleBackgroundMediaReconcile: (String) -> Void
    var notifyNowPlayingTabUnloaded: (UUID) -> Void

    static let inactive = Self(
        scheduleNowPlayingRefresh: { _ in },
        scheduleBackgroundMediaReconcile: { _ in },
        notifyNowPlayingTabUnloaded: { _ in }
    )
}

@MainActor
struct TabScriptMessageRuntime {
    var presentExternalURLInGlance: (URL, Tab, CGRect?) -> Void

    static let inactive = Self(
        presentExternalURLInGlance: { _, _, _ in }
    )
}

@MainActor
struct TabHistorySwipeRuntime {
    var windowIDContaining: (WKWebView) -> UUID?
    var beginHistorySwipeProtection: (
        _ tabId: UUID,
        _ webView: WKWebView,
        _ originURL: URL?,
        _ originHistoryItem: WKBackForwardListItem?
    ) -> Void
    var finishHistorySwipeProtection: (
        _ tabId: UUID,
        _ webView: WKWebView?,
        _ currentURL: URL?,
        _ currentHistoryItem: WKBackForwardListItem?
    ) -> Bool
    var cancelWindowMutationsAfterHistorySwipe: (UUID) -> Void
    var flushWindowMutationsAfterHistorySwipe: (UUID) -> Void

    static let inactive = Self(
        windowIDContaining: { _ in nil },
        beginHistorySwipeProtection: { _, _, _, _ in },
        finishHistorySwipeProtection: { _, _, _, _ in false },
        cancelWindowMutationsAfterHistorySwipe: { _ in },
        flushWindowMutationsAfterHistorySwipe: { _ in }
    )
}

@MainActor
struct TabNavigationCommandRuntime {
    var resolvedSearchEngineTemplate: () -> String?

    static let inactive = Self(
        resolvedSearchEngineTemplate: { nil }
    )
}

@MainActor
struct TabHistoryRecordingRuntime {
    var updateTitleIfNeeded: (
        _ title: String,
        _ url: URL,
        _ profileId: UUID?,
        _ isEphemeral: Bool
    ) -> Void
    var addVisit: (
        _ url: URL,
        _ title: String,
        _ timestamp: Date,
        _ tabId: UUID,
        _ profileId: UUID?,
        _ isEphemeral: Bool
    ) -> UUID?
    var currentProfileId: () -> UUID?

    static let inactive = Self(
        updateTitleIfNeeded: { _, _, _, _ in },
        addVisit: { _, _, _, _, _, _ in nil },
        currentProfileId: { nil }
    )
}

@MainActor
struct TabFindInPageRuntime {
    var webView: (_ tabId: UUID, _ windowId: UUID) -> WKWebView?

    static let inactive = Self(
        webView: { _, _ in nil }
    )
}

@MainActor
struct TabExtensionPropertiesRuntime {
    var notifyTabPropertiesChanged: (
        _ tab: Tab,
        _ properties: WKWebExtension.TabChangedProperties
    ) -> Void

    static let inactive = Self(
        notifyTabPropertiesChanged: { _, _ in }
    )
}

@MainActor
struct TabCloseLifecycleRuntime {
    var cleanupZoomForTab: (UUID) -> Void
    var updateTabVisibility: () -> Void
    var removeTab: (UUID) -> Void

    static let inactive = Self(
        cleanupZoomForTab: { _ in },
        updateTabVisibility: {},
        removeTab: { _ in }
    )
}

@MainActor
struct TabLifecycleNavigationRuntime {
    var resetRevisitProtection: (Tab) -> Void
    var prepareExtensionWebView: (WKWebView, URL, String) -> Void
    var prepareExtensionRuntimeBeforeCommit: (Tab, URL, String) -> Void
    var markExtensionEligibleAfterCommit: (Tab, String) -> Void
    var loadZoomForTab: (UUID) -> Void
    var applyAdblockZapperRulesAfterNavigation: (WKWebView, URL) -> Void
    var enforceSiteDataPolicyAfterNavigation: (Tab) -> Void
    var resolveAuthenticationChallenge: (
        _ challenge: URLAuthenticationChallenge,
        _ tab: Tab
    ) async -> SumiAuthChallengeDisposition?
    var isPreparingForDestructiveDataCleanupNavigation: (WKWebView) -> Bool
    var finishDestructiveDataCleanupNavigation: (WKWebView) -> Void

    static let inactive = Self(
        resetRevisitProtection: { _ in },
        prepareExtensionWebView: { _, _, _ in },
        prepareExtensionRuntimeBeforeCommit: { _, _, _ in },
        markExtensionEligibleAfterCommit: { _, _ in },
        loadZoomForTab: { _ in },
        applyAdblockZapperRulesAfterNavigation: { _, _ in },
        enforceSiteDataPolicyAfterNavigation: { _ in },
        resolveAuthenticationChallenge: { _, _ in .next },
        isPreparingForDestructiveDataCleanupNavigation: { _ in false },
        finishDestructiveDataCleanupNavigation: { _ in }
    )
}

@MainActor
struct TabPermissionRuntime {
    var permissionBridges: () -> BrowserPermissionBridgeRegistry?
    var handlePermissionLifecycleEvent: (SumiPermissionLifecycleEvent) -> Void
    var isActiveGlancePreviewSurface: (_ tabId: UUID, _ webView: WKWebView) -> Bool

    static let inactive = Self(
        permissionBridges: { nil },
        handlePermissionLifecycleEvent: { _ in },
        isActiveGlancePreviewSurface: { _, _ in false }
    )
}

@MainActor
struct TabWebViewCleanupRuntime {
    var deferProtectedWebViewCleanup: (WKWebView, UUID, String) -> Bool
    var cleanupUserScripts: (WKUserContentController, UUID) -> Void
    var removeWebViewFromContainers: (WKWebView) -> Void
    var removeAllWebViews: (_ tab: Tab, _ closeActiveFullscreenMedia: Bool) -> Bool

    static let inactive = Self(
        deferProtectedWebViewCleanup: { _, _, _ in false },
        cleanupUserScripts: { _, _ in },
        removeWebViewFromContainers: { _ in },
        removeAllWebViews: { _, _ in false }
    )
}

@MainActor
struct TabNormalWebViewExtensionRuntime {
    var registerNormalTabWithExtensionRuntimeIfNeeded: (Tab, String) -> Void
    var prepareWebViewForExtensionRuntime: (WKWebView, URL?, String) -> Void
    var ensureInitialDocumentExtensionContextsLoadedIfNeeded: (UUID) async -> Void

    static let inactive = Self(
        registerNormalTabWithExtensionRuntimeIfNeeded: { _, _ in },
        prepareWebViewForExtensionRuntime: { _, _, _ in },
        ensureInitialDocumentExtensionContextsLoadedIfNeeded: { _ in }
    )
}

@MainActor
struct TabNavigationDelegateRuntime {
    var externalSchemePermissionBridge: () -> SumiExternalSchemePermissionBridge?
    var downloadManager: () -> DownloadManager?

    static let inactive = Self(
        externalSchemePermissionBridge: { nil },
        downloadManager: { nil }
    )
}

@MainActor
struct TabFaviconExtensionRuntime {
    var installedExtensions: () -> [InstalledExtension]

    static let inactive = Self(
        installedExtensions: { [] }
    )
}

@MainActor
struct TabPopupHandlingRuntime {
    var hasBrowserRuntime: () -> Bool
    var consumeRecentlyOpenedExtensionTabRequest: (URL) -> Bool
    var evaluatePopupPermission: (
        _ request: SumiPopupPermissionRequest,
        _ tabContext: SumiPopupPermissionTabContext
    ) async -> SumiPopupPermissionResult?
    var evaluatePopupPermissionSynchronouslyForWebKitFallback: (
        _ request: SumiPopupPermissionRequest,
        _ tabContext: SumiPopupPermissionTabContext
    ) -> SumiPopupPermissionResult?
    var openExtensionExternalTab: (_ requestURL: URL, _ openerTab: Tab) -> Bool
    var presentWebPopup: (
        _ configuration: WKWebViewConfiguration,
        _ request: URLRequest,
        _ windowFeatures: WKWindowFeatures,
        _ openerTab: Tab,
        _ isExtensionOriginated: Bool
    ) -> WKWebView?
    var applyVisitedLinkStoreToPopupConfiguration: (_ openerTab: Tab, _ configuration: WKWebViewConfiguration) -> Void
    var createPopupTab: (_ openerTab: Tab, _ activate: Bool) -> Tab?
    var windowStateContainingTab: (Tab) -> BrowserWindowState?
    var selectTab: (_ tab: Tab, _ windowState: BrowserWindowState) -> Void

    static let inactive = Self(
        hasBrowserRuntime: { false },
        consumeRecentlyOpenedExtensionTabRequest: { _ in false },
        evaluatePopupPermission: { _, _ in nil },
        evaluatePopupPermissionSynchronouslyForWebKitFallback: { _, _ in nil },
        openExtensionExternalTab: { _, _ in false },
        presentWebPopup: { _, _, _, _, _ in nil },
        applyVisitedLinkStoreToPopupConfiguration: { _, _ in },
        createPopupTab: { _, _ in nil },
        windowStateContainingTab: { _ in nil },
        selectTab: { _, _ in }
    )
}

@MainActor
struct TabWebKitUIRuntime {
    var handleWebViewDidClose: (WKWebView) -> Bool
    var saveDownloadedData: (
        _ data: Data,
        _ suggestedFilename: String,
        _ mimeType: String?,
        _ originatingURL: URL
    ) -> Void

    static let inactive = Self(
        handleWebViewDidClose: { _ in false },
        saveDownloadedData: { _, _, _, _ in }
    )
}

@MainActor
struct TabInstallNavigationRuntime {
    var interceptInstallNavigation: (URL) -> Bool

    static let inactive = Self(
        interceptInstallNavigation: { _ in false }
    )
}

@MainActor
struct TabConfigurationPolicyWebViewReplacementRuntime {
    var trackedWindowIdContainingWebView: (WKWebView) -> UUID?
    var hasTrackedWebViews: (UUID) -> Bool
    var setTrackedWebView: (WKWebView, UUID, UUID) -> Void
    var removeTrackedWebViews: (Tab) -> Bool
    var refreshWindowAfterWebViewReplacement: (UUID) -> Void

    static let inactive = Self(
        trackedWindowIdContainingWebView: { _ in nil },
        hasTrackedWebViews: { _ in false },
        setTrackedWebView: { _, _, _ in },
        removeTrackedWebViews: { _ in false },
        refreshWindowAfterWebViewReplacement: { _ in }
    )
}

@MainActor
struct TabProfileResolutionRuntime {
    var ephemeralProfileForTab: (_ tabId: UUID, _ profileId: UUID) -> Profile?
    var profile: (UUID) -> Profile?
    var spaceProfile: (UUID) -> Profile?
    var currentProfile: () -> Profile?
    var firstProfile: () -> Profile?

    static let inactive = Self(
        ephemeralProfileForTab: { _, _ in nil },
        profile: { _ in nil },
        spaceProfile: { _ in nil },
        currentProfile: { nil },
        firstProfile: { nil }
    )
}

enum TabMainFrameNavigationKind {
    case load
    case backForward
}

enum SumiHistoryNavigationKind {
    case regular
    case backForward
}

struct TabBackForwardNavigationContext {
    let originURL: URL?
    let originHistoryURL: URL?
    let originHistoryItem: WKBackForwardListItem?
}

struct SumiAutoplayReloadRequirement: Equatable {
    let desiredPolicy: SumiAutoplayPolicy
    let runtimeRequirement: SumiRuntimePermissionReloadRequirement

    static func == (lhs: SumiAutoplayReloadRequirement, rhs: SumiAutoplayReloadRequirement) -> Bool {
        lhs.desiredPolicy == rhs.desiredPolicy
            && lhs.runtimeRequirement == rhs.runtimeRequirement
    }
}

enum BackForwardNavigationSettleDecision {
    static func shouldApplyDeferredActions(
        originURL: URL?,
        originHistoryURL: URL?,
        originHistoryItem: WKBackForwardListItem?,
        currentURL: URL?,
        currentHistoryURL: URL?,
        currentHistoryItem: WKBackForwardListItem?
    ) -> Bool {
        if let originHistoryItem,
           let currentHistoryItem,
           originHistoryItem === currentHistoryItem {
            return false
        }

        let resolvedOrigin = originHistoryURL ?? originURL
        let resolvedCurrent = currentHistoryURL ?? currentURL

        guard let resolvedCurrent else { return false }
        guard resolvedCurrent != resolvedOrigin else { return false }
        return true
    }
}

extension URL {
    var sumiSuggestedTitlePlaceholder: String? {
        if isFileURL {
            return lastPathComponent.isEmpty ? nil : lastPathComponent
        }

        let host = host?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (host?.isEmpty == false) ? host : nil
    }
}

extension WKBackForwardListItem {
    // Mirrors DDG's workaround for stale WebKit history titles.
    private static let tabTitleKey = UnsafeRawPointer(bitPattern: "tabTitleKey".hashValue)!

    var tabTitle: String? {
        get {
            objc_getAssociatedObject(self, Self.tabTitleKey) as? String
        }
        set {
            objc_setAssociatedObject(self, Self.tabTitleKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}

@MainActor
final class TabNavigationRuntime {
    var loadingState: Tab.LoadingState = .idle
    var restoredCanGoBack: Bool?
    var restoredCanGoForward: Bool?
    var webViewRouting = TabWebViewRoutingRuntime.inactive
    var persistenceCallbacks = TabRuntimePersistenceCallbacks.inactive
    var historySwipeRuntime = TabHistorySwipeRuntime.inactive
    var historyRecordingRuntime = TabHistoryRecordingRuntime.inactive
    var findInPageRuntime = TabFindInPageRuntime.inactive
    var extensionPropertiesRuntime = TabExtensionPropertiesRuntime.inactive
    var closeLifecycleRuntime = TabCloseLifecycleRuntime.inactive
    var lifecycleNavigationRuntime = TabLifecycleNavigationRuntime.inactive
    var permissionRuntime = TabPermissionRuntime.inactive
    var webViewCleanupRuntime = TabWebViewCleanupRuntime.inactive
    var normalWebViewExtensionRuntime = TabNormalWebViewExtensionRuntime.inactive
    var scriptMessageRuntime = TabScriptMessageRuntime.inactive
    var navigationDelegateRuntime = TabNavigationDelegateRuntime.inactive
    var faviconExtensionRuntime = TabFaviconExtensionRuntime.inactive
    var popupHandlingRuntime = TabPopupHandlingRuntime.inactive
    var webKitUIRuntime = TabWebKitUIRuntime.inactive
    var installNavigationRuntime = TabInstallNavigationRuntime.inactive
    var configurationPolicyWebViewReplacementRuntime =
        TabConfigurationPolicyWebViewReplacementRuntime.inactive
    var navigationCommandRuntime = TabNavigationCommandRuntime.inactive
    var profileResolutionRuntime = TabProfileResolutionRuntime.inactive
    var reloadPolicyRuntime = TabReloadPolicyRuntime.empty
    let navigationTransactionOwner = TabNavigationTransactionOwner()
    let navigationStateController = TabNavigationStateController()
    let historyRecorder = HistoryTabRecorder()
    let titleUpdateOwner = TabTitleUpdateOwner()
    let navigationDelegateBundles = NSMapTable<WKWebView, SumiTabNavigationDelegateAdapter>.weakToStrongObjects()
}

@MainActor
final class TabMediaRuntime {
    var lastMediaActivityAt: Date = .distantPast
    var audioStateCancellables: [ObjectIdentifier: AnyCancellable] = [:]
    var callbacks = TabMediaRuntimeCallbacks.inactive
}

enum TabPageSuspensionVeto: Equatable {
    case none
    case pageReportedUnableToSuspend
}
