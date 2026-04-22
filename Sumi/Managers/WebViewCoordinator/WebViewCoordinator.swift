//
//  WebViewCoordinator.swift
//  Sumi
//
//  Manages WebView instances across multiple windows
//

import Foundation
import AppKit
import Observation
import WebKit

enum WebViewSyncLoadPolicy {
    static func shouldLoadTarget(
        desiredURL: URL,
        targetURL: URL?,
        targetHistoryURL: URL?,
        isOriginatingWebView: Bool
    ) -> Bool {
        guard !isOriginatingWebView else { return false }
        guard targetURL != desiredURL else { return false }
        guard targetHistoryURL != desiredURL else { return false }
        return true
    }
}

enum VisibleTabPreparationPlan {
    static func visibleTabIDs(
        currentTabId: UUID?,
        isSplit: Bool,
        leftTabId: UUID?,
        rightTabId: UUID?,
        isPreviewActive: Bool
    ) -> [UUID] {
        guard let currentTabId else { return [] }
        guard !isPreviewActive else { return [currentTabId] }

        let isCurrentSplitPane = currentTabId == leftTabId || currentTabId == rightTabId
        guard isSplit, isCurrentSplitPane else {
            return [currentTabId]
        }

        var orderedIDs: [UUID] = []
        if let leftTabId {
            orderedIDs.append(leftTabId)
        }
        if let rightTabId, rightTabId != leftTabId {
            orderedIDs.append(rightTabId)
        }
        return orderedIDs.isEmpty ? [currentTabId] : orderedIDs
    }
}

enum HistorySwipeCompositorMutationPolicy {
    static func shouldDeferMutation(isProtectedSource: Bool) -> Bool {
        isProtectedSource
    }
}

@MainActor
final class SumiWebViewContainerView: NSView {
    let tabID: UUID
    let windowID: UUID
    let webView: WKWebView
    var fullscreenStateDidChange: ((SumiWebViewContainerView, WKWebView.FullscreenState) -> Void)?
    private var fullscreenStateObservation: NSKeyValueObservation?

    override var constraints: [NSLayoutConstraint] { [] }

    init(tabID: UUID, windowID: UUID, webView: WKWebView) {
        self.tabID = tabID
        self.windowID = windowID
        self.webView = webView
        super.init(frame: .zero)

        autoresizingMask = [.width, .height]
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = [.width, .height]
        attachDisplayedWebViewIfNeeded()
        observeFullscreenState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        attachDisplayedWebViewIfNeeded()
        webView.sumiFullscreenTabContentViewForHost?.frame = bounds
    }

    override func removeFromSuperview() {
        detachWebViewForCleanup()
        super.removeFromSuperview()
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        guard webView.sumiTabContentView !== webView else { return }
        subview.frame = bounds
        subview.autoresizingMask = [.width, .height]
    }

    func attachDisplayedWebViewIfNeeded() {
        guard let displayedView = webView.sumiFullscreenTabContentViewForHost else { return }

        if displayedView.superview !== self {
            displayedView.removeFromSuperview()
            addSubview(displayedView)
        }

        displayedView.frame = bounds
        displayedView.autoresizingMask = [.width, .height]
    }

    func detachWebViewForCleanup() {
        guard let displayedView = webView.sumiFullscreenTabContentViewForHost else { return }
        if displayedView.superview === self {
            displayedView.removeFromSuperview()
        }
    }

    private func observeFullscreenState() {
        fullscreenStateObservation = webView.observe(
            \.fullscreenState,
            options: [.new]
        ) { [weak self] _, change in
            guard let self, let state = change.newValue else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if state != .notInFullscreen {
                    self.attachDisplayedWebViewIfNeeded()
                }
                self.fullscreenStateDidChange?(self, state)
            }
        }
    }
}

private struct HistorySwipeProtectionContext {
    let tabID: UUID
    let windowID: UUID?
    let webViewID: ObjectIdentifier
    let hostID: ObjectIdentifier?
    let originURL: URL?
    let originHistoryItem: WKBackForwardListItem?
    let originHistoryURL: URL?
}

private struct FullscreenVideoSessionContext {
    let tabID: UUID
    let windowID: UUID
    let webViewID: ObjectIdentifier
    weak var host: SumiWebViewContainerView?
    weak var previousFirstResponder: NSResponder?
}

enum CompositorPaneDestination: String, CaseIterable {
    case single
    case left
    case right

    var viewIdentifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("SumiCompositorPane.\(rawValue)")
    }

    static func resolve(from view: NSView) -> Self? {
        var current: NSView? = view
        while let candidate = current {
            if let identifier = candidate.identifier,
               let destination = allCases.first(where: { $0.viewIdentifier == identifier })
            {
                return destination
            }
            current = candidate.superview
        }
        return nil
    }

    func resolve(in root: NSView) -> NSView? {
        root.sumiFirstSubview(matching: viewIdentifier)
    }
}

private struct WeakWKWebView {
    weak var value: WKWebView?
}

enum DeferredWebViewCommandKey: Hashable {
    case attachHost(ObjectIdentifier)
    case removeWebViewFromContainers(ObjectIdentifier)
    case removeAllWebViews(UUID)
    case cleanupWindow(UUID)
    case cleanupAllWebViews
    case rebuildLiveWebViews(UUID)
    case evictHiddenWebViews(UUID)
    case cleanupTabWebView(ObjectIdentifier)
    case performFallbackWebViewCleanup(ObjectIdentifier)
}

enum DeferredWebViewCommand {
    case attachHost(
        tabID: UUID,
        windowID: UUID,
        webViewID: ObjectIdentifier,
        destination: CompositorPaneDestination
    )
    case removeWebViewFromContainers(webViewID: ObjectIdentifier)
    case removeAllWebViews(tabID: UUID)
    case cleanupWindow(windowID: UUID)
    case cleanupAllWebViews
    case rebuildLiveWebViews(tabID: UUID, preferredPrimaryWindowID: UUID?)
    case evictHiddenWebViews(windowID: UUID)
    case cleanupTabWebView(webViewID: ObjectIdentifier, tabID: UUID)
    case performFallbackWebViewCleanup(webViewID: ObjectIdentifier, tabID: UUID)

    var key: DeferredWebViewCommandKey {
        switch self {
        case .attachHost(_, _, let webViewID, _):
            return .attachHost(webViewID)
        case .removeWebViewFromContainers(let webViewID):
            return .removeWebViewFromContainers(webViewID)
        case .removeAllWebViews(let tabID):
            return .removeAllWebViews(tabID)
        case .cleanupWindow(let windowID):
            return .cleanupWindow(windowID)
        case .cleanupAllWebViews:
            return .cleanupAllWebViews
        case .rebuildLiveWebViews(let tabID, _):
            return .rebuildLiveWebViews(tabID)
        case .evictHiddenWebViews(let windowID):
            return .evictHiddenWebViews(windowID)
        case .cleanupTabWebView(let webViewID, _):
            return .cleanupTabWebView(webViewID)
        case .performFallbackWebViewCleanup(let webViewID, _):
            return .performFallbackWebViewCleanup(webViewID)
        }
    }

    var debugSummary: String {
        switch self {
        case .attachHost(let tabID, let windowID, let webViewID, let destination):
            return "attachHost tab=\(tabID.uuidString.prefix(8)) window=\(windowID.uuidString.prefix(8)) webView=\(webViewID) pane=\(destination.rawValue)"
        case .removeWebViewFromContainers(let webViewID):
            return "removeWebViewFromContainers webView=\(webViewID)"
        case .removeAllWebViews(let tabID):
            return "removeAllWebViews tab=\(tabID.uuidString.prefix(8))"
        case .cleanupWindow(let windowID):
            return "cleanupWindow window=\(windowID.uuidString.prefix(8))"
        case .cleanupAllWebViews:
            return "cleanupAllWebViews"
        case .rebuildLiveWebViews(let tabID, let preferredPrimaryWindowID):
            return "rebuildLiveWebViews tab=\(tabID.uuidString.prefix(8)) preferredWindow=\(preferredPrimaryWindowID?.uuidString.prefix(8) ?? "nil")"
        case .evictHiddenWebViews(let windowID):
            return "evictHiddenWebViews window=\(windowID.uuidString.prefix(8))"
        case .cleanupTabWebView(let webViewID, let tabID):
            return "cleanupTabWebView tab=\(tabID.uuidString.prefix(8)) webView=\(webViewID)"
        case .performFallbackWebViewCleanup(let webViewID, let tabID):
            return "performFallbackWebViewCleanup tab=\(tabID.uuidString.prefix(8)) webView=\(webViewID)"
        }
    }
}

enum DeferredProtectedCommandEnqueueOutcome {
    case enqueued
    case collapsed
    case droppedAtCapacity
}

struct DeferredProtectedCommandBuffer {
    static let maxCommands = 8

    private(set) var commands: [DeferredWebViewCommand] = []

    var count: Int { commands.count }
    var isEmpty: Bool { commands.isEmpty }

    mutating func enqueue(_ command: DeferredWebViewCommand) -> DeferredProtectedCommandEnqueueOutcome {
        if let index = commands.firstIndex(where: { $0.key == command.key }) {
            commands[index] = command
            return .collapsed
        }
        guard commands.count < Self.maxCommands else {
            return .droppedAtCapacity
        }
        commands.append(command)
        return .enqueued
    }

    mutating func prune(
        where shouldDrop: (DeferredWebViewCommand) -> Bool
    ) -> [DeferredWebViewCommand] {
        var dropped: [DeferredWebViewCommand] = []
        commands.removeAll { command in
            guard shouldDrop(command) else { return false }
            dropped.append(command)
            return true
        }
        return dropped
    }

    mutating func drain() -> [DeferredWebViewCommand] {
        let drained = commands
        commands.removeAll(keepingCapacity: true)
        return drained
    }

    func summaries() -> [String] {
        commands.map(\.debugSummary)
    }
}

private struct TrackedWebViewOwner: Equatable {
    let tabID: UUID
    let windowID: UUID
}

private extension NSView {
    func sumiFirstSubview(
        matching identifier: NSUserInterfaceItemIdentifier
    ) -> NSView? {
        if self.identifier == identifier {
            return self
        }
        for subview in subviews {
            if let match = subview.sumiFirstSubview(matching: identifier) {
                return match
            }
        }
        return nil
    }
}

@MainActor
@Observable
class WebViewCoordinator {
    /// Window-specific web views: tabId -> windowId -> WKWebView
    @ObservationIgnored
    private var webViewsByTabAndWindow: [UUID: [UUID: WKWebView]] = [:]

    /// Stable AppKit hosts for web views. UI/compositor code attaches these containers, never naked WKWebView instances.
    @ObservationIgnored
    private var webViewHostsByTabAndWindow: [UUID: [UUID: SumiWebViewContainerView]] = [:]

    @ObservationIgnored
    private var webViewOwnersByIdentifier: [ObjectIdentifier: TrackedWebViewOwner] = [:]

    @ObservationIgnored
    private var recentlyVisibleTabIDsByWindow: [UUID: [UUID]] = [:]

    /// Prevent recursive sync calls
    @ObservationIgnored
    private var isSyncingTab: Set<UUID> = []

    /// Weak wrapper for NSView references stored per window
    private struct WeakNSView { weak var view: NSView? }

    /// Container views per window so the compositor can manage multiple windows safely
    @ObservationIgnored
    private var compositorContainerViews: [UUID: WeakNSView] = [:]

    /// Coalesce WebView creation requests so SwiftUI update passes never create WebViews inline.
    @ObservationIgnored
    private var scheduledPrepareWindowIds: Set<UUID> = []

    @ObservationIgnored
    weak var browserManager: BrowserManager?

    @ObservationIgnored
    private var activeHistorySwipeProtections: [ObjectIdentifier: HistorySwipeProtectionContext] = [:]

    @ObservationIgnored
    private var activeFullscreenVideoSessions: [ObjectIdentifier: FullscreenVideoSessionContext] = [:]

    @ObservationIgnored
    private var deferredProtectedWebViewCommands: [ObjectIdentifier: DeferredProtectedCommandBuffer] = [:]

    @ObservationIgnored
    private var weakWebViewsByIdentifier: [ObjectIdentifier: WeakWKWebView] = [:]

    private let hiddenWarmWebViewBufferPerWindow = 1

    // MARK: - Compositor Container Management

    func setCompositorContainerView(_ view: NSView?, for windowId: UUID) {
        if let view {
            compositorContainerViews[windowId] = WeakNSView(view: view)
        } else {
            compositorContainerViews.removeValue(forKey: windowId)
        }
    }

    func compositorContainerView(for windowId: UUID) -> NSView? {
        if let view = compositorContainerViews[windowId]?.view {
            return view
        }
        compositorContainerViews.removeValue(forKey: windowId)
        return nil
    }

    func removeCompositorContainerView(for windowId: UUID) {
        compositorContainerViews.removeValue(forKey: windowId)
        scheduledPrepareWindowIds.remove(windowId)
        recentlyVisibleTabIDsByWindow.removeValue(forKey: windowId)
        pruneInvalidDeferredProtectedCommands(reason: "removeCompositorContainerView")
    }

    func compositorContainers() -> [(UUID, NSView)] {
        var result: [(UUID, NSView)] = []
        var staleIdentifiers: [UUID] = []
        for (windowId, entry) in compositorContainerViews {
            if let view = entry.view {
                result.append((windowId, view))
            } else {
                staleIdentifiers.append(windowId)
            }
        }
        for id in staleIdentifiers {
            compositorContainerViews.removeValue(forKey: id)
        }
        return result
    }

    // MARK: - WebView Pool Management

    func getWebView(for tabId: UUID, in windowId: UUID) -> WKWebView? {
        webViewsByTabAndWindow[tabId]?[windowId]
    }

    func getWebViewHost(for tabId: UUID, in windowId: UUID) -> SumiWebViewContainerView? {
        guard let host = webViewHostsByTabAndWindow[tabId]?[windowId] else { return nil }
        guard webViewsByTabAndWindow[tabId]?[windowId] === host.webView else {
            webViewHostsByTabAndWindow[tabId]?[windowId] = nil
            cleanupEmptyTrackingBuckets(for: tabId)
            return nil
        }
        return host
    }

    func getAllWebViews(for tabId: UUID) -> [WKWebView] {
        guard let windowWebViews = webViewsByTabAndWindow[tabId] else { return [] }
        return Array(windowWebViews.values)
    }

    func windowIDs(for tabId: UUID) -> [UUID] {
        guard let windowWebViews = webViewsByTabAndWindow[tabId] else { return [] }
        return Array(windowWebViews.keys)
    }

    func setWebView(_ webView: WKWebView, for tabId: UUID, in windowId: UUID) {
        registerTrackedWebView(webView, for: tabId, in: windowId)
        ensureWebViewHost(for: webView, tabId: tabId, windowId: windowId)
    }

    @discardableResult
    private func ensureWebViewHost(
        for webView: WKWebView,
        tabId: UUID,
        windowId: UUID
    ) -> SumiWebViewContainerView {
        if webViewHostsByTabAndWindow[tabId] == nil {
            webViewHostsByTabAndWindow[tabId] = [:]
        }
        if let existing = webViewHostsByTabAndWindow[tabId]?[windowId],
           existing.webView === webView
        {
            return existing
        }

        let host = SumiWebViewContainerView(
            tabID: tabId,
            windowID: windowId,
            webView: webView
        )
        host.fullscreenStateDidChange = { [weak self] host, state in
            self?.handleFullscreenStateChange(for: host, state: state)
        }
        if webView.sumiIsInFullscreenElementPresentation {
            handleFullscreenStateChange(for: host, state: webView.fullscreenState)
        }
        webViewHostsByTabAndWindow[tabId]?[windowId] = host
        return host
    }

    @discardableResult
    func prepareVisibleWebViews(
        for windowState: BrowserWindowState,
        browserManager: BrowserManager
    ) -> Bool {
        let signpostState = PerformanceTrace.beginInterval("WebViewCoordinator.prepareVisibleWebViews")
        defer {
            PerformanceTrace.endInterval(
                "WebViewCoordinator.prepareVisibleWebViews",
                signpostState
            )
        }

        let visibleTabIDs = visibleTabIDs(for: windowState, browserManager: browserManager)
        noteVisibleTabs(visibleTabIDs, in: windowState.id)
        var didCreateWebView = false
        for tabId in visibleTabIDs {
            guard let tab = resolveTab(for: tabId, in: windowState, browserManager: browserManager) else {
                continue
            }

            browserManager.compositorManager.markTabAccessed(tab.id)
            if getWebView(for: tab.id, in: windowState.id) == nil {
                _ = getOrCreateWebView(
                    for: tab,
                    in: windowState.id,
                    tabManager: browserManager.tabManager
                )
                didCreateWebView = true
            }
        }

        evictHiddenWebViewsIfNeeded(
            in: windowState.id,
            visibleTabIDs: Set(visibleTabIDs),
            tabManager: browserManager.tabManager
        )

        return didCreateWebView
    }

    func schedulePrepareVisibleWebViews(
        for windowState: BrowserWindowState,
        browserManager: BrowserManager
    ) {
        let windowId = windowState.id
        guard scheduledPrepareWindowIds.insert(windowId).inserted else { return }

        DispatchQueue.main.async { [weak self, weak browserManager, weak windowState] in
            guard let self else { return }
            self.scheduledPrepareWindowIds.remove(windowId)

            guard let browserManager, let windowState else { return }
            let didCreateWebView = self.prepareVisibleWebViews(
                for: windowState,
                browserManager: browserManager
            )
            if didCreateWebView {
                browserManager.refreshCompositor(for: windowState)
            }
        }
    }

    // MARK: - History Swipe Protection

    func beginHistorySwipeProtection(
        tabId: UUID,
        webView: WKWebView,
        originURL: URL?,
        originHistoryItem: WKBackForwardListItem?
    ) {
        let webViewID = ObjectIdentifier(webView)
        noteWeakWebView(webView)
        let windowId = windowId(containing: webView)
        let host = host(containing: webView)
        activeHistorySwipeProtections[webViewID] = HistorySwipeProtectionContext(
            tabID: tabId,
            windowID: windowId,
            webViewID: webViewID,
            hostID: host.map(ObjectIdentifier.init),
            originURL: originURL,
            originHistoryItem: originHistoryItem,
            originHistoryURL: originHistoryItem?.url
        )
        RuntimeDiagnostics.swipeTrace(
            "begin tab=\(tabId.uuidString.prefix(8)) window=\(windowId?.uuidString.prefix(8) ?? "nil") webView=\(webViewID) host=\(host.map { String(describing: ObjectIdentifier($0)) } ?? "nil") url=\((originURL ?? originHistoryItem?.url)?.absoluteString ?? "nil")"
        )
    }

    @discardableResult
    func finishHistorySwipeProtection(
        tabId: UUID,
        webView: WKWebView?,
        currentURL: URL?,
        currentHistoryItem: WKBackForwardListItem?
    ) -> Bool {
        guard let webView else { return false }
        let webViewID = ObjectIdentifier(webView)
        let context = activeHistorySwipeProtections.removeValue(forKey: webViewID)
        let wasCancelled = isCancelledHistorySwipe(
            context: context,
            currentURL: currentURL,
            currentHistoryItem: currentHistoryItem
        )
        RuntimeDiagnostics.swipeTrace(
            "finish tab=\(tabId.uuidString.prefix(8)) webView=\(webViewID) cancelled=\(wasCancelled) url=\((currentURL ?? currentHistoryItem?.url)?.absoluteString ?? "nil")"
        )
        flushDeferredProtectedCommands(for: webViewID)
        return wasCancelled
    }

    func hasActiveHistorySwipe(in windowId: UUID) -> Bool {
        activeHistorySwipeProtections.values.contains { $0.windowID == windowId }
    }

    func hasActiveFullscreenVideo(in windowId: UUID) -> Bool {
        activeFullscreenVideoSessions.values.contains { $0.windowID == windowId }
    }

    func isWebViewProtectedFromCompositorMutation(_ webView: WKWebView) -> Bool {
        let webViewID = ObjectIdentifier(webView)
        return activeHistorySwipeProtections[webViewID] != nil
            || activeFullscreenVideoSessions[webViewID] != nil
            || webView.sumiIsInFullscreenElementPresentation
    }

    func isHostProtectedFromCompositorMutation(_ host: SumiWebViewContainerView) -> Bool {
        isWebViewProtectedFromCompositorMutation(host.webView)
    }

    func isViewProtectedFromCompositorMutation(_ view: NSView) -> Bool {
        if let host = view as? SumiWebViewContainerView {
            return isHostProtectedFromCompositorMutation(host)
        }
        if let webView = view as? WKWebView {
            return isWebViewProtectedFromCompositorMutation(webView)
        }
        return false
    }

    func windowID(containing webView: WKWebView) -> UUID? {
        windowId(containing: webView)
    }

    @discardableResult
    func attachHost(
        _ host: SumiWebViewContainerView,
        to container: NSView
    ) -> Bool {
        let deferredDestination = CompositorPaneDestination.resolve(from: container)
        if host.superview !== container,
           let deferredDestination,
           enqueueDeferredHistorySwipeCommand(
                .attachHost(
                    tabID: host.tabID,
                    windowID: host.windowID,
                    webViewID: ObjectIdentifier(host.webView),
                    destination: deferredDestination
                ),
                for: host.webView,
                reason: "attachHost"
           )
        {
            RuntimeDiagnostics.swipeTrace(
                "deferAttach tab=\(host.tabID.uuidString.prefix(8)) window=\(host.windowID.uuidString.prefix(8)) host=\(ObjectIdentifier(host))"
            )
            return false
        }

        if host.superview !== container {
            host.removeFromSuperview()
            container.addSubview(host)
        }

        host.attachDisplayedWebViewIfNeeded()
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        host.webView.sumiFullscreenTabContentViewForHost?.frame = host.bounds
        host.isHidden = false
        host.webView.sumiFullscreenTabContentViewForHost?.isHidden = false
        return true
    }

    func reconcileHostedSubviews(
        in container: NSView,
        keeping keepView: NSView?
    ) {
        for subview in container.subviews where subview !== keepView {
            if isViewProtectedFromCompositorMutation(subview) {
                RuntimeDiagnostics.swipeTrace(
                    "skipPruneProtected view=\(ObjectIdentifier(subview))"
                )
                subview.isHidden = true
                continue
            }
            subview.removeFromSuperview()
        }
        keepView?.isHidden = false
    }

    private func handleFullscreenStateChange(
        for host: SumiWebViewContainerView,
        state: WKWebView.FullscreenState
    ) {
        let webViewID = ObjectIdentifier(host.webView)

        if state == .notInFullscreen {
            let context = activeFullscreenVideoSessions.removeValue(forKey: webViewID)
            RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
                "Ended fullscreen video session for tab=\(host.tabID.uuidString.prefix(8)) window=\(host.windowID.uuidString.prefix(8))."
            }
            restoreAfterFullscreenVideoExit(context: context, host: host)
            flushDeferredProtectedCommands(for: webViewID)
            return
        }

        if activeFullscreenVideoSessions[webViewID] == nil {
            noteWeakWebView(host.webView)
            activeFullscreenVideoSessions[webViewID] = FullscreenVideoSessionContext(
                tabID: host.tabID,
                windowID: host.windowID,
                webViewID: webViewID,
                host: host,
                previousFirstResponder: host.window?.firstResponder
            )
            RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
                "Began fullscreen video session for tab=\(host.tabID.uuidString.prefix(8)) window=\(host.windowID.uuidString.prefix(8))."
            }
        }
    }

    private func restoreAfterFullscreenVideoExit(
        context: FullscreenVideoSessionContext?,
        host: SumiWebViewContainerView
    ) {
        guard let tab = (host.webView as? FocusableWKWebView)?.owningTab,
              let browserManager = tab.browserManager,
              let windowState = browserManager.windowRegistry?.windows[host.windowID]
        else {
            SumiNativeNowPlayingController.shared.scheduleRefresh(delayNanoseconds: 0)
            return
        }

        browserManager.refreshCompositor(for: windowState)

        Task { @MainActor [weak self, weak browserManager, weak windowState, weak tab] in
            await Task.yield()
            guard let self,
                  let browserManager,
                  let windowState,
                  let tab,
                  browserManager.currentTab(for: windowState)?.id == tab.id,
                  let window = windowState.window,
                  let restoredHost = self.getWebViewHost(for: tab.id, in: windowState.id)
            else {
                SumiNativeNowPlayingController.shared.scheduleRefresh(delayNanoseconds: 0)
                return
            }

            restoredHost.attachDisplayedWebViewIfNeeded()
            guard restoredHost.webView.window === window else {
                SumiNativeNowPlayingController.shared.scheduleRefresh(delayNanoseconds: 0)
                return
            }

            if window.firstResponder !== restoredHost.webView {
                window.makeFirstResponder(restoredHost.webView)
            }
            SumiNativeNowPlayingController.shared.scheduleRefresh(delayNanoseconds: 0)
        }
    }

    private func flushDeferredProtectedCommands(for webViewID: ObjectIdentifier) {
        guard activeHistorySwipeProtections[webViewID] == nil,
              activeFullscreenVideoSessions[webViewID] == nil
        else { return }
        pruneInvalidDeferredProtectedCommands(reason: "flush.preflight")
        var buffer = deferredProtectedWebViewCommands.removeValue(forKey: webViewID)
        let commands = buffer?.drain() ?? []
        guard !commands.isEmpty else { return }
        Task { @MainActor in
            let signpostState = PerformanceTrace.beginInterval(
                "WebViewCoordinator.flushDeferredProtectedCommands"
            )
            defer {
                PerformanceTrace.endInterval(
                    "WebViewCoordinator.flushDeferredProtectedCommands",
                    signpostState
                )
            }

            RuntimeDiagnostics.swipeTrace(
                "flushDeferredCommands sourceWebView=\(webViewID) count=\(commands.count)"
            )

            for command in commands {
                if executeDeferredProtectedCommand(
                    command,
                    sourceWebViewID: webViewID
                ) == false {
                    dropDeferredProtectedCommand(
                        command,
                        sourceWebViewID: webViewID,
                        reason: "flush.invalidTarget"
                    )
                }
            }
        }
    }

    private func isCancelledHistorySwipe(
        context: HistorySwipeProtectionContext?,
        currentURL: URL?,
        currentHistoryItem: WKBackForwardListItem?
    ) -> Bool {
        guard let context else { return false }
        if let originHistoryItem = context.originHistoryItem,
           let currentHistoryItem,
           originHistoryItem === currentHistoryItem
        {
            return true
        }
        let originURL = context.originHistoryURL ?? context.originURL
        let currentURL = currentHistoryItem?.url ?? currentURL
        return originURL != nil && originURL == currentURL
    }

    // MARK: - Smart WebView Assignment (Memory Optimization)
    
    /// Gets or creates a WebView for the specified tab and window.
    /// Implements smart assignment to prevent duplicate WebViews:
    /// - If no window is displaying this tab yet, creates a "primary" WebView
    /// - If another window is already displaying this tab, creates a "clone" WebView
    /// - Returns existing WebView if this window already has one
    func getOrCreateWebView(for tab: Tab, in windowId: UUID, tabManager: TabManager) -> WKWebView {
        let tabId = tab.id

        // Check if this window already has a WebView for this tab
        if let existing = getWebView(for: tabId, in: windowId) {
            return existing
        }

        if let adoptedWebView = adoptExistingPrimaryWebViewIfNeeded(for: tab, in: windowId) {
            return adoptedWebView
        }
        
        // Check if another window already has this tab displayed
        let allWindowsForTab = webViewsByTabAndWindow[tabId] ?? [:]
        let otherWindows = allWindowsForTab.filter { $0.key != windowId }
        
        if otherWindows.isEmpty {
            // This is the FIRST window to display this tab
            // Create the "primary" WebView and assign it to this tab
            let primaryWebView = createPrimaryWebView(for: tab, in: windowId)
            return primaryWebView
        } else {
            // Another window is already displaying this tab
            // Create a "clone" WebView for this window
            let cloneWebView = createCloneWebView(for: tab, in: windowId, primaryWindowId: otherWindows.first!.key)
            
            return cloneWebView
        }
    }
    
    /// Creates the "primary" WebView - the first WebView for a tab
    /// This WebView is owned by the tab and is the "source of truth"
    private func createPrimaryWebView(for tab: Tab, in windowId: UUID) -> WKWebView {
        if let adoptedWebView = adoptExistingPrimaryWebViewIfNeeded(for: tab, in: windowId) {
            return adoptedWebView
        }

        let webView = createWebViewInternal(for: tab, in: windowId, isPrimary: true)
        tab.assignWebViewToWindow(webView, windowId: windowId)
        return webView
    }
    
    /// Creates a "clone" WebView - additional WebViews for multi-window display
    /// These share the configuration but are separate instances
    private func createCloneWebView(for tab: Tab, in windowId: UUID, primaryWindowId: UUID) -> WKWebView {
        let tabId = tab.id

        // Get the primary WebView to copy configuration
        let primaryWebView = getWebView(for: tabId, in: primaryWindowId)
        
        // Create clone with shared configuration
        return createWebViewInternal(for: tab, in: windowId, isPrimary: false, copyFrom: primaryWebView)
    }
    
    /// Internal method to create a WebView with proper configuration
    private func createWebViewInternal(for tab: Tab, in windowId: UUID, isPrimary: Bool, copyFrom: WKWebView? = nil) -> WKWebView {
        let tabId = tab.id

        let configuration = resolvedConfiguration(
            for: tab,
            copying: copyFrom ?? tab.existingWebView
        )
        BrowserConfiguration.shared.applySitePermissionOverrides(
            to: configuration,
            url: tab.url,
            profileId: tab.resolveProfile()?.id ?? tab.profileId
        )
        tab.browserManager?.extensionManager.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            reason: "WebViewCoordinator.createWebViewInternal.configuration"
        )

        let newWebView = FocusableWKWebView(frame: .zero, configuration: configuration)
        newWebView.navigationDelegate = tab
        newWebView.uiDelegate = tab
        newWebView.allowsBackForwardNavigationGestures = true
        newWebView.allowsMagnification = true
        newWebView.setValue(true, forKey: "drawsBackground")
        newWebView.owningTab = tab
        newWebView.contextMenuBridge = WebContextMenuBridge(tab: tab, configuration: configuration)
        tab.replaceCoreScriptMessageHandlers(
            on: newWebView.configuration.userContentController
        )
        tab.installRuntimeObservers(on: newWebView)
        setWebView(newWebView, for: tabId, in: windowId)

        // Only load URL if this is the primary or if we're creating a clone
        // For clones, we sync the URL via syncTab later
        if let url = URL(string: tab.url.absoluteString) {
            prepareInitialExtensionNavigation(
                for: newWebView,
                tab: tab,
                in: windowId,
                url: url
            )
            if #available(macOS 15.5, *) {
                tab.performMainFrameNavigationAfterHydrationIfNeeded(
                    on: newWebView,
                    url: url
                ) { resolvedWebView in
                    resolvedWebView.load(URLRequest(url: url))
                }
            } else {
                tab.performMainFrameNavigation(
                    on: newWebView,
                    url: url
                ) { resolvedWebView in
                    resolvedWebView.load(URLRequest(url: url))
                }
            }
        }
        newWebView.sumiSetAudioMuted(tab.audioState.isMuted)
        
        return newWebView
    }

    func removeWebViewFromContainers(_ webView: WKWebView) {
        if enqueueDeferredProtectedCommand(
            .removeWebViewFromContainers(webViewID: ObjectIdentifier(webView)),
            for: webView,
            reason: "removeWebViewFromContainers"
        ) {
            return
        }

        if let host = host(containing: webView) {
            RuntimeDiagnostics.swipeTrace(
                "removeHost webView=\(ObjectIdentifier(webView)) host=\(ObjectIdentifier(host))"
            )
            host.removeFromSuperview()
        }

        for (windowId, entry) in compositorContainerViews {
            guard let container = entry.view else {
                compositorContainerViews.removeValue(forKey: windowId)
                continue
            }
            removeMatchingWebView(webView, from: container)
        }
    }

    /// `WKWebView` instances live under pane views, not only as direct children of the compositor container.
    private func removeMatchingWebView(_ webView: WKWebView, from root: NSView) {
        for subview in Array(root.subviews) {
            if let host = subview as? SumiWebViewContainerView,
               host.webView === webView
            {
                host.removeFromSuperview()
            } else if subview === webView {
                subview.removeFromSuperview()
            } else {
                removeMatchingWebView(webView, from: subview)
            }
        }
    }

    private func host(containing webView: WKWebView) -> SumiWebViewContainerView? {
        guard let owner = trackedOwner(containing: webView) else { return nil }
        guard let host = webViewHostsByTabAndWindow[owner.tabID]?[owner.windowID] else {
            return nil
        }
        guard host.webView === webView else {
            webViewHostsByTabAndWindow[owner.tabID]?[owner.windowID] = nil
            cleanupEmptyTrackingBuckets(for: owner.tabID)
            return nil
        }
        return host
    }

    private func windowId(containing webView: WKWebView) -> UUID? {
        guard let owner = trackedOwner(containing: webView) else { return nil }
        if webViewHostsByTabAndWindow[owner.tabID]?[owner.windowID]?.webView !== webView {
            ensureWebViewHost(for: webView, tabId: owner.tabID, windowId: owner.windowID)
        }
        return owner.windowID
    }

    @discardableResult
    func removeAllWebViews(for tab: Tab) -> Bool {
        let currentEntries = webViewsByTabAndWindow[tab.id] ?? [:]
        let protectedCandidateWebViews = uniqueWebViews(
            Array(currentEntries.values)
                + [tab.assignedWebView, tab.existingWebView].compactMap { $0 }
        )
        if protectedCandidateWebViews.contains(where: isWebViewProtectedFromCompositorMutation) {
            for protectedWebView in protectedCandidateWebViews where isWebViewProtectedFromCompositorMutation(protectedWebView) {
                _ = enqueueDeferredProtectedCommand(
                    .removeAllWebViews(tabID: tab.id),
                    for: protectedWebView,
                    reason: "removeAllWebViews"
                )
            }
            return false
        }

        let trackedEntries = currentEntries.map { windowId, webView in
            (TrackedWebViewOwner(tabID: tab.id, windowID: windowId), webView)
        }
        guard trackedEntries.isEmpty == false else { return false }

        for (owner, webView) in trackedEntries {
            removeWebViewFromContainers(webView)
            _ = unregisterTrackedWebViewSlot(
                owner: owner,
                expectedWebView: webView
            )
            tab.cleanupCloneWebView(webView)
        }
        refreshPrimaryTrackedWebView(for: tab, browserManager: tab.browserManager)
        return true
    }

    // MARK: - Window Cleanup

    func cleanupWindow(_ windowId: UUID, tabManager: TabManager) {
        let signpostState = PerformanceTrace.beginInterval("WebViewCoordinator.cleanupWindow")
        defer {
            PerformanceTrace.endInterval("WebViewCoordinator.cleanupWindow", signpostState)
        }

        scheduledPrepareWindowIds.remove(windowId)
        let webViewsToCleanup = trackedWebViews(in: windowId)

        RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
            "Cleaning up \(webViewsToCleanup.count) WebViews for window \(windowId.uuidString)."
        }

        for (owner, webView) in webViewsToCleanup {
            if isWebViewProtectedFromCompositorMutation(webView) {
                _ = enqueueDeferredProtectedCommand(
                    .cleanupWindow(windowID: windowId),
                    for: webView,
                    reason: "cleanupWindow"
                )
                continue
            }

            removeWebViewFromContainers(webView)
            _ = unregisterTrackedWebViewSlot(owner: owner, expectedWebView: webView)

            if let tab = tabManager.tab(for: owner.tabID) {
                tab.cleanupCloneWebView(webView)
                refreshPrimaryTrackedWebView(for: tab, browserManager: tabManager.browserManager)
            } else {
                performFallbackWebViewCleanup(
                    webView,
                    tabId: owner.tabID,
                    browserManager: tabManager.browserManager
                )
            }

            RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
                "Cleaned up WebView for tab=\(owner.tabID.uuidString.prefix(8)) in window=\(windowId.uuidString.prefix(8))."
            }
        }

        removeCompositorContainerView(for: windowId)
    }

    func cleanupAllWebViews(tabManager: TabManager) {
        let totalWebViews = webViewsByTabAndWindow.values.flatMap { $0.values }.count
        RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
            "Starting full WebView cleanup for \(totalWebViews) tracked views."
        }

        let trackedEntries = webViewsByTabAndWindow.flatMap { tabId, windowWebViews in
            windowWebViews.map { windowId, webView in
                (TrackedWebViewOwner(tabID: tabId, windowID: windowId), webView)
            }
        }

        for (owner, webView) in trackedEntries {
            if isWebViewProtectedFromCompositorMutation(webView) {
                _ = enqueueDeferredProtectedCommand(
                    .cleanupAllWebViews,
                    for: webView,
                    reason: "cleanupAllWebViews"
                )
                continue
            }

            removeWebViewFromContainers(webView)
            _ = unregisterTrackedWebViewSlot(owner: owner, expectedWebView: webView)

            if let tab = tabManager.tab(for: owner.tabID) {
                    tab.cleanupCloneWebView(webView)
                    refreshPrimaryTrackedWebView(for: tab, browserManager: tabManager.browserManager)
                } else {
                    performFallbackWebViewCleanup(
                        webView,
                        tabId: owner.tabID,
                        browserManager: tabManager.browserManager
                    )
                }

            RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
                "Cleaned up WebView for tab=\(owner.tabID.uuidString.prefix(8)) in window=\(owner.windowID.uuidString.prefix(8))."
            }
        }

        if webViewsByTabAndWindow.isEmpty {
            webViewHostsByTabAndWindow.removeAll()
            webViewOwnersByIdentifier.removeAll()
            recentlyVisibleTabIDsByWindow.removeAll()
            compositorContainerViews.removeAll()
            scheduledPrepareWindowIds.removeAll()
        }

        RuntimeDiagnostics.debug("Completed full WebView cleanup.", category: "WebViewCoordinator")
    }

    // MARK: - WebView Creation & Cross-Window Sync

    /// Create a new web view for a specific tab in a specific window
    func createWebView(for tab: Tab, in windowId: UUID) -> WKWebView {
        let tabId = tab.id

        if let adoptedWebView = adoptExistingPrimaryWebViewIfNeeded(for: tab, in: windowId) {
            return adoptedWebView
        }

        let configuration = resolvedConfiguration(
            for: tab,
            copying: tab.existingWebView
        )
        BrowserConfiguration.shared.applySitePermissionOverrides(
            to: configuration,
            url: tab.url,
            profileId: tab.resolveProfile()?.id ?? tab.profileId
        )

        let newWebView = FocusableWKWebView(frame: .zero, configuration: configuration)
        newWebView.navigationDelegate = tab
        newWebView.uiDelegate = tab
        newWebView.allowsBackForwardNavigationGestures = true
        newWebView.allowsMagnification = true
        newWebView.setValue(true, forKey: "drawsBackground")
        newWebView.owningTab = tab
        newWebView.contextMenuBridge = WebContextMenuBridge(tab: tab, configuration: configuration)
        tab.replaceCoreScriptMessageHandlers(
            on: newWebView.configuration.userContentController
        )
        tab.installRuntimeObservers(on: newWebView)
        setWebView(newWebView, for: tabId, in: windowId)

        if let url = URL(string: tab.url.absoluteString) {
            prepareInitialExtensionNavigation(
                for: newWebView,
                tab: tab,
                in: windowId,
                url: url
            )
            if #available(macOS 15.5, *) {
                tab.performMainFrameNavigationAfterHydrationIfNeeded(
                    on: newWebView,
                    url: url
                ) { resolvedWebView in
                    resolvedWebView.load(URLRequest(url: url))
                }
            } else {
                tab.performMainFrameNavigation(
                    on: newWebView,
                    url: url
                ) { resolvedWebView in
                    resolvedWebView.load(URLRequest(url: url))
                }
            }
        }
        newWebView.sumiSetAudioMuted(tab.audioState.isMuted)

        return newWebView
    }

    private func adoptExistingPrimaryWebViewIfNeeded(
        for tab: Tab,
        in windowId: UUID
    ) -> WKWebView? {
        guard let existingWebView = tab.existingWebView else { return nil }
        guard getAllWebViews(for: tab.id).isEmpty else { return nil }
        guard tab.primaryWindowId == nil || tab.primaryWindowId == windowId else { return nil }

        setWebView(existingWebView, for: tab.id, in: windowId)
        tab.assignWebViewToWindow(existingWebView, windowId: windowId)

        return existingWebView
    }

    @available(macOS 15.5, *)
    func rebuildLiveWebViews(
        for tab: Tab,
        preferredPrimaryWindowId: UUID? = nil,
        load url: URL? = nil
    ) {
        let trackedWindowIds = Set(windowIDs(for: tab.id))
        var targetWindowIds = trackedWindowIds

        if let primaryWindowId = tab.primaryWindowId {
            targetWindowIds.insert(primaryWindowId)
        }
        if let liveWindowIds = tab.browserManager?.windowRegistry?.windows.keys {
            targetWindowIds.formIntersection(liveWindowIds)
        }

        guard targetWindowIds.isEmpty == false else { return }

        let targetURL = url ?? tab.existingWebView?.url ?? tab.url
        let preferredPrimaryWindowIdCandidate: UUID?
        if let preferredPrimaryWindowId,
           targetWindowIds.contains(preferredPrimaryWindowId)
        {
            preferredPrimaryWindowIdCandidate = preferredPrimaryWindowId
        } else {
            preferredPrimaryWindowIdCandidate = nil
        }
        let existingPrimaryWindowIdCandidate: UUID?
        if let existingPrimaryWindowId = tab.primaryWindowId,
           targetWindowIds.contains(existingPrimaryWindowId)
        {
            existingPrimaryWindowIdCandidate = existingPrimaryWindowId
        } else {
            existingPrimaryWindowIdCandidate = nil
        }
        let primaryWindowId = preferredPrimaryWindowIdCandidate
            ?? existingPrimaryWindowIdCandidate
            ?? targetWindowIds.sorted { $0.uuidString < $1.uuidString }.first

        guard let primaryWindowId else { return }

        let protectedCandidateWebViews = Array((webViewsByTabAndWindow[tab.id] ?? [:]).values)
            + [tab.assignedWebView, tab.existingWebView].compactMap { $0 }
        if protectedCandidateWebViews.contains(where: isWebViewProtectedFromCompositorMutation) {
            let deferredWebViews = protectedCandidateWebViews.filter(isWebViewProtectedFromCompositorMutation)
            for protectedWebView in deferredWebViews {
                _ = enqueueDeferredProtectedCommand(
                    .rebuildLiveWebViews(
                        tabID: tab.id,
                        preferredPrimaryWindowID: preferredPrimaryWindowId
                    ),
                    for: protectedWebView,
                    reason: "rebuildLiveWebViews"
                )
            }
            return
        }

        let oldEntries = webViewsByTabAndWindow[tab.id] ?? [:]
        var cleanedIdentifiers: Set<ObjectIdentifier> = []

        func cleanup(_ webView: WKWebView?) {
            guard let webView else { return }
            let identifier = ObjectIdentifier(webView)
            guard cleanedIdentifiers.insert(identifier).inserted else { return }
            tab.cleanupCloneWebView(webView)
        }

        for (windowId, webView) in oldEntries {
            removeWebViewFromContainers(webView)
            _ = unregisterTrackedWebViewSlot(
                owner: TrackedWebViewOwner(tabID: tab.id, windowID: windowId),
                expectedWebView: webView
            )
            cleanup(webView)
        }
        cleanup(tab.assignedWebView)
        cleanup(tab.existingWebView)

        tab.cancelPendingMainFrameNavigation()
        tab._webView = nil
        tab._existingWebView = nil
        tab.primaryWindowId = nil
        tab.url = targetURL

        let recreatedPrimary = createWebViewInternal(
            for: tab,
            in: primaryWindowId,
            isPrimary: true,
            copyFrom: nil
        )
        tab.assignWebViewToWindow(recreatedPrimary, windowId: primaryWindowId)

        for windowId in targetWindowIds
            .filter({ $0 != primaryWindowId })
            .sorted(by: { $0.uuidString < $1.uuidString })
        {
            _ = createWebViewInternal(
                for: tab,
                in: windowId,
                isPrimary: false,
                copyFrom: recreatedPrimary
            )
        }

        for windowId in targetWindowIds {
            guard let windowState = tab.browserManager?.windowRegistry?.windows[windowId] else {
                continue
            }
            tab.browserManager?.refreshCompositor(for: windowState)
        }
    }

    func deferredProtectedCommandSummaries(for webView: WKWebView) -> [String] {
        deferredProtectedWebViewCommands[ObjectIdentifier(webView)]?.summaries() ?? []
    }

    func totalDeferredProtectedCommandCount() -> Int {
        deferredProtectedWebViewCommands.values.reduce(0) { partialResult, buffer in
            partialResult + buffer.count
        }
    }

    func simulateFullscreenStateChangeForTesting(
        tabId: UUID,
        in windowId: UUID,
        state: WKWebView.FullscreenState
    ) {
        guard let host = getWebViewHost(for: tabId, in: windowId) else { return }
        handleFullscreenStateChange(for: host, state: state)
    }

    @discardableResult
    func deferProtectedWebViewCleanup(
        _ webView: WKWebView,
        tabID: UUID,
        reason: String
    ) -> Bool {
        enqueueDeferredProtectedCommand(
            .cleanupTabWebView(
                webViewID: ObjectIdentifier(webView),
                tabID: tabID
            ),
            for: webView,
            reason: reason
        )
    }

    // MARK: - Private Helpers

    @discardableResult
    private func enqueueDeferredProtectedCommand(
        _ command: DeferredWebViewCommand,
        for webView: WKWebView,
        reason: String
    ) -> Bool {
        enqueueDeferredCommandIfNeeded(
            command,
            for: webView,
            reason: reason
        ) { webViewID in
            activeHistorySwipeProtections[webViewID] != nil
                || activeFullscreenVideoSessions[webViewID] != nil
                || webView.sumiIsInFullscreenElementPresentation
        }
    }

    @discardableResult
    private func enqueueDeferredHistorySwipeCommand(
        _ command: DeferredWebViewCommand,
        for webView: WKWebView,
        reason: String
    ) -> Bool {
        enqueueDeferredCommandIfNeeded(
            command,
            for: webView,
            reason: reason
        ) { webViewID in
            HistorySwipeCompositorMutationPolicy.shouldDeferMutation(
                isProtectedSource: activeHistorySwipeProtections[webViewID] != nil
            )
        }
    }

    @discardableResult
    private func enqueueDeferredCommandIfNeeded(
        _ command: DeferredWebViewCommand,
        for webView: WKWebView,
        reason: String,
        shouldDefer: (ObjectIdentifier) -> Bool
    ) -> Bool {
        let sourceWebViewID = ObjectIdentifier(webView)
        noteWeakWebView(webView)
        guard shouldDefer(sourceWebViewID) else {
            return false
        }

        pruneInvalidDeferredProtectedCommands(reason: "enqueue.preflight")
        guard isDeferredProtectedCommandValid(command) else {
            dropDeferredProtectedCommand(
                command,
                sourceWebViewID: sourceWebViewID,
                reason: "\(reason).invalidTarget"
            )
            return true
        }

        var buffer = deferredProtectedWebViewCommands[sourceWebViewID]
            ?? DeferredProtectedCommandBuffer()
        let outcome = buffer.enqueue(command)
        deferredProtectedWebViewCommands[sourceWebViewID] = buffer

        switch outcome {
        case .enqueued:
            PerformanceTrace.emitEvent("WebViewCoordinator.enqueueDeferredProtectedCommand")
            RuntimeDiagnostics.swipeTrace(
                "enqueueDeferredCommand reason=\(reason) sourceWebView=\(sourceWebViewID) command={\(command.debugSummary)} count=\(buffer.count)"
            )
        case .collapsed:
            PerformanceTrace.emitEvent("WebViewCoordinator.collapseDeferredProtectedCommand")
            RuntimeDiagnostics.swipeTrace(
                "collapseDeferredCommand reason=\(reason) sourceWebView=\(sourceWebViewID) command={\(command.debugSummary)} count=\(buffer.count)"
            )
        case .droppedAtCapacity:
            dropDeferredProtectedCommand(
                command,
                sourceWebViewID: sourceWebViewID,
                reason: "\(reason).capacity"
            )
        }

        return true
    }

    private func noteWeakWebView(_ webView: WKWebView) {
        weakWebViewsByIdentifier[ObjectIdentifier(webView)] = WeakWKWebView(value: webView)
    }

    private func resolveWeakWebView(
        with identifier: ObjectIdentifier
    ) -> WKWebView? {
        if let webView = weakWebViewsByIdentifier[identifier]?.value {
            return webView
        }
        weakWebViewsByIdentifier.removeValue(forKey: identifier)
        return nil
    }

    private func resolveWebView(
        with identifier: ObjectIdentifier
    ) -> WKWebView? {
        if let owner = webViewOwnersByIdentifier[identifier],
           let webView = webViewsByTabAndWindow[owner.tabID]?[owner.windowID],
           ObjectIdentifier(webView) == identifier
        {
            noteWeakWebView(webView)
            return webView
        }
        return resolveWeakWebView(with: identifier)
    }

    private func resolveHost(
        tabID: UUID,
        windowID: UUID,
        expectedWebViewID: ObjectIdentifier
    ) -> SumiWebViewContainerView? {
        guard let host = getWebViewHost(for: tabID, in: windowID),
              ObjectIdentifier(host.webView) == expectedWebViewID
        else {
            return nil
        }
        return host
    }

    private func resolveCompositorPane(
        _ destination: CompositorPaneDestination,
        in windowID: UUID
    ) -> NSView? {
        guard let root = compositorContainerView(for: windowID) else { return nil }
        return destination.resolve(in: root)
    }

    private func resolvedTab(with tabID: UUID) -> Tab? {
        if let tab = browserManager?.tabManager.tab(for: tabID) {
            return tab
        }
        if let windowStates = browserManager?.windowRegistry?.windows.values {
            for windowState in windowStates {
                if let tab = windowState.ephemeralTabs.first(where: { $0.id == tabID }) {
                    return tab
                }
            }
        }
        return nil
    }

    private func pruneDeadWeakWebViewReferences() {
        weakWebViewsByIdentifier = weakWebViewsByIdentifier.filter { _, entry in
            entry.value != nil
        }
    }

    private func pruneInvalidDeferredProtectedCommands(reason: String) {
        pruneDeadWeakWebViewReferences()

        for sourceWebViewID in Array(deferredProtectedWebViewCommands.keys) {
            guard resolveWebView(with: sourceWebViewID) != nil else {
                activeHistorySwipeProtections.removeValue(forKey: sourceWebViewID)
                activeFullscreenVideoSessions.removeValue(forKey: sourceWebViewID)
                if var buffer = deferredProtectedWebViewCommands.removeValue(forKey: sourceWebViewID) {
                    for command in buffer.drain() {
                        dropDeferredProtectedCommand(
                            command,
                            sourceWebViewID: sourceWebViewID,
                            reason: "\(reason).deadSource"
                        )
                    }
                }
                continue
            }

            guard var buffer = deferredProtectedWebViewCommands[sourceWebViewID] else {
                continue
            }
            let droppedCommands = buffer.prune { [self] command in
                isDeferredProtectedCommandValid(command) == false
            }

            if buffer.isEmpty {
                deferredProtectedWebViewCommands.removeValue(forKey: sourceWebViewID)
            } else {
                deferredProtectedWebViewCommands[sourceWebViewID] = buffer
            }

            for command in droppedCommands {
                dropDeferredProtectedCommand(
                    command,
                    sourceWebViewID: sourceWebViewID,
                    reason: "\(reason).invalidTarget"
                )
            }
        }
    }

    private func isDeferredProtectedCommandValid(
        _ command: DeferredWebViewCommand
    ) -> Bool {
        switch command {
        case .attachHost(let tabID, let windowID, let webViewID, let destination):
            return resolveHost(
                tabID: tabID,
                windowID: windowID,
                expectedWebViewID: webViewID
            ) != nil
                && resolveCompositorPane(destination, in: windowID) != nil
        case .removeWebViewFromContainers(let webViewID):
            return resolveWebView(with: webViewID) != nil
        case .removeAllWebViews(let tabID):
            return resolvedTab(with: tabID) != nil
        case .cleanupWindow(let windowID):
            return browserManager?.tabManager != nil
                && (
                    trackedWebViews(in: windowID).isEmpty == false
                        || compositorContainerView(for: windowID) != nil
                )
        case .cleanupAllWebViews:
            return browserManager?.tabManager != nil
                && webViewsByTabAndWindow.isEmpty == false
        case .rebuildLiveWebViews(let tabID, _):
            return resolvedTab(with: tabID) != nil
        case .evictHiddenWebViews(let windowID):
            return browserManager?.tabManager != nil
                && browserManager?.windowRegistry?.windows[windowID] != nil
        case .cleanupTabWebView(let webViewID, _):
            return resolveWebView(with: webViewID) != nil
        case .performFallbackWebViewCleanup(let webViewID, _):
            return resolveWebView(with: webViewID) != nil
        }
    }

    @discardableResult
    private func executeDeferredProtectedCommand(
        _ command: DeferredWebViewCommand,
        sourceWebViewID: ObjectIdentifier
    ) -> Bool {
        guard isDeferredProtectedCommandValid(command) else {
            return false
        }

        RuntimeDiagnostics.swipeTrace(
            "executeDeferredCommand sourceWebView=\(sourceWebViewID) command={\(command.debugSummary)}"
        )

        switch command {
        case .attachHost(let tabID, let windowID, let webViewID, let destination):
            guard let host = resolveHost(
                    tabID: tabID,
                    windowID: windowID,
                    expectedWebViewID: webViewID
                  ),
                  let container = resolveCompositorPane(destination, in: windowID)
            else {
                return false
            }
            _ = attachHost(host, to: container)
        case .removeWebViewFromContainers(let webViewID):
            guard let webView = resolveWebView(with: webViewID) else {
                return false
            }
            removeWebViewFromContainers(webView)
        case .removeAllWebViews(let tabID):
            guard let tab = resolvedTab(with: tabID) else {
                return false
            }
            _ = removeAllWebViews(for: tab)
        case .cleanupWindow(let windowID):
            guard let tabManager = browserManager?.tabManager else {
                return false
            }
            cleanupWindow(windowID, tabManager: tabManager)
        case .cleanupAllWebViews:
            guard let tabManager = browserManager?.tabManager else {
                return false
            }
            cleanupAllWebViews(tabManager: tabManager)
        case .rebuildLiveWebViews(let tabID, let preferredPrimaryWindowID):
            guard let tab = resolvedTab(with: tabID) else {
                return false
            }
            if #available(macOS 15.5, *) {
                rebuildLiveWebViews(
                    for: tab,
                    preferredPrimaryWindowId: preferredPrimaryWindowID
                )
            }
        case .evictHiddenWebViews(let windowID):
            guard let browserManager,
                  browserManager.windowRegistry?.windows[windowID] != nil
            else {
                return false
            }
            evictHiddenWebViewsIfNeeded(
                in: windowID,
                visibleTabIDs: visibleTabIDSet(
                    in: windowID,
                    browserManager: browserManager
                ),
                tabManager: browserManager.tabManager
            )
        case .cleanupTabWebView(let webViewID, let tabID):
            guard let webView = resolveWebView(with: webViewID) else {
                return false
            }
            if let tab = resolvedTab(with: tabID) {
                tab.cleanupCloneWebView(webView)
            } else {
                performFallbackWebViewCleanup(
                    webView,
                    tabId: tabID,
                    browserManager: browserManager
                )
            }
        case .performFallbackWebViewCleanup(let webViewID, let tabID):
            guard let webView = resolveWebView(with: webViewID) else {
                return false
            }
            performFallbackWebViewCleanup(
                webView,
                tabId: tabID,
                browserManager: browserManager
            )
        }

        return true
    }

    private func dropDeferredProtectedCommand(
        _ command: DeferredWebViewCommand,
        sourceWebViewID: ObjectIdentifier,
        reason: String
    ) {
        PerformanceTrace.emitEvent("WebViewCoordinator.dropDeferredProtectedCommand")
        RuntimeDiagnostics.swipeTrace(
            "dropDeferredCommand reason=\(reason) sourceWebView=\(sourceWebViewID) command={\(command.debugSummary)}"
        )
    }

    private func visibleTabIDs(
        for windowState: BrowserWindowState,
        browserManager: BrowserManager
    ) -> [UUID] {
        VisibleTabPreparationPlan.visibleTabIDs(
            currentTabId: browserManager.currentTab(for: windowState)?.id,
            isSplit: browserManager.splitManager.isSplit(for: windowState.id),
            leftTabId: browserManager.splitManager.leftTabId(for: windowState.id),
            rightTabId: browserManager.splitManager.rightTabId(for: windowState.id),
            isPreviewActive: browserManager.splitManager.getSplitState(for: windowState.id).isPreviewActive
        ).filter { tabId in
            guard let tab = resolveTab(for: tabId, in: windowState, browserManager: browserManager) else {
                return false
            }
            return !tab.representsSumiSettingsSurface && !tab.representsSumiEmptySurface
        }
    }

    private func visibleTabIDSet(
        in windowId: UUID,
        browserManager: BrowserManager?
    ) -> Set<UUID> {
        guard let browserManager,
              let windowState = browserManager.windowRegistry?.windows[windowId]
        else {
            return []
        }
        return Set(visibleTabIDs(for: windowState, browserManager: browserManager))
    }

    private func noteVisibleTabs(_ tabIDs: [UUID], in windowId: UUID) {
        guard tabIDs.isEmpty == false else { return }
        var mru = recentlyVisibleTabIDsByWindow[windowId] ?? []
        for tabId in tabIDs.reversed() {
            mru.removeAll { $0 == tabId }
            mru.insert(tabId, at: 0)
        }
        if mru.count > 32 {
            mru = Array(mru.prefix(32))
        }
        recentlyVisibleTabIDsByWindow[windowId] = mru
    }

    private func removeTabFromVisibilityHistory(_ tabId: UUID, in windowId: UUID) {
        guard var mru = recentlyVisibleTabIDsByWindow[windowId] else { return }
        mru.removeAll { $0 == tabId }
        if mru.isEmpty {
            recentlyVisibleTabIDsByWindow.removeValue(forKey: windowId)
        } else {
            recentlyVisibleTabIDsByWindow[windowId] = mru
        }
    }

    private func registerTrackedWebView(
        _ webView: WKWebView,
        for tabId: UUID,
        in windowId: UUID
    ) {
        let owner = TrackedWebViewOwner(tabID: tabId, windowID: windowId)
        let webViewID = ObjectIdentifier(webView)
        noteWeakWebView(webView)

        if let existingOwner = webViewOwnersByIdentifier[webViewID],
           existingOwner != owner
        {
            _ = unregisterTrackedWebViewSlot(
                owner: existingOwner,
                expectedWebView: webView,
                removeFromSuperview: true
            )
        }

        if let existingWebView = webViewsByTabAndWindow[tabId]?[windowId],
           existingWebView !== webView
        {
            _ = unregisterTrackedWebViewSlot(
                owner: owner,
                expectedWebView: existingWebView,
                removeFromSuperview: true,
                removeRecentVisibility: false
            )
        }

        if webViewsByTabAndWindow[tabId] == nil {
            webViewsByTabAndWindow[tabId] = [:]
        }
        webViewsByTabAndWindow[tabId]?[windowId] = webView
        webViewOwnersByIdentifier[webViewID] = owner
        assertTrackingConsistency("registerTrackedWebView")
    }

    @discardableResult
    private func unregisterTrackedWebViewSlot(
        owner: TrackedWebViewOwner,
        expectedWebView: WKWebView? = nil,
        removeFromSuperview: Bool = false,
        removeRecentVisibility: Bool = true
    ) -> WKWebView? {
        let trackedWebView = webViewsByTabAndWindow[owner.tabID]?[owner.windowID]
        if let expectedWebView,
           let trackedWebView,
           trackedWebView !== expectedWebView
        {
            let expectedIdentifier = ObjectIdentifier(expectedWebView)
            if webViewOwnersByIdentifier[expectedIdentifier] == owner {
                webViewOwnersByIdentifier.removeValue(forKey: expectedIdentifier)
            }
            return nil
        }

        let resolvedWebView = trackedWebView ?? expectedWebView
        let resolvedIdentifier = resolvedWebView.map(ObjectIdentifier.init)

        if removeFromSuperview,
           let host = webViewHostsByTabAndWindow[owner.tabID]?[owner.windowID]
        {
            host.removeFromSuperview()
        }

        webViewsByTabAndWindow[owner.tabID]?[owner.windowID] = nil
        webViewHostsByTabAndWindow[owner.tabID]?[owner.windowID] = nil
        if let resolvedIdentifier,
           webViewOwnersByIdentifier[resolvedIdentifier] == owner
        {
            webViewOwnersByIdentifier.removeValue(forKey: resolvedIdentifier)
        }
        if removeRecentVisibility {
            removeTabFromVisibilityHistory(owner.tabID, in: owner.windowID)
        }
        cleanupEmptyTrackingBuckets(for: owner.tabID)
        pruneInvalidDeferredProtectedCommands(reason: "unregisterTrackedWebViewSlot")
        assertTrackingConsistency("unregisterTrackedWebViewSlot")
        return resolvedWebView
    }

    private func cleanupEmptyTrackingBuckets(for tabId: UUID) {
        if webViewsByTabAndWindow[tabId]?.isEmpty == true {
            webViewsByTabAndWindow.removeValue(forKey: tabId)
        }
        if webViewHostsByTabAndWindow[tabId]?.isEmpty == true {
            webViewHostsByTabAndWindow.removeValue(forKey: tabId)
        }
    }

    private func trackedOwner(containing webView: WKWebView) -> TrackedWebViewOwner? {
        let webViewID = ObjectIdentifier(webView)
        guard let owner = webViewOwnersByIdentifier[webViewID] else { return nil }
        guard let trackedWebView = webViewsByTabAndWindow[owner.tabID]?[owner.windowID],
              trackedWebView === webView
        else {
            webViewOwnersByIdentifier.removeValue(forKey: webViewID)
            if webViewHostsByTabAndWindow[owner.tabID]?[owner.windowID]?.webView === webView {
                webViewHostsByTabAndWindow[owner.tabID]?[owner.windowID] = nil
                cleanupEmptyTrackingBuckets(for: owner.tabID)
            }
            assertTrackingConsistency("trackedOwner.stale")
            return nil
        }
        return owner
    }

    private func trackedWebViews(in windowId: UUID) -> [(TrackedWebViewOwner, WKWebView)] {
        webViewsByTabAndWindow.compactMap { tabId, windowWebViews in
            guard let webView = windowWebViews[windowId] else { return nil }
            return (TrackedWebViewOwner(tabID: tabId, windowID: windowId), webView)
        }
    }

    private func uniqueWebViews(_ webViews: [WKWebView]) -> [WKWebView] {
        var seen: Set<ObjectIdentifier> = []
        var unique: [WKWebView] = []
        for webView in webViews {
            let identifier = ObjectIdentifier(webView)
            if seen.insert(identifier).inserted {
                unique.append(webView)
            }
        }
        return unique
    }

    private func refreshPrimaryTrackedWebView(
        for tab: Tab,
        browserManager: BrowserManager?
    ) {
        guard let replacement = preferredPrimaryWebViewCandidate(
            for: tab.id,
            browserManager: browserManager
        ) else {
            if tab._webView != nil {
                tab._webView = nil
            }
            if tab.primaryWindowId != nil {
                tab.primaryWindowId = nil
            }
            return
        }

        if tab._webView !== replacement.webView || tab.primaryWindowId != replacement.owner.windowID {
            tab.assignWebViewToWindow(replacement.webView, windowId: replacement.owner.windowID)
        }
    }

    private func preferredPrimaryWebViewCandidate(
        for tabId: UUID,
        browserManager: BrowserManager?
    ) -> (owner: TrackedWebViewOwner, webView: WKWebView)? {
        guard let windowWebViews = webViewsByTabAndWindow[tabId], windowWebViews.isEmpty == false else {
            return nil
        }

        let candidates = windowWebViews.map { windowId, webView in
            (TrackedWebViewOwner(tabID: tabId, windowID: windowId), webView)
        }

        return candidates.min { lhs, rhs in
            candidatePriority(for: lhs.0, browserManager: browserManager)
                < candidatePriority(for: rhs.0, browserManager: browserManager)
        }
    }

    private func candidatePriority(
        for owner: TrackedWebViewOwner,
        browserManager: BrowserManager?
    ) -> (Int, Int, String) {
        let visibleRank: Int
        if let browserManager,
           let windowState = browserManager.windowRegistry?.windows[owner.windowID],
           visibleTabIDs(for: windowState, browserManager: browserManager).contains(owner.tabID)
        {
            visibleRank = 0
        } else {
            visibleRank = 1
        }

        let mruRank = recentlyVisibleTabIDsByWindow[owner.windowID]?
            .firstIndex(of: owner.tabID) ?? Int.max
        return (visibleRank, mruRank, owner.windowID.uuidString)
    }

    private func evictHiddenWebViewsIfNeeded(
        in windowId: UUID,
        visibleTabIDs: Set<UUID>,
        tabManager: TabManager
    ) {
        let signpostState = PerformanceTrace.beginInterval("WebViewCoordinator.evictHiddenWebViews")
        defer {
            PerformanceTrace.endInterval("WebViewCoordinator.evictHiddenWebViews", signpostState)
        }

        let trackedEntries = trackedWebViews(in: windowId)
        guard trackedEntries.count > visibleTabIDs.count + hiddenWarmWebViewBufferPerWindow else {
            return
        }

        let hiddenWarmTabID = recentlyVisibleTabIDsByWindow[windowId]?.first(where: { tabId in
            guard visibleTabIDs.contains(tabId) == false else { return false }
            return webViewsByTabAndWindow[tabId]?[windowId] != nil
        })

        let hiddenWarmTabIDs: Set<UUID> = hiddenWarmTabID.map { Set([$0]) } ?? []
        let retainedTabIDs = visibleTabIDs.union(hiddenWarmTabIDs)
        let hiddenEntries = trackedEntries.filter { owner, _ in
            retainedTabIDs.contains(owner.tabID) == false
        }

        guard hiddenEntries.isEmpty == false else { return }

        for (owner, webView) in hiddenEntries {
            if isWebViewProtectedFromCompositorMutation(webView) {
                _ = enqueueDeferredProtectedCommand(
                    .evictHiddenWebViews(windowID: windowId),
                    for: webView,
                    reason: "evictHiddenWebViews"
                )
                continue
            }

            removeWebViewFromContainers(webView)
            _ = unregisterTrackedWebViewSlot(owner: owner, expectedWebView: webView)

            if let tab = tabManager.tab(for: owner.tabID) {
                tab.cleanupCloneWebView(webView)
                refreshPrimaryTrackedWebView(for: tab, browserManager: tabManager.browserManager)
            } else {
                performFallbackWebViewCleanup(
                    webView,
                    tabId: owner.tabID,
                    browserManager: tabManager.browserManager
                )
            }

            RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
                "Evicted hidden WebView for tab=\(owner.tabID.uuidString.prefix(8)) in window=\(owner.windowID.uuidString.prefix(8))."
            }
        }
    }

    private func assertTrackingConsistency(_ context: StaticString) {
#if DEBUG
        var indexedWebViewIDs: Set<ObjectIdentifier> = []

        for (tabId, windowWebViews) in webViewsByTabAndWindow {
            for (windowId, webView) in windowWebViews {
                let identifier = ObjectIdentifier(webView)
                assert(
                    indexedWebViewIDs.insert(identifier).inserted,
                    "Duplicate tracked WKWebView \(identifier) during \(context)"
                )
                assert(
                    webViewOwnersByIdentifier[identifier] == TrackedWebViewOwner(
                        tabID: tabId,
                        windowID: windowId
                    ),
                    "Missing reverse index for WKWebView \(identifier) during \(context)"
                )
                if let host = webViewHostsByTabAndWindow[tabId]?[windowId] {
                    assert(
                        host.webView === webView,
                        "Mismatched host for WKWebView \(identifier) during \(context)"
                    )
                }
            }
        }

        for (identifier, owner) in webViewOwnersByIdentifier {
            guard let webView = webViewsByTabAndWindow[owner.tabID]?[owner.windowID] else {
                assertionFailure("Stale reverse index \(identifier) during \(context)")
                continue
            }
            assert(
                ObjectIdentifier(webView) == identifier,
                "Reverse index mismatch for WKWebView \(identifier) during \(context)"
            )
        }
#else
        _ = context
#endif
    }

    private func resolvedConfiguration(
        for tab: Tab,
        copying sourceWebView: WKWebView?
    ) -> WKWebViewConfiguration {
        let resolvedProfile = tab.resolveProfile()
        let reusableSourceWebView = sourceWebView
        let configuration: WKWebViewConfiguration

        if let profile = resolvedProfile {
            if let reusableSourceWebView {
                configuration = BrowserConfiguration.shared.isolatedWebViewConfigurationCopy(
                    from: reusableSourceWebView.configuration,
                    websiteDataStore: profile.dataStore
                )
            } else {
                configuration = BrowserConfiguration.shared.cacheOptimizedWebViewConfiguration(
                    for: profile
                )
            }
        } else if let reusableSourceWebView {
            configuration = BrowserConfiguration.shared.isolatedWebViewConfigurationCopy(
                from: reusableSourceWebView.configuration,
                websiteDataStore: reusableSourceWebView.configuration.websiteDataStore
            )
        } else {
            configuration = BrowserConfiguration.shared.isolatedWebViewConfigurationCopy(
                from: BrowserConfiguration.shared.webViewConfiguration,
                websiteDataStore: BrowserConfiguration.shared.webViewConfiguration.websiteDataStore
            )
        }

        BrowserConfiguration.shared.applyMediaSessionPolicy(
            to: configuration,
            profile: resolvedProfile
        )
        return configuration
    }

    private func prepareInitialExtensionNavigation(
        for webView: WKWebView,
        tab: Tab,
        in windowId: UUID,
        url: URL
    ) {
        guard let browserManager = tab.browserManager else { return }

        browserManager.extensionManager.prepareWebViewForExtensionRuntime(
            webView,
            currentURL: url,
            reason: "WebViewCoordinator.prepareInitialExtensionNavigation"
        )

        if let windowState = browserManager.windowRegistry?.windows[windowId],
           browserManager.currentTab(for: windowState)?.id == tab.id
        {
            browserManager.extensionManager.notifyTabActivated(
                newTab: tab,
                previous: nil
            )
        }

    }

    private func performFallbackWebViewCleanup(
        _ webView: WKWebView,
        tabId: UUID,
        browserManager: BrowserManager?
    ) {
        if enqueueDeferredProtectedCommand(
            .performFallbackWebViewCleanup(
                webViewID: ObjectIdentifier(webView),
                tabID: tabId
            ),
            for: webView,
            reason: "performFallbackWebViewCleanup"
        ) {
            return
        }

        RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
            "Performing fallback WebView cleanup for tab=\(tabId.uuidString.prefix(8))."
        }

        SumiWebViewShutdown.perform(
            on: webView,
            tabId: tabId,
            browserManager: browserManager
        )

        RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
            "Fallback WebView cleanup completed for tab=\(tabId.uuidString.prefix(8))."
        }
    }

    // MARK: - Cross-Window Sync

    /// Sync a tab's URL across all windows displaying it
    func syncTab(_ tab: Tab, to url: URL, originatingWebView: WKWebView? = nil) {
        let tabId = tab.id
        // Prevent recursive sync calls
        guard !isSyncingTab.contains(tabId) else { return }

        isSyncingTab.insert(tabId)
        defer { isSyncingTab.remove(tabId) }

        // Get all web views for this tab across all windows
        let allWebViews = getAllWebViews(for: tabId)

        for webView in allWebViews {
            if isWebViewProtectedFromCompositorMutation(webView) {
                RuntimeDiagnostics.swipeTrace(
                    "skipSyncProtected webView=\(ObjectIdentifier(webView)) tab=\(tabId.uuidString.prefix(8))"
                )
                continue
            }
            let isOriginatingWebView = originatingWebView.map { $0 === webView } ?? false
            let targetHistoryURL = webView.backForwardList.currentItem?.url
            guard WebViewSyncLoadPolicy.shouldLoadTarget(
                desiredURL: url,
                targetURL: webView.url,
                targetHistoryURL: targetHistoryURL,
                isOriginatingWebView: isOriginatingWebView
            ) else {
                continue
            }

            if #available(macOS 15.5, *) {
                tab.performMainFrameNavigationAfterHydrationIfNeeded(
                    on: webView,
                    url: url
                ) { resolvedWebView in
                    resolvedWebView.load(URLRequest(url: url))
                }
            } else {
                tab.performMainFrameNavigation(
                    on: webView,
                    url: url
                ) { resolvedWebView in
                    resolvedWebView.load(URLRequest(url: url))
                }
            }
        }
    }

    /// Reload a tab across all windows displaying it
    func reloadTab(_ tab: Tab) {
        let tabId = tab.id
        let allWebViews = getAllWebViews(for: tabId)
        for webView in allWebViews {
            if isWebViewProtectedFromCompositorMutation(webView) {
                RuntimeDiagnostics.swipeTrace(
                    "skipReloadProtected webView=\(ObjectIdentifier(webView)) tab=\(tabId.uuidString.prefix(8))"
                )
                continue
            }
            let targetURL = webView.url ?? tab.url
            if #available(macOS 15.5, *) {
                tab.performMainFrameNavigationAfterHydrationIfNeeded(
                    on: webView,
                    url: targetURL
                ) { resolvedWebView in
                    resolvedWebView.reload()
                }
            } else {
                tab.performMainFrameNavigation(
                    on: webView,
                    url: targetURL
                ) { resolvedWebView in
                    resolvedWebView.reload()
                }
            }
        }
    }

    /// Set mute state for a tab across all windows
    func setMuteState(_ muted: Bool, for tabId: UUID, excludingWindow originatingWindowId: UUID?) {
        guard let windowWebViews = webViewsByTabAndWindow[tabId] else { return }

        for (_, webView) in windowWebViews {
            webView.sumiSetAudioMuted(muted)
        }
    }

    private func resolveTab(
        for tabId: UUID,
        in windowState: BrowserWindowState,
        browserManager: BrowserManager
    ) -> Tab? {
        if windowState.isIncognito,
           let ephemeralTab = windowState.ephemeralTabs.first(where: { $0.id == tabId })
        {
            return ephemeralTab
        }
        return browserManager.tabManager.tab(for: tabId)
    }
}
