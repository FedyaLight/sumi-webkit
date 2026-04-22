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
        // Show the view if we have a link to display (current or last shown)
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
                .onChange(of: hoveredLink) {_,  newLink in
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
        } else {
            Color.clear
                .onChange(of: hoveredLink) {_,  newLink in
                    handleHoverChange(newLink: newLink)
                }
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
    @State private var hoveredLink: String?
    @State private var isCommandPressed: Bool = false
    
    private let dragCoordinateSpace = "splitPreview"

    private var cornerRadius: CGFloat {
        if #available(macOS 26.0, *) {
            return 8
        } else {
            return 8
        }
    }

    var body: some View {
        ZStack() {
            Group {
                if browserManager.currentTab(for: windowState) != nil {
                    if splitManager.isSplit(for: windowState.id) == false,
                       browserManager.currentTab(for: windowState)?.representsSumiSettingsSurface == true
                    {
                        SumiSettingsTabRootView(
                            browserManager: browserManager,
                            windowState: windowState
                        )
                        .environmentObject(browserManager)
                        .environmentObject(browserManager.extensionSurfaceStore)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 0)
                        .allowsHitTesting(true)
                    } else if splitManager.isSplit(for: windowState.id) == false,
                              browserManager.currentTab(for: windowState)?.representsSumiEmptySurface == true
                    {
                        EmptyWebsiteView()
                    } else {
                        GeometryReader { _ in
                            TabCompositorWrapper(
                                browserManager: browserManager,
                                webViewCoordinator: webViewCoordinator,
                                hoveredLink: $hoveredLink,
                                isCommandPressed: $isCommandPressed,
                                splitFraction: splitManager.dividerFraction(for: windowState.id),
                                isSplit: splitManager.isSplit(for: windowState.id),
                                leftId: splitManager.leftTabId(for: windowState.id),
                                rightId: splitManager.rightTabId(for: windowState.id),
                                windowState: windowState
                            )
                            .coordinateSpace(name: dragCoordinateSpace)
                            .background(shouldShowSplit ? Color.clear : Color(nsColor: .windowBackgroundColor))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                            .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 0)
                            .allowsHitTesting(true)
                        }
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
                    HStack {
                        LinkStatusBar(
                            hoveredLink: hoveredLink,
                            isCommandPressed: isCommandPressed
                        )
                        .padding(10)
                        Spacer()
                    }
                }
                
            }
            
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
            }
            
        }
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
    let isSplit: Bool
    let leftId: UUID?
    let rightId: UUID?
    let currentId: UUID?
    let compositorVersion: Int
    let currentTabUnloaded: Bool
    let visibleTabIds: Set<UUID>
    let isPreviewActive: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.splitFraction == rhs.splitFraction
            && lhs.isSplit == rhs.isSplit
            && lhs.leftId == rhs.leftId
            && lhs.rightId == rhs.rightId
            && lhs.currentId == rhs.currentId
            && lhs.compositorVersion == rhs.compositorVersion
            && lhs.currentTabUnloaded == rhs.currentTabUnloaded
            && lhs.visibleTabIds == rhs.visibleTabIds
            && lhs.isPreviewActive == rhs.isPreviewActive
    }
}

@MainActor
final class WindowWebContentController: NSViewController {
    private let browserManager: BrowserManager
    private let webViewCoordinator: WebViewCoordinator
    private let windowState: BrowserWindowState
    private lazy var containerView = ContainerView(
        browserManager: browserManager,
        splitManager: browserManager.splitManager,
        windowId: windowState.id
    )

    private var pendingDisplayState: WebsiteDisplayState?
    private var appliedDisplayState: WebsiteDisplayState?
    private var isDisplayStateApplyScheduled = false
    private var lastAppliedSize: CGSize = .zero
    private var lastMeasuredSize: CGSize = .zero
    private var lastHoverTabId: UUID?
    private var pendingSplitRepairKeepSide: SplitViewManager.Side? = nil
    private var hoveredLinkHandler: ((String?) -> Void)?
    private var commandHoverHandler: ((Bool) -> Void)?
    private var accentColor: NSColor = .controlAccentColor

    init(
        browserManager: BrowserManager,
        webViewCoordinator: WebViewCoordinator,
        windowState: BrowserWindowState
    ) {
        self.browserManager = browserManager
        self.webViewCoordinator = webViewCoordinator
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
        let size = view.bounds.size
        guard lastMeasuredSize != size else { return }
        lastMeasuredSize = size

        if webViewCoordinator.hasActiveHistorySwipe(in: windowState.id) {
            browserManager.enqueueWindowMutationDuringHistorySwipe(
                .refreshCompositor,
                for: windowState
            )
            view.layoutSubtreeIfNeeded()
            return
        }

        scheduleDisplayStateApply()
    }

    func update(
        displayState: WebsiteDisplayState,
        accentColor: NSColor,
        hoveredLinkHandler: @escaping (String?) -> Void,
        commandHoverHandler: @escaping (Bool) -> Void
    ) {
        pendingDisplayState = displayState
        self.accentColor = accentColor
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
        let currentSize = containerView.bounds.size
        guard appliedDisplayState != displayState
                || hasStaleSubviews
                || lastAppliedSize != currentSize
        else {
            return
        }

        let previousCurrentId = appliedDisplayState?.currentId
        apply(displayState: displayState, currentTab: currentTab)
        appliedDisplayState = displayState
        lastAppliedSize = currentSize

        if previousCurrentId != displayState.currentId {
            restoreFocusIfNeeded(for: displayState.currentId)
        }
    }

    private func apply(displayState: WebsiteDisplayState, currentTab: Tab?) {
        let splitManager = browserManager.splitManager
        containerView.configureOverlay(
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

            let gap: CGFloat = 8
            let fraction = max(
                splitManager.minFraction,
                min(splitManager.maxFraction, displayState.splitFraction)
            )
            let total = containerView.bounds
            let orientation = splitManager.orientation(for: windowState.id)
            let leftRect: NSRect
            let rightRect: NSRect
            if orientation == .horizontal {
                let leftWidthRaw = floor(total.width * fraction)
                let rightWidthRaw = max(0, total.width - leftWidthRaw)
                leftRect = NSRect(
                    x: total.minX,
                    y: total.minY,
                    width: max(1, leftWidthRaw - gap / 2),
                    height: total.height
                )
                rightRect = NSRect(
                    x: total.minX + leftWidthRaw + gap / 2,
                    y: total.minY,
                    width: max(1, rightWidthRaw - gap / 2),
                    height: total.height
                )
            } else {
                let topHeightRaw = floor(total.height * fraction)
                let bottomHeightRaw = max(0, total.height - topHeightRaw)
                leftRect = NSRect(
                    x: total.minX,
                    y: total.maxY - topHeightRaw,
                    width: total.width,
                    height: max(1, topHeightRaw - gap / 2)
                )
                rightRect = NSRect(
                    x: total.minX,
                    y: total.minY,
                    width: total.width,
                    height: max(1, bottomHeightRaw - gap / 2)
                )
            }

            showSplitPanes(
                leftTab: leftTab,
                rightTab: rightTab,
                leftRect: leftRect,
                rightRect: rightRect,
                activeSide: splitManager.activeSide(for: windowState.id) ?? .left,
                accent: accentColor,
                orientation: orientation
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
        containerView.singlePaneView.frame = containerView.bounds
        containerView.singlePaneView.isHidden = false
        containerView.leftPaneView.isHidden = true
        containerView.rightPaneView.isHidden = true
        configurePaneContainer(
            containerView.leftPaneView,
            frame: .zero,
            isActive: false,
            accent: .clear,
            side: .left,
            orientation: .horizontal
        )
        configurePaneContainer(
            containerView.rightPaneView,
            frame: .zero,
            isActive: false,
            accent: .clear,
            side: .right,
            orientation: .horizontal
        )

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
        leftRect: NSRect,
        rightRect: NSRect,
        activeSide: SplitViewManager.Side,
        accent: NSColor,
        orientation: SplitOrientation
    ) {
        containerView.singlePaneView.isHidden = true
        webViewCoordinator.reconcileHostedSubviews(in: containerView.singlePaneView, keeping: nil)

        containerView.leftPaneView.isHidden = false
        containerView.rightPaneView.isHidden = false
        configurePaneContainer(
            containerView.leftPaneView,
            frame: leftRect,
            isActive: activeSide == .left,
            accent: accent,
            side: .left,
            orientation: orientation
        )
        configurePaneContainer(
            containerView.rightPaneView,
            frame: rightRect,
            isActive: activeSide == .right,
            accent: accent,
            side: .right,
            orientation: orientation
        )

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

    private func configurePaneContainer(
        _ pane: NSView,
        frame: NSRect,
        isActive: Bool,
        accent: NSColor,
        side: SplitViewManager.Side,
        orientation: SplitOrientation
    ) {
        let cornerRadius: CGFloat = 8
        if let pane = pane as? PaneContainerView {
            pane.applyLayout(
                frame: frame,
                isActive: isActive,
                accent: accent,
                side: side,
                orientation: orientation,
                cornerRadius: cornerRadius,
                pathBuilder: createUnevenRoundedRectPath
            )
            return
        }

        pane.frame = frame
        pane.autoresizingMask = []
    }

    private func createUnevenRoundedRectPath(
        rect: CGRect,
        topLeadingRadius: CGFloat,
        bottomLeadingRadius: CGFloat,
        bottomTrailingRadius: CGFloat,
        topTrailingRadius: CGFloat
    ) -> CGPath {
        let path = CGMutablePath()

        let minX = rect.minX
        let minY = rect.minY
        let maxX = rect.maxX
        let maxY = rect.maxY

        path.move(to: CGPoint(x: minX + topLeadingRadius, y: maxY))
        path.addLine(to: CGPoint(x: maxX - topTrailingRadius, y: maxY))
        if topTrailingRadius > 0 {
            path.addArc(
                tangent1End: CGPoint(x: maxX, y: maxY),
                tangent2End: CGPoint(x: maxX, y: maxY - topTrailingRadius),
                radius: topTrailingRadius
            )
        }

        path.addLine(to: CGPoint(x: maxX, y: minY + bottomTrailingRadius))
        if bottomTrailingRadius > 0 {
            path.addArc(
                tangent1End: CGPoint(x: maxX, y: minY),
                tangent2End: CGPoint(x: maxX - bottomTrailingRadius, y: minY),
                radius: bottomTrailingRadius
            )
        }

        path.addLine(to: CGPoint(x: minX + bottomLeadingRadius, y: minY))
        if bottomLeadingRadius > 0 {
            path.addArc(
                tangent1End: CGPoint(x: minX, y: minY),
                tangent2End: CGPoint(x: minX, y: minY + bottomLeadingRadius),
                radius: bottomLeadingRadius
            )
        }

        path.addLine(to: CGPoint(x: minX, y: maxY - topLeadingRadius))
        if topLeadingRadius > 0 {
            path.addArc(
                tangent1End: CGPoint(x: minX, y: maxY),
                tangent2End: CGPoint(x: minX + topLeadingRadius, y: maxY),
                radius: topLeadingRadius
            )
        }

        path.closeSubpath()
        return path
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
               (tab.representsSumiSettingsSurface || tab.representsSumiEmptySurface)
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
    var isSplit: Bool
    var leftId: UUID?
    var rightId: UUID?
    let windowState: BrowserWindowState
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.sumiSettings) private var sumiSettings

    func makeNSViewController(context: Context) -> WindowWebContentController {
        WindowWebContentController(
            browserManager: browserManager,
            webViewCoordinator: webViewCoordinator,
            windowState: windowState
        )
    }

    func updateNSViewController(_ controller: WindowWebContentController, context: Context) {
        let hoveredLinkBinding = $hoveredLink
        let commandPressedBinding = $isCommandPressed
        controller.update(
            displayState: makeDisplayState(),
            accentColor: NSColor(tokens.accent),
            hoveredLinkHandler: { hoveredLinkBinding.wrappedValue = $0 },
            commandHoverHandler: { commandPressedBinding.wrappedValue = $0 }
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

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private func makeDisplayState() -> WebsiteDisplayState {
        let currentTab = browserManager.currentTab(for: windowState)
        let currentId = currentTab?.id
        return WebsiteDisplayState(
            splitFraction: splitFraction,
            isSplit: isSplit,
            leftId: leftId,
            rightId: rightId,
            currentId: currentId,
            compositorVersion: windowState.compositorVersion,
            currentTabUnloaded: currentTab?.isUnloaded ?? true,
            visibleTabIds: visibleTabIds(currentId: currentId),
            isPreviewActive: browserManager.splitManager.getSplitState(for: windowState.id).isPreviewActive
        )
    }
}

// MARK: - WebsiteView Extensions

private extension WebsiteView {
    var shouldShowSplit: Bool {
        guard splitManager.isSplit(for: windowState.id) else { return false }
        guard let current = browserManager.currentTab(for: windowState)?.id else { return false }
        return current == splitManager.leftTabId(for: windowState.id) || current == splitManager.rightTabId(for: windowState.id)
    }
}

// MARK: - Container View that forwards right-clicks to webviews

private class ContainerView: NSView {
    let singlePaneView = NSView()
    let leftPaneView = PaneContainerView()
    let rightPaneView = PaneContainerView()
    let overlayView = SplitDropCaptureView(frame: .zero)

    init(browserManager: BrowserManager, splitManager: SplitViewManager, windowId: UUID) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        singlePaneView.identifier = CompositorPaneDestination.single.viewIdentifier
        leftPaneView.identifier = CompositorPaneDestination.left.viewIdentifier
        rightPaneView.identifier = CompositorPaneDestination.right.viewIdentifier
        singlePaneView.autoresizingMask = [.width, .height]
        leftPaneView.wantsLayer = true
        rightPaneView.wantsLayer = true

        addSubview(singlePaneView)
        addSubview(leftPaneView)
        addSubview(rightPaneView)

        overlayView.autoresizingMask = [.width, .height]
        overlayView.layer?.zPosition = 10_000
        addSubview(overlayView)

        configureOverlay(
            browserManager: browserManager,
            splitManager: splitManager,
            windowId: windowId
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureOverlay(
        browserManager: BrowserManager,
        splitManager: SplitViewManager,
        windowId: UUID
    ) {
        overlayView.frame = bounds
        overlayView.browserManager = browserManager
        overlayView.splitManager = splitManager
        overlayView.windowId = windowId
    }

    // Don't intercept events - let them pass through to webviews
    override var acceptsFirstResponder: Bool { false }

    override func resetCursorRects() {
        // Empty: prevents NSHostingView and other ancestors from registering
        // arrow cursor rects over the webview. WKWebView uses NSCursor.set()
        // internally, which works correctly when cursor rects don't override it.
    }

    // Forward right-clicks to the webview below so context menus work
    override func rightMouseDown(with event: NSEvent) {
        // Find the webview at this point and forward the event
        let point = convert(event.locationInWindow, from: nil)
        // Use hitTest to find the actual view at this point (will skip overlay if hitTest returns nil)
        if let hitView = hitTest(point) {
            if let webView = hitView as? WKWebView {
                webView.rightMouseDown(with: event)
                return
            }
            // Check if hitView contains a webview
            if let webView = findWebView(in: hitView, at: point) {
                webView.rightMouseDown(with: event)
                return
            }
        }
        // Defensive: `hitTest` can miss when overlay ordering changes; scan subviews for a WKWebView.
        for subview in subviews.reversed() {
            if let webView = findWebView(in: subview, at: point) {
                webView.rightMouseDown(with: event)
                return
            }
        }
        super.rightMouseDown(with: event)
    }
    
    private func findWebView(in view: NSView, at point: NSPoint) -> WKWebView? {
        let pointInView = view.convert(point, from: self)
        if view.bounds.contains(pointInView) {
            if let webView = view as? WKWebView {
                return webView
            }
            for subview in view.subviews {
                if let webView = findWebView(in: subview, at: point) {
                    return webView
                }
            }
        }
        return nil
    }
}

private final class PaneContainerView: NSView {
    private let maskShapeLayer = CAShapeLayer()
    private let borderShapeLayer = CAShapeLayer()
    private var lastBounds: CGRect = .zero
    private var lastIsActive = false
    private var lastAccent = NSColor.clear
    private var lastSide: SplitViewManager.Side = .left
    private var lastOrientation: SplitOrientation = .horizontal
    private var lastCornerRadius: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.mask = maskShapeLayer
        borderShapeLayer.fillColor = NSColor.clear.cgColor
        borderShapeLayer.lineWidth = 1.0
        layer?.addSublayer(borderShapeLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyLayout(
        frame: NSRect,
        isActive: Bool,
        accent: NSColor,
        side: SplitViewManager.Side,
        orientation: SplitOrientation,
        cornerRadius: CGFloat,
        pathBuilder: (
            _ rect: CGRect,
            _ topLeadingRadius: CGFloat,
            _ bottomLeadingRadius: CGFloat,
            _ bottomTrailingRadius: CGFloat,
            _ topTrailingRadius: CGFloat
        ) -> CGPath
    ) {
        self.frame = frame
        autoresizingMask = []

        let needsPathUpdate =
            bounds != lastBounds ||
            side != lastSide ||
            orientation != lastOrientation ||
            abs(cornerRadius - lastCornerRadius) > 0.0001
        let needsStyleUpdate =
            isActive != lastIsActive ||
            accent.isEqual(lastAccent) == false ||
            needsPathUpdate

        if needsPathUpdate {
            let path = pathBuilder(
                bounds,
                orientation == .horizontal ? (side == .left ? 0 : cornerRadius) : (side == .left ? 0 : cornerRadius),
                orientation == .horizontal ? cornerRadius : (side == .left ? cornerRadius : 0),
                orientation == .horizontal ? cornerRadius : (side == .left ? cornerRadius : 0),
                orientation == .horizontal ? (side == .right ? 0 : cornerRadius) : (side == .left ? 0 : cornerRadius)
            )
            maskShapeLayer.path = path
            borderShapeLayer.path = path
            lastBounds = bounds
            lastSide = side
            lastOrientation = orientation
            lastCornerRadius = cornerRadius
        }

        if needsStyleUpdate {
            borderShapeLayer.strokeColor = isActive
                ? accent.withAlphaComponent(0.9).cgColor
                : NSColor.clear.cgColor
            lastIsActive = isActive
            lastAccent = accent
        }
    }
}
