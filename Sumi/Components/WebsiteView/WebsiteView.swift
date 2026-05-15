//
//  WebsiteView.swift
//  Sumi
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI
import AppKit

// MARK: - Status Bar View
struct LinkStatusBar: View {
    let hoveredLink: String?
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
        truncateLink(link)
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
    @Environment(KeyboardShortcutManager.self) private var keyboardShortcutManager
    @EnvironmentObject var splitManager: SplitViewManager
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @ObservedObject private var sidebarDragState = SidebarDragState.shared
    @State private var hoveredLink: String?

    private let dragCoordinateSpace = "splitPreview"

    private var chromeGeometry: BrowserChromeGeometry {
        BrowserChromeGeometry(settings: sumiSettings)
    }

    private var browserContentSurfaceBackground: Color {
        themeContext.nativeSurfaceThemeContext.tokens(settings: sumiSettings).windowBackground
    }

    var body: some View {
        ZStack() {
            tabCompositor
                .allowsHitTesting(nativeSurfaceIsVisible == false)

            nativeSurface
                .id(windowState.nativeSurfaceRoutingRevision)

            VStack {
                Spacer()
                if sumiSettings.showLinkStatusBar {
                    LinkStatusBar(
                        hoveredLink: hoveredLink
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
    }

    private var nativeSurfaceIsVisible: Bool {
        guard splitManager.isSplit(for: windowState.id) == false else { return false }
        guard let currentTab = browserManager.currentTab(for: windowState) else { return true }
        return currentTab.representsSumiHistorySurface
            || currentTab.representsSumiBookmarksSurface
            || currentTab.representsSumiSettingsSurface
            || currentTab.representsSumiEmptySurface
    }

    private var tabCompositor: some View {
        TabCompositorWrapper(
            browserManager: browserManager,
            webViewCoordinator: webViewCoordinator,
            hoveredLink: $hoveredLink,
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
    }

    @ViewBuilder
    private var nativeSurface: some View {
        if let currentTab = browserManager.currentTab(for: windowState) {
            if splitManager.isSplit(for: windowState.id) == false,
               currentTab.representsSumiHistorySurface
            {
                SumiHistoryTabRootView(
                    browserManager: browserManager,
                    windowState: windowState
                )
                .environmentObject(browserManager)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .browserContentSurface(
                    geometry: chromeGeometry,
                    background: browserContentSurfaceBackground
                )
                .allowsHitTesting(true)
            } else if splitManager.isSplit(for: windowState.id) == false,
                      currentTab.representsSumiBookmarksSurface
            {
                SumiBookmarksTabRootView(
                    browserManager: browserManager,
                    windowState: windowState
                )
                .environmentObject(browserManager)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .browserContentSurface(
                    geometry: chromeGeometry,
                    background: browserContentSurfaceBackground
                )
                .allowsHitTesting(true)
            } else if splitManager.isSplit(for: windowState.id) == false,
                      currentTab.representsSumiSettingsSurface
            {
                SumiSettingsTabRootView(
                    browserManager: browserManager,
                    windowState: windowState
                )
                .environmentObject(browserManager)
                .environmentObject(browserManager.extensionSurfaceStore)
                .environment(keyboardShortcutManager)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .browserContentSurface(
                    geometry: chromeGeometry,
                    background: browserContentSurfaceBackground
                )
                .allowsHitTesting(true)
            } else if splitManager.isSplit(for: windowState.id) == false,
                      currentTab.representsSumiEmptySurface
            {
                EmptyWebsiteView()
            }
        } else {
            EmptyWebsiteView()
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
