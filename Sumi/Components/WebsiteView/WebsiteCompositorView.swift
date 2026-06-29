import AppKit
import QuartzCore
import SwiftUI
import WebKit

@MainActor
private func hostedWebViewCount(in root: NSView, stoppingAfter limit: Int = .max) -> Int {
    var count = 0
    for subview in root.subviews {
        if subview is SumiWebViewContainerView || subview is WKWebView {
            count += 1
        } else {
            count += hostedWebViewCount(in: subview, stoppingAfter: limit - count)
        }
        if count > limit {
            return count
        }
    }
    return count
}

// MARK: - Tab Compositor Wrapper

struct WebsiteDisplayState: Equatable {
    let splitGroup: SplitGroup?
    let currentId: UUID?
    let compositorVersion: Int
    let currentTabUnloaded: Bool
    let visibleTabIds: Set<UUID>
    let isSplitDropCaptureActive: Bool

    var activeSplitGroup: SplitGroup? {
        guard let splitGroup,
              let currentId,
              splitGroup.contains(currentId)
        else {
            return nil
        }
        return splitGroup
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.splitGroup == rhs.splitGroup
            && lhs.currentId == rhs.currentId
            && lhs.compositorVersion == rhs.compositorVersion
            && lhs.currentTabUnloaded == rhs.currentTabUnloaded
            && lhs.visibleTabIds == rhs.visibleTabIds
            && lhs.isSplitDropCaptureActive == rhs.isSplitDropCaptureActive
    }
}

@MainActor
protocol WindowWebContentBrowserContext: AnyObject {
    var sidebarDragState: SidebarDragState { get }

    func currentTab(for windowState: BrowserWindowState) -> Tab?
    func tab(for tabId: UUID) -> Tab?
    func splitGroup(for windowId: UUID) -> SplitGroup?
    func schedulePrepareVisibleWebViews(for windowState: BrowserWindowState)
    func enqueueWindowMutationDuringHistorySwipe(
        _ kind: HistorySwipeDeferredWindowMutationKind,
        for windowState: BrowserWindowState
    )
    func removeSplitGroup(id: UUID)
    func updateSplitLayoutSizes(
        groupId: UUID,
        path: [Int],
        sizes: [Double],
        for windowId: UUID
    )
    func configureSplitDropCapture(_ view: SplitDropCaptureView, windowId: UUID)
    func configureSplitControls(
        _ controls: SplitPaneControlsView,
        tab: Tab,
        windowState: BrowserWindowState
    )
}

@MainActor
final class BrowserManagerWindowWebContentContext: WindowWebContentBrowserContext {
    private let browserManager: BrowserManager
    let sidebarDragState: SidebarDragState

    init(
        browserManager: BrowserManager,
        sidebarDragState: SidebarDragState
    ) {
        self.browserManager = browserManager
        self.sidebarDragState = sidebarDragState
    }

    func currentTab(for windowState: BrowserWindowState) -> Tab? {
        browserManager.currentTab(for: windowState)
    }

    func tab(for tabId: UUID) -> Tab? {
        browserManager.tabManager.tab(for: tabId)
    }

    func splitGroup(for windowId: UUID) -> SplitGroup? {
        browserManager.splitManager.splitGroup(for: windowId)
    }

    func removeSplitGroup(id: UUID) {
        browserManager.tabManager.removeSplitGroup(id: id)
    }

    func updateSplitLayoutSizes(
        groupId: UUID,
        path: [Int],
        sizes: [Double],
        for windowId: UUID
    ) {
        browserManager.splitManager.updateLayoutSizes(
            groupId: groupId,
            path: path,
            sizes: sizes,
            for: windowId
        )
    }

    func schedulePrepareVisibleWebViews(for windowState: BrowserWindowState) {
        browserManager.schedulePrepareVisibleWebViews(for: windowState)
    }

    func enqueueWindowMutationDuringHistorySwipe(
        _ kind: HistorySwipeDeferredWindowMutationKind,
        for windowState: BrowserWindowState
    ) {
        browserManager.enqueueWindowMutationDuringHistorySwipe(kind, for: windowState)
    }

    func configureSplitDropCapture(_ view: SplitDropCaptureView, windowId: UUID) {
        view.browserManager = browserManager
        view.splitManager = browserManager.splitManager
        view.sidebarDragState = sidebarDragState
        view.windowId = windowId
    }

    func configureSplitControls(
        _ controls: SplitPaneControlsView,
        tab: Tab,
        windowState: BrowserWindowState
    ) {
        controls.configure(
            tab: tab,
            browserManager: browserManager,
            splitManager: browserManager.splitManager,
            windowState: windowState,
            sidebarDragState: sidebarDragState
        )
    }
}

private enum WindowWebContentPresentationDecision {
    case single(tab: Tab?, repairSplitGroupId: UUID?)
    case split(group: SplitGroup, tabs: [Tab])
}

@MainActor
private final class WindowWebContentVisualHandoffFlowOwner {
    struct Runtime {
        let hasActiveHistorySwipe: () -> Bool
        let tab: (UUID) -> Tab?
        let splitGroup: () -> SplitGroup?
        let displayedHost: (UUID) -> SumiWebViewContainerView?
        let splitPaneTabIds: () -> [UUID]
        let singlePaneRoot: () -> NSView?
        let hasHostedSplitWebViews: () -> Bool
    }

    private let runtime: Runtime

    init(runtime: Runtime) {
        self.runtime = runtime
    }

    func needsDisplayStateApply(
        appliedDisplayState: WebsiteDisplayState?,
        displayState: WebsiteDisplayState,
        currentTab: Tab?
    ) -> Bool {
        appliedDisplayState != displayState
            || hasStaleHostedWebViews(currentTab: currentTab, displayState: displayState)
    }

    func presentationDecision(
        for displayState: WebsiteDisplayState,
        currentTab: Tab?
    ) -> WindowWebContentPresentationDecision {
        guard let group = displayState.activeSplitGroup else {
            return .single(tab: currentTab, repairSplitGroupId: nil)
        }

        let tabs = group.tabIds.compactMap { runtime.tab($0) }
        guard tabs.count == group.tabIds.count else {
            return .single(tab: currentTab, repairSplitGroupId: group.id)
        }

        return .split(group: group, tabs: tabs)
    }

    func immediatePresentationDecision(
        currentTab: Tab?
    ) -> WindowWebContentPresentationDecision? {
        guard !runtime.hasActiveHistorySwipe(),
              let currentTab,
              currentTab.requiresPrimaryWebView
        else {
            return nil
        }

        if let group = runtime.splitGroup(),
           group.contains(currentTab.id) {
            let tabs = group.tabIds.compactMap { runtime.tab($0) }
            guard tabs.count == group.tabIds.count else { return nil }
            return .split(group: group, tabs: tabs)
        }

        return .single(tab: currentTab, repairSplitGroupId: nil)
    }

    func incomingTabIDsForVisualHandoff(
        _ decision: WindowWebContentPresentationDecision
    ) -> Set<UUID>? {
        switch decision {
        case .single(let tab, _):
            guard let tab,
                  tab.requiresPrimaryWebView,
                  runtime.displayedHost(tab.id) == nil
            else {
                return nil
            }
            return [tab.id]
        case .split(let group, _):
            return Set(group.tabIds)
        }
    }

    private func hasStaleHostedWebViews(
        currentTab: Tab?,
        displayState: WebsiteDisplayState
    ) -> Bool {
        guard !runtime.hasActiveHistorySwipe() else {
            return false
        }

        guard let activeSplitGroup = displayState.activeSplitGroup else {
            let expected = (currentTab != nil && displayState.currentTabUnloaded == false) ? 1 : 0
            if let singlePaneRoot = runtime.singlePaneRoot(),
               hostedWebViewCount(in: singlePaneRoot, stoppingAfter: expected) > expected {
                return true
            }
            if runtime.hasHostedSplitWebViews() { return true }
            return false
        }

        if let singlePaneRoot = runtime.singlePaneRoot(),
           hostedWebViewCount(in: singlePaneRoot, stoppingAfter: 0) > 0 {
            return true
        }
        for tabId in runtime.splitPaneTabIds() where activeSplitGroup.contains(tabId) == false {
            return true
        }
        return false
    }
}

@MainActor
final class WindowWebContentController: NSViewController {
    private let browserContext: any WindowWebContentBrowserContext
    private let webViewCoordinator: WebViewCoordinator
    private let windowState: BrowserWindowState
    private var chromeGeometry: BrowserChromeGeometry
    private lazy var containerView = WindowWebContentSplitHostLayoutView(
        browserContext: browserContext,
        windowId: windowState.id,
        chromeGeometry: chromeGeometry
    )

    private var pendingDisplayState: WebsiteDisplayState?
    private var appliedDisplayState: WebsiteDisplayState?
    private var isDisplayStateApplyScheduled = false
    private var contentBackgroundColor: Color = .white
    private var lastHoverTabId: UUID?
    private var pendingSplitRepairGroupId: UUID?
    private var hoveredLinkHandler: ((String?) -> Void)?
    private lazy var hostLifecycleOwner = WindowWebContentHostLifecycleOwner(
        containerView: containerView,
        webViewCoordinator: webViewCoordinator,
        windowID: windowState.id,
        chromeGeometry: chromeGeometry,
        contentBackgroundColor: contentBackgroundColor
    )
    private lazy var visualHandoffCovers = WindowWebContentVisualHandoffCoverController(
        containerView: containerView,
        releaseCover: { [weak self] webViewID, host in
            guard let self else { return }
            self.containerView.removeVisualHandoffCover(host)
            self.hostLifecycleOwner.removeParkedProtectedHost(for: webViewID)
            self.webViewCoordinator.finishVisualHandoffProtection(for: host.webView)
        }
    )
    private lazy var visualHandoffFlow = WindowWebContentVisualHandoffFlowOwner(
        runtime: .init(
            hasActiveHistorySwipe: { [weak self] in
                guard let self else { return true }
                return self.webViewCoordinator.hasActiveHistorySwipe(in: self.windowState.id)
            },
            tab: { [weak self] tabId in
                self?.browserContext.tab(for: tabId)
            },
            splitGroup: { [weak self] in
                guard let self else { return nil }
                return self.browserContext.splitGroup(for: self.windowState.id)
            },
            displayedHost: { [weak self] tabId in
                self?.hostLifecycleOwner.displayedHost(for: tabId)
            },
            splitPaneTabIds: { [weak self] in
                self?.hostLifecycleOwner.splitPaneTabIds ?? []
            },
            singlePaneRoot: { [weak self] in
                self?.containerView.singlePaneView
            },
            hasHostedSplitWebViews: { [weak self] in
                self?.containerView.hasHostedSplitWebViews ?? false
            }
        )
    )
    private lazy var mediaTouchBarRecoveryController = WindowMediaTouchBarRecoveryController(
        windowID: windowState.id,
        recover: { [weak self] tabID, webView in
            self?.recoverMediaTouchBarAfterWebKitReparent(tabID: tabID, webView: webView)
        }
    )

    fileprivate init(
        browserContext: any WindowWebContentBrowserContext,
        webViewCoordinator: WebViewCoordinator,
        chromeGeometry: BrowserChromeGeometry,
        windowState: BrowserWindowState
    ) {
        self.browserContext = browserContext
        self.webViewCoordinator = webViewCoordinator
        self.chromeGeometry = chromeGeometry
        self.windowState = windowState
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = containerView
        webViewCoordinator.setCompositorContainerView(containerView, for: windowState.id)
        webViewCoordinator.setImmediateVisualHandoffHandler({ [weak self] in
            self?.performImmediateVisualHandoffIfPossible() ?? false
        }, for: windowState.id)
        mediaTouchBarRecoveryController.start()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.browserContext.schedulePrepareVisibleWebViews(for: self.windowState)
        }
    }

    func tearDownController() {
        if webViewCoordinator.hasActiveFullscreen(in: windowState.id) {
            webViewCoordinator.closeActiveFullscreenMedia(in: windowState.id)
        }
        releaseVisualHandoffCovers()
        hostLifecycleOwner.clearSinglePane()
        hostLifecycleOwner.clearAllSplitPaneHosts()
        mediaTouchBarRecoveryController.stop()
        webViewCoordinator.setImmediateVisualHandoffHandler(nil, for: windowState.id)
        webViewCoordinator.removeCompositorContainerView(for: windowState.id)
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        if webViewCoordinator.hasActiveHistorySwipe(in: windowState.id) {
            browserContext.enqueueWindowMutationDuringHistorySwipe(
                .refreshCompositor,
                for: windowState
            )
            view.layoutSubtreeIfNeeded()
        }
    }

    func update(
        displayState: WebsiteDisplayState,
        hoveredLinkHandler: @escaping (String?) -> Void,
        chromeGeometry: BrowserChromeGeometry,
        contentBackgroundColor: Color
    ) {
        let currentTab = browserContext.currentTab(for: windowState)
        let needsDisplayStateApply = visualHandoffFlow.needsDisplayStateApply(
            appliedDisplayState: appliedDisplayState,
            displayState: displayState,
            currentTab: currentTab
        )

        let previousBg = self.contentBackgroundColor
        self.contentBackgroundColor = contentBackgroundColor
        let bgChanged = previousBg != contentBackgroundColor

        if self.chromeGeometry != chromeGeometry || bgChanged {
            self.chromeGeometry = chromeGeometry
            containerView.setChromeGeometry(chromeGeometry)
            hostLifecycleOwner.updateViewportStyle(
                chromeGeometry: chromeGeometry,
                contentBackgroundColor: contentBackgroundColor
            )
        }

        pendingDisplayState = displayState
        self.hoveredLinkHandler = hoveredLinkHandler

        if displayState.currentId == nil {
            hoveredLinkHandler(nil)
            lastHoverTabId = nil
        }

        if !displayState.visibleTabIds.isEmpty
            && hostLifecycleOwner.missingPreparedWebViews(
                for: displayState.visibleTabIds,
                browserContext: browserContext
            ) {
            browserContext.schedulePrepareVisibleWebViews(for: windowState)
        }

        if lastHoverTabId != displayState.currentId,
           let currentTab {
            setupHoverCallbacks(for: currentTab)
            lastHoverTabId = displayState.currentId
        }

        guard needsDisplayStateApply else { return }
        scheduleDisplayStateApply()
    }

    private func scheduleDisplayStateApply() {
        guard !isDisplayStateApplyScheduled else { return }
        isDisplayStateApplyScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.applyPendingDisplayStateIfNeeded()
        }
    }

    private func applyPendingDisplayStateIfNeeded() {
        isDisplayStateApplyScheduled = false
        guard let displayState = pendingDisplayState else { return }

        if webViewCoordinator.hasActiveHistorySwipe(in: windowState.id) {
            browserContext.enqueueWindowMutationDuringHistorySwipe(
                .refreshCompositor,
                for: windowState
            )
            return
        }

        let currentTab = browserContext.currentTab(for: windowState)
        guard visualHandoffFlow.needsDisplayStateApply(
            appliedDisplayState: appliedDisplayState,
            displayState: displayState,
            currentTab: currentTab
        ) else { return }

        let previousCurrentId = appliedDisplayState?.currentId
        apply(displayState: displayState, currentTab: currentTab)
        appliedDisplayState = displayState

        if previousCurrentId != displayState.currentId {
            restoreFocusIfNeeded(for: displayState.currentId)
        }
    }

    private func apply(displayState: WebsiteDisplayState, currentTab: Tab?) {
        containerView.setSplitDropCaptureActive(displayState.isSplitDropCaptureActive)
        apply(visualHandoffFlow.presentationDecision(for: displayState, currentTab: currentTab))
    }

    private func apply(_ decision: WindowWebContentPresentationDecision) {
        let didBeginVisualHandoff = beginVisualHandoffCovers(for: decision)

        switch decision {
        case .single(let tab, let repairSplitGroupId):
            if let repairSplitGroupId {
                scheduleSplitRepair(groupId: repairSplitGroupId)
            }
            showSinglePane(tab: tab)
        case .split(let group, let tabs):
            showSplitGroup(group, tabs: tabs)
        }

        scheduleVisualHandoffCoverRelease(if: didBeginVisualHandoff)
    }

    private func performImmediateVisualHandoffIfPossible() -> Bool {
        let currentTab = browserContext.currentTab(for: windowState)
        guard let decision = visualHandoffFlow.immediatePresentationDecision(currentTab: currentTab)
        else {
            return false
        }

        apply(decision)

        guard let currentTab else { return false }
        return hostLifecycleOwner.displayedHost(for: currentTab.id) != nil
    }

    private func beginVisualHandoffCovers(for decision: WindowWebContentPresentationDecision) -> Bool {
        guard let incomingTabIDs = visualHandoffFlow.incomingTabIDsForVisualHandoff(decision) else {
            return false
        }
        return beginVisualHandoffCovers(excluding: incomingTabIDs)
    }

    @discardableResult
    private func beginVisualHandoffCovers(excluding incomingTabIDs: Set<UUID>) -> Bool {
        var seenWebViewIDs = Set<ObjectIdentifier>()
        let outgoingHosts = hostLifecycleOwner.displayedHosts(excluding: incomingTabIDs)
        guard !outgoingHosts.isEmpty else { return false }

        releaseVisualHandoffCovers()

        for host in outgoingHosts {
            let webViewID = ObjectIdentifier(host.webView)
            guard seenWebViewIDs.insert(webViewID).inserted else { continue }

            let frameInContainer = host.convert(host.bounds, to: containerView)
            webViewCoordinator.beginVisualHandoffProtection(for: host.webView)
            hostLifecycleOwner.prepareForVisualHandoff(host)
            visualHandoffCovers.placeCover(host, frameInContainer: frameInContainer)
        }

        return visualHandoffCovers.hasCovers
    }

    private func scheduleVisualHandoffCoverRelease(if didBeginVisualHandoff: Bool) {
        guard didBeginVisualHandoff else { return }
        scheduleVisualHandoffCoverRelease()
    }

    private func scheduleVisualHandoffCoverRelease() {
        visualHandoffCovers.scheduleRelease()
    }

    private func releaseVisualHandoffCovers() {
        visualHandoffCovers.releaseCovers()
    }

    private func showSinglePane(tab: Tab?) {
        containerView.setPaneLayout(.single)
        containerView.layoutSubtreeIfNeeded()
        containerView.singlePaneView.isHidden = false

        if let tab, let host = webViewHost(for: tab, slot: .single) {
            hostLifecycleOwner.attach(host, to: containerView.singlePaneView)
            containerView.singlePaneView.removeHostedSubviews(
                keeping: host,
                shouldRemove: hostLifecycleOwner.shouldRemoveHostedSubview
            )
        } else {
            hostLifecycleOwner.clearSinglePane()
        }

        hostLifecycleOwner.clearAllSplitPaneHosts()
    }

    private func showSplitGroup(_ group: SplitGroup, tabs: [Tab]) {
        containerView.setPaneLayout(.split(group))
        containerView.layoutSubtreeIfNeeded()

        let visibleIds = Set(group.tabIds)
        for tabId in hostLifecycleOwner.splitPaneTabIds where visibleIds.contains(tabId) == false {
            hostLifecycleOwner.clearSplitPaneHost(tabId)
        }

        for tab in tabs {
            guard let paneView = containerView.paneView(for: tab.id) else {
                hostLifecycleOwner.clearSplitPaneHost(tab.id)
                continue
            }
            if let host = webViewHost(for: tab, slot: .split(tab.id)) {
                paneView.configureSplitControls(
                    tab: tab,
                    browserContext: browserContext,
                    windowState: windowState
                )
                hostLifecycleOwner.attach(host, to: paneView)
                paneView.removeHostedSubviews(
                    keeping: host,
                    shouldRemove: hostLifecycleOwner.shouldRemoveHostedSubview
                )
            } else {
                paneView.clearSplitControls()
                hostLifecycleOwner.clearSplitPaneHost(tab.id)
            }
        }

        hostLifecycleOwner.clearSinglePane()
    }

    private func restoreFocusIfNeeded(for tabId: UUID?) {
        guard webViewCoordinator.hasActiveHistorySwipe(in: windowState.id) == false else { return }
        guard let tabId,
              let window = view.window,
              let host = hostLifecycleOwner.displayedHost(for: tabId),
              host.window === window
        else {
            return
        }
        guard !host.webView.sumiIsInFullscreenElementPresentation else { return }
        guard window.firstResponder !== host.webView else { return }
        window.makeFirstResponder(host.webView)
    }

    private func recoverMediaTouchBarAfterWebKitReparent(tabID: UUID?, webView: WKWebView) {
        guard webViewCoordinator.hasActiveHistorySwipe(in: windowState.id) == false,
              !webView.sumiIsInFullscreenElementPresentation,
              let window = view.window,
              window.isKeyWindow
        else {
            return
        }

        let currentTab = browserContext.currentTab(for: windowState)
        guard let currentTab,
              tabID == nil || currentTab.id == tabID
        else {
            return
        }

        if hostLifecycleOwner.displayedHost(for: currentTab.id) == nil,
           let displayState = pendingDisplayState ?? appliedDisplayState {
            apply(displayState: displayState, currentTab: currentTab)
            appliedDisplayState = displayState
        }

        guard let host = hostLifecycleOwner.displayedHost(for: currentTab.id),
              host.webView === webView
        else {
            return
        }

        host.attachDisplayedContentIfNeeded()
        host.layoutSubtreeIfNeeded()

        guard host.window === window,
              webView.window === window,
              webView.superview != nil
        else {
            return
        }

        resetWebKitMediaTouchBar(for: webView, in: window)
    }

    private func resetWebKitMediaTouchBar(for webView: WKWebView, in window: NSWindow) {
        let wasFirstResponder = window.firstResponder === webView
        webView.touchBar = nil
        if wasFirstResponder {
            window.makeFirstResponder(nil)
        }
        window.makeFirstResponder(webView)
        webView.touchBar = nil
    }

    private func setupHoverCallbacks(for tab: Tab) {
        tab.onLinkHover = { [weak self] href in
            DispatchQueue.main.async {
                self?.hoveredLinkHandler?(href)
            }
        }
    }

    private func webViewHost(for tab: Tab, slot: WindowWebContentPaneSlot) -> SumiWebViewContainerView? {
        guard tab.requiresPrimaryWebView else {
            hostLifecycleOwner.clearPaneHost(slot)
            return nil
        }
        let webView = webViewCoordinator.getWebView(for: tab.id, in: windowState.id)
            ?? webViewCoordinator.getOrCreateWebView(for: tab, in: windowState.id)
        guard let webView else {
            hostLifecycleOwner.clearPaneHost(slot)
            return nil
        }

        if let host = hostLifecycleOwner.host(for: slot),
           host.tabID == tab.id,
           host.webView === webView {
            return host
        }

        if let promotedHost = webViewCoordinator.takePromotedHost(
            for: tab.id,
            in: windowState.id,
            expectedWebView: webView
        ) {
            hostLifecycleOwner.replaceHost(promotedHost, in: slot)
            return promotedHost
        }

        if let displayedHost = hostLifecycleOwner.displayedHost(for: tab.id),
           displayedHost.webView === webView {
            hostLifecycleOwner.moveDisplayedHost(displayedHost, to: slot)
            return displayedHost
        }

        if webViewCoordinator.isWebViewProtectedFromCompositorMutation(webView),
           let existingHost = hostLifecycleOwner.protectedHost(for: webView) {
            hostLifecycleOwner.moveDisplayedHost(existingHost, to: slot)
            return existingHost
        }

        let host = SumiWebViewContainerView(tab: tab, webView: webView)
        hostLifecycleOwner.replaceHost(host, in: slot)
        return host
    }

    private func scheduleSplitRepair(groupId: UUID) {
        guard pendingSplitRepairGroupId != groupId else { return }
        pendingSplitRepairGroupId = groupId

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.browserContext.removeSplitGroup(id: groupId)
            self.pendingSplitRepairGroupId = nil
        }
    }
}

@MainActor
private final class WindowWebContentHostLifecycleOwner {
    private let containerView: WindowWebContentSplitHostLayoutView
    private let webViewCoordinator: WebViewCoordinator
    private let windowID: UUID
    private let hostRegistry = WindowWebContentHostRegistry()
    private var chromeGeometry: BrowserChromeGeometry
    private var contentBackgroundColor: Color

    var splitPaneTabIds: [UUID] {
        hostRegistry.splitPaneTabIds
    }

    init(
        containerView: WindowWebContentSplitHostLayoutView,
        webViewCoordinator: WebViewCoordinator,
        windowID: UUID,
        chromeGeometry: BrowserChromeGeometry,
        contentBackgroundColor: Color
    ) {
        self.containerView = containerView
        self.webViewCoordinator = webViewCoordinator
        self.windowID = windowID
        self.chromeGeometry = chromeGeometry
        self.contentBackgroundColor = contentBackgroundColor
    }

    func host(for slot: WindowWebContentPaneSlot) -> SumiWebViewContainerView? {
        hostRegistry.host(for: slot)
    }

    func displayedHost(for tabId: UUID) -> SumiWebViewContainerView? {
        hostRegistry.displayedHost(for: tabId)
    }

    func displayedHosts(excluding incomingTabIDs: Set<UUID>) -> [SumiWebViewContainerView] {
        hostRegistry.displayedHosts(excluding: incomingTabIDs)
    }

    func protectedHost(for webView: WKWebView) -> SumiWebViewContainerView? {
        hostRegistry.protectedHost(for: webView)
    }

    func replaceHost(_ host: SumiWebViewContainerView, in slot: WindowWebContentPaneSlot) {
        clearPaneHost(slot)
        configureViewportStyle(on: host)
        hostRegistry.setHost(host, for: slot)
    }

    func moveDisplayedHost(_ host: SumiWebViewContainerView, to slot: WindowWebContentPaneSlot) {
        clearPaneHost(slot)
        configureViewportStyle(on: host)
        hostRegistry.clearReferences(to: host)
        hostRegistry.setHost(host, for: slot)
    }

    func attach(_ host: SumiWebViewContainerView, to paneView: PaneContainerView) {
        let isProtected = webViewCoordinator.isWebViewProtectedFromCompositorMutation(host.webView)
        performWithoutImplicitAnimations {
            hostRegistry.removeParkedProtectedHost(for: host.webView)
            if host.superview != nil && host.superview !== paneView {
                host.prepareForSuperviewTransferPreservingDisplayedContent()
                host.removeFromSuperview()
            }
            if host.superview == nil || host.superview === paneView {
                paneView.placeContentHostAboveChromeShadow(host)
            }
            host.frame = paneView.bounds
            host.autoresizingMask = [.width, .height]
            configureViewportStyle(on: host)

            // Temporary drawsBackground = false transition gate to guarantee zero white flashes
            host.webView.setValue(false, forKey: "drawsBackground")

            host.attachDisplayedContentIfNeeded()
            host.isHidden = false
            paneView.layoutSubtreeIfNeeded()
            host.layoutSubtreeIfNeeded()
        }

        let webView = host.webView
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak webView] in
            webView?.setValue(true, forKey: "drawsBackground")
        }

        if isProtected {
            hostRegistry.parkProtectedHost(host)
        }
        webViewCoordinator.completePromotedHostAttachment(for: host.tabID, in: windowID)
    }

    func clearPaneHost(_ slot: WindowWebContentPaneSlot) {
        switch slot {
        case .single:
            clearSinglePane()
        case .split(let tabId):
            clearSplitPaneHost(tabId)
        }
    }

    func clearSinglePane() {
        if let host = hostRegistry.removeSinglePaneHost() {
            removeHostFromDisplay(host)
        }
        containerView.singlePaneView.removeHostedSubviews(
            keeping: nil,
            shouldRemove: shouldRemoveHostedSubview
        )
    }

    func clearSplitPaneHost(_ tabId: UUID) {
        if let host = hostRegistry.removeSplitPaneHost(for: tabId) {
            removeHostFromDisplay(host)
        }
        if let paneView = containerView.paneView(for: tabId) {
            paneView.clearSplitControls()
            paneView.removeHostedSubviews(
                keeping: nil,
                shouldRemove: shouldRemoveHostedSubview
            )
        }
    }

    func clearAllSplitPaneHosts() {
        for tabId in hostRegistry.splitPaneTabIds {
            clearSplitPaneHost(tabId)
        }
        containerView.clearSplitTree()
    }

    func prepareForVisualHandoff(_ host: SumiWebViewContainerView) {
        hostRegistry.clearReferences(to: host)
        hostRegistry.parkProtectedHost(host)
    }

    func removeParkedProtectedHost(for webViewID: ObjectIdentifier) {
        hostRegistry.removeParkedProtectedHost(for: webViewID)
    }

    func shouldRemoveHostedSubview(_ subview: NSView) -> Bool {
        guard let host = subview as? SumiWebViewContainerView else {
            return true
        }
        if webViewCoordinator.isWebViewProtectedFromCompositorMutation(host.webView) {
            parkProtectedHost(host)
            return false
        }
        hostRegistry.removeParkedProtectedHost(for: host.webView)
        return true
    }

    func missingPreparedWebViews(
        for visibleTabIds: Set<UUID>,
        browserContext: any WindowWebContentBrowserContext
    ) -> Bool {
        visibleTabIds.contains { tabId in
            if let tab = browserContext.tab(for: tabId),
               tab.requiresPrimaryWebView == false {
                return false
            }
            return webViewCoordinator.getWebView(for: tabId, in: windowID) == nil
        }
    }

    func updateViewportStyle(
        chromeGeometry: BrowserChromeGeometry,
        contentBackgroundColor: Color
    ) {
        self.chromeGeometry = chromeGeometry
        self.contentBackgroundColor = contentBackgroundColor
        for host in hostRegistry.displayedHosts {
            configureViewportStyle(on: host)
        }
    }

    private func removeHostFromDisplay(_ host: SumiWebViewContainerView) {
        if webViewCoordinator.isWebViewProtectedFromCompositorMutation(host.webView) {
            parkProtectedHost(host)
        } else {
            hostRegistry.removeParkedProtectedHost(for: host.webView)
            host.removeFromSuperview()
        }
    }

    private func parkProtectedHost(_ host: SumiWebViewContainerView) {
        hostRegistry.parkProtectedHost(host)
        host.isHidden = true
    }

    private func configureViewportStyle(on host: SumiWebViewContainerView) {
        host.setBrowserContentViewport(geometry: chromeGeometry)
        let nsColor = NSColor(contentBackgroundColor)
        host.webView.underPageBackgroundColor = nsColor
        host.webView.layer?.backgroundColor = nsColor.cgColor
        host.layer?.backgroundColor = nsColor.cgColor
    }

    private func performWithoutImplicitAnimations(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            updates()
        }
        CATransaction.commit()
    }
}

struct TabCompositorWrapper: NSViewControllerRepresentable {
    private let makeBrowserContext: () -> any WindowWebContentBrowserContext
    private let currentTabForDisplayState: (BrowserWindowState) -> Tab?
    let webViewCoordinator: WebViewCoordinator
    @Binding var hoveredLink: String?
    var splitGroup: SplitGroup?
    var isSplitDropCaptureActive: Bool
    var chromeGeometry: BrowserChromeGeometry
    let windowState: BrowserWindowState
    var contentBackgroundColor: Color

    init(
        browserManager: BrowserManager,
        sidebarDragState: SidebarDragState,
        webViewCoordinator: WebViewCoordinator,
        hoveredLink: Binding<String?>,
        splitGroup: SplitGroup?,
        isSplitDropCaptureActive: Bool,
        chromeGeometry: BrowserChromeGeometry,
        windowState: BrowserWindowState,
        contentBackgroundColor: Color
    ) {
        self.makeBrowserContext = {
            BrowserManagerWindowWebContentContext(
                browserManager: browserManager,
                sidebarDragState: sidebarDragState
            )
        }
        self.currentTabForDisplayState = { windowState in
            browserManager.currentTab(for: windowState)
        }
        self.webViewCoordinator = webViewCoordinator
        self._hoveredLink = hoveredLink
        self.splitGroup = splitGroup
        self.isSplitDropCaptureActive = isSplitDropCaptureActive
        self.chromeGeometry = chromeGeometry
        self.windowState = windowState
        self.contentBackgroundColor = contentBackgroundColor
    }

    init(
        browserContext: any WindowWebContentBrowserContext,
        webViewCoordinator: WebViewCoordinator,
        hoveredLink: Binding<String?>,
        splitGroup: SplitGroup?,
        isSplitDropCaptureActive: Bool,
        chromeGeometry: BrowserChromeGeometry,
        windowState: BrowserWindowState,
        contentBackgroundColor: Color
    ) {
        self.makeBrowserContext = { browserContext }
        self.currentTabForDisplayState = { windowState in
            browserContext.currentTab(for: windowState)
        }
        self.webViewCoordinator = webViewCoordinator
        self._hoveredLink = hoveredLink
        self.splitGroup = splitGroup
        self.isSplitDropCaptureActive = isSplitDropCaptureActive
        self.chromeGeometry = chromeGeometry
        self.windowState = windowState
        self.contentBackgroundColor = contentBackgroundColor
    }

    final class Coordinator {
        var hoveredLink: Binding<String?>

        private var pendingHoveredLink: String?
        private var hasPendingHoveredLink = false
        private var isHoveredLinkUpdateScheduled = false

        init(hoveredLink: Binding<String?>) {
            self.hoveredLink = hoveredLink
        }

        @MainActor
        func setHoveredLink(_ link: String?) {
            guard hoveredLink.wrappedValue != link || hasPendingHoveredLink else { return }

            pendingHoveredLink = link
            hasPendingHoveredLink = true

            guard !isHoveredLinkUpdateScheduled else { return }
            isHoveredLinkUpdateScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.flushPendingHoveredLink()
            }
        }

        @MainActor
        private func flushPendingHoveredLink() {
            isHoveredLinkUpdateScheduled = false
            guard hasPendingHoveredLink else { return }

            let link = pendingHoveredLink
            pendingHoveredLink = nil
            hasPendingHoveredLink = false

            guard hoveredLink.wrappedValue != link else { return }
            hoveredLink.wrappedValue = link
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(hoveredLink: $hoveredLink)
    }

    func makeNSViewController(context: Context) -> WindowWebContentController {
        WindowWebContentController(
            browserContext: makeBrowserContext(),
            webViewCoordinator: webViewCoordinator,
            chromeGeometry: chromeGeometry,
            windowState: windowState
        )
    }

    func updateNSViewController(_ controller: WindowWebContentController, context: Context) {
        context.coordinator.hoveredLink = $hoveredLink
        controller.update(
            displayState: makeDisplayState(),
            hoveredLinkHandler: { context.coordinator.setHoveredLink($0) },
            chromeGeometry: chromeGeometry,
            contentBackgroundColor: contentBackgroundColor
        )
    }

    static func dismantleNSViewController(_ controller: WindowWebContentController, coordinator: ()) {
        controller.tearDownController()
    }

    private func visibleTabIds(currentId: UUID?) -> Set<UUID> {
        Set(VisibleTabPreparationPlan.visibleTabIDs(
            currentTabId: currentId,
            splitTabIds: splitGroup?.tabIds ?? []
        ))
    }

    private func makeDisplayState() -> WebsiteDisplayState {
        let currentTab = currentTabForDisplayState(windowState)
        let currentId = currentTab?.id
        return WebsiteDisplayState(
            splitGroup: splitGroup,
            currentId: currentId,
            compositorVersion: windowState.compositorVersion,
            currentTabUnloaded: currentTab?.isUnloaded ?? true,
            visibleTabIds: visibleTabIds(currentId: currentId),
            isSplitDropCaptureActive: isSplitDropCaptureActive
        )
    }
}
