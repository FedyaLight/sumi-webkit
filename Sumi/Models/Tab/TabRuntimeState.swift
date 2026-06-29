import AppKit
import Combine
import Foundation
import ObjectiveC.runtime
import SwiftUI
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
    var pendingMainFrameNavigationTask: Task<Void, Never>?
    var pendingMainFrameNavigationToken: UUID?
    var pendingMainFrameNavigationKind: TabMainFrameNavigationKind?
    var pendingBackForwardNavigationContext: TabBackForwardNavigationContext?
    var pendingBackForwardSettleTask: Task<Void, Never>?
    var isFreezingNavigationStateDuringBackForwardGesture = false
    let navigationStateController = TabNavigationStateController()
    let historyRecorder = HistoryTabRecorder()
    let titleUpdateOwner = TabTitleUpdateOwner()
    let navigationDelegateBundles = NSMapTable<WKWebView, SumiTabNavigationDelegateBundle>.weakToStrongObjects()
}

@MainActor
final class TabMediaRuntime {
    var lastMediaActivityAt: Date = .distantPast
    var audioStateCancellables: [ObjectIdentifier: AnyCancellable] = [:]
}

@MainActor
final class TabFaviconRuntime {
    private var resolvedCacheKey: String?
    private var tabExtension: FaviconsTabExtension?
    private var cancellables: Set<AnyCancellable> = []

    @discardableResult
    func applyCachedFaviconOrPlaceholder(
        for url: URL,
        tab: Tab,
        allowCacheLookup: Bool = true
    ) -> Bool {
        let defaultFavicon = SwiftUI.Image(systemName: "globe")
        let referenceKey = TabFaviconStore.referenceKey(forDocumentURL: url)
        let partition = tab.faviconService.partition(profile: tab.resolveProfile())

        if SumiSurface.isSettingsSurfaceURL(url) {
            tab.favicon = SwiftUI.Image(systemName: SumiSurface.settingsTabFaviconSystemImageName)
            tab.faviconIsTemplateGlobePlaceholder = false
            resolvedCacheKey = nil
            return true
        }

        if SumiSurface.isHistorySurfaceURL(url) {
            tab.favicon = SwiftUI.Image(systemName: SumiSurface.historyTabFaviconSystemImageName)
            tab.faviconIsTemplateGlobePlaceholder = false
            resolvedCacheKey = nil
            return true
        }

        if SumiSurface.isBookmarksSurfaceURL(url) {
            tab.favicon = SwiftUI.Image(systemName: SumiSurface.bookmarksTabFaviconSystemImageName)
            tab.faviconIsTemplateGlobePlaceholder = false
            resolvedCacheKey = nil
            return true
        }

        guard allowCacheLookup,
              let referenceKey,
              let image = TabFaviconStore.getCachedImage(
                forReferenceKey: referenceKey,
                partition: partition,
                context: .tabSidebar,
                faviconImageService: tab.faviconImageService
              )
        else {
            if resolvedCacheKey == referenceKey,
               !tab.faviconIsTemplateGlobePlaceholder {
                return false
            }
            tab.favicon = defaultFavicon
            tab.faviconIsTemplateGlobePlaceholder = true
            return false
        }

        tab.favicon = SwiftUI.Image(nsImage: image)
        tab.faviconIsTemplateGlobePlaceholder = false
        resolvedCacheKey = referenceKey
        return true
    }

    func fetchFaviconForVisiblePresentation(tab: Tab) async {
        guard tab.faviconIsTemplateGlobePlaceholder else { return }

        let requestedURL = tab.url
        if applyCachedFaviconOrPlaceholder(for: requestedURL, tab: tab) {
            return
        }

        let partition = tab.faviconService.partition(profile: tab.resolveProfile())
        if let image = await loadExtensionPageFavicon(
            for: requestedURL,
            partition: partition,
            tab: tab
        ),
           !Task.isCancelled,
           tab.url == requestedURL {
            tab.favicon = SwiftUI.Image(nsImage: image)
            tab.faviconIsTemplateGlobePlaceholder = false
            resolvedCacheKey = TabFaviconStore.referenceKey(forDocumentURL: requestedURL)
            return
        }

        if let image = await TabFaviconStore.loadCachedDisplayImage(
            forDocumentURL: requestedURL,
            partition: partition,
            context: .tabSidebar,
            priority: .visibleSidebarOrTabStrip,
            faviconImageService: tab.faviconImageService
        ),
           !Task.isCancelled,
           tab.url == requestedURL {
            tab.favicon = SwiftUI.Image(nsImage: image)
            tab.faviconIsTemplateGlobePlaceholder = false
            resolvedCacheKey = TabFaviconStore.referenceKey(forDocumentURL: requestedURL)
            return
        }

        loadCachedFaviconFromExtension()
    }

    func ensureExtension(tab: Tab, using scriptsProvider: SumiFaviconUserScripts) {
        cancellables = []

        let extensionInstance = FaviconsTabExtension(
            scriptsPublisher: Just(scriptsProvider).eraseToAnyPublisher(),
            tab: tab,
            faviconService: tab.faviconService,
            faviconImageService: tab.faviconImageService
        )
        tabExtension = extensionInstance
        extensionInstance.loadCachedFavicon(previousURL: nil, error: nil)

        var subscriptions = cancellables
        extensionInstance.faviconPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self, weak tab] (image: NSImage?) in
                guard let self, let tab, let image else { return }
                let currentURL = tab.existingWebView?.url ?? tab.url
                guard let referenceKey = TabFaviconStore.referenceKey(forDocumentURL: currentURL) else { return }
                tab.favicon = SwiftUI.Image(nsImage: image)
                tab.faviconIsTemplateGlobePlaceholder = false
                self.resolvedCacheKey = referenceKey
            }
            .store(in: &subscriptions)
        cancellables = subscriptions
    }

    func loadCachedFaviconFromExtension(previousURL: URL? = nil, error: Error? = nil) {
        tabExtension?.loadCachedFavicon(previousURL: previousURL, error: error)
    }

    private func loadExtensionPageFavicon(
        for url: URL,
        partition: SumiFaviconPartition,
        tab: Tab
    ) async -> NSImage? {
        guard ExtensionUtils.isExtensionOwnedURL(url) else { return nil }
        let installedExtensions =
            tab.browserManager?.extensionsModule.managerIfLoadedAndEnabled()?.installedExtensions
            ?? tab.browserManager?.extensionSurfaceStore.installedExtensions
            ?? []
        guard let iconPath = ExtensionUtils.iconPath(
            forExtensionOwnedURL: url,
            installedExtensions: installedExtensions
        ) else {
            return nil
        }

        return await TabFaviconStore.loadExtensionPageImage(
            forDocumentURL: url,
            iconFileURL: URL(fileURLWithPath: iconPath),
            partition: partition,
            context: .tabSidebar,
            faviconImageService: tab.faviconImageService
        )
    }
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
    /// Document sequence when `didOpenTab` last succeeded; `nil` if never notified.
    var openNotifiedDocumentSequence: UInt64?
    /// Profile extension-context binding generation observed at the last pre-commit `didOpenTab`.
    var openNotifiedExtensionContextBindingGeneration: UInt64?
    /// Whether every enabled content-script extension context was loaded when `didOpenTab` last ran.
    var openNotifiedWithLoadedContexts: Bool?
    var lastReportedURL: URL?
    var lastReportedLoadingComplete: Bool?
    var lastReportedTitle: String?
    var didReportOpenForGeneration: UInt64 = 0
    var eligibleGeneration: UInt64 = 0
}

@MainActor
final class TabWebViewOwnershipOwner {
    private(set) var webView: WKWebView?
    private(set) var existingWebView: WKWebView?
    private(set) var primaryWindowId: UUID?

    var assignedWebView: WKWebView? {
        primaryWindowId != nil ? webView : nil
    }

    var isUnloaded: Bool {
        webView == nil
    }

    func setCurrentWebViewForLegacyBridge(_ webView: WKWebView?) {
        self.webView = webView
    }

    func setExistingWebViewForLegacyBridge(_ webView: WKWebView?) {
        existingWebView = webView
    }

    func setPrimaryWindowIdForLegacyBridge(_ primaryWindowId: UUID?) {
        self.primaryWindowId = primaryWindowId
    }

    func parkExistingWebView(_ webView: WKWebView?) {
        existingWebView = webView
    }

    func clearParkedExistingWebView() {
        existingWebView = nil
    }

    func adoptParkedWebViewAsCurrent(_ webView: WKWebView) {
        self.webView = webView
    }

    func replaceUntrackedWebView(_ webView: WKWebView) {
        self.webView = webView
        primaryWindowId = nil
    }

    func assignPrimaryWebView(_ webView: WKWebView, windowId: UUID) {
        self.webView = webView
        primaryWindowId = windowId
    }

    func clearCurrentWebViewOwnership() {
        webView = nil
        primaryWindowId = nil
    }

    func clearAllWebViewOwnership() {
        webView = nil
        existingWebView = nil
        primaryWindowId = nil
    }

    @discardableResult
    func clearCurrentWebViewOwnershipIfIdentical(to webView: WKWebView) -> Bool {
        guard self.webView === webView else { return false }
        clearCurrentWebViewOwnership()
        return true
    }
}

@MainActor
final class TabWebViewRuntime {
    var profileAwaitCancellable: AnyCancellable?
    let reloadPolicyStateOwner = TabReloadPolicyStateOwner()
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
                tab.visitedLinkStore.recordVisitedLink(
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
