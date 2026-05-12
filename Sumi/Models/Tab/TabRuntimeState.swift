import Combine
import AppKit
import Foundation
import ObjectiveC.runtime
import OSLog
import WebKit

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

struct SumiTrackingProtectionReloadRequirement: Equatable {
    let siteHost: String?
    let desiredAttachmentState: SumiTrackingProtectionAttachmentState

    static func == (lhs: SumiTrackingProtectionReloadRequirement, rhs: SumiTrackingProtectionReloadRequirement) -> Bool {
        lhs.siteHost == rhs.siteHost
            && lhs.desiredAttachmentState == rhs.desiredAttachmentState
    }
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
           originHistoryItem === currentHistoryItem
        {
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
    var pendingMainFrameNavigationTask: Task<Void, Never>?
    var pendingMainFrameNavigationToken: UUID?
    var pendingMainFrameNavigationKind: TabMainFrameNavigationKind?
    var pendingBackForwardNavigationContext: TabBackForwardNavigationContext?
    var pendingBackForwardSettleTask: Task<Void, Never>?
    var isFreezingNavigationStateDuringBackForwardGesture = false
    let navigationStateController = TabNavigationStateController()
    let historyRecorder = HistoryTabRecorder()
    let navigationDelegateBundles = NSMapTable<WKWebView, SumiTabNavigationDelegateBundle>.weakToStrongObjects()
}

@MainActor
final class TabMediaRuntime {
    var lastMediaActivityAt: Date = .distantPast
    var audioStateCancellables: [ObjectIdentifier: AnyCancellable] = [:]
}

enum TabPageSuspensionVeto: Equatable {
    case none
    case pageReportedUnableToSuspend
}

@MainActor
final class TabExtensionRuntimeState {
    var controllerGeneration: UInt64 = 0
    var documentSequence: UInt64 = 0
    var committedMainDocumentURL: URL?
    var lastReportedURL: URL?
    var lastReportedLoadingComplete: Bool?
    var lastReportedTitle: String?
    var didReportOpenForGeneration: UInt64 = 0
    var eligibleGeneration: UInt64 = 0
}

@MainActor
final class TabWebViewRuntime {
    var webView: WKWebView?
    var existingWebView: WKWebView?
    var webViewConfigurationOverride: WKWebViewConfiguration?
    var primaryWindowId: UUID?
    var isSuspended: Bool = false
    var lastSuspendedURL: URL?
    var lastSelectedAt: Date?
    var pageSuspensionVeto: TabPageSuspensionVeto = .none
    var hasPictureInPictureVideo: Bool = false
    var isDisplayingPDFDocument: Bool = false
    var isSuspensionRestoreInProgress: Bool = false
    var suspensionRestoreTraceState: OSSignpostIntervalState?
    var profileAwaitCancellable: AnyCancellable?
    var trackingProtectionAppliedAttachmentState: SumiTrackingProtectionAttachmentState?
    var trackingProtectionReloadRequirement: SumiTrackingProtectionReloadRequirement?
    var autoplayReloadRequirement: SumiAutoplayReloadRequirement?
    var lastWebViewInteractionEvent: NSEvent?
    var webViewInteractionCancellables: [ObjectIdentifier: AnyCancellable] = [:]
    var resolvedFaviconCacheKey: String?
    var faviconsTabExtension: FaviconsTabExtension?
    var faviconCancellables: Set<AnyCancellable> = []
    let extensionRuntimeState = TabExtensionRuntimeState()
    let findInPage = FindInPageTabExtension()
}

@MainActor
final class HistoryTabRecorder {
    private enum VisitState {
        case expected
        case added
    }

    private var currentURL: URL? {
        didSet {
            if oldValue != currentURL {
                visitState = .expected
            }
        }
    }
    private var visitState: VisitState = .expected
    private(set) var localVisitIDs: [UUID] = []

    func didCommitMainFrameNavigation(
        to url: URL,
        kind: SumiHistoryNavigationKind,
        tab: Tab
    ) {
        currentURL = url
        guard shouldCapture(url: url, tab: tab), visitState == .expected else { return }

        if kind == .backForward {
            visitState = .added
            return
        }

        addVisit(url: url, tab: tab)
    }

    func didSameDocumentNavigation(to url: URL, type: SumiSameDocumentNavigationType?, tab: Tab) {
        currentURL = url
        guard shouldCapture(url: url, tab: tab) else { return }
        guard type == .anchorNavigation || type == .sessionStatePush else { return }
        addVisit(url: url, tab: tab)
    }

    func updateTitle(_ title: String, tab: Tab) {
        let url = currentURL ?? tab.existingWebView?.url ?? tab.url
        let profile = tab.resolveProfile()
        tab.browserManager?.historyManager.updateTitleIfNeeded(
            title: title,
            url: url,
            profileId: profile?.id ?? tab.browserManager?.currentProfile?.id,
            isEphemeral: profile?.isEphemeral ?? tab.isEphemeral
        )
    }

    private func addVisit(url: URL, tab: Tab) {
        let profile = tab.resolveProfile()
        let title = tab.resolvedHistoryTitle(for: url)
        if let visitID = tab.browserManager?.historyManager.addVisit(
            url: url,
            title: title,
            timestamp: Date(),
            tabId: tab.id,
            profileId: profile?.id ?? tab.browserManager?.currentProfile?.id,
            isEphemeral: profile?.isEphemeral ?? tab.isEphemeral
        ) {
            localVisitIDs.append(visitID)
            if let profile {
                SharedVisitedLinkStoreProvider.shared.recordVisitedLink(
                    url,
                    for: profile,
                    sourceConfiguration: tab.existingWebView?.configuration
                )
            }
        }
        visitState = .added
    }

    private func shouldCapture(url: URL, tab: Tab) -> Bool {
        guard !tab.isEphemeral else { return false }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        return true
    }
}
