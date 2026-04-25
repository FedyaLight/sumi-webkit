//
//  WebsiteView.swift
//  Sumi
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI
import WebKit
import AppKit

// MARK: - Status Bar View
struct LinkStatusBar: View {
    let hoveredLink: String?
    let isCommandPressed: Bool
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var shouldShow: Bool = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var displayedLink: String? = nil
    
    var body: some View {
        Group {
            if let link = displayedLink, !link.isEmpty {
                Text(displayText(for: link))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(backgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 999))
                    .overlay(
                        RoundedRectangle(cornerRadius: 999)
                            .stroke(borderColor, lineWidth: 1)
                    )
                    .opacity(shouldShow ? 1 : 0)
                    .animation(.easeOut(duration: 0.25), value: shouldShow)
            }
        }
        .onChange(of: hoveredLink) { _, newLink in
            handleHoverChange(newLink: newLink)
        }
        .onAppear {
            handleHoverChange(newLink: hoveredLink)
        }
        .onDisappear {
            hoverTask?.cancel()
            hoverTask = nil
            shouldShow = false
            displayedLink = nil
        }
    }
    
    private func displayText(for link: String) -> String {
        let truncatedLink = truncateLink(link)
        if isCommandPressed {
            return "Open \(truncatedLink) in a new tab and focus it"
        } else {
            return truncatedLink
        }
    }
    
    private func handleHoverChange(newLink: String?) {
        // Cancel any existing task
        hoverTask?.cancel()
        hoverTask = nil
        
        if let link = newLink, !link.isEmpty {
            // New link - update displayed link immediately
            displayedLink = link
            
            // Wait then show if not already showing
            if !shouldShow {
                hoverTask = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                    if !Task.isCancelled {
                        await MainActor.run { shouldShow = true }
                    }
                }
            }
        } else {
            // Link cleared - wait then hide
            hoverTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s delay
                if !Task.isCancelled {
                    await MainActor.run {
                        shouldShow = false
                    }
                    // Clear displayed link after fade out animation completes
                    try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s for fade out
                    if !Task.isCancelled {
                        await MainActor.run {
                            displayedLink = nil
                        }
                    }
                }
            }
        }
    }
    
    private func truncateLink(_ link: String) -> String {
        if link.count > 60 {
            let firstPart = String(link.prefix(30))
            let lastPart = String(link.suffix(30))
            return "\(firstPart)...\(lastPart)"
        }
        return link
    }
    
    private var backgroundColor: Color {
        tokens.statusPanelBackground
    }
    
    private var textColor: Color {
        tokens.statusPanelText
    }
    
    private var borderColor: Color {
        tokens.statusPanelBorder
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}

struct WebsiteView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(WebViewCoordinator.self) private var webViewCoordinator
    @Environment(BrowserWindowState.self) private var windowState
    @EnvironmentObject var splitManager: SplitViewManager
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @ObservedObject private var sidebarDragState = SidebarDragState.shared
    @State private var hoveredLink: String?
    @State private var isCommandPressed: Bool = false
    
    private let dragCoordinateSpace = "splitPreview"

    private var chromeGeometry: BrowserChromeGeometry {
        BrowserChromeGeometry(settings: sumiSettings)
    }

    private var contentSurfaceBackground: Color {
        themeContext.tokens(settings: sumiSettings).windowBackground
    }

    var body: some View {
        ZStack() {
            Group {
                if browserManager.currentTab(for: windowState) != nil {
                    if splitManager.isSplit(for: windowState.id) == false,
                       browserManager.currentTab(for: windowState)?.representsSumiHistorySurface == true
                    {
                        SumiHistoryTabRootView(
                            browserManager: browserManager,
                            windowState: windowState
                        )
                        .environmentObject(browserManager)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .browserContentSurface(
                            geometry: chromeGeometry,
                            background: contentSurfaceBackground
                        )
                        .allowsHitTesting(true)
                    } else if splitManager.isSplit(for: windowState.id) == false,
                       browserManager.currentTab(for: windowState)?.representsSumiBookmarksSurface == true
                    {
                        SumiBookmarksTabRootView(
                            browserManager: browserManager,
                            windowState: windowState
                        )
                        .environmentObject(browserManager)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .browserContentSurface(
                            geometry: chromeGeometry,
                            background: contentSurfaceBackground
                        )
                        .allowsHitTesting(true)
                    } else if splitManager.isSplit(for: windowState.id) == false,
                       browserManager.currentTab(for: windowState)?.representsSumiSettingsSurface == true
                    {
                        SumiSettingsTabRootView(
                            browserManager: browserManager,
                            windowState: windowState
                        )
                        .environmentObject(browserManager)
                        .environmentObject(browserManager.extensionSurfaceStore)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .browserContentSurface(
                            geometry: chromeGeometry,
                            background: contentSurfaceBackground
                        )
                        .allowsHitTesting(true)
                    } else if splitManager.isSplit(for: windowState.id) == false,
                              browserManager.currentTab(for: windowState)?.representsSumiEmptySurface == true
                    {
                        EmptyWebsiteView()
                    } else {
                        TabCompositorWrapper(
                            browserManager: browserManager,
                            webViewCoordinator: webViewCoordinator,
                            hoveredLink: $hoveredLink,
                            isCommandPressed: $isCommandPressed,
                            splitFraction: splitManager.dividerFraction(for: windowState.id),
                            splitOrientation: splitManager.orientation(for: windowState.id),
                            isSplit: splitManager.isSplit(for: windowState.id),
                            leftId: splitManager.leftTabId(for: windowState.id),
                            rightId: splitManager.rightTabId(for: windowState.id),
                            isSplitDropCaptureActive: sidebarDragState.isDragging && sidebarDragState.isInternalDragSession,
                            chromeGeometry: chromeGeometry,
                            windowState: windowState
                        )
                        .coordinateSpace(name: dragCoordinateSpace)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .browserContentSurface(
                            geometry: chromeGeometry,
                            background: contentSurfaceBackground
                        )
                        .allowsHitTesting(true)
                    }
                    // Removed SwiftUI contextMenu - it intercepts ALL right-clicks
                    // WKWebView's willOpenMenu will handle context menus for images
                } else {
                    EmptyWebsiteView()
                }
            }
            VStack {
                Spacer()
                if sumiSettings.showLinkStatusBar {
                    LinkStatusBar(
                        hoveredLink: hoveredLink,
                        isCommandPressed: isCommandPressed
                    )
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
            }
            .allowsHitTesting(false)
            
            // Split preview overlay - shows cards during drag operations
            if splitManager.getSplitState(for: windowState.id).isPreviewActive {
                SplitPreviewOverlay()
                    .environmentObject(splitManager)
                    .environmentObject(browserManager)
                    .environment(windowState)
                    .coordinateSpace(name: dragCoordinateSpace)
                    .animation(
                        .spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.2),
                        value: splitManager.getSplitState(for: windowState.id).isPreviewActive
                    )
                    .allowsHitTesting(false)
            }
            
        }
        .id(windowState.nativeSurfaceRoutingRevision)
    }

}

private struct BrowserContentSurfaceModifier: ViewModifier {
    let geometry: BrowserChromeGeometry
    let background: Color

    func body(content: Content) -> some View {
        content
            .background(background)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: geometry.contentRadius,
                    style: .continuous
                )
            )
            .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 0)
    }
}

private extension View {
    func browserContentSurface(
        geometry: BrowserChromeGeometry,
        background: Color
    ) -> some View {
        modifier(
            BrowserContentSurfaceModifier(
                geometry: geometry,
                background: background
            )
        )
    }
}

// MARK: - Split Preview Overlay
private struct SplitPreviewOverlay: View {
    @EnvironmentObject var splitManager: SplitViewManager
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.sumiSettings) private var sumiSettings
    
    var body: some View {
        GeometryReader { geometry in
            let splitState = splitManager.getSplitState(for: windowState.id)
            let dragLocation = splitState.dragLocation
            let cardPadding: CGFloat = 20
            let cardWidth: CGFloat = 315
            let cardHeight: CGFloat = 522
            
            HStack(spacing: 0) {
                // Left card - vertically centered with magnetic effect
                VStack {
                    Spacer()
                    MagneticCardView(
                        side: .left,
                        icon: "rectangle.lefthalf.filled",
                        text: "Add left split",
                        dragLocation: dragLocation,
                        cardFrame: CGRect(
                            x: cardPadding,
                            y: (geometry.size.height - cardHeight) / 2,
                            width: cardWidth,
                            height: cardHeight
                        ),
                        geometry: geometry,
                        accentColor: tokens.accent
                    )
                    Spacer()
                }
                .padding(.leading, cardPadding)
                
                Spacer()
                
                // Right card - vertically centered with magnetic effect
                VStack {
                    Spacer()
                    MagneticCardView(
                        side: .right,
                        icon: "rectangle.righthalf.filled",
                        text: "Add right split",
                        dragLocation: dragLocation,
                        cardFrame: CGRect(
                            x: geometry.size.width - cardPadding - cardWidth,
                            y: (geometry.size.height - cardHeight) / 2,
                            width: cardWidth,
                            height: cardHeight
                        ),
                        geometry: geometry,
                        accentColor: tokens.accent
                    )
                    Spacer()
                }
                .padding(.trailing, cardPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false) // Don't intercept mouse events - let drag handling work
        }
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}

// MARK: - Magnetic Card View
private struct MagneticCardView: View {
    let side: SplitViewManager.Side
    let icon: String
    let text: String
    let dragLocation: CGPoint?
    let cardFrame: CGRect
    let geometry: GeometryProxy
    let accentColor: Color
    
    @EnvironmentObject var splitManager: SplitViewManager
    @Environment(BrowserWindowState.self) private var windowState
    
    @State private var offset: CGSize = .zero
    @State private var isMagneticallyActive: Bool = false
    
    // Computed property: card is hovered if previewSide matches OR if magnetically active
    private var cardIsHovered: Bool {
        let splitState = splitManager.getSplitState(for: windowState.id)
        return splitState.previewSide == side || isMagneticallyActive
    }
    
    var body: some View {
        SplitCardView(
            icon: icon,
            text: text,
            isTabHovered: cardIsHovered,
            accentColor: accentColor
        )
        .offset(offset)
        .scaleEffect(1.0) // Cards appear at full size
        .animation(
            dragLocation != nil ? .interactiveSpring(response: 0.3, dampingFraction: 0.7) : .spring(response: 0.4, dampingFraction: 0.6),
            value: offset
        )
        .transition(.asymmetric(
            insertion: .scale(scale: 0.7, anchor: .center),
            removal: .scale(scale: 0.5, anchor: .center).combined(with: .opacity)
        ))
        .onChange(of: dragLocation) { _, location in
            guard let location = location else {
                if isMagneticallyActive {
                    isMagneticallyActive = false
                    offset = .zero
                    // Clear preview side when drag ends
                    splitManager.updatePreviewSide(nil, for: windowState.id)
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                }
                return
            }
            
            // dragLocation is in NSView coordinates (relative to container view, bottom-left origin)
            // cardFrame is in GeometryReader coordinates (top-left origin)
            // Convert NSView Y coordinate to SwiftUI coordinate space
            let geometryHeight = geometry.size.height
            let convertedLocation = CGPoint(x: location.x, y: geometryHeight - location.y)
            
            let cardCenter = CGPoint(x: cardFrame.midX, y: cardFrame.midY)
            
            // Check if drag is within card bounds (with some margin for magnetic effect)
            let margin: CGFloat = 50
            let expandedFrame = cardFrame.insetBy(dx: -margin, dy: -margin)
            
            if expandedFrame.contains(convertedLocation) {
                // Calculate magnetic offset (45% of distance to center)
                let dx = (convertedLocation.x - cardCenter.x) * 0.45
                let dy = (convertedLocation.y - cardCenter.y) * 0.45
                offset = CGSize(width: dx, height: dy)
                
                if !isMagneticallyActive {
                    isMagneticallyActive = true
                    // Update preview side to indicate this card is hovered
                    splitManager.updatePreviewSide(side, for: windowState.id)
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                }
            } else {
                if isMagneticallyActive {
                    isMagneticallyActive = false
                    offset = .zero
                    // Clear preview side when leaving card
                    splitManager.updatePreviewSide(nil, for: windowState.id)
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                }
            }
        }
    }
}

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
    private var commandHoverHandler: ((Bool) -> Void)?

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
        commandHoverHandler: @escaping (Bool) -> Void,
        chromeGeometry: BrowserChromeGeometry
    ) {
        if self.chromeGeometry != chromeGeometry {
            self.chromeGeometry = chromeGeometry
            containerView.setChromeGeometry(chromeGeometry)
        }

        pendingDisplayState = displayState
        self.hoveredLinkHandler = hoveredLinkHandler
        self.commandHoverHandler = commandHoverHandler

        if displayState.currentId == nil {
            hoveredLinkHandler(nil)
            commandHoverHandler(false)
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
            if subview is WKWebView {
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

        if let tab, let host = webViewHost(for: tab) {
            _ = webViewCoordinator.attachHost(host, to: containerView.singlePaneView)
            webViewCoordinator.reconcileHostedSubviews(in: containerView.singlePaneView, keeping: host)
        } else {
            webViewCoordinator.reconcileHostedSubviews(in: containerView.singlePaneView, keeping: nil)
        }

        webViewCoordinator.reconcileHostedSubviews(in: containerView.leftPaneView, keeping: nil)
        webViewCoordinator.reconcileHostedSubviews(in: containerView.rightPaneView, keeping: nil)
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
        webViewCoordinator.reconcileHostedSubviews(in: containerView.singlePaneView, keeping: nil)

        containerView.leftPaneView.isHidden = false
        containerView.rightPaneView.isHidden = false

        if let leftTab, let host = webViewHost(for: leftTab) {
            _ = webViewCoordinator.attachHost(host, to: containerView.leftPaneView)
            webViewCoordinator.reconcileHostedSubviews(in: containerView.leftPaneView, keeping: host)
        } else {
            webViewCoordinator.reconcileHostedSubviews(in: containerView.leftPaneView, keeping: nil)
        }

        if let rightTab, let host = webViewHost(for: rightTab) {
            _ = webViewCoordinator.attachHost(host, to: containerView.rightPaneView)
            webViewCoordinator.reconcileHostedSubviews(in: containerView.rightPaneView, keeping: host)
        } else {
            webViewCoordinator.reconcileHostedSubviews(in: containerView.rightPaneView, keeping: nil)
        }
    }

    private func restoreFocusIfNeeded(for tabId: UUID?) {
        guard webViewCoordinator.hasActiveHistorySwipe(in: windowState.id) == false else { return }
        guard let tabId,
              let window = view.window,
              let host = webViewCoordinator.getWebViewHost(for: tabId, in: windowState.id),
              host.window === window
        else {
            return
        }
        guard window.firstResponder !== host.webView else { return }
        window.makeFirstResponder(host.webView)
    }

    private func setupHoverCallbacks(for tab: Tab) {
        tab.onLinkHover = { [weak self] href in
            DispatchQueue.main.async {
                self?.hoveredLinkHandler?(href)
            }
        }

        tab.onCommandHover = { [weak self] href in
            DispatchQueue.main.async {
                self?.commandHoverHandler?(href != nil)
            }
        }
    }

    private func webViewHost(for tab: Tab) -> SumiWebViewContainerView? {
        webViewCoordinator.getWebViewHost(for: tab.id, in: windowState.id)
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
    @Binding var isCommandPressed: Bool
    var splitFraction: CGFloat
    var splitOrientation: SplitOrientation
    var isSplit: Bool
    var leftId: UUID?
    var rightId: UUID?
    var isSplitDropCaptureActive: Bool
    var chromeGeometry: BrowserChromeGeometry
    let windowState: BrowserWindowState

    func makeNSViewController(context: Context) -> WindowWebContentController {
        WindowWebContentController(
            browserManager: browserManager,
            webViewCoordinator: webViewCoordinator,
            chromeGeometry: chromeGeometry,
            windowState: windowState
        )
    }

    func updateNSViewController(_ controller: WindowWebContentController, context: Context) {
        let hoveredLinkBinding = $hoveredLink
        let commandPressedBinding = $isCommandPressed
        controller.update(
            displayState: makeDisplayState(),
            hoveredLinkHandler: { hoveredLinkBinding.wrappedValue = $0 },
            commandHoverHandler: { commandPressedBinding.wrappedValue = $0 },
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

private enum WebColumnPaintlessChrome {
    static func configure(
        _ view: NSView,
        cornerRadius: CGFloat = 0,
        clipsToBounds: Bool = false
    ) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.isOpaque = false
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = clipsToBounds
    }
}

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
        WebColumnPaintlessChrome.configure(self)
        applyChromeGeometry()

        singlePaneView.identifier = CompositorPaneDestination.single.viewIdentifier
        leftPaneView.identifier = CompositorPaneDestination.left.viewIdentifier
        rightPaneView.identifier = CompositorPaneDestination.right.viewIdentifier

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

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        // Paintless AppKit shell. SwiftUI WindowBackground owns browser chrome fill.
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        WebColumnPaintlessChrome.configure(self)
        applyChromeGeometry()
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
        applyChromeGeometry()
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

    private func applyChromeGeometry() {
        singlePaneView.setChromeGeometry(chromeGeometry)
        leftPaneView.setChromeGeometry(chromeGeometry)
        rightPaneView.setChromeGeometry(chromeGeometry)
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
    private var chromeGeometry = BrowserChromeGeometry()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        applyChromeGeometry()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        // Paintless AppKit pane. The resolved SwiftUI window background shows through gaps.
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyChromeGeometry()
    }

    func setChromeGeometry(_ geometry: BrowserChromeGeometry) {
        guard chromeGeometry != geometry else { return }
        chromeGeometry = geometry
        applyChromeGeometry()
    }

    private func applyChromeGeometry() {
        WebColumnPaintlessChrome.configure(
            self,
            cornerRadius: chromeGeometry.contentRadius,
            clipsToBounds: true
        )
    }
}
