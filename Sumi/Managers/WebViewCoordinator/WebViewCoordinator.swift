//
//  WebViewCoordinator.swift
//  Sumi
//
//  Manages WebView instances across multiple windows
//

import AppKit
import Combine
import CoreGraphics
import Foundation
import Observation
import QuartzCore
import WebKit

extension Notification.Name {
    static let sumiWebViewNeedsMediaTouchBarRecovery = Notification.Name(
        "SumiWebViewNeedsMediaTouchBarRecovery"
    )
}

enum SumiMediaTouchBarRecoveryNotificationKey {
    static let tabID = "tabID"
    static let windowID = "windowID"
}

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
        splitTabIds: [UUID]
    ) -> [UUID] {
        guard let currentTabId else { return [] }

        guard splitTabIds.contains(currentTabId) else {
            return [currentTabId]
        }

        var seenIDs = Set<UUID>()
        var orderedIDs: [UUID] = []
        for tabId in splitTabIds {
            guard seenIDs.insert(tabId).inserted else { continue }
            orderedIDs.append(tabId)
        }
        return orderedIDs.isEmpty ? [currentTabId] : orderedIDs
    }
}

private enum InitialDocumentWarmupDeferral {
    case waitForInFlight
    case start(profileId: UUID, browserManager: BrowserManager, windowId: UUID)
}

@MainActor
private struct InitialDocumentWarmupGate {
    private var inFlightProfileIds: Set<UUID> = []
    private var attemptedProfileIds: Set<UUID> = []

    mutating func deferralIfNeeded(
        for tab: Tab,
        in windowId: UUID,
        browserManager coordinatorBrowserManager: BrowserManager?
    ) -> InitialDocumentWarmupDeferral? {
        guard tab.isEphemeral == false,
              Self.isWarmupURL(tab.url),
              let profileId = tab.resolveProfile()?.id ?? tab.profileId,
              let browserManager = tab.browserManager ?? coordinatorBrowserManager
        else {
            return nil
        }

        if inFlightProfileIds.contains(profileId) {
            return .waitForInFlight
        }

        guard attemptedProfileIds.contains(profileId) == false,
              browserManager.extensionsModule
                .needsInitialDocumentExtensionContextLoadIfNeeded(profileId: profileId)
        else {
            return nil
        }

        attemptedProfileIds.insert(profileId)
        inFlightProfileIds.insert(profileId)
        return .start(
            profileId: profileId,
            browserManager: browserManager,
            windowId: windowId
        )
    }

    mutating func finish(profileId: UUID) {
        inFlightProfileIds.remove(profileId)
    }

    private static func isWarmupURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }
}

private enum NormalTabWebViewCreationPlan {
    case useExisting(WKWebView)
    case adoptExistingPrimary(WKWebView)
    case deferForInitialDocumentWarmup(InitialDocumentWarmupDeferral)
    case createPrimary
    case createClone(primaryWindowId: UUID)
}


private struct HistorySwipeProtectionContext {
    let windowID: UUID?
    let originURL: URL?
    let originHistoryItem: WKBackForwardListItem?
    let originHistoryURL: URL?
}

private struct FullscreenProtectionContext {
    let windowID: UUID?
}

@MainActor
private final class FullscreenWebViewProtection {
    private var activeContexts: [ObjectIdentifier: FullscreenProtectionContext] = [:]
    private var stateCancellablesByWebViewID: [ObjectIdentifier: AnyCancellable] = [:]

    func hasActive(in windowID: UUID) -> Bool {
        activeContexts.values.contains { $0.windowID == windowID }
    }

    func activeWebViewIDs(in windowID: UUID) -> [ObjectIdentifier] {
        activeContexts.compactMap { webViewID, context in
            context.windowID == windowID ? webViewID : nil
        }
    }

    func isProtected(_ webViewID: ObjectIdentifier) -> Bool {
        activeContexts[webViewID] != nil
    }

    func begin(webViewID: ObjectIdentifier, windowID: UUID?) {
        activeContexts[webViewID] = FullscreenProtectionContext(windowID: windowID)
    }

    func finish(webViewID: ObjectIdentifier) -> FullscreenProtectionContext? {
        activeContexts.removeValue(forKey: webViewID)
    }

    func remove(_ webViewID: ObjectIdentifier) {
        activeContexts.removeValue(forKey: webViewID)
        stateCancellablesByWebViewID.removeValue(forKey: webViewID)?.cancel()
    }

    func removeAll() {
        activeContexts.removeAll()
        stateCancellablesByWebViewID.values.forEach { $0.cancel() }
        stateCancellablesByWebViewID.removeAll()
    }

    func installObservationIfNeeded(
        on webView: WKWebView,
        stateDidChange: @escaping @MainActor (WKWebView) -> Void
    ) {
        let webViewID = ObjectIdentifier(webView)
        guard stateCancellablesByWebViewID[webViewID] == nil else {
            if webView.sumiIsInFullscreenElementPresentation {
                stateDidChange(webView)
            }
            return
        }

        stateCancellablesByWebViewID[webViewID] = webView
            .publisher(for: \.fullscreenState, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak webView] _ in
                guard let webView else { return }
                stateDidChange(webView)
            }
    }

    func uninstallObservationIfUntracked(_ webView: WKWebView, isTracked: Bool) {
        guard !isTracked else { return }
        remove(ObjectIdentifier(webView))
    }
}

enum CompositorPaneDestination: String, CaseIterable {
    case single
    case left
    case right

    var viewIdentifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("SumiCompositorPane.\(rawValue)")
    }

}

private struct WeakWKWebView {
    weak var value: WKWebView?
}

private struct WeakWebViewRegistry {
    private var webViewsByIdentifier: [ObjectIdentifier: WeakWKWebView] = [:]

    mutating func note(_ webView: WKWebView) {
        webViewsByIdentifier[ObjectIdentifier(webView)] = WeakWKWebView(value: webView)
    }

    mutating func resolve(with identifier: ObjectIdentifier) -> WKWebView? {
        if let webView = webViewsByIdentifier[identifier]?.value {
            return webView
        }
        webViewsByIdentifier.removeValue(forKey: identifier)
        return nil
    }

    mutating func pruneStaleIdentifiers() -> [ObjectIdentifier] {
        let staleIDs = webViewsByIdentifier.compactMap { key, entry -> ObjectIdentifier? in
            entry.value == nil ? key : nil
        }
        for id in staleIDs {
            webViewsByIdentifier.removeValue(forKey: id)
        }
        return staleIDs
    }
}

enum DeferredWebViewCommandKey: Hashable {
    case removeWebViewFromContainers(ObjectIdentifier)
    case removeAllWebViews(UUID)
    case removeTrackedWebView(ObjectIdentifier, UUID, UUID)
    case closeWebViewFromWebKit(ObjectIdentifier)
    case cleanupWindow(UUID)
    case cleanupAllWebViews
    case rebuildLiveWebViews(UUID)
    case evictHiddenWebViews(UUID)
    case cleanupTabWebView(ObjectIdentifier)
    case performFallbackWebViewCleanup(ObjectIdentifier)
}

enum DeferredWebViewCommand {
    case removeWebViewFromContainers(webViewID: ObjectIdentifier)
    case removeAllWebViews(tabID: UUID)
    case removeTrackedWebView(webViewID: ObjectIdentifier, tabID: UUID, windowID: UUID)
    case closeWebViewFromWebKit(webViewID: ObjectIdentifier)
    case cleanupWindow(windowID: UUID)
    case cleanupAllWebViews
    case rebuildLiveWebViews(tabID: UUID, preferredPrimaryWindowID: UUID?)
    case evictHiddenWebViews(windowID: UUID)
    case cleanupTabWebView(webViewID: ObjectIdentifier, tabID: UUID)
    case performFallbackWebViewCleanup(webViewID: ObjectIdentifier, tabID: UUID)

    var key: DeferredWebViewCommandKey {
        switch self {
        case .removeWebViewFromContainers(let webViewID):
            return .removeWebViewFromContainers(webViewID)
        case .removeAllWebViews(let tabID):
            return .removeAllWebViews(tabID)
        case .removeTrackedWebView(let webViewID, let tabID, let windowID):
            return .removeTrackedWebView(webViewID, tabID, windowID)
        case .closeWebViewFromWebKit(let webViewID):
            return .closeWebViewFromWebKit(webViewID)
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
        case .removeWebViewFromContainers(let webViewID):
            return "removeWebViewFromContainers webView=\(webViewID)"
        case .removeAllWebViews(let tabID):
            return "removeAllWebViews tab=\(tabID.uuidString.prefix(8))"
        case .removeTrackedWebView(let webViewID, let tabID, let windowID):
            return "removeTrackedWebView tab=\(tabID.uuidString.prefix(8)) window=\(windowID.uuidString.prefix(8)) webView=\(webViewID)"
        case .closeWebViewFromWebKit(let webViewID):
            return "closeWebViewFromWebKit webView=\(webViewID)"
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

}

private struct DeferredProtectedWebViewCommandStore {
    private var buffersBySourceWebViewID: [ObjectIdentifier: DeferredProtectedCommandBuffer] = [:]

    var sourceWebViewIDs: [ObjectIdentifier] {
        Array(buffersBySourceWebViewID.keys)
    }

    mutating func enqueue(
        _ command: DeferredWebViewCommand,
        sourceWebViewID: ObjectIdentifier
    ) -> (outcome: DeferredProtectedCommandEnqueueOutcome, count: Int) {
        var buffer = buffersBySourceWebViewID[sourceWebViewID]
            ?? DeferredProtectedCommandBuffer()
        let outcome = buffer.enqueue(command)
        buffersBySourceWebViewID[sourceWebViewID] = buffer
        return (outcome, buffer.count)
    }

    mutating func drainCommands(for sourceWebViewID: ObjectIdentifier) -> [DeferredWebViewCommand] {
        var buffer = buffersBySourceWebViewID.removeValue(forKey: sourceWebViewID)
        return buffer?.drain() ?? []
    }

    mutating func removeAllCommands(for sourceWebViewID: ObjectIdentifier) {
        buffersBySourceWebViewID.removeValue(forKey: sourceWebViewID)
    }

    mutating func pruneCommands(
        for sourceWebViewID: ObjectIdentifier,
        where shouldDrop: (DeferredWebViewCommand) -> Bool
    ) -> [DeferredWebViewCommand] {
        guard var buffer = buffersBySourceWebViewID[sourceWebViewID] else {
            return []
        }

        let droppedCommands = buffer.prune(where: shouldDrop)
        if buffer.isEmpty {
            buffersBySourceWebViewID.removeValue(forKey: sourceWebViewID)
        } else {
            buffersBySourceWebViewID[sourceWebViewID] = buffer
        }
        return droppedCommands
    }
}

@MainActor
@Observable
class WebViewCoordinator: SumiDestructiveBrowsingDataCleanupPreparing {
    @ObservationIgnored
    private let webViewRegistry = WindowWebViewRegistry()

    @ObservationIgnored
    private var promotedHostsByTabAndWindow: [UUID: [UUID: SumiWebViewContainerView]] = [:]

    @ObservationIgnored
    private var promotedHostAttachmentCompletionsByTabAndWindow: [UUID: [UUID: (@MainActor () -> Void)]] = [:]

    /// Prevent recursive sync calls
    @ObservationIgnored
    private var isSyncingTab: Set<UUID> = []

    /// Weak wrapper for NSView references stored per window
    private struct WeakNSView { weak var view: NSView? }

    /// Container views per window so the compositor can manage multiple windows safely
    @ObservationIgnored
    private var compositorContainerViews: [UUID: WeakNSView] = [:]

    @ObservationIgnored
    private var immediateVisualHandoffHandlersByWindow: [UUID: @MainActor () -> Bool] = [:]

    /// Coalesce WebView creation requests so SwiftUI update passes never create WebViews inline.
    @ObservationIgnored
    private var scheduledPrepareWindowIds: Set<UUID> = []

    @ObservationIgnored
    private var initialDocumentWarmupGate = InitialDocumentWarmupGate()

    @ObservationIgnored
    weak var browserManager: BrowserManager?

    @ObservationIgnored
    private var activeHistorySwipeProtections: [ObjectIdentifier: HistorySwipeProtectionContext] = [:]

    @ObservationIgnored
    private var visualHandoffProtectedWebViewIDs: Set<ObjectIdentifier> = []

    @ObservationIgnored
    private let fullscreenProtection = FullscreenWebViewProtection()

    @ObservationIgnored
    private var deferredProtectedWebViewCommands = DeferredProtectedWebViewCommandStore()

    @ObservationIgnored
    private var weakWebViewRegistry = WeakWebViewRegistry()

    @ObservationIgnored
    private var nowPlayingSessionCancellablesByWebViewID: [ObjectIdentifier: AnyCancellable] = [:]

    @ObservationIgnored
    private var destructiveCleanupBlankingWebViewIDs: Set<ObjectIdentifier> = []

    // MARK: - Compositor Container Management

    func setCompositorContainerView(_ view: NSView?, for windowId: UUID) {
        if let view {
            compositorContainerViews[windowId] = WeakNSView(view: view)
        } else {
            compositorContainerViews.removeValue(forKey: windowId)
        }
    }

    func setImmediateVisualHandoffHandler(
        _ handler: (@MainActor () -> Bool)?,
        for windowId: UUID
    ) {
        immediateVisualHandoffHandlersByWindow[windowId] = handler
    }

    @discardableResult
    func performImmediateVisualHandoffIfPossible(in windowId: UUID) -> Bool {
        immediateVisualHandoffHandlersByWindow[windowId]?() ?? false
    }

    func compositorContainerView(for windowId: UUID) -> NSView? {
        if let view = compositorContainerViews[windowId]?.view {
            return view
        }
        compositorContainerViews.removeValue(forKey: windowId)
        immediateVisualHandoffHandlersByWindow.removeValue(forKey: windowId)
        return nil
    }

    func removeCompositorContainerView(for windowId: UUID) {
        compositorContainerViews.removeValue(forKey: windowId)
        immediateVisualHandoffHandlersByWindow.removeValue(forKey: windowId)
        scheduledPrepareWindowIds.remove(windowId)
        webViewRegistry.removeVisibilityHistory(for: windowId)
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
            immediateVisualHandoffHandlersByWindow.removeValue(forKey: id)
        }
        return result
    }

    // MARK: - WebView Pool Management

    func getWebView(for tabId: UUID, in windowId: UUID) -> WKWebView? {
        webViewRegistry.webView(for: tabId, in: windowId)
    }

    func getAllWebViews(for tabId: UUID) -> [WKWebView] {
        webViewRegistry.webViews(for: tabId)
    }

    func liveWebViews(for tab: Tab) -> [WKWebView] {
        var seen = Set<ObjectIdentifier>()
        var result: [WKWebView] = []
        func appendUnique(_ webView: WKWebView?) {
            guard let webView else { return }
            let id = ObjectIdentifier(webView)
            if seen.insert(id).inserted {
                result.append(webView)
            }
        }
        let windowWebViews = webViewRegistry.windowWebViews(for: tab.id)
        if windowWebViews.isEmpty == false {
            result.reserveCapacity(windowWebViews.count + 2)
            for webView in windowWebViews.values {
                appendUnique(webView)
            }
        } else {
            result.reserveCapacity(2)
        }
        appendUnique(tab.assignedWebView)
        appendUnique(tab.existingWebView)
        return result
    }

    func isPreparingForDestructiveDataCleanupNavigation(on webView: WKWebView) -> Bool {
        destructiveCleanupBlankingWebViewIDs.contains(ObjectIdentifier(webView))
    }

    func finishDestructiveDataCleanupNavigation(on webView: WKWebView) {
        destructiveCleanupBlankingWebViewIDs.remove(ObjectIdentifier(webView))
    }

    func prepareForDestructiveDataCleanup(profileIDs: Set<UUID>) async {
        guard !profileIDs.isEmpty else { return }
        guard let browserManager else { return }

        var seenTabIDs = Set<UUID>()
        var preparedWebViewCount = 0
        var skippedProtectedWebViewCount = 0

        func visit(_ tab: Tab) {
            guard seenTabIDs.insert(tab.id).inserted else { return }
            guard let profileId = tab.resolveProfile()?.id ?? tab.profileId,
                  profileIDs.contains(profileId),
                  !tab.representsSumiNativeSurface
            else {
                return
            }

            let liveWebViews = liveWebViews(for: tab)
            let eligibleWebViews = liveWebViews.filter {
                isWebViewProtectedFromCompositorMutation($0) == false
            }
            guard !eligibleWebViews.isEmpty else {
                skippedProtectedWebViewCount += liveWebViews.count
                return
            }

            tab.cancelPendingMainFrameNavigation()
            for webView in eligibleWebViews {
                prepareForDestructiveCleanup(webView, tab: tab)
                preparedWebViewCount += 1
            }
        }

        browserManager.tabManager.allPinnedTabsAllProfiles.forEach(visit)
        browserManager.tabManager.allTabs().forEach(visit)

        RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
            "Prepared \(preparedWebViewCount) live WebView(s) for destructive data cleanup across \(profileIDs.count) profile(s); skipped \(skippedProtectedWebViewCount) protected WebView(s)."
        }
    }

    func windowIDs(for tabId: UUID) -> [UUID] {
        webViewRegistry.windowIDs(for: tabId)
    }

    func setWebView(_ webView: WKWebView, for tabId: UUID, in windowId: UUID) {
        registerTrackedWebView(webView, for: tabId, in: windowId)
    }

    private func prepareForDestructiveCleanup(_ webView: WKWebView, tab: Tab) {
        tab.stopLoading(on: webView)
        webView.pauseAllMediaPlayback(completionHandler: nil)

        if webView.cameraCaptureState != .none {
            webView.setCameraCaptureState(.none, completionHandler: nil)
        }
        if webView.microphoneCaptureState != .none {
            webView.setMicrophoneCaptureState(.none, completionHandler: nil)
        }

        guard webView.url?.absoluteString != SumiSurface.emptyTabURL.absoluteString else {
            finishDestructiveDataCleanupNavigation(on: webView)
            return
        }

        let webViewID = ObjectIdentifier(webView)
        destructiveCleanupBlankingWebViewIDs.insert(webViewID)
        if webView.load(URLRequest(url: SumiSurface.emptyTabURL)) == nil {
            destructiveCleanupBlankingWebViewIDs.remove(webViewID)
        }
    }

    func registerPromotedHost(
        _ host: SumiWebViewContainerView,
        for tabId: UUID,
        in windowId: UUID,
        attachmentCompletion: (@MainActor () -> Void)? = nil
    ) {
        promotedHostsByTabAndWindow[tabId, default: [:]][windowId] = host
        if let attachmentCompletion {
            promotedHostAttachmentCompletionsByTabAndWindow[tabId, default: [:]][windowId] = attachmentCompletion
        } else {
            promotedHostAttachmentCompletionsByTabAndWindow[tabId]?[windowId] = nil
            if promotedHostAttachmentCompletionsByTabAndWindow[tabId]?.isEmpty == true {
                promotedHostAttachmentCompletionsByTabAndWindow[tabId] = nil
            }
        }
    }

    func takePromotedHost(for tabId: UUID, in windowId: UUID, expectedWebView: WKWebView) -> SumiWebViewContainerView? {
        guard let host = promotedHostsByTabAndWindow[tabId]?[windowId] else { return nil }
        guard host.webView === expectedWebView else { return nil }

        promotedHostsByTabAndWindow[tabId]?[windowId] = nil
        if promotedHostsByTabAndWindow[tabId]?.isEmpty == true {
            promotedHostsByTabAndWindow[tabId] = nil
        }

        host.prepareForSuperviewTransferPreservingDisplayedContent()
        return host
    }

    func completePromotedHostAttachment(for tabId: UUID, in windowId: UUID) {
        guard let completion = promotedHostAttachmentCompletionsByTabAndWindow[tabId]?[windowId] else {
            return
        }

        promotedHostAttachmentCompletionsByTabAndWindow[tabId]?[windowId] = nil
        if promotedHostAttachmentCompletionsByTabAndWindow[tabId]?.isEmpty == true {
            promotedHostAttachmentCompletionsByTabAndWindow[tabId] = nil
        }
        completion()
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
        webViewRegistry.noteVisibleTabs(visibleTabIDs, in: windowState.id)
        var didCreateWebView = false
        for tabId in visibleTabIDs {
            guard let tab = resolveTab(for: tabId, in: windowState, browserManager: browserManager) else {
                continue
            }
            guard browserManager.canMaterializeNormalTabWebViewDuringStartup(tab) else {
                continue
            }

            browserManager.compositorManager.markTabAccessed(tab.id)
            if getWebView(for: tab.id, in: windowState.id) == nil {
                if getOrCreateWebView(
                    for: tab,
                    in: windowState.id
                ) != nil {
                    didCreateWebView = true
                }
            }
        }

        evictHiddenWebViewsIfNeeded(
            in: windowState.id,
            visibleTabIDs: Set(visibleTabIDs),
            tabManager: browserManager.tabManager
        )
        browserManager.tabSuspensionService.scheduleProactiveTimerReconcile(
            reason: "visible-webviews-prepared"
        )
        browserManager.backgroundMediaOptimizationService.scheduleReconcile(
            reason: "visible-webviews-prepared"
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

    // MARK: - Window Cleanup

    func cleanupWindow(_ windowId: UUID, tabManager: TabManager) {
        let signpostState = PerformanceTrace.beginInterval("WebViewCoordinator.cleanupWindow")
        defer {
            PerformanceTrace.endInterval("WebViewCoordinator.cleanupWindow", signpostState)
        }

        scheduledPrepareWindowIds.remove(windowId)
        let webViewsToCleanup = webViewRegistry.trackedWebViews(in: windowId)

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

            let tab = tabManager.tab(for: owner.tabID)
            cleanupUnprotectedTrackedWebView(
                webView,
                owner: owner,
                tab: tab,
                browserManager: tabManager.browserManager
            )
            if let tab {
                refreshPrimaryTrackedWebView(for: tab, browserManager: tabManager.browserManager)
            }

            RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
                "Cleaned up WebView for tab=\(owner.tabID.uuidString.prefix(8)) in window=\(windowId.uuidString.prefix(8))."
            }
        }

        removeCompositorContainerView(for: windowId)
    }

    func cleanupAllWebViews(tabManager: TabManager) {
        let totalWebViews = webViewRegistry.totalTrackedWebViewCount
        RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
            "Starting full WebView cleanup for \(totalWebViews) tracked views."
        }

        let trackedEntries = webViewRegistry.trackedWebViews()

        for (owner, webView) in trackedEntries {
            if isWebViewProtectedFromCompositorMutation(webView) {
                _ = enqueueDeferredProtectedCommand(
                    .cleanupAllWebViews,
                    for: webView,
                    reason: "cleanupAllWebViews"
                )
                continue
            }

            let tab = tabManager.tab(for: owner.tabID)
            cleanupUnprotectedTrackedWebView(
                webView,
                owner: owner,
                tab: tab,
                browserManager: tabManager.browserManager
            )
            if let tab {
                refreshPrimaryTrackedWebView(for: tab, browserManager: tabManager.browserManager)
            }

            RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
                "Cleaned up WebView for tab=\(owner.tabID.uuidString.prefix(8)) in window=\(owner.windowID.uuidString.prefix(8))."
            }
        }

        if webViewRegistry.isEmpty {
            webViewRegistry.removeAll()
            compositorContainerViews.removeAll()
            immediateVisualHandoffHandlersByWindow.removeAll()
            scheduledPrepareWindowIds.removeAll()
            visualHandoffProtectedWebViewIDs.removeAll()
            fullscreenProtection.removeAll()
            nowPlayingSessionCancellablesByWebViewID.values.forEach { $0.cancel() }
            nowPlayingSessionCancellablesByWebViewID.removeAll()
        }

        RuntimeDiagnostics.debug("Completed full WebView cleanup.", category: "WebViewCoordinator")

        pruneStaleWebViewBookkeeping(reason: "cleanupAllWebViews")
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
        activeHistorySwipeProtections[webViewID] = HistorySwipeProtectionContext(
            windowID: windowId,
            originURL: originURL,
            originHistoryItem: originHistoryItem,
            originHistoryURL: originHistoryItem?.url
        )
        RuntimeDiagnostics.swipeTrace(
            "begin tab=\(tabId.uuidString.prefix(8)) window=\(windowId?.uuidString.prefix(8) ?? "nil") webView=\(webViewID) url=\((originURL ?? originHistoryItem?.url)?.absoluteString ?? "nil")"
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

    func hasActiveFullscreen(in windowId: UUID) -> Bool {
        fullscreenProtection.hasActive(in: windowId)
    }

    func closeActiveFullscreenMedia(in windowId: UUID) {
        for webViewID in fullscreenProtection.activeWebViewIDs(in: windowId) {
            guard let webView = resolveWebView(with: webViewID) else { continue }
            requestFullscreenMediaExit(on: webView)
        }
    }

    private func closeFullscreenMediaIfNeeded(on webView: WKWebView) {
        let webViewID = ObjectIdentifier(webView)
        guard webView.sumiIsInFullscreenElementPresentation
            || fullscreenProtection.isProtected(webViewID)
        else {
            return
        }
        requestFullscreenMediaExit(on: webView)
    }

    private func requestFullscreenMediaExit(on webView: WKWebView) {
        webView.sumiFullscreenWindowController?.window?.toggleFullScreen(webView)
    }

    func isWebViewProtectedFromCompositorMutation(_ webView: WKWebView) -> Bool {
        let webViewID = ObjectIdentifier(webView)
        return activeHistorySwipeProtections[webViewID] != nil
            || visualHandoffProtectedWebViewIDs.contains(webViewID)
            || fullscreenProtection.isProtected(webViewID)
    }

    func beginVisualHandoffProtection(for webView: WKWebView) {
        let webViewID = ObjectIdentifier(webView)
        noteWeakWebView(webView)
        visualHandoffProtectedWebViewIDs.insert(webViewID)
    }

    func finishVisualHandoffProtection(for webView: WKWebView) {
        let webViewID = ObjectIdentifier(webView)
        guard visualHandoffProtectedWebViewIDs.remove(webViewID) != nil else { return }
        flushDeferredProtectedCommands(for: webViewID)
    }

    private func beginFullscreenProtectionIfNeeded(for webView: WKWebView) {
        guard webView.sumiIsInFullscreenElementPresentation else {
            finishFullscreenProtectionIfNeeded(for: webView)
            return
        }

        let webViewID = ObjectIdentifier(webView)
        noteWeakWebView(webView)
        let owner = trackedOwner(containing: webView)
        fullscreenProtection.begin(
            webViewID: webViewID,
            windowID: owner?.windowID ?? windowId(containing: webView)
        )
        RuntimeDiagnostics.protectedWebViewTrace(
            "beginFullscreenProtection webView=\(webViewID) tab=\(owner?.tabID.uuidString.prefix(8) ?? "nil") window=\(owner?.windowID.uuidString.prefix(8) ?? "nil")"
        )
    }

    private func finishFullscreenProtectionIfNeeded(for webView: WKWebView) {
        let webViewID = ObjectIdentifier(webView)
        guard let context = fullscreenProtection.finish(webViewID: webViewID) else { return }
        let owner = trackedOwner(containing: webView)

        RuntimeDiagnostics.protectedWebViewTrace(
            "finishFullscreenProtection webView=\(webViewID)"
        )
        flushDeferredProtectedCommands(for: webViewID)
        if let windowID = context.windowID,
           let windowState = browserManager?.windowRegistry?.windows[windowID] {
            browserManager?.refreshCompositor(for: windowState)
        }
        postMediaTouchBarRecoveryRequest(
            for: webView,
            owner: owner,
            fallbackWindowID: context.windowID
        )
    }

    private func postMediaTouchBarRecoveryRequest(
        for webView: WKWebView,
        owner: TrackedWebViewOwner?,
        fallbackWindowID: UUID?
    ) {
        guard let windowID = owner?.windowID ?? fallbackWindowID else { return }
        var userInfo: [String: Any] = [
            SumiMediaTouchBarRecoveryNotificationKey.windowID: windowID
        ]
        if let tabID = owner?.tabID {
            userInfo[SumiMediaTouchBarRecoveryNotificationKey.tabID] = tabID
        }
        NotificationCenter.default.post(
            name: .sumiWebViewNeedsMediaTouchBarRecovery,
            object: webView,
            userInfo: userInfo
        )
    }

    func windowID(containing webView: WKWebView) -> UUID? {
        windowId(containing: webView)
    }

    @discardableResult
    func handleWebViewDidClose(_ webView: WKWebView) -> Bool {
        let webViewID = ObjectIdentifier(webView)
        noteWeakWebView(webView)
        finishDestructiveDataCleanupNavigation(on: webView)

        if enqueueDeferredProtectedCommand(
            .closeWebViewFromWebKit(webViewID: webViewID),
            for: webView,
            reason: "webViewDidClose"
        ) {
            closeFullscreenMediaIfNeeded(on: webView)
            return true
        }

        if let owner = trackedOwner(containing: webView) {
            return closeTrackedWebViewFromWebKit(webView, owner: owner)
        }

        if let (tab, windowState) = untrackedTabContext(for: webView) {
            closeTabForWebKitCloseRequest(tab, windowState: windowState)
            return true
        }

        SumiAuxiliaryWebViewShutdown.perform(
            on: webView,
            browserManager: browserManager,
            reason: "WebKit webViewDidClose fallback"
        )
        return true
    }

    private func flushDeferredProtectedCommands(for webViewID: ObjectIdentifier) {
        guard activeHistorySwipeProtections[webViewID] == nil,
              visualHandoffProtectedWebViewIDs.contains(webViewID) == false,
              fullscreenProtection.isProtected(webViewID) == false
        else { return }
        pruneInvalidDeferredProtectedCommands(reason: "flush.preflight")
        let commands = deferredProtectedWebViewCommands.drainCommands(for: webViewID)
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

            RuntimeDiagnostics.protectedWebViewTrace(
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
    func getOrCreateWebView(for tab: Tab, in windowId: UUID) -> WKWebView? {
        switch normalTabWebViewCreationPlan(for: tab, in: windowId) {
        case .useExisting(let existing):
            return existing
        case .adoptExistingPrimary(let adoptedWebView):
            adoptExistingPrimaryWebView(adoptedWebView, for: tab, in: windowId)
            return adoptedWebView
        case .deferForInitialDocumentWarmup(let deferral):
            startInitialDocumentWarmupIfNeeded(deferral)
            return nil
        case .createPrimary:
            return createPrimaryWebView(for: tab, in: windowId)
        case .createClone(let primaryWindowId):
            return createCloneWebView(
                for: tab,
                in: windowId,
                primaryWindowId: primaryWindowId
            )
        }
    }

    private func normalTabWebViewCreationPlan(
        for tab: Tab,
        in windowId: UUID
    ) -> NormalTabWebViewCreationPlan {
        let tabId = tab.id

        if let existing = getWebView(for: tabId, in: windowId) {
            return .useExisting(existing)
        }

        if let adoptableWebView = adoptableExistingPrimaryWebView(for: tab, in: windowId) {
            return .adoptExistingPrimary(adoptableWebView)
        }

        if let deferral = initialDocumentWarmupGate.deferralIfNeeded(
            for: tab,
            in: windowId,
            browserManager: browserManager
        ) {
            return .deferForInitialDocumentWarmup(deferral)
        }

        let allWindowsForTab = webViewRegistry.windowWebViews(for: tabId)
        let otherWindows = allWindowsForTab.filter { $0.key != windowId }

        if otherWindows.isEmpty {
            return .createPrimary
        }

        return .createClone(
            primaryWindowId: primaryWindowIdForClone(
                of: tab,
                otherWindows: otherWindows
            )
        )
    }

    private func primaryWindowIdForClone(
        of tab: Tab,
        otherWindows: [UUID: WKWebView]
    ) -> UUID {
        if let primaryWindowId = tab.primaryWindowId,
           otherWindows[primaryWindowId] != nil
        {
            return primaryWindowId
        }

        return otherWindows.keys.min { $0.uuidString < $1.uuidString }!
    }

    private func startInitialDocumentWarmupIfNeeded(
        _ deferral: InitialDocumentWarmupDeferral
    ) {
        guard case let .start(profileId, browserManager, windowId) = deferral else {
            return
        }
        Task { @MainActor [weak self, weak browserManager] in
            await browserManager?.extensionsModule
                .ensureInitialDocumentExtensionContextsLoadedIfNeeded(
                    profileId: profileId
                )
            guard let self else { return }
            self.initialDocumentWarmupGate.finish(profileId: profileId)

            guard let browserManager,
                  let windowState = browserManager.windowRegistry?.windows[windowId]
            else { return }
            browserManager.refreshCompositor(for: windowState)
        }
    }
    
    /// Creates the "primary" WebView - the first WebView for a tab
    /// This WebView is owned by the tab and is the "source of truth"
    private func createPrimaryWebView(for tab: Tab, in windowId: UUID) -> WKWebView? {
        guard let webView = tab.ensureWebView() else {
            assertionFailure("Unable to create normal tab WebView without a resolved profile")
            return nil
        }
        tab.assignWebViewToWindow(webView, windowId: windowId)
        setWebView(webView, for: tab.id, in: windowId)
        return webView
    }
    
    /// Creates a "clone" WebView - additional WebViews for multi-window display
    /// These share the configuration but are separate instances
    private func createCloneWebView(for tab: Tab, in windowId: UUID, primaryWindowId: UUID) -> WKWebView? {
        guard getWebView(for: tab.id, in: primaryWindowId) != nil else {
            assertionFailure("Cannot create a clone WebView before the primary WebView is tracked")
            return nil
        }
        guard let newWebView = tab.makeNormalTabWebView(reason: "WebViewCoordinator.createCloneWebView") else {
            assertionFailure("Unable to create normal tab clone WebView without a resolved profile")
            return nil
        }

        setWebView(newWebView, for: tab.id, in: windowId)
        loadInitialURLIfNeeded(for: newWebView, tab: tab)
        newWebView.sumiSetAudioMuted(tab.audioState.isMuted)
        notifyTabActivatedIfCurrent(tab, in: windowId)
        return newWebView
    }

    private func loadInitialURLIfNeeded(for webView: WKWebView, tab: Tab) {
        if let url = URL(string: tab.url.absoluteString) {
            let performLoad = { [weak tab, weak webView] in
                guard let tab, let webView else { return }
                tab.performMainFrameNavigationAfterHydrationIfNeeded(
                    on: webView
                ) { resolvedWebView in
                    guard !resolvedWebView.isLoading, resolvedWebView.url == nil else { return }
                    resolvedWebView.load(URLRequest(url: url))
                }
            }

            let profileId = tab.resolveProfile()?.id ?? tab.profileId
            Task { @MainActor [weak tab] in
                if let controller = webView.configuration.userContentController
                    .sumiNormalTabUserContentController,
                    controller.hasInstalledInitialUserContent == false
                {
                    await controller.waitForInitialUserContentInstallation()
                }
                if let profileId,
                   let extensionsModule = tab?.browserManager?.extensionsModule
                {
                    await extensionsModule.ensureInitialDocumentExtensionContextsLoadedIfNeeded(
                        profileId: profileId
                    )
                }
                tab?.registerNormalTabWithExtensionRuntimeIfNeeded(
                    reason: "WebViewCoordinator.loadInitialURLIfNeeded"
                )
                performLoad()
            }
        }
    }

    func removeWebViewFromContainers(_ webView: WKWebView) {
        if enqueueDeferredProtectedCommand(
            .removeWebViewFromContainers(webViewID: ObjectIdentifier(webView)),
            for: webView,
            reason: "removeWebViewFromContainers"
        ) {
            return
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

    private func windowId(containing webView: WKWebView) -> UUID? {
        guard let owner = trackedOwner(containing: webView) else { return nil }
        return owner.windowID
    }

    @discardableResult
    func removeAllWebViews(
        for tab: Tab,
        closeActiveFullscreenMedia: Bool = false
    ) -> Bool {
        let currentEntries = webViewRegistry.windowWebViews(for: tab.id)
        let protectedCandidateWebViews = uniqueWebViews(
            Array(currentEntries.values)
                + [tab.assignedWebView, tab.existingWebView].compactMap { $0 }
        )
        if protectedCandidateWebViews.contains(where: isWebViewProtectedFromCompositorMutation) {
            let protectedTrackedIDs = Set(
                currentEntries.values
                    .filter { isWebViewProtectedFromCompositorMutation($0) }
                    .map(ObjectIdentifier.init)
            )
            var closedMediaWebViewIDs: Set<ObjectIdentifier> = []

            func closeFullscreenMediaOnce(on webView: WKWebView) {
                guard closeActiveFullscreenMedia else { return }
                guard closedMediaWebViewIDs.insert(ObjectIdentifier(webView)).inserted else { return }
                closeFullscreenMediaIfNeeded(on: webView)
            }

            for (windowId, protectedWebView) in currentEntries where isWebViewProtectedFromCompositorMutation(protectedWebView) {
                closeFullscreenMediaOnce(on: protectedWebView)
                _ = enqueueDeferredProtectedCommand(
                    .removeTrackedWebView(
                        webViewID: ObjectIdentifier(protectedWebView),
                        tabID: tab.id,
                        windowID: windowId
                    ),
                    for: protectedWebView,
                    reason: "removeAllWebViews"
                )
            }
            for protectedWebView in protectedCandidateWebViews where isWebViewProtectedFromCompositorMutation(protectedWebView) {
                let protectedWebViewID = ObjectIdentifier(protectedWebView)
                closeFullscreenMediaOnce(on: protectedWebView)

                guard !protectedTrackedIDs.contains(protectedWebViewID) else { continue }
                _ = enqueueDeferredProtectedCommand(
                    .cleanupTabWebView(
                        webViewID: protectedWebViewID,
                        tabID: tab.id
                    ),
                    for: protectedWebView,
                    reason: "removeAllWebViews.untracked"
                )
            }
            return false
        }

        let trackedEntries = currentEntries.map { windowId, webView in
            (TrackedWebViewOwner(tabID: tab.id, windowID: windowId), webView)
        }
        guard trackedEntries.isEmpty == false else { return false }

        for (owner, webView) in trackedEntries {
            cleanupUnprotectedTrackedWebView(
                webView,
                owner: owner,
                tab: tab,
                browserManager: tab.browserManager
            )
        }
        refreshPrimaryTrackedWebView(for: tab, browserManager: tab.browserManager)
        return true
    }

    @discardableResult
    func suspendWebViews(for tab: Tab, reason: String) -> Bool {
        let liveWebViews = liveWebViews(for: tab)
        guard !liveWebViews.isEmpty else { return false }
        guard !liveWebViews.contains(where: isWebViewProtectedFromCompositorMutation) else {
            RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
                "Skipping suspension cleanup for protected tab=\(tab.id.uuidString.prefix(8)) reason=\(reason)."
            }
            return false
        }

        let trackedEntries = webViewRegistry.trackedWebViews(for: tab.id)
        var cleanedIdentifiers: Set<ObjectIdentifier> = []

        func cleanup(_ webView: WKWebView) {
            let identifier = ObjectIdentifier(webView)
            guard cleanedIdentifiers.insert(identifier).inserted else { return }
            tab.cleanupCloneWebView(webView)
        }

        for (owner, webView) in trackedEntries {
            removeWebViewFromContainers(webView)
            _ = unregisterTrackedWebViewSlot(
                owner: owner,
                expectedWebView: webView
            )
            cleanup(webView)
        }

        for webView in liveWebViews {
            cleanup(webView)
        }

        tab.cancelPendingMainFrameNavigation()
        tab._webView = nil
        tab._existingWebView = nil
        tab.primaryWindowId = nil

        RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
            "Suspension released \(cleanedIdentifiers.count) WebView(s) for tab=\(tab.id.uuidString.prefix(8)) reason=\(reason)."
        }

        return !cleanedIdentifiers.isEmpty
    }

    // MARK: - WebView Creation & Cross-Window Sync

    private func adoptableExistingPrimaryWebView(
        for tab: Tab,
        in windowId: UUID
    ) -> WKWebView? {
        guard let existingWebView = tab.existingWebView else { return nil }
        guard getAllWebViews(for: tab.id).isEmpty else { return nil }
        guard tab.primaryWindowId == nil || tab.primaryWindowId == windowId else { return nil }
        return existingWebView
    }

    private func adoptExistingPrimaryWebView(
        _ webView: WKWebView,
        for tab: Tab,
        in windowId: UUID
    ) {
        setWebView(webView, for: tab.id, in: windowId)
        tab.assignWebViewToWindow(webView, windowId: windowId)
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

        let protectedCandidateWebViews = Array(webViewRegistry.windowWebViews(for: tab.id).values)
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

        let oldEntries = webViewRegistry.windowWebViews(for: tab.id)
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

        guard let recreatedPrimary = tab.ensureWebView() else {
            assertionFailure("Unable to rebuild normal tab WebView without a resolved profile")
            return
        }
        tab.assignWebViewToWindow(recreatedPrimary, windowId: primaryWindowId)
        setWebView(recreatedPrimary, for: tab.id, in: primaryWindowId)

        for windowId in targetWindowIds
            .filter({ $0 != primaryWindowId })
            .sorted(by: { $0.uuidString < $1.uuidString })
        {
            _ = createCloneWebView(
                for: tab,
                in: windowId,
                primaryWindowId: primaryWindowId
            )
        }

        for windowId in targetWindowIds {
            guard let windowState = tab.browserManager?.windowRegistry?.windows[windowId] else {
                continue
            }
            tab.browserManager?.refreshCompositor(for: windowState)
        }
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
                || visualHandoffProtectedWebViewIDs.contains(webViewID)
                || fullscreenProtection.isProtected(webViewID)
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

        let enqueueResult = deferredProtectedWebViewCommands.enqueue(
            command,
            sourceWebViewID: sourceWebViewID
        )

        switch enqueueResult.outcome {
        case .enqueued:
            PerformanceTrace.emitEvent("WebViewCoordinator.enqueueDeferredProtectedCommand")
            RuntimeDiagnostics.protectedWebViewTrace(
                "enqueueDeferredCommand reason=\(reason) sourceWebView=\(sourceWebViewID) command={\(command.debugSummary)} count=\(enqueueResult.count)"
            )
        case .collapsed:
            PerformanceTrace.emitEvent("WebViewCoordinator.collapseDeferredProtectedCommand")
            RuntimeDiagnostics.protectedWebViewTrace(
                "collapseDeferredCommand reason=\(reason) sourceWebView=\(sourceWebViewID) command={\(command.debugSummary)} count=\(enqueueResult.count)"
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
        weakWebViewRegistry.note(webView)
    }

    private func installFullscreenStateObservationIfNeeded(on webView: WKWebView) {
        noteWeakWebView(webView)
        fullscreenProtection.installObservationIfNeeded(on: webView) { [weak self] webView in
            self?.updateFullscreenProtection(for: webView)
        }
    }

    private func installNowPlayingSessionObservationIfNeeded(on webView: WKWebView) {
        let webViewID = ObjectIdentifier(webView)
        guard nowPlayingSessionCancellablesByWebViewID[webViewID] == nil else { return }
        // WebKit can re-establish its active playback manager after the fullscreen
        // transition itself has completed, so keep one late recovery trigger.
        nowPlayingSessionCancellablesByWebViewID[webViewID] = webView
            .publisher(for: \.sumiHasActiveNowPlayingSession, options: [.new])
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak webView] hasActiveSession in
                guard hasActiveSession,
                      let self,
                      let webView
                else {
                    return
                }
                self.postMediaTouchBarRecoveryRequest(
                    for: webView,
                    owner: self.trackedOwner(containing: webView),
                    fallbackWindowID: self.windowId(containing: webView)
                )
            }
    }

    private func updateFullscreenProtection(for webView: WKWebView) {
        if webView.sumiIsInFullscreenElementPresentation {
            beginFullscreenProtectionIfNeeded(for: webView)
        } else {
            finishFullscreenProtectionIfNeeded(for: webView)
        }
    }

    private func uninstallFullscreenStateObservationIfUntracked(_ webView: WKWebView) {
        fullscreenProtection.uninstallObservationIfUntracked(
            webView,
            isTracked: webViewRegistry.isIndexed(webView)
        )
    }

    private func uninstallNowPlayingSessionObservationIfUntracked(_ webView: WKWebView) {
        guard webViewRegistry.isIndexed(webView) == false else { return }
        nowPlayingSessionCancellablesByWebViewID.removeValue(forKey: ObjectIdentifier(webView))?.cancel()
    }

    private func resolveWeakWebView(
        with identifier: ObjectIdentifier
    ) -> WKWebView? {
        weakWebViewRegistry.resolve(with: identifier)
    }

    private func resolveWebView(
        with identifier: ObjectIdentifier
    ) -> WKWebView? {
        if let webView = webViewRegistry.trackedWebView(with: identifier) {
            noteWeakWebView(webView)
            return webView
        }
        return resolveWeakWebView(with: identifier)
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

    private func pruneStaleWebViewBookkeeping(reason: String) {
        let staleIDs = weakWebViewRegistry.pruneStaleIdentifiers()
        guard staleIDs.isEmpty == false else { return }
        for id in staleIDs {
            activeHistorySwipeProtections.removeValue(forKey: id)
            visualHandoffProtectedWebViewIDs.remove(id)
            fullscreenProtection.remove(id)
            deferredProtectedWebViewCommands.removeAllCommands(for: id)
        }
        RuntimeDiagnostics.protectedWebViewTrace(
            "pruneStaleWebViewBookkeeping reason=\(reason) count=\(staleIDs.count)"
        )
    }

    private func pruneInvalidDeferredProtectedCommands(reason: String) {
        pruneStaleWebViewBookkeeping(reason: "\(reason).staleBookkeeping")

        for sourceWebViewID in deferredProtectedWebViewCommands.sourceWebViewIDs {
            guard resolveWebView(with: sourceWebViewID) != nil else {
                activeHistorySwipeProtections.removeValue(forKey: sourceWebViewID)
                fullscreenProtection.remove(sourceWebViewID)
                for command in deferredProtectedWebViewCommands.drainCommands(for: sourceWebViewID) {
                    dropDeferredProtectedCommand(
                        command,
                        sourceWebViewID: sourceWebViewID,
                        reason: "\(reason).deadSource"
                    )
                }
                continue
            }

            let droppedCommands = deferredProtectedWebViewCommands.pruneCommands(for: sourceWebViewID) { [self] command in
                isDeferredProtectedCommandValid(command) == false
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
        case .removeWebViewFromContainers(let webViewID):
            return resolveWebView(with: webViewID) != nil
        case .removeAllWebViews(let tabID):
            return resolvedTab(with: tabID) != nil
        case .removeTrackedWebView(let webViewID, _, _):
            return resolveWebView(with: webViewID) != nil
        case .closeWebViewFromWebKit(let webViewID):
            return resolveWebView(with: webViewID) != nil
        case .cleanupWindow(let windowID):
            return browserManager?.tabManager != nil
                && (
                    webViewRegistry.trackedWebViews(in: windowID).isEmpty == false
                        || compositorContainerView(for: windowID) != nil
                )
        case .cleanupAllWebViews:
            return browserManager?.tabManager != nil
                && webViewRegistry.isEmpty == false
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

        RuntimeDiagnostics.protectedWebViewTrace(
            "executeDeferredCommand sourceWebView=\(sourceWebViewID) command={\(command.debugSummary)}"
        )

        switch command {
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
        case .removeTrackedWebView(let webViewID, let tabID, let windowID):
            guard let webView = resolveWebView(with: webViewID) else {
                return false
            }
            cleanupTrackedWebView(
                webView,
                owner: TrackedWebViewOwner(tabID: tabID, windowID: windowID)
            )
        case .closeWebViewFromWebKit(let webViewID):
            guard let webView = resolveWebView(with: webViewID) else {
                return false
            }
            handleWebViewDidClose(webView)
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
            rebuildLiveWebViews(
                for: tab,
                preferredPrimaryWindowId: preferredPrimaryWindowID
            )
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
        RuntimeDiagnostics.protectedWebViewTrace(
            "dropDeferredCommand reason=\(reason) sourceWebView=\(sourceWebViewID) command={\(command.debugSummary)}"
        )
    }

    private func cleanupTrackedWebView(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner
    ) {
        finishDestructiveDataCleanupNavigation(on: webView)
        let tab = resolvedTab(with: owner.tabID)
        let cleanupBrowserManager = tab?.browserManager ?? browserManager
        cleanupUnprotectedTrackedWebView(
            webView,
            owner: owner,
            tab: tab,
            browserManager: cleanupBrowserManager
        )
        if let tab {
            refreshPrimaryTrackedWebView(for: tab, browserManager: cleanupBrowserManager)
        }
    }

    private func cleanupUnprotectedTrackedWebView(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner,
        tab: Tab?,
        browserManager: BrowserManager?
    ) {
        removeWebViewFromContainers(webView)
        _ = unregisterTrackedWebViewSlot(owner: owner, expectedWebView: webView)

        if let tab {
            tab.cleanupCloneWebView(webView)
        } else {
            performFallbackWebViewCleanup(
                webView,
                tabId: owner.tabID,
                browserManager: browserManager
            )
        }
    }

    @discardableResult
    private func closeTrackedWebViewFromWebKit(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner
    ) -> Bool {
        guard let browserManager,
              let tab = resolvedTab(with: owner.tabID)
        else {
            cleanupTrackedWebView(webView, owner: owner)
            return true
        }

        let windowState = browserManager.windowRegistry?.windows[owner.windowID]
            ?? browserManager.windowState(containing: tab)
        closeTabForWebKitCloseRequest(tab, windowState: windowState)
        return true
    }

    private func closeTabForWebKitCloseRequest(
        _ tab: Tab,
        windowState: BrowserWindowState?
    ) {
        guard let browserManager else {
            tab.performComprehensiveWebViewCleanup()
            return
        }

        if let windowState {
            browserManager.closeTab(tab, in: windowState)
            return
        }

        if let containingWindow = browserManager.windowState(containing: tab) {
            browserManager.closeTab(tab, in: containingWindow)
            return
        }

        tab.performComprehensiveWebViewCleanup()
        browserManager.tabManager.removeTab(tab.id)
    }

    private func untrackedTabContext(
        for webView: WKWebView
    ) -> (tab: Tab, windowState: BrowserWindowState?)? {
        guard let browserManager else { return nil }

        func matches(_ tab: Tab) -> Bool {
            tab.existingWebView === webView || tab.assignedWebView === webView
        }

        if let windowStates = browserManager.windowRegistry?.allWindows {
            for windowState in windowStates {
                if let tab = windowState.ephemeralTabs.first(where: matches) {
                    return (tab, windowState)
                }
            }
        }

        if let tab = browserManager.tabManager.allTabs().first(where: matches) {
            return (
                tab,
                browserManager.windowState(containing: tab)
            )
        }

        return nil
    }

    private func visibleTabIDs(
        for windowState: BrowserWindowState,
        browserManager: BrowserManager
    ) -> [UUID] {
        VisibleTabPreparationPlan.visibleTabIDs(
            currentTabId: browserManager.currentTab(for: windowState)?.id,
            splitTabIds: browserManager.splitManager.visibleTabIds(for: windowState.id)
        ).filter { tabId in
            guard let tab = resolveTab(for: tabId, in: windowState, browserManager: browserManager) else {
                return false
            }
            return tab.requiresPrimaryWebView
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

    private func registerTrackedWebView(
        _ webView: WKWebView,
        for tabId: UUID,
        in windowId: UUID
    ) {
        let owner = TrackedWebViewOwner(tabID: tabId, windowID: windowId)
        noteWeakWebView(webView)

        if let existingOwner = webViewRegistry.indexedOwner(containing: webView),
           existingOwner != owner
        {
            _ = unregisterTrackedWebViewSlot(
                owner: existingOwner,
                expectedWebView: webView,
                removeFromSuperview: true
            )
        }

        if let existingWebView = webViewRegistry.webView(for: owner),
           existingWebView !== webView
        {
            _ = unregisterTrackedWebViewSlot(
                owner: owner,
                expectedWebView: existingWebView,
                removeFromSuperview: true,
                removeRecentVisibility: false
            )
        }

        webViewRegistry.setWebView(webView, for: owner)
        installFullscreenStateObservationIfNeeded(on: webView)
        installNowPlayingSessionObservationIfNeeded(on: webView)
        webViewRegistry.assertTrackingConsistency("registerTrackedWebView")
    }

    @discardableResult
    private func unregisterTrackedWebViewSlot(
        owner: TrackedWebViewOwner,
        expectedWebView: WKWebView? = nil,
        removeFromSuperview: Bool = false,
        removeRecentVisibility: Bool = true
    ) -> WKWebView? {
        let trackedWebView = webViewRegistry.webView(for: owner)
        if let expectedWebView,
           let trackedWebView,
           trackedWebView !== expectedWebView
        {
            webViewRegistry.removeReverseIndex(for: expectedWebView, ifOwnedBy: owner)
            return nil
        }

        let resolvedWebView = trackedWebView ?? expectedWebView

        if removeFromSuperview,
           let resolvedWebView
        {
            removeWebViewFromContainers(resolvedWebView)
        }

        webViewRegistry.removeWebView(
            owner: owner,
            resolvedWebView: resolvedWebView,
            removeRecentVisibility: removeRecentVisibility
        )
        if let resolvedWebView {
            uninstallFullscreenStateObservationIfUntracked(resolvedWebView)
            uninstallNowPlayingSessionObservationIfUntracked(resolvedWebView)
        }
        pruneInvalidDeferredProtectedCommands(reason: "unregisterTrackedWebViewSlot")
        webViewRegistry.assertTrackingConsistency("unregisterTrackedWebViewSlot")
        return resolvedWebView
    }

    private func trackedOwner(containing webView: WKWebView) -> TrackedWebViewOwner? {
        webViewRegistry.trackedOwner(containing: webView)
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
        let candidates = webViewRegistry.trackedWebViews(for: tabId)
        guard candidates.isEmpty == false else { return nil }

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

        let mruRank = webViewRegistry.recentVisibilityRank(for: owner)
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

        let trackedEntries = webViewRegistry.trackedWebViews(in: windowId)
        let hiddenEntries = trackedEntries.filter { owner, _ in
            visibleTabIDs.contains(owner.tabID) == false
        }

        guard hiddenEntries.isEmpty == false else { return }

        guard let browserManager = tabManager.browserManager else { return }
        let globallyVisibleTabIDs = browserManager.tabSuspensionService
            .suspensionEvaluationContext()
            .visibleTabIDs

        for (owner, webView) in hiddenEntries.sorted(by: {
            if $0.0.tabID != $1.0.tabID {
                return $0.0.tabID.uuidString < $1.0.tabID.uuidString
            }
            return $0.0.windowID.uuidString < $1.0.windowID.uuidString
        }) {
            guard globallyVisibleTabIDs.contains(owner.tabID) else { continue }
            guard let tab = resolvedTab(with: owner.tabID) else { continue }
            guard liveWebViews(for: tab).count > 1 else { continue }

            if isWebViewProtectedFromCompositorMutation(webView) {
                _ = enqueueDeferredProtectedCommand(
                    .evictHiddenWebViews(windowID: windowId),
                    for: webView,
                    reason: "hiddenCloneCleanup"
                )
                continue
            }

            cleanupUnprotectedTrackedWebView(
                webView,
                owner: owner,
                tab: tab,
                browserManager: browserManager
            )
            refreshPrimaryTrackedWebView(for: tab, browserManager: browserManager)

            RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
                "Cleaned hidden clone for visible tab=\(owner.tabID.uuidString.prefix(8)) window=\(windowId.uuidString.prefix(8))."
            }
        }
    }

    private func notifyTabActivatedIfCurrent(_ tab: Tab, in windowId: UUID) {
        guard let browserManager = tab.browserManager else { return }

        if let windowState = browserManager.windowRegistry?.windows[windowId],
           browserManager.currentTab(for: windowState)?.id == tab.id
        {
            browserManager.extensionsModule.notifyTabActivatedIfLoaded(
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
                RuntimeDiagnostics.protectedWebViewTrace(
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

            tab.performMainFrameNavigationAfterHydrationIfNeeded(
                on: webView
            ) { resolvedWebView in
                resolvedWebView.load(URLRequest(url: url))
            }
        }
    }

    /// Reload a tab across all windows displaying it
    func reloadTab(_ tab: Tab) {
        let reloadTargetURL = tab.existingWebView?.url ?? tab.url
        if tab.protectionAttachmentRequiresNormalWebViewRebuild(for: reloadTargetURL)
            || tab.autoplayPolicyRequiresNormalWebViewRebuild(for: reloadTargetURL) {
            tab.refresh()
            return
        }
        let tabId = tab.id
        let allWebViews = getAllWebViews(for: tabId)
        for webView in allWebViews {
            if isWebViewProtectedFromCompositorMutation(webView) {
                RuntimeDiagnostics.protectedWebViewTrace(
                    "skipReloadProtected webView=\(ObjectIdentifier(webView)) tab=\(tabId.uuidString.prefix(8))"
                )
                continue
            }
            tab.performMainFrameNavigationAfterHydrationIfNeeded(
                on: webView
            ) { resolvedWebView in
                resolvedWebView.reload()
            }
        }
    }

    /// Set mute state for a tab across all windows
    func setMuteState(_ muted: Bool, for tabId: UUID) {
        let windowWebViews = webViewRegistry.windowWebViews(for: tabId)
        guard windowWebViews.isEmpty == false else { return }

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
