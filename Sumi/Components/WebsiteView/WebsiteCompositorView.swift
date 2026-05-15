import AppKit
import SwiftUI
import WebKit

// MARK: - Tab Compositor Wrapper

struct WebsiteDisplayState: Equatable {
    let splitFraction: CGFloat
    let splitOrientation: SplitOrientation
    let isSplit: Bool
    let leftId: UUID?
    let rightId: UUID?
    let currentId: UUID?
    let compositorVersion: Int
    let currentTabUnloaded: Bool
    let visibleTabIds: Set<UUID>
    let isPreviewActive: Bool
    let isSplitDropCaptureActive: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.splitFraction == rhs.splitFraction
            && lhs.splitOrientation == rhs.splitOrientation
            && lhs.isSplit == rhs.isSplit
            && lhs.leftId == rhs.leftId
            && lhs.rightId == rhs.rightId
            && lhs.currentId == rhs.currentId
            && lhs.compositorVersion == rhs.compositorVersion
            && lhs.currentTabUnloaded == rhs.currentTabUnloaded
            && lhs.visibleTabIds == rhs.visibleTabIds
            && lhs.isPreviewActive == rhs.isPreviewActive
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
    private var lastHoverTabId: UUID?
    private var pendingSplitRepairKeepSide: SplitViewManager.Side? = nil
    private var hoveredLinkHandler: ((String?) -> Void)?
    private var singlePaneHost: SumiWebViewContainerView?
    private var leftPaneHost: SumiWebViewContainerView?
    private var rightPaneHost: SumiWebViewContainerView?
    private var parkedProtectedHosts: [ObjectIdentifier: SumiWebViewContainerView] = [:]

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

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.browserManager.schedulePrepareVisibleWebViews(for: self.windowState)
        }
    }

    func tearDownController() {
        if webViewCoordinator.hasActiveFullscreen(in: windowState.id) {
            webViewCoordinator.closeActiveFullscreenMedia(in: windowState.id)
        }
        clearPane(.single)
        clearPane(.left)
        clearPane(.right)
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
        chromeGeometry: BrowserChromeGeometry
    ) {
        if self.chromeGeometry != chromeGeometry {
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
           let currentTab = browserManager.currentTab(for: windowState)
        {
            setupHoverCallbacks(for: currentTab)
            lastHoverTabId = displayState.currentId
        }

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
        guard appliedDisplayState != displayState
                || hasStaleSubviews
        else {
            return
        }

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

        if displayState.isPreviewActive {
            showSinglePane(tab: currentTab)
            return
        }

        let isCurrentPane = displayState.currentId != nil
            && (displayState.currentId == displayState.leftId || displayState.currentId == displayState.rightId)

        if displayState.isSplit && isCurrentPane {
            let leftTab = displayState.leftId.flatMap { browserManager.tabManager.tab(for: $0) }
            let rightTab = displayState.rightId.flatMap { browserManager.tabManager.tab(for: $0) }

            if leftTab == nil && rightTab == nil {
                scheduleSplitRepair(keep: .left)
                showSinglePane(tab: currentTab)
                return
            }
            if leftTab == nil {
                scheduleSplitRepair(keep: .right)
                showSinglePane(tab: currentTab)
                return
            }
            if rightTab == nil {
                scheduleSplitRepair(keep: .left)
                showSinglePane(tab: currentTab)
                return
            }

            let fraction = max(
                splitManager.minFraction,
                min(splitManager.maxFraction, displayState.splitFraction)
            )

            showSplitPanes(
                leftTab: leftTab,
                rightTab: rightTab,
                fraction: fraction,
                orientation: displayState.splitOrientation
            )
            return
        }

        showSinglePane(tab: currentTab)
    }

    private func hostedWebViewCount(in root: NSView) -> Int {
        var count = 0
        for subview in root.subviews {
            if subview is SumiWebViewContainerView || subview is WKWebView {
                count += 1
            } else {
                count += hostedWebViewCount(in: subview)
            }
        }
        return count
    }

    private func compositorSubtreeHasStaleWebViews(
        currentTab: Tab?,
        displayState: WebsiteDisplayState
    ) -> Bool {
        guard !webViewCoordinator.hasActiveHistorySwipe(in: windowState.id) else {
            return false
        }

        if displayState.isPreviewActive {
            let expected = (currentTab != nil && displayState.currentTabUnloaded == false) ? 1 : 0
            if hostedWebViewCount(in: containerView.singlePaneView) > expected { return true }
            if hostedWebViewCount(in: containerView.leftPaneView) > 0 { return true }
            if hostedWebViewCount(in: containerView.rightPaneView) > 0 { return true }
            return false
        }

        let isCurrentPane = displayState.currentId != nil
            && (displayState.currentId == displayState.leftId || displayState.currentId == displayState.rightId)

        if displayState.isSplit, isCurrentPane {
            let leftTab = displayState.leftId.flatMap { browserManager.tabManager.tab(for: $0) }
            let rightTab = displayState.rightId.flatMap { browserManager.tabManager.tab(for: $0) }
            let leftExpected = (leftTab != nil && leftTab?.isUnloaded == false) ? 1 : 0
            let rightExpected = (rightTab != nil && rightTab?.isUnloaded == false) ? 1 : 0
            if hostedWebViewCount(in: containerView.leftPaneView) > leftExpected { return true }
            if hostedWebViewCount(in: containerView.rightPaneView) > rightExpected { return true }
            if hostedWebViewCount(in: containerView.singlePaneView) > 0 { return true }
            return false
        }

        let expected = (currentTab != nil && displayState.currentTabUnloaded == false) ? 1 : 0
        if hostedWebViewCount(in: containerView.singlePaneView) > expected { return true }
        if hostedWebViewCount(in: containerView.leftPaneView) > 0 { return true }
        if hostedWebViewCount(in: containerView.rightPaneView) > 0 { return true }
        return false
    }

    private func showSinglePane(tab: Tab?) {
        containerView.setPaneLayout(.single)
        containerView.layoutSubtreeIfNeeded()
        containerView.singlePaneView.isHidden = false
        containerView.leftPaneView.isHidden = true
        containerView.rightPaneView.isHidden = true

        if let tab, let host = webViewHost(for: tab, pane: .single) {
            attach(host, to: containerView.singlePaneView)
            containerView.singlePaneView.removeHostedSubviews(
                keeping: host,
                shouldRemove: shouldRemoveHostedSubview
            )
        } else {
            clearPane(.single)
        }

        clearPane(.left)
        clearPane(.right)
    }

    private func showSplitPanes(
        leftTab: Tab?,
        rightTab: Tab?,
        fraction: CGFloat,
        orientation: SplitOrientation
    ) {
        containerView.setPaneLayout(.split(fraction: fraction, orientation: orientation))
        containerView.layoutSubtreeIfNeeded()
        containerView.singlePaneView.isHidden = true
        clearPane(.single)

        containerView.leftPaneView.isHidden = false
        containerView.rightPaneView.isHidden = false

        if let leftTab, let host = webViewHost(for: leftTab, pane: .left) {
            attach(host, to: containerView.leftPaneView)
            containerView.leftPaneView.removeHostedSubviews(
                keeping: host,
                shouldRemove: shouldRemoveHostedSubview
            )
        } else {
            clearPane(.left)
        }

        if let rightTab, let host = webViewHost(for: rightTab, pane: .right) {
            attach(host, to: containerView.rightPaneView)
            containerView.rightPaneView.removeHostedSubviews(
                keeping: host,
                shouldRemove: shouldRemoveHostedSubview
            )
        } else {
            clearPane(.right)
        }
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

    private func setupHoverCallbacks(for tab: Tab) {
        tab.onLinkHover = { [weak self] href in
            DispatchQueue.main.async {
                self?.hoveredLinkHandler?(href)
            }
        }
    }

    private func webViewHost(
        for tab: Tab,
        pane: CompositorPaneDestination
    ) -> SumiWebViewContainerView? {
        guard tab.requiresPrimaryWebView else {
            clearPane(pane)
            return nil
        }
        let webView = webViewCoordinator.getWebView(for: tab.id, in: windowState.id)
            ?? webViewCoordinator.getOrCreateWebView(for: tab, in: windowState.id)
        guard let webView else {
            clearPane(pane)
            return nil
        }

        if let host = paneHost(pane),
           host.tabID == tab.id,
           host.webView === webView
        {
            return host
        }

        if webViewCoordinator.isWebViewProtectedFromCompositorMutation(webView),
           let existingHost = protectedHost(for: webView) {
            clearPane(pane)
            configureViewportStyle(on: existingHost)
            clearPaneHostReferences(to: existingHost)
            setPaneHost(existingHost, for: pane)
            return existingHost
        }

        clearPane(pane)
        let host = SumiWebViewContainerView(tab: tab, webView: webView)
        configureViewportStyle(on: host)
        setPaneHost(host, for: pane)
        return host
    }

    private func attach(_ host: SumiWebViewContainerView, to paneView: PaneContainerView) {
        let isProtected = webViewCoordinator.isWebViewProtectedFromCompositorMutation(host.webView)
        if isProtected {
            attachProtectedHost(host, to: paneView)
            return
        }

        parkedProtectedHosts.removeValue(forKey: ObjectIdentifier(host.webView))
        if host.superview != nil && host.superview !== paneView {
            host.removeFromSuperview()
        }
        if host.superview == nil || host.superview === paneView {
            paneView.placeContentHostAboveChromeShadow(host)
        }
        host.frame = paneView.bounds
        host.autoresizingMask = [.width, .height]
        configureViewportStyle(on: host)
        if !isProtected {
            host.attachDisplayedContentIfNeeded()
        }
        host.isHidden = false
    }

    private func attachProtectedHost(_ host: SumiWebViewContainerView, to paneView: PaneContainerView) {
        let webViewID = ObjectIdentifier(host.webView)
        parkedProtectedHosts[webViewID] = host

        if host.superview != nil && host.superview !== paneView {
            host.removeFromSuperview()
        }
        if host.superview == nil || host.superview === paneView {
            paneView.placeContentHostAboveChromeShadow(host)
        }
        host.frame = paneView.bounds
        host.autoresizingMask = [.width, .height]
        configureViewportStyle(on: host)
        host.isHidden = false
    }

    private func protectedHost(for webView: WKWebView) -> SumiWebViewContainerView? {
        let webViewID = ObjectIdentifier(webView)
        if let parkedHost = parkedProtectedHosts[webViewID] {
            return parkedHost
        }

        if let currentHost = [singlePaneHost, leftPaneHost, rightPaneHost]
            .compactMap({ $0 })
            .first(where: { $0.webView === webView }) {
            parkedProtectedHosts[webViewID] = currentHost
            return currentHost
        }

        return nil
    }

    private func clearPane(_ pane: CompositorPaneDestination) {
        let paneView = paneView(for: pane)
        if let host = paneHost(pane) {
            if webViewCoordinator.isWebViewProtectedFromCompositorMutation(host.webView) {
                parkProtectedHost(host)
            } else {
                parkedProtectedHosts.removeValue(forKey: ObjectIdentifier(host.webView))
                host.removeFromSuperview()
            }
        }
        setPaneHost(nil, for: pane)
        paneView.removeHostedSubviews(
            keeping: nil,
            shouldRemove: shouldRemoveHostedSubview
        )
    }

    private func shouldRemoveHostedSubview(_ subview: NSView) -> Bool {
        guard let host = subview as? SumiWebViewContainerView else {
            return true
        }
        if webViewCoordinator.isWebViewProtectedFromCompositorMutation(host.webView) {
            parkProtectedHost(host)
            return false
        }
        parkedProtectedHosts.removeValue(forKey: ObjectIdentifier(host.webView))
        return true
    }

    private func parkProtectedHost(_ host: SumiWebViewContainerView) {
        parkedProtectedHosts[ObjectIdentifier(host.webView)] = host
        host.isHidden = true
    }

    private func displayedHost(for tabId: UUID) -> SumiWebViewContainerView? {
        [singlePaneHost, leftPaneHost, rightPaneHost].compactMap { $0 }.first {
            $0.tabID == tabId
        }
    }

    private func paneHost(_ pane: CompositorPaneDestination) -> SumiWebViewContainerView? {
        switch pane {
        case .single:
            return singlePaneHost
        case .left:
            return leftPaneHost
        case .right:
            return rightPaneHost
        }
    }

    private func setPaneHost(_ host: SumiWebViewContainerView?, for pane: CompositorPaneDestination) {
        switch pane {
        case .single:
            singlePaneHost = host
        case .left:
            leftPaneHost = host
        case .right:
            rightPaneHost = host
        }
    }

    private func clearPaneHostReferences(to host: SumiWebViewContainerView) {
        if singlePaneHost === host {
            singlePaneHost = nil
        }
        if leftPaneHost === host {
            leftPaneHost = nil
        }
        if rightPaneHost === host {
            rightPaneHost = nil
        }
    }

    private func paneView(for pane: CompositorPaneDestination) -> PaneContainerView {
        switch pane {
        case .single:
            return containerView.singlePaneView
        case .left:
            return containerView.leftPaneView
        case .right:
            return containerView.rightPaneView
        }
    }

    private func missingPreparedWebViews(for visibleTabIds: Set<UUID>) -> Bool {
        visibleTabIds.contains { tabId in
            if let tab = browserManager.tabManager.tab(for: tabId),
               tab.requiresPrimaryWebView == false
            {
                return false
            }
            return webViewCoordinator.getWebView(for: tabId, in: windowState.id) == nil
        }
    }

    private func updateDisplayedHostViewportStyles() {
        [singlePaneHost, leftPaneHost, rightPaneHost].compactMap { $0 }.forEach {
            configureViewportStyle(on: $0)
        }
    }

    private func configureViewportStyle(on host: SumiWebViewContainerView) {
        host.setBrowserContentViewport(geometry: chromeGeometry)
    }

    private func scheduleSplitRepair(keep side: SplitViewManager.Side) {
        guard pendingSplitRepairKeepSide != side else { return }
        pendingSplitRepairKeepSide = side

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.browserManager.splitManager.exitSplit(keep: side, for: self.windowState.id)
            self.pendingSplitRepairKeepSide = nil
        }
    }
}

struct TabCompositorWrapper: NSViewControllerRepresentable {
    let browserManager: BrowserManager
    let webViewCoordinator: WebViewCoordinator
    @Binding var hoveredLink: String?
    var splitFraction: CGFloat
    var splitOrientation: SplitOrientation
    var isSplit: Bool
    var leftId: UUID?
    var rightId: UUID?
    var isSplitDropCaptureActive: Bool
    var chromeGeometry: BrowserChromeGeometry
    let windowState: BrowserWindowState

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
            chromeGeometry: chromeGeometry
        )
    }

    static func dismantleNSViewController(_ controller: WindowWebContentController, coordinator: ()) {
        controller.tearDownController()
    }

    private func visibleTabIds(currentId: UUID?) -> Set<UUID> {
        guard let currentId else { return [] }
        let split = browserManager.splitManager
        guard split.getSplitState(for: windowState.id).isPreviewActive == false else {
            return [currentId]
        }
        let leftId = split.leftTabId(for: windowState.id)
        let rightId = split.rightTabId(for: windowState.id)
        let isCurrentPane = currentId == leftId || currentId == rightId
        guard split.isSplit(for: windowState.id), isCurrentPane else {
            return [currentId]
        }
        return Set([leftId, rightId].compactMap { $0 })
    }

    private func makeDisplayState() -> WebsiteDisplayState {
        let currentTab = browserManager.currentTab(for: windowState)
        let currentId = currentTab?.id
        return WebsiteDisplayState(
            splitFraction: splitFraction,
            splitOrientation: splitOrientation,
            isSplit: isSplit,
            leftId: leftId,
            rightId: rightId,
            currentId: currentId,
            compositorVersion: windowState.compositorVersion,
            currentTabUnloaded: currentTab?.isUnloaded ?? true,
            visibleTabIds: visibleTabIds(currentId: currentId),
            isPreviewActive: browserManager.splitManager.getSplitState(for: windowState.id).isPreviewActive,
            isSplitDropCaptureActive: isSplitDropCaptureActive
        )
    }
}

// MARK: - Container View

private class ContainerView: NSView {
    enum PaneLayout: Equatable {
        case single
        case split(fraction: CGFloat, orientation: SplitOrientation)
    }

    let singlePaneView = PaneContainerView()
    let leftPaneView = PaneContainerView()
    let rightPaneView = PaneContainerView()
    private let splitDropCaptureView = SplitDropCaptureView(frame: .zero)
    private var paneLayout: PaneLayout = .single
    private var chromeGeometry: BrowserChromeGeometry

    init(
        browserManager: BrowserManager,
        splitManager: SplitViewManager,
        windowId: UUID,
        chromeGeometry: BrowserChromeGeometry
    ) {
        self.chromeGeometry = chromeGeometry
        super.init(frame: .zero)

        singlePaneView.identifier = CompositorPaneDestination.single.viewIdentifier
        leftPaneView.identifier = CompositorPaneDestination.left.viewIdentifier
        rightPaneView.identifier = CompositorPaneDestination.right.viewIdentifier
        singlePaneView.setChromeGeometry(chromeGeometry)
        leftPaneView.setChromeGeometry(chromeGeometry)
        rightPaneView.setChromeGeometry(chromeGeometry)

        addSubview(singlePaneView)
        addSubview(leftPaneView)
        addSubview(rightPaneView)

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
        leftPaneView.setChromeGeometry(geometry)
        rightPaneView.setChromeGeometry(geometry)
        needsLayout = true
    }

    func setSplitDropCaptureActive(
        _ isActive: Bool,
        browserManager: BrowserManager,
        splitManager: SplitViewManager,
        windowId: UUID
    ) {
        splitDropCaptureView.browserManager = browserManager
        splitDropCaptureView.splitManager = splitManager
        splitDropCaptureView.windowId = windowId

        if isActive {
            if splitDropCaptureView.superview !== self {
                addSubview(splitDropCaptureView, positioned: .above, relativeTo: nil)
            }
            splitDropCaptureView.frame = bounds
        } else if splitDropCaptureView.superview === self {
            splitDropCaptureView.removeFromSuperview()
        }
    }

    // Don't intercept events - let them pass through to webviews
    override var acceptsFirstResponder: Bool { false }

    override func resetCursorRects() {
        // Empty: prevents NSHostingView and other ancestors from registering
        // arrow cursor rects over the webview. WKWebView uses NSCursor.set()
        // internally, which works correctly when cursor rects don't override it.
    }

    private func applyPaneLayout() {
        switch paneLayout {
        case .single:
            singlePaneView.frame = pixelAligned(bounds)
            leftPaneView.frame = .zero
            rightPaneView.frame = .zero

        case .split(let fraction, let orientation):
            singlePaneView.frame = .zero
            let frames = splitPaneFrames(fraction: fraction, orientation: orientation)
            leftPaneView.frame = frames.left
            rightPaneView.frame = frames.right
        }
    }

    private func splitPaneFrames(
        fraction: CGFloat,
        orientation: SplitOrientation
    ) -> (left: NSRect, right: NSRect) {
        let total = pixelAligned(bounds)
        let gap = pixelAlignedLength(chromeGeometry.elementSeparation)
        let halfGap = gap / 2

        switch orientation {
        case .horizontal:
            let splitX = pixelAlignedCoordinate(total.minX + total.width * fraction)
            let leftMaxX = pixelAlignedCoordinate(splitX - halfGap)
            let rightMinX = pixelAlignedCoordinate(splitX + halfGap)
            return (
                left: pixelAligned(NSRect(
                    x: total.minX,
                    y: total.minY,
                    width: max(1, leftMaxX - total.minX),
                    height: total.height
                )),
                right: pixelAligned(NSRect(
                    x: rightMinX,
                    y: total.minY,
                    width: max(1, total.maxX - rightMinX),
                    height: total.height
                ))
            )

        case .vertical:
            let splitY = pixelAlignedCoordinate(total.maxY - total.height * fraction)
            let bottomMaxY = pixelAlignedCoordinate(splitY - halfGap)
            let topMinY = pixelAlignedCoordinate(splitY + halfGap)
            return (
                left: pixelAligned(NSRect(
                    x: total.minX,
                    y: topMinY,
                    width: total.width,
                    height: max(1, total.maxY - topMinY)
                )),
                right: pixelAligned(NSRect(
                    x: total.minX,
                    y: total.minY,
                    width: total.width,
                    height: max(1, bottomMaxY - total.minY)
                ))
            )
        }
    }

    private var backingScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private func pixelAlignedCoordinate(_ value: CGFloat) -> CGFloat {
        (value * backingScale).rounded(.toNearestOrAwayFromZero) / backingScale
    }

    private func pixelAlignedLength(_ value: CGFloat) -> CGFloat {
        max(0, pixelAlignedCoordinate(value))
    }

    private func pixelAligned(_ rect: NSRect) -> NSRect {
        let minX = pixelAlignedCoordinate(rect.minX)
        let minY = pixelAlignedCoordinate(rect.minY)
        let maxX = pixelAlignedCoordinate(rect.maxX)
        let maxY = pixelAlignedCoordinate(rect.maxY)
        return NSRect(
            x: minX,
            y: minY,
            width: max(0, maxX - minX),
            height: max(0, maxY - minY)
        )
    }
}

private final class PaneContainerView: NSView {
    private let chromeShadowView = BrowserContentViewportShadowView(frame: .zero)
    private var chromeGeometry = BrowserChromeGeometry()

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
    }

    func removeHostedSubviews(
        keeping keepView: NSView?,
        shouldRemove: (NSView) -> Bool = { _ in true }
    ) {
        for subview in subviews
            where subview !== keepView && subview !== chromeShadowView
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
        chromeShadowView.cornerRadius = min(
            max(0, chromeGeometry.contentRadius),
            max(0, bounds.width / 2),
            max(0, bounds.height / 2)
        )
    }

    private var hostedContentView: SumiWebViewContainerView? {
        subviews.first { $0 is SumiWebViewContainerView && !$0.isHidden } as? SumiWebViewContainerView
    }
}
