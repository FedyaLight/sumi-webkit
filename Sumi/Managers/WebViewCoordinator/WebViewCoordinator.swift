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
import ObjectiveC.runtime
import QuartzCore
import WebKit

private enum SumiWKFullscreenWindowControllerSelectors {
    /// Matches `WKFullScreenWindowController` private initializer used by DuckDuckGo’s Mission Control workaround.
    static let initWithWindowWebViewPage = NSSelectorFromString("initWithWindow:webView:page:")
}

private enum SumiFullscreenWindowControllerAssociatedKeys {
    private static let associatedTabStorage = StaticString("Sumi.sumiFullscreenWindowController.associatedTab")

    static var associatedTab: UnsafeRawPointer {
        UnsafeRawPointer(associatedTabStorage.utf8Start)
    }
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

@MainActor
final class SumiWebViewContainerView: NSView {
    /// DuckDuckGo `WebViewContainerView` parity: Mission Control `initWithWindow:webView:page:` workaround (off by default).
    private static let missionControlFullscreenWindowReinitEnabled = false

    /// DuckDuckGo: wire `WKFullScreenWindowController.nextResponder` to the embedder `NSViewController`
    /// (`WindowWebContentController` when attached — Sumi’s analogue of `MainViewController`).
    private static let webKitFullscreenNextResponderBridgeEnabled = true

    let tabID: UUID
    let webView: WKWebView
    weak var tab: Tab?

    private var cancellables = Set<AnyCancellable>()
    private var blurViewIsHiddenCancellable: AnyCancellable?
    private var viewportCornerRadius: CGFloat = 0
    /// DDG `MainViewController` parity: fullscreen `nextResponder` target (see `WebsiteCompositorView.attach`).
    weak var compositorContentOwner: WindowWebContentController?

    override var constraints: [NSLayoutConstraint] { [] }

    init(tab: Tab, webView: WKWebView) {
        self.tab = tab
        self.tabID = tab.id
        self.webView = webView
        super.init(frame: .zero)

        configure(webView: webView)
    }

    private func configure(webView: WKWebView) {
        autoresizingMask = [.width, .height]
        wantsLayer = true
        clipsToBounds = true
        layer?.backgroundColor = NSColor.clear.cgColor
        if #available(macOS 10.15, *) {
            layer?.cornerCurve = .continuous
        }
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = [.width, .height]

        addDisplayedContent(webView.sumiTabContentView)
        updateViewportMask()
    }

    func setBrowserContentViewport(geometry: BrowserChromeGeometry) {
        let radiusChanged = abs(viewportCornerRadius - geometry.contentRadius) > 0.000_1
        guard radiusChanged else { return }

        viewportCornerRadius = geometry.contentRadius

        updateViewportMask()
        needsLayout = true
    }

    func attachDisplayedContentIfNeeded() {
        let displayedView = webView.sumiTabContentView
        frameDisplayedContent(displayedView)
        guard displayedView.superview !== self else { return }
        addDisplayedContent(displayedView)
    }

    private func addDisplayedContent(_ displayedView: NSView) {
        frameDisplayedContent(displayedView)
        addSubview(displayedView)
    }

    private func frameDisplayedContent(_ displayedView: NSView) {
        displayedView.frame = bounds
        displayedView.autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        webView.sumiTabContentView.frame = bounds
        updateViewportMask()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard containsPointInsideRoundedViewport(point) else {
            return nil
        }
        return super.hitTest(point)
    }

    override func removeFromSuperview() {
        let wasAttached = superview != nil
        blurViewIsHiddenCancellable?.cancel()
        blurViewIsHiddenCancellable = nil
        cancellables.removeAll()
        compositorContentOwner = nil
        if wasAttached {
            webView.sumiTabContentView.removeFromSuperview()
        }
        super.removeFromSuperview()
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        guard subview === webView.sumiTabContentView else { return }
        guard webView.sumiTabContentView !== webView else {
            blurViewIsHiddenCancellable?.cancel()
            blurViewIsHiddenCancellable = nil
            cancellables.removeAll()
            return
        }

        subview.frame = bounds
        subview.autoresizingMask = [.width, .height]

        // DuckDuckGo `WebViewContainerView.didAddSubview`: tame `NSVisualEffectView` sizing during fullscreen placeholder.
        if let blurView = subview.subviews.first(where: { $0 is NSVisualEffectView }),
           blurView.frame != subview.bounds {
            blurView.frame = subview.bounds
            blurView.isHidden = false
            blurViewIsHiddenCancellable?.cancel()
            blurViewIsHiddenCancellable = blurView.publisher(for: \.isHidden)
                .sink { [weak blurView] isHidden in
                    if isHidden {
                        blurView?.isHidden = false
                    }
                }
        } else {
            blurViewIsHiddenCancellable?.cancel()
            blurViewIsHiddenCancellable = nil
        }

        cancellables.removeAll()

        webView.publisher(for: \.window)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] fullScreenWindow in
                guard let self,
                      let fullScreenWindow,
                      let fullScreenWindowController = fullScreenWindow.windowController,
                      fullScreenWindowController.sumiIsWebKitFullScreenWindowController
                else { return }

                fullScreenWindowController.sumiAssociatedTab =
                    (self.webView as? FocusableWKWebView)?.owningTab ?? self.tab
                self.observeTabMainWindow(fullScreenWindowController: fullScreenWindowController)
                self.observeFullScreenWindowWillExitFullScreen(fullScreenWindowController: fullScreenWindowController)
            }
            .store(in: &cancellables)
    }

    private var effectiveViewportCornerRadius: CGFloat {
        min(
            max(0, viewportCornerRadius),
            max(0, bounds.width / 2),
            max(0, bounds.height / 2)
        )
    }

    private func updateViewportMask() {
        guard let layer else { return }

        let radius = effectiveViewportCornerRadius
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contentsScale = scale
        layer.masksToBounds = radius > 0
        layer.cornerRadius = radius
        if #available(macOS 10.15, *) {
            layer.cornerCurve = .continuous
        }
        CATransaction.commit()
    }

    private func containsPointInsideRoundedViewport(_ point: NSPoint) -> Bool {
        guard bounds.contains(point) else { return false }

        let radius = effectiveViewportCornerRadius
        guard radius > 0 else { return true }

        let minX = bounds.minX
        let maxX = bounds.maxX
        let minY = bounds.minY
        let maxY = bounds.maxY

        if point.x >= minX + radius && point.x <= maxX - radius {
            return true
        }

        if point.y >= minY + radius && point.y <= maxY - radius {
            return true
        }

        let center: NSPoint
        if point.x < minX + radius {
            center = point.y < minY + radius
                ? NSPoint(x: minX + radius, y: minY + radius)
                : NSPoint(x: minX + radius, y: maxY - radius)
        } else {
            center = point.y < minY + radius
                ? NSPoint(x: maxX - radius, y: minY + radius)
                : NSPoint(x: maxX - radius, y: maxY - radius)
        }

        let dx = point.x - center.x
        let dy = point.y - center.y
        return dx * dx + dy * dy <= radius * radius
    }

    /// DuckDuckGo `observeTabMainWindow`: fullscreen `WKFullScreenWindowController.nextResponder` → embedder VC.
    private func observeTabMainWindow(fullScreenWindowController: NSWindowController) {
        guard webView !== webView.sumiTabContentView else {
            assertionFailure("WebView tab content placeholder should be present for fullscreen menu routing")
            return
        }

        webView.sumiTabContentView.publisher(for: \.window)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak fullScreenWindowController] window in
                guard let self,
                      let fullScreenWindowController,
                      let window,
                      let mainViewController = window.windowController?.contentViewController
                else { return }

                guard Self.webKitFullscreenNextResponderBridgeEnabled else { return }
                let nextTarget = self.compositorContentOwner ?? mainViewController
                fullScreenWindowController.nextResponder = nextTarget
            }
            .store(in: &cancellables)
    }

    /// DuckDuckGo `observeFullScreenWindowWillExitFullScreen` (Mission Control controller re-init when enabled).
    private func observeFullScreenWindowWillExitFullScreen(fullScreenWindowController: NSWindowController) {
        guard let fullScreenWindow = fullScreenWindowController.window else { return }

        NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification, object: fullScreenWindow)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak fullScreenWindowController] _ in
                guard let self else { return }
                self.cancellables.removeAll()

                let shouldReinitWindowController = Self.missionControlFullscreenWindowReinitEnabled
                    && NSWorkspace.sumiIsMissionControlActive()
                    && fullScreenWindowController != nil
                    && (fullScreenWindowController?.responds(
                        to: SumiWKFullscreenWindowControllerSelectors.initWithWindowWebViewPage
                    ) ?? false)

                guard shouldReinitWindowController,
                      let fullScreenWindowController
                else { return }

                DispatchQueue.main.async { [weak fullScreenWindowController, weak webView = self.webView] in
                    guard let webView,
                          let fullScreenWindowController,
                          let window = fullScreenWindowController.window,
                          let pageRef = webView.sumiValue(forIvar: SumiFullscreenKey.page),
                          let method = class_getInstanceMethod(
                              object_getClass(fullScreenWindowController),
                              SumiWKFullscreenWindowControllerSelectors.initWithWindowWebViewPage
                          )
                    else { return }

                    window.close()
                    fullScreenWindowController.window = nil

                    let newWindow = type(of: window).init(
                        contentRect: NSScreen.main?.frame ?? .zero,
                        styleMask: window.styleMask,
                        backing: .buffered,
                        defer: false
                    )

                    let imp = method_getImplementation(method)
                    typealias InitWithWindowWebViewPage = @convention(c) (
                        NSWindowController,
                        ObjectiveC.Selector,
                        NSWindow,
                        WKWebView,
                        UnsafeRawPointer
                    ) -> NSWindowController?
                    let initWithWindowWebViewPage = unsafeBitCast(imp, to: InitWithWindowWebViewPage.self)
                    _ = initWithWindowWebViewPage(
                        fullScreenWindowController,
                        SumiWKFullscreenWindowControllerSelectors.initWithWindowWebViewPage,
                        newWindow,
                        webView,
                        pageRef
                    )

                    _ = Unmanaged.passUnretained(fullScreenWindowController).retain()
                }
            }
            .store(in: &cancellables)
    }

    private enum SumiFullscreenKey {
        static let page = "_page"
    }
}

private extension NSObject {
    func sumiValue(forIvar name: String) -> UnsafeRawPointer? {
        guard let ivar = class_getInstanceVariable(object_getClass(self), name),
              let value = object_getIvar(self, ivar)
        else { return nil }
        return UnsafeRawPointer(Unmanaged.passUnretained(value as AnyObject).toOpaque())
    }
}

private extension [CFString: Any] {
    /// DuckDuckGo `NSWorkspaceExtension` parity for `CGWindowListCopyWindowInfo` dictionaries.
    var sumiWindowListName: String? {
        self[kCGWindowName] as? String
    }

    var sumiWindowListOwnerName: String? {
        self[kCGWindowOwnerName] as? String
    }

    var sumiWindowListSize: CGSize {
        guard let bounds = self[kCGWindowBounds] as? [String: NSNumber],
              let width = bounds["Width"]?.intValue,
              let height = bounds["Height"]?.intValue
        else {
            return .zero
        }
        return CGSize(width: width, height: height)
    }
}

private extension NSWorkspace {
    /// Detect if macOS Mission Control is active — aligned with DuckDuckGo `NSWorkspace.isMissionControlActive()`.
    static func sumiIsMissionControlActive() -> Bool {
        guard let visibleWindows = CGWindowListCopyWindowInfo(
            .optionOnScreenOnly,
            CGWindowID(0)
        ) as? [[CFString: Any]] else {
            return false
        }

        let dockAppWindows = visibleWindows.filter { window in
            window.sumiWindowListOwnerName == "Dock"
        }
        var missionControlWindows = dockAppWindows.filter { window in
            window.sumiWindowListName?.hasPrefix("Wallpaper") != true
        }
        for screen in NSScreen.screens {
            if let idx = missionControlWindows.firstIndex(where: { window in
                window.sumiWindowListSize == screen.frame.size
            }) {
                missionControlWindows.remove(at: idx)
            }
        }

        return missionControlWindows.isEmpty == false
    }
}

private extension NSWindowController {
    final class WeakTabReference: NSObject {
        weak var tab: Tab?

        init(tab: Tab) {
            self.tab = tab
        }
    }

    var sumiAssociatedTab: Tab? {
        get {
            (objc_getAssociatedObject(
                self,
                SumiFullscreenWindowControllerAssociatedKeys.associatedTab
            ) as? WeakTabReference)?.tab
        }
        set {
            objc_setAssociatedObject(
                self,
                SumiFullscreenWindowControllerAssociatedKeys.associatedTab,
                newValue.map { WeakTabReference(tab: $0) },
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    /// WebKit’s fullscreen window controller (not Sumi’s main browser window / SwiftUI host).
    var sumiIsWebKitFullScreenWindowController: Bool {
        guard className.localizedCaseInsensitiveContains("FullScreen") else { return false }
        return responds(to: SumiWKFullscreenWindowControllerSelectors.initWithWindowWebViewPage)
    }
}

private struct HistorySwipeProtectionContext {
    let windowID: UUID?
    let originURL: URL?
    let originHistoryItem: WKBackForwardListItem?
    let originHistoryURL: URL?
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

enum DeferredWebViewCommandKey: Hashable {
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

}

private struct TrackedWebViewOwner: Equatable {
    let tabID: UUID
    let windowID: UUID
}

@MainActor
@Observable
class WebViewCoordinator {
    /// Window-specific web views: tabId -> windowId -> WKWebView
    @ObservationIgnored
    private var webViewsByTabAndWindow: [UUID: [UUID: WKWebView]] = [:]

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
    private var deferredProtectedWebViewCommands: [ObjectIdentifier: DeferredProtectedCommandBuffer] = [:]

    @ObservationIgnored
    private var weakWebViewsByIdentifier: [ObjectIdentifier: WeakWKWebView] = [:]

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

    func getAllWebViews(for tabId: UUID) -> [WKWebView] {
        guard let windowWebViews = webViewsByTabAndWindow[tabId] else { return [] }
        return Array(windowWebViews.values)
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
        if let windowWebViews = webViewsByTabAndWindow[tab.id] {
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

    func windowIDs(for tabId: UUID) -> [UUID] {
        guard let windowWebViews = webViewsByTabAndWindow[tabId] else { return [] }
        return Array(windowWebViews.keys)
    }

    func setWebView(_ webView: WKWebView, for tabId: UUID, in windowId: UUID) {
        registerTrackedWebView(webView, for: tabId, in: windowId)
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

    func isWebViewProtectedFromCompositorMutation(_ webView: WKWebView) -> Bool {
        let webViewID = ObjectIdentifier(webView)
        return activeHistorySwipeProtections[webViewID] != nil
    }

    func windowID(containing webView: WKWebView) -> UUID? {
        windowId(containing: webView)
    }

    private func flushDeferredProtectedCommands(for webViewID: ObjectIdentifier) {
        guard activeHistorySwipeProtections[webViewID] == nil else { return }
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
    func getOrCreateWebView(for tab: Tab, in windowId: UUID) -> WKWebView? {
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
    private func createPrimaryWebView(for tab: Tab, in windowId: UUID) -> WKWebView? {
        if let adoptedWebView = adoptExistingPrimaryWebViewIfNeeded(for: tab, in: windowId) {
            return adoptedWebView
        }

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

            if let controller = webView.configuration.userContentController.sumiNormalTabUserContentController {
                Task { @MainActor in
                    let signpostState = PerformanceTrace.beginInterval("ContentBlocking.assetsInstallWait")
                    await controller.waitForContentBlockingAssetsInstalled()
                    PerformanceTrace.endInterval("ContentBlocking.assetsInstallWait", signpostState)
                    performLoad()
                }
            } else {
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

        let trackedEntries = (webViewsByTabAndWindow[tab.id] ?? [:]).map { windowId, webView in
            (TrackedWebViewOwner(tabID: tab.id, windowID: windowId), webView)
        }
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
            webViewOwnersByIdentifier.removeAll()
            recentlyVisibleTabIDsByWindow.removeAll()
            compositorContainerViews.removeAll()
            scheduledPrepareWindowIds.removeAll()
        }

        RuntimeDiagnostics.debug("Completed full WebView cleanup.", category: "WebViewCoordinator")

        pruneStaleWebViewBookkeeping(reason: "cleanupAllWebViews")
    }

    // MARK: - WebView Creation & Cross-Window Sync

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
        guard weakWebViewsByIdentifier.isEmpty == false else { return }
        let staleIDs = weakWebViewsByIdentifier.compactMap { key, entry -> ObjectIdentifier? in
            entry.value == nil ? key : nil
        }
        guard staleIDs.isEmpty == false else { return }
        for id in staleIDs {
            weakWebViewsByIdentifier.removeValue(forKey: id)
            activeHistorySwipeProtections.removeValue(forKey: id)
            deferredProtectedWebViewCommands.removeValue(forKey: id)
        }
        RuntimeDiagnostics.swipeTrace(
            "pruneStaleWebViewBookkeeping reason=\(reason) count=\(staleIDs.count)"
        )
    }

    private func pruneInvalidDeferredProtectedCommands(reason: String) {
        pruneStaleWebViewBookkeeping(reason: "\(reason).staleBookkeeping")

        for sourceWebViewID in Array(deferredProtectedWebViewCommands.keys) {
            guard resolveWebView(with: sourceWebViewID) != nil else {
                activeHistorySwipeProtections.removeValue(forKey: sourceWebViewID)
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
           let resolvedWebView
        {
            removeWebViewFromContainers(resolvedWebView)
        }

        webViewsByTabAndWindow[owner.tabID]?[owner.windowID] = nil
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
    }

    private func trackedOwner(containing webView: WKWebView) -> TrackedWebViewOwner? {
        let webViewID = ObjectIdentifier(webView)
        guard let owner = webViewOwnersByIdentifier[webViewID] else { return nil }
        guard let trackedWebView = webViewsByTabAndWindow[owner.tabID]?[owner.windowID],
              trackedWebView === webView
        else {
            webViewOwnersByIdentifier.removeValue(forKey: webViewID)
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

            removeWebViewFromContainers(webView)
            _ = unregisterTrackedWebViewSlot(owner: owner, expectedWebView: webView)
            tab.cleanupCloneWebView(webView)
            refreshPrimaryTrackedWebView(for: tab, browserManager: browserManager)

            RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
                "Cleaned hidden clone for visible tab=\(owner.tabID.uuidString.prefix(8)) window=\(windowId.uuidString.prefix(8))."
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

            tab.performMainFrameNavigationAfterHydrationIfNeeded(
                on: webView
            ) { resolvedWebView in
                resolvedWebView.load(URLRequest(url: url))
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
            tab.performMainFrameNavigationAfterHydrationIfNeeded(
                on: webView
            ) { resolvedWebView in
                resolvedWebView.reload()
            }
        }
    }

    /// Set mute state for a tab across all windows
    func setMuteState(_ muted: Bool, for tabId: UUID) {
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
