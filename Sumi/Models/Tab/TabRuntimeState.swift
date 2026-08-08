import AppKit
import Combine
import Foundation
import ObjectiveC.runtime
import SumiDomain
import SumiWebRuntime
import WebKit

@MainActor
struct TabBrowserRuntime {
    var linkPresentationCommands: TabLinkPresentationCommands
    var webPageMenuCommands: TabWebPageMenuCommands
    var webViewRoutingRuntime: TabWebViewRoutingRuntime
    var persistenceRuntimeCallbacks: TabRuntimePersistenceCallbacks
    var mediaRuntimeCallbacks: TabMediaRuntimeCallbacks
    var navigationCommandRuntime: TabNavigationCommandRuntime
    var profileResolutionRuntime: TabProfileResolutionRuntime
    var reloadPolicies: TabReloadPolicies
    var historySwipeRuntime: TabHistorySwipeRuntime
    var historyRecordingRuntime: TabHistoryRecordingRuntime
    var findInPageRuntime: TabFindInPageRuntime
    var extensionPropertiesRuntime: TabExtensionPropertiesRuntime
    var closeLifecycleRuntime: TabCloseLifecycleRuntime
    var lifecycleNavigationRuntime: TabLifecycleNavigationRuntime
    var permissionRuntime: TabPermissionRuntime
    var webViewCleanupRuntime: TabWebViewCleanupRuntime
    var untrackedWebViewInstallation: (any UntrackedWebViewInstalling)?
    var normalWebViewExtensionRuntime: TabNormalWebViewExtensionRuntime
    var navigationDelegateRuntime: TabNavigationDelegateRuntime
    var faviconExtensionRuntime: TabFaviconExtensionRuntime
    var popupPermissionEvaluator: (any PopupPermissionEvaluating)?
    var extensionPopupRequestConsumer:
        (any ExtensionPopupRequestConsuming)?
    var extensionExternalTabOpening: (any ExtensionExternalTabOpening)?
    var physicalWebPopupOpening: (any PhysicalWebPopupOpening)?
    var webKitChildTabOpening: (any WebKitChildTabOpening)?
    var webKitChildWindowOpening: (any WebKitChildWindowOpening)?
    var webKitUIRuntime: TabWebKitUIRuntime
    var webViewReplacementRuntime: TabWebViewReplacementRuntime
    var webViewConfigurationContext: () -> TabWebViewConfigurationContext
    var currentProfileUpdates: () -> AnyPublisher<Profile?, Never>?
    var settings: () -> SumiSettingsService?

    static let inactive = Self(
        linkPresentationCommands: .inactive,
        webPageMenuCommands: .inactive,
        webViewRoutingRuntime: .inactive,
        persistenceRuntimeCallbacks: .inactive,
        mediaRuntimeCallbacks: .inactive,
        navigationCommandRuntime: .inactive,
        profileResolutionRuntime: .inactive,
        reloadPolicies: .inactive,
        historySwipeRuntime: .inactive,
        historyRecordingRuntime: .inactive,
        findInPageRuntime: .inactive,
        extensionPropertiesRuntime: .inactive,
        closeLifecycleRuntime: .inactive,
        lifecycleNavigationRuntime: .inactive,
        permissionRuntime: .inactive,
        webViewCleanupRuntime: .inactive,
        untrackedWebViewInstallation: nil,
        normalWebViewExtensionRuntime: .inactive,
        navigationDelegateRuntime: .inactive,
        faviconExtensionRuntime: .inactive,
        popupPermissionEvaluator: nil,
        extensionPopupRequestConsumer: nil,
        extensionExternalTabOpening: nil,
        physicalWebPopupOpening: nil,
        webKitChildTabOpening: nil,
        webKitChildWindowOpening: nil,
        webKitUIRuntime: .inactive,
        webViewReplacementRuntime: .inactive,
        webViewConfigurationContext: { .empty },
        currentProfileUpdates: { nil },
        settings: { nil }
    )
}

@MainActor
final class TabBrowserRuntimeReference {
    var runtime: TabBrowserRuntime

    init(_ runtime: TabBrowserRuntime) {
        self.runtime = runtime
    }
}

@MainActor
struct TabWebViewRoutingRuntime {
    var syncTabAcrossWindows: (UUID, WKWebView?) -> Void
    var reloadTabAcrossWindows: (
        UUID,
        TabMainFrameNavigationIntent,
        WebRuntimeMainFrameReloadPolicy
    ) -> Void
    var reloadTabInWindow: (
        UUID,
        UUID,
        TabMainFrameNavigationIntent,
        WebRuntimeMainFrameReloadPolicy
    ) -> TabMainFrameReloadCommandOutcome
    var retainWebContentProcessRecovery: (UUID, WKWebView) -> Bool
    var recoverWebContentProcess: (
        UUID,
        WKWebView
    ) -> TabMainFrameReloadCommandOutcome
    var cancelWebContentProcessRecovery: (WKWebView) -> Void
    var setMuteState: (Bool, UUID) -> Void
    var bindWebViewSession: (WebViewSessionHandle) -> Void

    static let inactive = Self(
        syncTabAcrossWindows: { _, _ in /* No-op. */ },
        reloadTabAcrossWindows: { _, _, _ in /* No-op. */ },
        reloadTabInWindow: { _, _, _, _ in .failed },
        retainWebContentProcessRecovery: { _, _ in false },
        recoverWebContentProcess: { _, _ in .failed },
        cancelWebContentProcessRecovery: { _ in /* No-op. */ },
        setMuteState: { _, _ in /* No-op. */ },
        bindWebViewSession: { _ in /* No-op. */ }
    )
}

@MainActor
struct TabRuntimePersistenceCallbacks {
    var updateNavigationState: (Tab) -> Void
    var scheduleRuntimeStatePersistence: (Tab) -> Void

    static let inactive = Self(
        updateNavigationState: { _ in /* No-op. */ },
        scheduleRuntimeStatePersistence: { _ in /* No-op. */ }
    )
}

@MainActor
struct TabMediaRuntimeCallbacks {
    var scheduleNowPlayingRefresh: (UInt64) -> Void
    var notifyNowPlayingTabUnloaded: (UUID) -> Void

    static let inactive = Self(
        scheduleNowPlayingRefresh: { _ in /* No-op. */ },
        notifyNowPlayingTabUnloaded: { _ in /* No-op. */ }
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
        beginHistorySwipeProtection: { _, _, _, _ in /* No-op. */ },
        finishHistorySwipeProtection: { _, _, _, _ in false },
        cancelWindowMutationsAfterHistorySwipe: { _ in /* No-op. */ },
        flushWindowMutationsAfterHistorySwipe: { _ in /* No-op. */ }
    )
}

@MainActor
struct TabNavigationCommandRuntime {
    var resolvedSearchEngineTemplate: () -> String?
    var prepareExtensionPageNavigation: (Tab, URL, String) -> TabWebViewReplacementOutcome

    init(
        resolvedSearchEngineTemplate: @escaping () -> String?,
        prepareExtensionPageNavigation: @escaping (Tab, URL, String) -> TabWebViewReplacementOutcome = {
            _, _, _ in .notNeeded
        }
    ) {
        self.resolvedSearchEngineTemplate = resolvedSearchEngineTemplate
        self.prepareExtensionPageNavigation = prepareExtensionPageNavigation
    }

    static let inactive = Self(resolvedSearchEngineTemplate: { nil })
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
        updateTitleIfNeeded: { _, _, _, _ in /* No-op. */ },
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
        notifyTabPropertiesChanged: { _, _ in /* No-op. */ }
    )
}

@MainActor
struct TabCloseLifecycleRuntime {
    var cleanupZoomForTab: (UUID) -> Void
    var updateTabVisibility: () -> Void
    var removeTab: (UUID) -> Void

    static let inactive = Self(
        cleanupZoomForTab: { _ in /* No-op. */ },
        updateTabVisibility: { /* No-op. */ },
        removeTab: { _ in /* No-op. */ }
    )
}

@MainActor
struct TabLifecycleNavigationRuntime {
    var resetRevisitProtection: (Tab) -> Void
    var reconcileDocumentSuspensionState: (Tab) -> Void
    var prepareExtensionWebView: (WKWebView, URL, String) -> Void
    var prepareExtensionRuntimeBeforeCommit: (Tab, URL, String) -> Void
    var markExtensionEligibleAfterCommit: (Tab, String) -> Void
    var loadZoomForTab: (UUID, WKWebView) -> Void
    var applyAdblockZapperRulesAfterNavigation: (WKWebView, URL, Tab) -> Void
    var enforceSiteDataPolicyAfterNavigation: (Tab) -> Void
    var resolveAuthenticationChallenge: (
        _ challenge: URLAuthenticationChallenge,
        _ tab: Tab,
        _ webView: WKWebView?,
        _ mainFrameURL: URL?
    ) async -> SumiAuthChallengeDisposition?
    var destructiveDataCleanupNavigationWillStart: (
        WKWebView,
        ObjectIdentifier,
        AnyObject,
        URL?,
        UInt64?
    ) -> Void
    var isPreparingForDataCleanupNavigation: (
        WKWebView,
        ObjectIdentifier,
        AnyObject
    ) -> Bool
    var finishDestructiveDataCleanupNavigation: (
        WKWebView,
        ObjectIdentifier,
        AnyObject,
        Bool
    ) -> Void
    var handleDestructiveDataCleanupProcessTermination: (WKWebView) -> Bool

    static let inactive = Self(
        resetRevisitProtection: { _ in /* No-op. */ },
        reconcileDocumentSuspensionState: { _ in /* No-op. */ },
        prepareExtensionWebView: { _, _, _ in /* No-op. */ },
        prepareExtensionRuntimeBeforeCommit: { _, _, _ in /* No-op. */ },
        markExtensionEligibleAfterCommit: { _, _ in /* No-op. */ },
        loadZoomForTab: { _, _ in /* No-op. */ },
        applyAdblockZapperRulesAfterNavigation: { _, _, _ in /* No-op. */ },
        enforceSiteDataPolicyAfterNavigation: { _ in /* No-op. */ },
        resolveAuthenticationChallenge: { _, _, _, _ in .next },
        destructiveDataCleanupNavigationWillStart: { _, _, _, _, _ in /* No-op. */ },
        isPreparingForDataCleanupNavigation: { _, _, _ in false },
        finishDestructiveDataCleanupNavigation: { _, _, _, _ in /* No-op. */ },
        handleDestructiveDataCleanupProcessTermination: { _ in false }
    )
}

@MainActor
struct TabPermissionSurfaceState: Equatable {
    let isActive: Bool
    let isVisible: Bool

    static let inactive = Self(isActive: false, isVisible: false)
}

@MainActor
struct TabPermissionRuntime {
    var permissionBridges: () -> BrowserPermissionBridgeRegistry?
    var handlePermissionLifecycleEvent: (SumiPermissionLifecycleEvent) -> Void
    var isActiveGlancePreviewSurface: (_ tabId: UUID, _ webView: WKWebView) -> Bool
    var surfaceState: (_ tabId: UUID, _ webView: WKWebView) -> TabPermissionSurfaceState
    var profile: (_ tabId: UUID, _ webView: WKWebView) -> Profile?

    static let inactive = Self(
        permissionBridges: { nil },
        handlePermissionLifecycleEvent: { _ in /* No-op. */ },
        isActiveGlancePreviewSurface: { _, _ in false },
        surfaceState: { _, _ in .inactive },
        profile: { _, _ in nil }
    )
}

@MainActor
enum TabWebViewTeardownIntent: Equatable {
    case suspension
    case retirement
}

@MainActor
struct TabWebViewCleanupRuntime {
    var deferProtectedWebViewCleanup: (WKWebView, UUID, String) -> Bool
    var deferWebsiteDataMutationWebViewMaterialization: (
        Tab,
        @MainActor @Sendable @escaping () -> Void
    ) -> Bool
    var deferWebsiteDataMutationMainFrameSubmission: (
        Tab,
        WKWebView,
        UInt64,
        @MainActor @Sendable @escaping () -> Void
    ) -> Bool
    var retireParkedWebView: (Tab, WKWebView, String) -> Bool
    var removeWebViewFromContainers: (WKWebView) -> Void
    var removeAllWebViews: (
        _ tab: Tab,
        _ intent: TabWebViewTeardownIntent
    ) -> WebViewTabTeardownResult

    static let inactive = Self(
        deferProtectedWebViewCleanup: { _, _, _ in false },
        deferWebsiteDataMutationWebViewMaterialization: { _, _ in false },
        deferWebsiteDataMutationMainFrameSubmission: { _, _, _, _ in false },
        retireParkedWebView: { _, _, _ in false },
        removeWebViewFromContainers: { _ in /* No-op. */ },
        removeAllWebViews: { _, _ in .none }
    )
}

@MainActor
struct TabNormalWebViewExtensionRuntime {
    var registerTabWithExtensionRuntimeIfNeeded: (Tab, String) -> Void
    var prepareWebViewForExtensionRuntime: (WKWebView, URL?, String) -> Void
    var ensureInitialExtensionContextsIfNeeded: (UUID) async -> Void
    var warmInitialDocumentNativeMessagingIfNeeded: (UUID) async -> Void
    var reconcileOnUserGesture: (Tab, String) -> Void = { _, _ in }

    static let inactive = Self(
        registerTabWithExtensionRuntimeIfNeeded: { _, _ in /* No-op. */ },
        prepareWebViewForExtensionRuntime: { _, _, _ in /* No-op. */ },
        ensureInitialExtensionContextsIfNeeded: { _ in /* No-op. */ },
        warmInitialDocumentNativeMessagingIfNeeded: { _ in /* No-op. */ },
        reconcileOnUserGesture: { _, _ in /* No-op. */ }
    )
}

@MainActor
struct TabNavigationDelegateRuntime {
    var externalSchemePermissionBridge: () -> SumiExternalSchemePermissionBridge?
    var downloadManager: () -> DownloadManager?
    var downloadTransportFactory: () -> (any DownloadWebKitTransportAdapting)?
    var autoplayPolicy: @MainActor (URL?, Profile?) -> SumiAutoplayPolicy = {
        _, _ in .default
    }

    static let inactive = Self(
        externalSchemePermissionBridge: { nil },
        downloadManager: { nil },
        downloadTransportFactory: { nil }
    )
}

@MainActor
struct TabFaviconExtensionRuntime {
    var installedExtensions: () -> [InstalledExtension]
    var shortcutLaunchURL: (UUID) -> URL? = { _ in nil }

    static let inactive = Self(
        installedExtensions: { [] },
        shortcutLaunchURL: { _ in nil }
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
        saveDownloadedData: { _, _, _, _ in /* No-op. */ }
    )
}

@MainActor
struct TabWebViewReplacementRuntime {
    var rebuildTrackedWebViews: (
        Tab,
        UUID?,
        URL,
        String,
        DeferredWebViewRebuildConfiguration
    ) -> TabWebViewRebuildResult
    var commitUntrackedReplacement: (
        Tab,
        WKWebView,
        WKWebView
    ) -> WebViewDetachedReplacementCommitOutcome

    static let inactive = Self(
        rebuildTrackedWebViews: { _, _, _, _, _ in .failed },
        commitUntrackedReplacement: { _, _, _ in .rejected }
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
    let webView: WKWebView
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
    private var browserRuntime = TabBrowserRuntimeReference(.inactive)
    private var sharesAttachedBrowserRuntime = false

    var webViewRouting: TabWebViewRoutingRuntime {
        get { browserRuntime.runtime.webViewRoutingRuntime }
        set { set(\.webViewRoutingRuntime, to: newValue) }
    }
    var persistenceCallbacks: TabRuntimePersistenceCallbacks {
        get { browserRuntime.runtime.persistenceRuntimeCallbacks }
        set { set(\.persistenceRuntimeCallbacks, to: newValue) }
    }
    var historySwipeRuntime: TabHistorySwipeRuntime {
        get { browserRuntime.runtime.historySwipeRuntime }
        set { set(\.historySwipeRuntime, to: newValue) }
    }
    var historyRecordingRuntime: TabHistoryRecordingRuntime {
        get { browserRuntime.runtime.historyRecordingRuntime }
        set { set(\.historyRecordingRuntime, to: newValue) }
    }
    var findInPageRuntime: TabFindInPageRuntime {
        get { browserRuntime.runtime.findInPageRuntime }
        set { set(\.findInPageRuntime, to: newValue) }
    }
    var extensionPropertiesRuntime: TabExtensionPropertiesRuntime {
        get { browserRuntime.runtime.extensionPropertiesRuntime }
        set { set(\.extensionPropertiesRuntime, to: newValue) }
    }
    var closeLifecycleRuntime: TabCloseLifecycleRuntime {
        get { browserRuntime.runtime.closeLifecycleRuntime }
        set { set(\.closeLifecycleRuntime, to: newValue) }
    }
    var lifecycleNavigationRuntime: TabLifecycleNavigationRuntime {
        get { browserRuntime.runtime.lifecycleNavigationRuntime }
        set { set(\.lifecycleNavigationRuntime, to: newValue) }
    }
    var permissionRuntime: TabPermissionRuntime {
        get { browserRuntime.runtime.permissionRuntime }
        set { set(\.permissionRuntime, to: newValue) }
    }
    var webViewCleanupRuntime: TabWebViewCleanupRuntime {
        get { browserRuntime.runtime.webViewCleanupRuntime }
        set { set(\.webViewCleanupRuntime, to: newValue) }
    }
    var normalWebViewExtensionRuntime: TabNormalWebViewExtensionRuntime {
        get { browserRuntime.runtime.normalWebViewExtensionRuntime }
        set { set(\.normalWebViewExtensionRuntime, to: newValue) }
    }
    var navigationDelegateRuntime: TabNavigationDelegateRuntime {
        get { browserRuntime.runtime.navigationDelegateRuntime }
        set { set(\.navigationDelegateRuntime, to: newValue) }
    }
    var faviconExtensionRuntime: TabFaviconExtensionRuntime {
        get { browserRuntime.runtime.faviconExtensionRuntime }
        set { set(\.faviconExtensionRuntime, to: newValue) }
    }
    var popupPermissionEvaluator: (any PopupPermissionEvaluating)? {
        get { browserRuntime.runtime.popupPermissionEvaluator }
        set { set(\.popupPermissionEvaluator, to: newValue) }
    }
    var extensionPopupRequestConsumer:
        (any ExtensionPopupRequestConsuming)? {
        get { browserRuntime.runtime.extensionPopupRequestConsumer }
        set { set(\.extensionPopupRequestConsumer, to: newValue) }
    }
    var extensionExternalTabOpening: (any ExtensionExternalTabOpening)? {
        get { browserRuntime.runtime.extensionExternalTabOpening }
        set { set(\.extensionExternalTabOpening, to: newValue) }
    }
    var physicalWebPopupOpening: (any PhysicalWebPopupOpening)? {
        get { browserRuntime.runtime.physicalWebPopupOpening }
        set { set(\.physicalWebPopupOpening, to: newValue) }
    }
    var webKitChildTabOpening: (any WebKitChildTabOpening)? {
        get { browserRuntime.runtime.webKitChildTabOpening }
        set { set(\.webKitChildTabOpening, to: newValue) }
    }
    var webKitChildWindowOpening: (any WebKitChildWindowOpening)? {
        get { browserRuntime.runtime.webKitChildWindowOpening }
        set { set(\.webKitChildWindowOpening, to: newValue) }
    }
    var webKitUIRuntime: TabWebKitUIRuntime {
        get { browserRuntime.runtime.webKitUIRuntime }
        set { set(\.webKitUIRuntime, to: newValue) }
    }
    var webViewReplacementRuntime: TabWebViewReplacementRuntime {
        get { browserRuntime.runtime.webViewReplacementRuntime }
        set { set(\.webViewReplacementRuntime, to: newValue) }
    }
    var navigationCommandRuntime: TabNavigationCommandRuntime {
        get { browserRuntime.runtime.navigationCommandRuntime }
        set { set(\.navigationCommandRuntime, to: newValue) }
    }
    var profileResolutionRuntime: TabProfileResolutionRuntime {
        get { browserRuntime.runtime.profileResolutionRuntime }
        set { set(\.profileResolutionRuntime, to: newValue) }
    }
    var reloadPolicies: TabReloadPolicies {
        get { browserRuntime.runtime.reloadPolicies }
        set { set(\.reloadPolicies, to: newValue) }
    }
    let navigationTransactionOwner = TabNavigationTransactionOwner()
    let navigationStateController = TabNavigationStateController()
    let historyRecorder = HistoryTabRecorder()
    let titleUpdateOwner = TabTitleUpdateOwner()
    let navigationDelegateBundles = NSMapTable<WKWebView, SumiTabNavigationDelegateAdapter>.weakToStrongObjects()

    func attach(browserRuntime: TabBrowserRuntimeReference) {
        self.browserRuntime = browserRuntime
        sharesAttachedBrowserRuntime = true
    }

    private func set<Value>(
        _ keyPath: WritableKeyPath<TabBrowserRuntime, Value>,
        to value: Value
    ) {
        if sharesAttachedBrowserRuntime {
            browserRuntime = TabBrowserRuntimeReference(browserRuntime.runtime)
            sharesAttachedBrowserRuntime = false
        }
        browserRuntime.runtime[keyPath: keyPath] = value
    }
}

@MainActor
final class TabMediaRuntime {
    var lastMediaActivityAt: Date = .distantPast
    var audioStateCancellables: [ObjectIdentifier: AnyCancellable] = [:]
    private(set) var pictureInPictureWebViewIDs: Set<ObjectIdentifier> = []
    private var browserRuntime = TabBrowserRuntimeReference(.inactive)
    private var sharesAttachedBrowserRuntime = false

    var callbacks: TabMediaRuntimeCallbacks {
        get { browserRuntime.runtime.mediaRuntimeCallbacks }
        set {
            if sharesAttachedBrowserRuntime {
                browserRuntime = TabBrowserRuntimeReference(
                    browserRuntime.runtime
                )
                sharesAttachedBrowserRuntime = false
            }
            browserRuntime.runtime.mediaRuntimeCallbacks = newValue
        }
    }

    func attach(browserRuntime: TabBrowserRuntimeReference) {
        self.browserRuntime = browserRuntime
        sharesAttachedBrowserRuntime = true
    }

    var hasActivePictureInPicture: Bool {
        !pictureInPictureWebViewIDs.isEmpty
    }

    func isPictureInPictureActive(for webView: WKWebView) -> Bool {
        pictureInPictureWebViewIDs.contains(ObjectIdentifier(webView))
    }

    func setPictureInPictureActive(_ isActive: Bool, for webView: WKWebView) {
        let webViewID = ObjectIdentifier(webView)
        if isActive {
            pictureInPictureWebViewIDs.insert(webViewID)
        } else {
            pictureInPictureWebViewIDs.remove(webViewID)
        }
    }

    func removePictureInPictureState(for webView: WKWebView) {
        pictureInPictureWebViewIDs.remove(ObjectIdentifier(webView))
    }
}
