import Combine
import Foundation
import ObjectiveC.runtime
import WebKit

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
    var activeWindowId: () -> UUID?
    var webView: (_ tabId: UUID, _ windowId: UUID) -> WKWebView?

    static let inactive = Self(
        activeWindowId: { nil },
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
    var configurationPolicyWebViewReplacementRuntime =
        TabConfigurationPolicyWebViewReplacementRuntime.inactive
    var navigationCommandRuntime = TabNavigationCommandRuntime.inactive
    var profileResolutionRuntime = TabProfileResolutionRuntime.inactive
    var reloadPolicyRuntime = TabReloadPolicyRuntime.empty
    let navigationTransactionOwner = TabNavigationTransactionOwner()
    let navigationStateController = TabNavigationStateController()
    let historyRecorder = HistoryTabRecorder()
    let titleUpdateOwner = TabTitleUpdateOwner()
    let navigationDelegateBundles = NSMapTable<WKWebView, SumiTabNavigationDelegateBundle>.weakToStrongObjects()
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
