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
final class WindowWebContentController: NSViewController {
    private let browserManager: BrowserManager
    private let webViewCoordinator: WebViewCoordinator
    private let windowState: BrowserWindowState
    private var chromeGeometry: BrowserChromeGeometry
    private lazy var containerView = ContainerView(
        browserManager: browserManager,
        splitManager: browserManager.splitManager,
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
    private let hostRegistry = WindowWebContentHostRegistry()
    private lazy var visualHandoffCovers = VisualHandoffCoverController(
        containerView: containerView,
        releaseCover: { [weak self] webViewID, host in
            guard let self else { return }
            self.containerView.removeVisualHandoffCover(host)
            self.hostRegistry.removeParkedProtectedHost(for: webViewID)
            self.webViewCoordinator.finishVisualHandoffProtection(for: host.webView)
        }
    )
    private lazy var mediaTouchBarRecoveryController = WindowMediaTouchBarRecoveryController(
        windowID: windowState.id,
        recover: { [weak self] tabID, webView in
            self?.recoverMediaTouchBarAfterWebKitReparent(tabID: tabID, webView: webView)
        }
    )

    init(
        browserManager: BrowserManager,
        webViewCoordinator: WebViewCoordinator,
        chromeGeometry: BrowserChromeGeometry,
        windowState: BrowserWindowState
    ) {
        self.browserManager = browserManager
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
            self.browserManager.schedulePrepareVisibleWebViews(for: self.windowState)
        }
    }

    func tearDownController() {
        if webViewCoordinator.hasActiveFullscreen(in: windowState.id) {
            webViewCoordinator.closeActiveFullscreenMedia(in: windowState.id)
        }
        releaseVisualHandoffCovers()
        clearSinglePane()
        clearAllSplitPaneHosts()
        mediaTouchBarRecoveryController.stop()
        webViewCoordinator.setImmediateVisualHandoffHandler(nil, for: windowState.id)
        webViewCoordinator.removeCompositorContainerView(for: windowState.id)
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        if webViewCoordinator.hasActiveHistorySwipe(in: windowState.id) {
            browserManager.enqueueWindowMutationDuringHistorySwipe(
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
        let currentTab = browserManager.currentTab(for: windowState)
        let displayStateChanged = appliedDisplayState != displayState
        let hasStaleSubviews = compositorSubtreeHasStaleWebViews(
            currentTab: currentTab,
            displayState: displayState
        )
        let needsDisplayStateApply = displayStateChanged || hasStaleSubviews

        let previousBg = self.contentBackgroundColor
        self.contentBackgroundColor = contentBackgroundColor
        let bgChanged = previousBg != contentBackgroundColor

        if self.chromeGeometry != chromeGeometry || bgChanged {
            self.chromeGeometry = chromeGeometry
            containerView.setChromeGeometry(chromeGeometry)
            updateDisplayedHostViewportStyles()
        }

        pendingDisplayState = displayState
        self.hoveredLinkHandler = hoveredLinkHandler

        if displayState.currentId == nil {
            hoveredLinkHandler(nil)
            lastHoverTabId = nil
        }

        if !displayState.visibleTabIds.isEmpty && missingPreparedWebViews(for: displayState.visibleTabIds) {
            browserManager.schedulePrepareVisibleWebViews(for: windowState)
        }

        if lastHoverTabId != displayState.currentId,
           let currentTab
        {
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
            browserManager.enqueueWindowMutationDuringHistorySwipe(
                .refreshCompositor,
                for: windowState
            )
            return
        }

        let currentTab = browserManager.currentTab(for: windowState)
        let hasStaleSubviews = compositorSubtreeHasStaleWebViews(
            currentTab: currentTab,
            displayState: displayState
        )
        guard appliedDisplayState != displayState || hasStaleSubviews else { return }

        let previousCurrentId = appliedDisplayState?.currentId
        apply(displayState: displayState, currentTab: currentTab)
        appliedDisplayState = displayState

        if previousCurrentId != displayState.currentId {
            restoreFocusIfNeeded(for: displayState.currentId)
        }
    }

    private func apply(displayState: WebsiteDisplayState, currentTab: Tab?) {
        let splitManager = browserManager.splitManager
        containerView.setSplitDropCaptureActive(
            displayState.isSplitDropCaptureActive,
            browserManager: browserManager,
            splitManager: splitManager,
            windowId: windowState.id
        )

        if let group = displayState.splitGroup,
           let currentId = displayState.currentId,
           group.contains(currentId)
        {
            let tabs = group.tabIds.compactMap { browserManager.tabManager.tab(for: $0) }
            guard tabs.count == group.tabIds.count else {
                let didBeginVisualHandoff = beginSinglePaneVisualHandoffIfNeeded(to: currentTab)
                scheduleSplitRepair(groupId: group.id)
                showSinglePane(tab: currentTab)
                scheduleVisualHandoffCoverRelease(if: didBeginVisualHandoff)
                return
            }
            let didBeginVisualHandoff = beginVisualHandoffCovers(excluding: Set(group.tabIds))
            showSplitGroup(group, tabs: tabs)
            scheduleVisualHandoffCoverRelease(if: didBeginVisualHandoff)
            return
        }

        let didBeginVisualHandoff = beginSinglePaneVisualHandoffIfNeeded(to: currentTab)
        showSinglePane(tab: currentTab)
        scheduleVisualHandoffCoverRelease(if: didBeginVisualHandoff)
    }

    private func performImmediateVisualHandoffIfPossible() -> Bool {
        guard !webViewCoordinator.hasActiveHistorySwipe(in: windowState.id),
              let currentTab = browserManager.currentTab(for: windowState),
              currentTab.requiresPrimaryWebView
        else {
            return false
        }

        if let group = browserManager.splitManager.splitGroup(for: windowState.id),
           group.contains(currentTab.id)
        {
            let tabs = group.tabIds.compactMap { browserManager.tabManager.tab(for: $0) }
            guard tabs.count == group.tabIds.count else { return false }
            let didBeginVisualHandoff = beginVisualHandoffCovers(excluding: Set(group.tabIds))
            showSplitGroup(group, tabs: tabs)
            scheduleVisualHandoffCoverRelease(if: didBeginVisualHandoff)
        } else {
            let didBeginVisualHandoff = beginSinglePaneVisualHandoffIfNeeded(to: currentTab)
            showSinglePane(tab: currentTab)
            scheduleVisualHandoffCoverRelease(if: didBeginVisualHandoff)
        }

        return displayedHost(for: currentTab.id) != nil
    }

    private func beginSinglePaneVisualHandoffIfNeeded(to tab: Tab?) -> Bool {
        guard let tab, tab.requiresPrimaryWebView else { return false }
        guard displayedHost(for: tab.id) == nil else { return false }
        return beginVisualHandoffCovers(excluding: [tab.id])
    }

    @discardableResult
    private func beginVisualHandoffCovers(excluding incomingTabIDs: Set<UUID>) -> Bool {
        var seenWebViewIDs = Set<ObjectIdentifier>()
        let outgoingHosts = hostRegistry.displayedHosts(excluding: incomingTabIDs)
        guard !outgoingHosts.isEmpty else { return false }

        releaseVisualHandoffCovers()

        for host in outgoingHosts {
            let webViewID = ObjectIdentifier(host.webView)
            guard seenWebViewIDs.insert(webViewID).inserted else { continue }

            let frameInContainer = host.convert(host.bounds, to: containerView)
            webViewCoordinator.beginVisualHandoffProtection(for: host.webView)
            hostRegistry.clearReferences(to: host)
            hostRegistry.parkProtectedHost(host)
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

    private func compositorSubtreeHasStaleWebViews(
        currentTab: Tab?,
        displayState: WebsiteDisplayState
    ) -> Bool {
        guard !webViewCoordinator.hasActiveHistorySwipe(in: windowState.id) else {
            return false
        }

        let shouldShowSplit = displayState.currentId.map {
            displayState.splitGroup?.contains($0) == true
        } ?? false

        if shouldShowSplit == false {
            let expected = (currentTab != nil && displayState.currentTabUnloaded == false) ? 1 : 0
            if hostedWebViewCount(in: containerView.singlePaneView, stoppingAfter: expected) > expected { return true }
            if containerView.hasHostedSplitWebViews { return true }
            return false
        }

        if hostedWebViewCount(in: containerView.singlePaneView, stoppingAfter: 0) > 0 { return true }
        guard let group = displayState.splitGroup else { return false }
        for tabId in hostRegistry.splitPaneTabIds where group.contains(tabId) == false {
            return true
        }
        return false
    }

    private func showSinglePane(tab: Tab?) {
        containerView.setPaneLayout(.single)
        containerView.layoutSubtreeIfNeeded()
        containerView.singlePaneView.isHidden = false

        if let tab, let host = webViewHost(for: tab, slot: .single) {
            attach(host, to: containerView.singlePaneView)
            containerView.singlePaneView.removeHostedSubviews(
                keeping: host,
                shouldRemove: shouldRemoveHostedSubview
            )
        } else {
            clearSinglePane()
        }

        clearAllSplitPaneHosts()
    }

    private func showSplitGroup(_ group: SplitGroup, tabs: [Tab]) {
        containerView.setPaneLayout(.split(group))
        containerView.layoutSubtreeIfNeeded()

        let visibleIds = Set(group.tabIds)
        for tabId in hostRegistry.splitPaneTabIds where visibleIds.contains(tabId) == false {
            clearSplitPaneHost(tabId)
        }

        for tab in tabs {
            guard let paneView = containerView.paneView(for: tab.id) else {
                clearSplitPaneHost(tab.id)
                continue
            }
            if let host = webViewHost(for: tab, slot: .split(tab.id)) {
                paneView.configureSplitControls(
                    tab: tab,
                    browserManager: browserManager,
                    splitManager: browserManager.splitManager,
                    windowState: windowState
                )
                attach(host, to: paneView)
                paneView.removeHostedSubviews(
                    keeping: host,
                    shouldRemove: shouldRemoveHostedSubview
                )
            } else {
                paneView.clearSplitControls()
                clearSplitPaneHost(tab.id)
            }
        }

        clearSinglePane()
    }

    private func restoreFocusIfNeeded(for tabId: UUID?) {
        guard webViewCoordinator.hasActiveHistorySwipe(in: windowState.id) == false else { return }
        guard let tabId,
              let window = view.window,
              let host = displayedHost(for: tabId),
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

        let currentTab = browserManager.currentTab(for: windowState)
        guard let currentTab,
              tabID == nil || currentTab.id == tabID
        else {
            return
        }

        if displayedHost(for: currentTab.id) == nil,
           let displayState = pendingDisplayState ?? appliedDisplayState {
            apply(displayState: displayState, currentTab: currentTab)
            appliedDisplayState = displayState
        }

        guard let host = displayedHost(for: currentTab.id),
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
            clearPaneHost(slot)
            return nil
        }
        let webView = webViewCoordinator.getWebView(for: tab.id, in: windowState.id)
            ?? webViewCoordinator.getOrCreateWebView(for: tab, in: windowState.id)
        guard let webView else {
            clearPaneHost(slot)
            return nil
        }

        if let host = hostRegistry.host(for: slot),
           host.tabID == tab.id,
           host.webView === webView {
            return host
        }

        if let promotedHost = webViewCoordinator.takePromotedHost(
            for: tab.id,
            in: windowState.id,
            expectedWebView: webView
        ) {
            clearPaneHost(slot)
            configureViewportStyle(on: promotedHost)
            hostRegistry.setHost(promotedHost, for: slot)
            return promotedHost
        }

        if let displayedHost = hostRegistry.displayedHost(for: tab.id),
           displayedHost.webView === webView {
            clearPaneHost(slot)
            configureViewportStyle(on: displayedHost)
            hostRegistry.clearReferences(to: displayedHost)
            hostRegistry.setHost(displayedHost, for: slot)
            return displayedHost
        }

        if webViewCoordinator.isWebViewProtectedFromCompositorMutation(webView),
           let existingHost = hostRegistry.protectedHost(for: webView) {
            clearPaneHost(slot)
            configureViewportStyle(on: existingHost)
            hostRegistry.clearReferences(to: existingHost)
            hostRegistry.setHost(existingHost, for: slot)
            return existingHost
        }

        clearPaneHost(slot)
        let host = SumiWebViewContainerView(tab: tab, webView: webView)
        configureViewportStyle(on: host)
        hostRegistry.setHost(host, for: slot)
        return host
    }

    private func attach(_ host: SumiWebViewContainerView, to paneView: PaneContainerView) {
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
        webViewCoordinator.completePromotedHostAttachment(for: host.tabID, in: windowState.id)
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

    private func clearPaneHost(_ slot: WindowWebContentPaneSlot) {
        switch slot {
        case .single:
            clearSinglePane()
        case .split(let tabId):
            clearSplitPaneHost(tabId)
        }
    }

    private func clearSinglePane() {
        if let host = hostRegistry.removeSinglePaneHost() {
            removeHostFromDisplay(host)
        }
        containerView.singlePaneView.removeHostedSubviews(
            keeping: nil,
            shouldRemove: shouldRemoveHostedSubview
        )
    }

    private func clearSplitPaneHost(_ tabId: UUID) {
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

    private func clearAllSplitPaneHosts() {
        for tabId in hostRegistry.splitPaneTabIds {
            clearSplitPaneHost(tabId)
        }
        containerView.clearSplitTree()
    }

    private func removeHostFromDisplay(_ host: SumiWebViewContainerView) {
        if webViewCoordinator.isWebViewProtectedFromCompositorMutation(host.webView) {
            parkProtectedHost(host)
        } else {
            hostRegistry.removeParkedProtectedHost(for: host.webView)
            host.removeFromSuperview()
        }
    }

    private func shouldRemoveHostedSubview(_ subview: NSView) -> Bool {
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

    private func parkProtectedHost(_ host: SumiWebViewContainerView) {
        hostRegistry.parkProtectedHost(host)
        host.isHidden = true
    }

    private func displayedHost(for tabId: UUID) -> SumiWebViewContainerView? {
        hostRegistry.displayedHost(for: tabId)
    }

    private func missingPreparedWebViews(for visibleTabIds: Set<UUID>) -> Bool {
        visibleTabIds.contains { tabId in
            if let tab = browserManager.tabManager.tab(for: tabId),
               tab.requiresPrimaryWebView == false {
                return false
            }
            return webViewCoordinator.getWebView(for: tabId, in: windowState.id) == nil
        }
    }

    private func updateDisplayedHostViewportStyles() {
        for host in hostRegistry.displayedHosts {
            configureViewportStyle(on: host)
        }
    }

    private func configureViewportStyle(on host: SumiWebViewContainerView) {
        host.setBrowserContentViewport(geometry: chromeGeometry)
        let nsColor = NSColor(contentBackgroundColor)
        host.webView.underPageBackgroundColor = nsColor
        host.webView.layer?.backgroundColor = nsColor.cgColor
        host.layer?.backgroundColor = nsColor.cgColor
    }

    private func scheduleSplitRepair(groupId: UUID) {
        guard pendingSplitRepairGroupId != groupId else { return }
        pendingSplitRepairGroupId = groupId

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.browserManager.tabManager.removeSplitGroup(id: groupId)
            self.pendingSplitRepairGroupId = nil
        }
    }
}

@MainActor
private final class VisualHandoffCoverController {
    private static let releaseDelay: TimeInterval = 0.1

    private let containerView: ContainerView
    private let releaseCover: (ObjectIdentifier, SumiWebViewContainerView) -> Void
    private var coverHosts: [ObjectIdentifier: SumiWebViewContainerView] = [:]
    private var releaseWorkItem: DispatchWorkItem?
    private var releaseGeneration = 0

    var hasCovers: Bool {
        !coverHosts.isEmpty
    }

    init(
        containerView: ContainerView,
        releaseCover: @escaping (ObjectIdentifier, SumiWebViewContainerView) -> Void
    ) {
        self.containerView = containerView
        self.releaseCover = releaseCover
    }

    func placeCover(
        _ host: SumiWebViewContainerView,
        frameInContainer: NSRect
    ) {
        containerView.placeVisualHandoffCover(host, frameInContainer: frameInContainer)
        coverHosts[ObjectIdentifier(host.webView)] = host
    }

    func scheduleRelease() {
        guard !coverHosts.isEmpty else { return }

        releaseWorkItem?.cancel()
        releaseGeneration &+= 1
        let generation = releaseGeneration
        CATransaction.flush()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.releaseGeneration == generation
            else {
                return
            }
            self.containerView.layoutSubtreeIfNeeded()
            self.containerView.displayIfNeeded()
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.releaseGeneration == generation
                else {
                    return
                }
                self.releaseCovers()
            }
        }
        releaseWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.releaseDelay,
            execute: workItem
        )
    }

    func releaseCovers() {
        releaseGeneration &+= 1
        releaseWorkItem?.cancel()
        releaseWorkItem = nil

        let covers = coverHosts
        coverHosts.removeAll(keepingCapacity: true)
        for (webViewID, host) in covers {
            releaseCover(webViewID, host)
        }
    }
}

struct TabCompositorWrapper: NSViewControllerRepresentable {
    let browserManager: BrowserManager
    let webViewCoordinator: WebViewCoordinator
    @Binding var hoveredLink: String?
    var splitGroup: SplitGroup?
    var isSplitDropCaptureActive: Bool
    var chromeGeometry: BrowserChromeGeometry
    let windowState: BrowserWindowState
    var contentBackgroundColor: Color

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
            browserManager: browserManager,
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
        let currentTab = browserManager.currentTab(for: windowState)
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

// MARK: - Container View

private final class ContainerView: NSView {
    enum PaneLayout: Equatable {
        case single
        case split(SplitGroup)
    }

    let singlePaneView = PaneContainerView()
    private let splitRootView = SplitRootView()
    private let visualHandoffOverlayView = VisualHandoffOverlayView()
    private let splitDropCaptureView = SplitDropCaptureView(frame: .zero)
    private var paneLayout: PaneLayout = .single
    private var chromeGeometry: BrowserChromeGeometry
    private weak var splitManager: SplitViewManager?
    private var windowId: UUID

    var hasHostedSplitWebViews: Bool {
        splitRootView.hasHostedWebViews
    }

    init(
        browserManager: BrowserManager,
        splitManager: SplitViewManager,
        windowId: UUID,
        chromeGeometry: BrowserChromeGeometry
    ) {
        self.chromeGeometry = chromeGeometry
        self.splitManager = splitManager
        self.windowId = windowId
        super.init(frame: .zero)

        singlePaneView.identifier = CompositorPaneDestination.single.viewIdentifier
        singlePaneView.setChromeGeometry(chromeGeometry)
        splitRootView.setChromeGeometry(chromeGeometry)

        addSubview(singlePaneView)
        addSubview(splitRootView)
        visualHandoffOverlayView.isHidden = true
        addSubview(visualHandoffOverlayView)

        setSplitDropCaptureActive(
            false,
            browserManager: browserManager,
            splitManager: splitManager,
            windowId: windowId
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        applyPaneLayout()
        visualHandoffOverlayView.frame = bounds
        if splitDropCaptureView.superview === self {
            splitDropCaptureView.frame = bounds
        }
    }

    func setPaneLayout(_ layout: PaneLayout) {
        guard paneLayout != layout else { return }
        paneLayout = layout
        needsLayout = true
    }

    func setChromeGeometry(_ geometry: BrowserChromeGeometry) {
        guard chromeGeometry != geometry else { return }
        chromeGeometry = geometry
        singlePaneView.setChromeGeometry(geometry)
        splitRootView.setChromeGeometry(geometry)
        needsLayout = true
    }

    func setSplitDropCaptureActive(
        _ isActive: Bool,
        browserManager: BrowserManager,
        splitManager: SplitViewManager,
        windowId: UUID
    ) {
        self.splitManager = splitManager
        self.windowId = windowId
        splitDropCaptureView.browserManager = browserManager
        splitDropCaptureView.splitManager = splitManager
        splitDropCaptureView.windowId = windowId

        if isActive {
            if splitDropCaptureView.superview !== self {
                addSubview(splitDropCaptureView, positioned: .above, relativeTo: nil)
            }
            splitDropCaptureView.frame = bounds
        } else if splitDropCaptureView.superview === self {
            splitDropCaptureView.cancelActiveDragPreview()
            splitDropCaptureView.removeFromSuperview()
        }
    }

    func paneView(for tabId: UUID) -> PaneContainerView? {
        splitRootView.paneView(for: tabId)
    }

    func clearSplitTree() {
        splitRootView.clear()
    }

    func placeVisualHandoffCover(
        _ host: SumiWebViewContainerView,
        frameInContainer: NSRect
    ) {
        host.prepareForSuperviewTransferPreservingDisplayedContent()
        visualHandoffOverlayView.addSubview(host)
        host.frame = frameInContainer
        host.autoresizingMask = []
        host.isHidden = false
        visualHandoffOverlayView.isHidden = false
    }

    func removeVisualHandoffCover(_ host: SumiWebViewContainerView) {
        host.removeFromSuperview()
        visualHandoffOverlayView.isHidden = visualHandoffOverlayView.subviews.isEmpty
    }

    override var acceptsFirstResponder: Bool { false }

    override func resetCursorRects() {}

    private func applyPaneLayout() {
        switch paneLayout {
        case .single:
            singlePaneView.isHidden = false
            splitRootView.isHidden = true
            singlePaneView.frame = bounds
            splitRootView.frame = .zero

        case .split(let group):
            singlePaneView.isHidden = true
            splitRootView.isHidden = false
            singlePaneView.frame = .zero
            splitRootView.frame = bounds
            splitRootView.configure(
                group: group,
                chromeGeometry: chromeGeometry,
                onResize: { [weak self] path, sizes in
                    guard let self else { return }
                    self.splitManager?.updateLayoutSizes(
                        groupId: group.id,
                        path: path,
                        sizes: sizes,
                        for: self.windowId
                    )
                }
            )
        }
    }
}

private final class VisualHandoffOverlayView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private final class SplitRootView: NSView {
    private var chromeGeometry = BrowserChromeGeometry()
    private var paneViewsByTabId: [UUID: PaneContainerView] = [:]
    private var rootView: NSView?
    private var currentGroup: SplitGroup?
    private var onResize: (([Int], [Double]) -> Void)?
    private var layoutGeneration: UInt = 0

    var hasHostedWebViews: Bool {
        rootView.map { hostedWebViewCount(in: $0, stoppingAfter: 0) > 0 } ?? false
    }

    override var acceptsFirstResponder: Bool { false }

    func setChromeGeometry(_ geometry: BrowserChromeGeometry) {
        guard chromeGeometry != geometry else { return }
        chromeGeometry = geometry
        paneViewsByTabId.values.forEach { $0.setChromeGeometry(geometry) }
        needsLayout = true
    }

    func configure(
        group: SplitGroup,
        chromeGeometry: BrowserChromeGeometry,
        onResize: @escaping ([Int], [Double]) -> Void
    ) {
        self.onResize = onResize
        setChromeGeometry(chromeGeometry)
        if let currentGroup,
           currentGroup.layoutTree.hasSameStructure(as: group.layoutTree) {
            self.currentGroup = group
            rootView?.frame = bounds
            applyStoredSizes(from: group.layoutTree, to: rootView)
            return
        }

        rootView?.removeFromSuperview()
        paneViewsByTabId.removeAll(keepingCapacity: true)
        currentGroup = group
        layoutGeneration &+= 1
        let view = makeView(for: group.layoutTree, path: [], generation: layoutGeneration)
        rootView = view
        addSubview(view)
        needsLayout = true
    }

    func clear() {
        currentGroup = nil
        layoutGeneration &+= 1
        paneViewsByTabId.values.forEach { $0.clearSplitControls() }
        rootView?.removeFromSuperview()
        rootView = nil
        paneViewsByTabId.removeAll(keepingCapacity: true)
    }

    func paneView(for tabId: UUID) -> PaneContainerView? {
        paneViewsByTabId[tabId]
    }

    override func layout() {
        super.layout()
        rootView?.frame = bounds
    }

    private func makeView(for tree: SplitLayoutTree, path: [Int], generation: UInt) -> NSView {
        switch tree {
        case .leaf(let tabId, _):
            let pane = PaneContainerView()
            pane.identifier = NSUserInterfaceItemIdentifier("split-pane-\(tabId.uuidString)")
            pane.setChromeGeometry(chromeGeometry)
            paneViewsByTabId[tabId] = pane
            return pane

        case .split(let axis, _, let children):
            let split = NativeSplitTreeView(axis: axis, path: path, sizes: children.map(\.sizeInParent))
            split.resizeHandler = { [weak self] resizePath, sizes in
                guard let self, generation == self.layoutGeneration else { return }
                self.onResize?(resizePath, sizes)
            }
            for (index, child) in children.enumerated() {
                split.addSubview(makeView(for: child, path: path + [index], generation: generation))
            }
            return split
        }
    }

    private func applyStoredSizes(from tree: SplitLayoutTree, to view: NSView?) {
        guard let view else { return }
        switch tree {
        case .leaf:
            return
        case .split(_, _, let children):
            if let splitView = view as? NativeSplitTreeView {
                splitView.updateStoredSizes(children.map(\.sizeInParent))
            }
            for (childTree, childView) in zip(children, view.subviews) {
                applyStoredSizes(from: childTree, to: childView)
            }
        }
    }

}

private final class NativeSplitTreeView: NSSplitView, NSSplitViewDelegate {
    let path: [Int]
    var resizeHandler: (([Int], [Double]) -> Void)?
    private var storedSizes: [Double]
    private var needsStoredSizeApplication = true
    private var isApplyingStoredSizes = false
    private var lastReportedSizes: [Double] = []

    init(axis: SplitAxis, path: [Int], sizes: [Double]) {
        self.path = path
        self.storedSizes = sizes
        super.init(frame: .zero)
        isVertical = axis == .row
        dividerStyle = .thin
        wantsLayer = false
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { false }

    override func layout() {
        let shouldSuppressResizeReports = needsStoredSizeApplication
        if shouldSuppressResizeReports {
            isApplyingStoredSizes = true
        }
        super.layout()
        if shouldSuppressResizeReports {
            isApplyingStoredSizes = false
        }
        applyStoredSizesIfNeeded()
    }

    func updateStoredSizes(_ sizes: [Double]) {
        guard sizes.count == subviews.count else { return }
        let normalized = Self.normalizedSizes(sizes, fallbackCount: subviews.count)
        guard !normalized.isApproximatelyEqual(to: storedSizes) else { return }
        storedSizes = normalized
        needsStoredSizeApplication = true
        needsLayout = true
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !isApplyingStoredSizes,
              !needsStoredSizeApplication,
              !isHidden,
              bounds.width > 0,
              bounds.height > 0
        else { return }
        let lengths = subviews.map { isVertical ? $0.frame.width : $0.frame.height }
        let total = lengths.reduce(0, +)
        guard total > 0 else { return }
        let sizes = lengths.map { Double($0 / total) }
        guard !sizes.isApproximatelyEqual(to: lastReportedSizes) else { return }
        lastReportedSizes = sizes
        resizeHandler?(path, sizes)
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        proposedMinimumPosition + 48
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        proposedMaximumPosition - 48
    }

    private func applyStoredSizesIfNeeded() {
        guard needsStoredSizeApplication, subviews.count >= 2 else { return }
        let totalLength = isVertical ? bounds.width : bounds.height
        guard totalLength > 0 else { return }

        needsStoredSizeApplication = false
        isApplyingStoredSizes = true
        let normalized = Self.normalizedSizes(storedSizes, fallbackCount: subviews.count)
        storedSizes = normalized
        lastReportedSizes = normalized
        var accumulated: CGFloat = 0
        for index in 0 ..< subviews.count - 1 {
            let fraction = CGFloat(normalized[safe: index] ?? (1 / Double(subviews.count)))
            accumulated += totalLength * fraction
            setPosition(accumulated, ofDividerAt: index)
        }
        isApplyingStoredSizes = false
    }

    private static func normalizedSizes(_ sizes: [Double], fallbackCount: Int) -> [Double] {
        guard sizes.count == fallbackCount, fallbackCount > 0 else {
            return Array(repeating: 1 / Double(max(1, fallbackCount)), count: max(0, fallbackCount))
        }
        let total = sizes.reduce(0) { $0 + max(0.01, $1) }
        guard total > 0 else {
            return Array(repeating: 1 / Double(fallbackCount), count: fallbackCount)
        }
        return sizes.map { max(0.01, $0) / total }
    }
}

final class PaneContainerView: NSView {
    private let chromeShadowView = BrowserContentViewportShadowView(frame: .zero)
    private var chromeGeometry = BrowserChromeGeometry()
    private var splitControlsView: SplitPaneControlsView?
    private var paneTrackingArea: NSTrackingArea?
    private var isPointerInside = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        chromeShadowView.isHidden = true
        addSubview(chromeShadowView, positioned: .below, relativeTo: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { false }

    func setChromeGeometry(_ geometry: BrowserChromeGeometry) {
        guard chromeGeometry != geometry else { return }
        chromeGeometry = geometry
        needsLayout = true
    }

    func placeContentHostAboveChromeShadow(_ host: SumiWebViewContainerView) {
        chromeShadowView.isHidden = false
        addSubview(host, positioned: .above, relativeTo: chromeShadowView)
        if let splitControlsView {
            addSubview(splitControlsView, positioned: .above, relativeTo: host)
        }
    }

    func configureSplitControls(
        tab: Tab,
        browserManager: BrowserManager,
        splitManager: SplitViewManager,
        windowState: BrowserWindowState
    ) {
        let controls = splitControlsView ?? SplitPaneControlsView()
        splitControlsView = controls
        controls.configure(
            tab: tab,
            browserManager: browserManager,
            splitManager: splitManager,
            windowState: windowState
        )
        if controls.superview !== self {
            addSubview(controls, positioned: .above, relativeTo: nil)
        }
        controls.setVisible(isPointerInside, animated: false)
        needsLayout = true
    }

    func clearSplitControls() {
        splitControlsView?.removeFromSuperview()
        splitControlsView = nil
        isPointerInside = false
    }

    func removeHostedSubviews(
        keeping keepView: NSView?,
        shouldRemove: (NSView) -> Bool = { _ in true }
    ) {
        for subview in subviews
            where subview !== keepView && subview !== chromeShadowView && subview !== splitControlsView
        {
            if shouldRemove(subview) {
                subview.removeFromSuperview()
            }
        }
        keepView?.isHidden = false
        chromeShadowView.isHidden = keepView == nil
    }

    override func layout() {
        super.layout()
        layoutChromeShadow()
        layoutSplitControls()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let paneTrackingArea {
            removeTrackingArea(paneTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInActiveApp, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        paneTrackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isPointerInside = true
        splitControlsView?.setVisible(true, animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isPointerInside = false
        splitControlsView?.setVisible(false, animated: true)
    }

    private func layoutChromeShadow() {
        let outset = BrowserContentViewportShadowView.shadowOutset
        chromeShadowView.isHidden = bounds.width <= 0
            || bounds.height <= 0
            || hostedContentView == nil
        chromeShadowView.frame = bounds.insetBy(dx: -outset, dy: -outset)
        chromeShadowView.viewportRect = NSRect(
            x: outset,
            y: outset,
            width: bounds.width,
            height: bounds.height
        )
        chromeShadowView.cornerRadii = chromeGeometry.contentCornerRadii
    }

    private func layoutSplitControls() {
        guard let controls = splitControlsView else { return }
        let size = controls.intrinsicContentSize
        controls.frame = NSRect(
            x: max(0, (bounds.width - size.width) / 2),
            y: max(0, bounds.height - size.height),
            width: size.width,
            height: size.height
        )
    }

    private var hostedContentView: SumiWebViewContainerView? {
        subviews.first { $0 is SumiWebViewContainerView && !$0.isHidden } as? SumiWebViewContainerView
    }
}

private final class SplitPaneControlsView: NSVisualEffectView {
    private let stackView = NSStackView()
    private let dragButton = SplitPaneDragButton()
    private let expandButton = SplitPaneToolbarButton(icon: .fullscreen)
    private weak var splitManager: SplitViewManager?
    private weak var windowState: BrowserWindowState?
    private weak var tab: Tab?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 6

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 13
        stackView.edgeInsets = NSEdgeInsets(top: 6.5, left: 9.5, bottom: 3.5, right: 9.5)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        dragButton.toolTip = "Rearrange Split"
        expandButton.toolTip = "Expand Tab"
        expandButton.target = self
        expandButton.action = #selector(expandTab)
        stackView.addArrangedSubview(dragButton)
        stackView.addArrangedSubview(expandButton)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        alphaValue = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 64, height: 26)
    }

    func configure(
        tab: Tab,
        browserManager: BrowserManager,
        splitManager: SplitViewManager,
        windowState: BrowserWindowState
    ) {
        self.tab = tab
        self.splitManager = splitManager
        self.windowState = windowState
        dragButton.configure(
            tab: tab,
            windowState: windowState,
            browserManager: browserManager,
            splitManager: splitManager
        )
    }

    func setVisible(_ isVisible: Bool, animated: Bool) {
        let targetAlpha: CGFloat = isVisible ? 1 : 0
        guard abs(alphaValue - targetAlpha) > 0.001 else { return }

        let updates = { self.alphaValue = targetAlpha }
        guard animated else {
            updates()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = targetAlpha
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        alphaValue > 0.05 ? super.hitTest(point) : nil
    }

    @objc private func expandTab() {
        guard let tab, let splitManager, let windowState else { return }
        splitManager.expandSplitPane(tabId: tab.id, in: windowState)
    }
}

private enum SplitPaneToolbarIcon {
    case dragHandle
    case fullscreen

    var image: NSImage {
        switch self {
        case .dragHandle:
            return Self.dragHandleImage
        case .fullscreen:
            return Self.fullscreenImage
        }
    }

    private static let dragHandleImage: NSImage = {
        let image = NSImage(size: NSSize(width: 14, height: 14))
        image.lockFocus()
        NSColor.black.setFill()
        let dotDiameter: CGFloat = 1.2
        let dotOrigins: [CGPoint] = [
            CGPoint(x: 2.6, y: 4.0),
            CGPoint(x: 6.4, y: 4.0),
            CGPoint(x: 10.2, y: 4.0),
            CGPoint(x: 2.6, y: 8.8),
            CGPoint(x: 6.4, y: 8.8),
            CGPoint(x: 10.2, y: 8.8),
        ]
        for origin in dotOrigins {
            NSBezierPath(ovalIn: NSRect(
                x: origin.x,
                y: origin.y,
                width: dotDiameter,
                height: dotDiameter
            )).fill()
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }()

    private static let fullscreenImage: NSImage = {
        let image = NSImage(size: NSSize(width: 14, height: 14))
        image.lockFocus()
        NSColor.black.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        path.move(to: CGPoint(x: 8.4, y: 11.9))
        path.line(to: CGPoint(x: 11.9, y: 11.9))
        path.line(to: CGPoint(x: 11.9, y: 8.4))
        path.move(to: CGPoint(x: 11.9, y: 11.9))
        path.line(to: CGPoint(x: 8.4, y: 8.4))

        path.move(to: CGPoint(x: 2.1, y: 5.6))
        path.line(to: CGPoint(x: 2.1, y: 2.1))
        path.line(to: CGPoint(x: 5.6, y: 2.1))
        path.move(to: CGPoint(x: 2.1, y: 2.1))
        path.line(to: CGPoint(x: 5.6, y: 5.6))

        path.stroke()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }()
}

private class SplitPaneToolbarButton: NSButton {
    init(icon: SplitPaneToolbarIcon) {
        super.init(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        image = icon.image
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        contentTintColor = .labelColor
        wantsLayer = true
        layer?.cornerRadius = 4
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 16, height: 16)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = isHighlighted
            ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            : NSColor.clear.cgColor
    }
}

private final class SplitPaneDragButton: SplitPaneToolbarButton, NSDraggingSource {
    private static let transparentDragImage: NSImage = {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()
        return image
    }()

    private weak var tab: Tab?
    private weak var windowState: BrowserWindowState?
    private weak var browserManager: BrowserManager?
    private weak var splitManager: SplitViewManager?
    private var didStartDrag = false
    private var mouseDownEvent: NSEvent?

    init() {
        super.init(icon: .dragHandle)
        contentTintColor = .labelColor
    }

    func configure(
        tab: Tab,
        windowState: BrowserWindowState,
        browserManager: BrowserManager,
        splitManager: SplitViewManager
    ) {
        self.tab = tab
        self.windowState = windowState
        self.browserManager = browserManager
        self.splitManager = splitManager
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        didStartDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartDrag else { return }
        startDrag(with: mouseDownEvent ?? event, sessionEvent: event)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
        if !didStartDrag {
            super.mouseUp(with: event)
        }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    func draggingSession(
        _ session: NSDraggingSession,
        movedTo screenPoint: NSPoint
    ) {
        guard let locations = SidebarDragLocationMapper.sourceLocationsFromScreenPoint(
            callbackScreenPoint: screenPoint,
            in: self
        ) else { return }
        SidebarDragState.shared.updateDragLocation(
            locations.dropLocation,
            previewLocation: locations.previewLocation
        )
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        SidebarDragState.shared.resetInteractionState()
        setSplitDropShieldActive(false)
        NotificationCenter.default.post(name: .tabDragDidEnd, object: nil)
        didStartDrag = false
        mouseDownEvent = nil
    }

    private func startDrag(with event: NSEvent, sessionEvent: NSEvent) {
        guard let tab, let windowState else { return }
        let spaceId = tab.spaceId ?? windowState.currentSpaceId
        guard let spaceId else { return }

        let item = SumiDragItem(
            tabId: tab.id,
            title: tab.name,
            urlString: tab.url.absoluteString
        )
        let scope = SidebarDragScope(
            windowId: windowState.id,
            spaceId: spaceId,
            profileId: windowState.currentProfileId,
            sourceContainer: .spaceRegular(spaceId),
            sourceItemId: tab.id,
            sourceItemKind: .tab
        )

        let localPoint = convert(event.locationInWindow, from: nil)
        let dragLocation = SidebarDragLocationMapper.swiftUIGlobalPoint(
            fromLocalPoint: localPoint,
            in: self
        )
        let previewLocation = SidebarDragLocationMapper.swiftUIPreviewPoint(
            fromLocalPoint: localPoint,
            in: self
        )
        let previewModel = SidebarDragPreviewModel(
            item: item,
            sourceZone: .spaceRegular(spaceId),
            baseKind: .row,
            previewIcon: tab.favicon,
            chromeTemplateSystemImageName: nil,
            sourceSize: CGSize(width: 180, height: SidebarRowLayout.rowHeight),
            normalizedTopLeadingAnchor: CGPoint(x: 0.5, y: 0.5),
            pinnedConfig: .large,
            shortcutPresentationState: nil,
            folderGlyphPresentation: nil,
            folderGlyphPalette: nil
        )

        didStartDrag = true
        SidebarDragState.shared.beginInternalDragSession(
            itemId: tab.id,
            location: dragLocation,
            previewLocation: previewLocation,
            previewKind: .row,
            previewAssets: [:],
            previewModel: previewModel,
            scope: scope
        )
        setSplitDropShieldActive(true)

        let dragItem = NSDraggingItem(pasteboardWriter: item.pasteboardItem(scope: scope))
        dragItem.setDraggingFrame(
            NSRect(x: localPoint.x, y: localPoint.y, width: 1, height: 1),
            contents: Self.transparentDragImage
        )
        let session = beginDraggingSession(with: [dragItem], event: sessionEvent, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    private func setSplitDropShieldActive(_ isActive: Bool) {
        guard let browserManager, let splitManager, let windowState else { return }
        enclosingContainerView?.setSplitDropCaptureActive(
            isActive,
            browserManager: browserManager,
            splitManager: splitManager,
            windowId: windowState.id
        )
    }

    private var enclosingContainerView: ContainerView? {
        var view = superview
        while let current = view {
            if let container = current as? ContainerView {
                return container
            }
            view = current.superview
        }
        return nil
    }
}

private extension Array where Element == Double {
    func isApproximatelyEqual(to other: [Double], accuracy: Double = 0.0005) -> Bool {
        guard count == other.count else { return false }
        return zip(self, other).allSatisfy { abs($0 - $1) <= accuracy }
    }
}
