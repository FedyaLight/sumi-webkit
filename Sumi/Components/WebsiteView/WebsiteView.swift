//
//  WebsiteView.swift
//  Sumi
//
//

import AppKit
import SwiftUI

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

@MainActor
struct WebsiteViewBrowserContext {
    let currentTab: (BrowserWindowState) -> Tab?
    let workspaceTheme: (UUID?) -> WorkspaceTheme?
    let makeWebContentContext: () -> any WindowWebContentBrowserContext
}

@MainActor
struct WebsiteNativeSurfaceRootBuilders {
    let history: (BrowserWindowState) -> AnyView
    let bookmarks: (BrowserWindowState) -> AnyView
    let settings: (BrowserWindowState) -> AnyView
}

struct WebsiteView: View {
    @Environment(WebViewCoordinator.self) private var webViewCoordinator
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(KeyboardShortcutManager.self) private var keyboardShortcutManager
    @EnvironmentObject var splitManager: SplitViewManager
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @ObservedObject private var sidebarDragState: SidebarDragState
    @State private var hoveredLink: String?

    private let browserContext: WebsiteViewBrowserContext
    private let nativeSurfaceRootBuilders: WebsiteNativeSurfaceRootBuilders
    private let dragCoordinateSpace = "splitPreview"

    init(
        browserContext: WebsiteViewBrowserContext,
        nativeSurfaceRootBuilders: WebsiteNativeSurfaceRootBuilders,
        sidebarDragState: SidebarDragState
    ) {
        self.browserContext = browserContext
        self.nativeSurfaceRootBuilders = nativeSurfaceRootBuilders
        self._sidebarDragState = ObservedObject(wrappedValue: sidebarDragState)
    }

    private var chromeGeometry: BrowserChromeGeometry {
        BrowserChromeGeometry(settings: sumiSettings)
    }

    private var tabThemeContext: ResolvedThemeContext {
        guard let currentTab = browserContext.currentTab(windowState) else {
            return themeContext
        }
        let tabTheme: WorkspaceTheme
        if let spaceId = currentTab.spaceId,
           let workspaceTheme = browserContext.workspaceTheme(spaceId) {
            tabTheme = workspaceTheme
        } else {
            tabTheme = windowState.workspaceTheme
        }
        return windowState.resolvedThemeContext(
            for: tabTheme,
            global: themeContext.globalColorScheme,
            settings: sumiSettings
        )
    }

    private var browserContentSurfaceBackground: Color {
        tabThemeContext.nativeSurfaceThemeContext.tokens(settings: sumiSettings).windowBackground
    }

    var body: some View {
        let nativeSurfaceKind = activeNativeSurfaceKind

        ZStack {
            tabCompositor
                .allowsHitTesting(nativeSurfaceKind == nil)

            nativeSurface(kind: nativeSurfaceKind)
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

            // Native edge preview for sidebar-to-content split drops.
            SplitPreviewOverlay()
                .environmentObject(splitManager)
                .environment(windowState)
                .coordinateSpace(name: dragCoordinateSpace)
                .allowsHitTesting(false)
        }
    }

    private enum NativeSurfaceKind {
        case history
        case bookmarks
        case settings
        case empty
    }

    private var activeNativeSurfaceKind: NativeSurfaceKind? {
        guard splitManager.isSplit(for: windowState.id) == false else { return nil }
        guard let currentTab = browserContext.currentTab(windowState) else { return .empty }
        if currentTab.representsSumiHistorySurface { return .history }
        if currentTab.representsSumiBookmarksSurface { return .bookmarks }
        if currentTab.representsSumiSettingsSurface { return .settings }
        if currentTab.representsSumiEmptySurface { return .empty }
        return nil
    }

    private var tabCompositor: some View {
        TabCompositorWrapper(
            browserContext: browserContext.makeWebContentContext(),
            webViewCoordinator: webViewCoordinator,
            hoveredLink: $hoveredLink,
            splitGroup: splitManager.splitGroup(for: windowState.id),
            isSplitDropCaptureActive: sidebarDragState.isInternalDragGeometryArmed
                || (sidebarDragState.isDragging && sidebarDragState.isInternalDragSession),
            chromeGeometry: chromeGeometry,
            windowState: windowState,
            contentBackgroundColor: browserContentSurfaceBackground
        )
        .coordinateSpace(name: dragCoordinateSpace)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func nativeSurface(kind: NativeSurfaceKind?) -> some View {
        let currentTabThemeContext = tabThemeContext
        let contentBackground = currentTabThemeContext.nativeSurfaceThemeContext.tokens(settings: sumiSettings).windowBackground

        switch kind {
        case .history:
            nativeSurfaceRootBuilders.history(windowState)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.resolvedThemeContext, currentTabThemeContext)
            .browserContentSurface(
                geometry: chromeGeometry,
                background: contentBackground
            )
            .allowsHitTesting(true)
        case .bookmarks:
            nativeSurfaceRootBuilders.bookmarks(windowState)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.resolvedThemeContext, currentTabThemeContext)
            .browserContentSurface(
                geometry: chromeGeometry,
                background: contentBackground
            )
            .allowsHitTesting(true)
        case .settings:
            nativeSurfaceRootBuilders.settings(windowState)
            .environment(keyboardShortcutManager)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.resolvedThemeContext, currentTabThemeContext)
            .browserContentSurface(
                geometry: chromeGeometry,
                background: contentBackground
            )
            .allowsHitTesting(true)
        case .empty:
            EmptyWebsiteView()
        case nil:
            EmptyView()
        }
    }
}

// MARK: - Split Preview Overlay
private struct SplitPreviewOverlay: View {
    @EnvironmentObject var splitManager: SplitViewManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.sumiSettings) private var sumiSettings
    @State private var renderedZone: SplitPreviewZone?
    @State private var renderedOpacity: Double = 0
    @State private var renderGeneration: UInt = 0
    @State private var fadeOutCleanupTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            let previewState = splitManager.previewState(for: windowState.id)
            let requestedZone = SplitPreviewZone.make(
                previewState: previewState,
                containerHeight: geometry.size.height
            )

            ZStack {
                if let renderedZone {
                    SplitPreviewZoneShape(rect: renderedZone.rect)
                        .fill(previewFill(for: renderedZone.style))
                        .overlay {
                            SplitPreviewZoneShape(rect: renderedZone.rect)
                                .stroke(
                                    previewStroke(for: renderedZone.style),
                                    lineWidth: 1.5
                                )
                        }
                        .opacity(renderedOpacity)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .onAppear {
                syncRenderedZone(to: requestedZone)
            }
            .onChange(of: requestedZone) { _, newZone in
                syncRenderedZone(to: newZone)
            }
        }
        .onDisappear {
            fadeOutCleanupTask?.cancel()
            fadeOutCleanupTask = nil
        }
        .allowsHitTesting(false)
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var previewAnimation: Animation {
        .easeInOut(duration: 0.16)
    }

    private func syncRenderedZone(to requestedZone: SplitPreviewZone?) {
        renderGeneration &+= 1
        let generation = renderGeneration
        fadeOutCleanupTask?.cancel()
        fadeOutCleanupTask = nil
        guard let requestedZone else {
            guard renderedZone != nil else { return }
            withAnimation(previewAnimation) {
                renderedOpacity = 0
            }
            fadeOutCleanupTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard !Task.isCancelled,
                      generation == renderGeneration,
                      renderedOpacity == 0
                else { return }

                renderedZone = nil
                fadeOutCleanupTask = nil
            }
            return
        }

        if renderedZone == nil {
            renderedZone = requestedZone
            renderedOpacity = 0
            DispatchQueue.main.async {
                withAnimation(previewAnimation) {
                    renderedOpacity = 1
                }
            }
            return
        }

        withAnimation(previewAnimation) {
            renderedZone = requestedZone
            renderedOpacity = 1
        }
    }

    private func previewFill(for style: SplitDropPreviewStyle) -> Color {
        switch style {
        case .edge:
            return tokens.floatingBarBackground.opacity(0.65)
        case .center:
            return tokens.floatingBarBackground.opacity(0.65)
        }
    }

    private func previewStroke(for style: SplitDropPreviewStyle) -> Color {
        switch style {
        case .edge:
            return tokens.accent.opacity(0.86)
        case .center:
            return tokens.accent.opacity(0.78)
        }
    }
}

private struct SplitPreviewZone: Equatable {
    let rect: CGRect
    let style: SplitDropPreviewStyle

    static func make(
        previewState: SplitViewManager.WindowSplitPreviewState,
        containerHeight: CGFloat
    ) -> SplitPreviewZone? {
        guard previewState.isActive,
              let targetRect = previewState.targetRect
        else { return nil }

        let swiftUITargetRect = targetRect.convertedFromAppKitCoordinates(
            containerHeight: containerHeight
        )
        return SplitPreviewZone(
            rect: swiftUITargetRect.standardized,
            style: previewState.style
        )
    }
}

private struct SplitPreviewZoneShape: Shape {
    var rect: CGRect

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>> {
        get {
            AnimatablePair(
                rect.origin.x,
                AnimatablePair(
                    rect.origin.y,
                    AnimatablePair(rect.size.width, rect.size.height)
                )
            )
        }
        set {
            rect = CGRect(
                x: newValue.first,
                y: newValue.second.first,
                width: newValue.second.second.first,
                height: newValue.second.second.second
            )
        }
    }

    func path(in _: CGRect) -> Path {
        let insetRect = inset(rect.standardized, by: 8)
        return Path(
            roundedRect: insetRect,
            cornerRadius: min(10, min(insetRect.width, insetRect.height) / 2)
        )
    }

    private func inset(_ rect: CGRect, by amount: CGFloat) -> CGRect {
        let dx = min(amount, max(0, rect.width / 2 - 1))
        let dy = min(amount, max(0, rect.height / 2 - 1))
        return rect.insetBy(dx: dx, dy: dy)
    }
}

private extension CGRect {
    func convertedFromAppKitCoordinates(containerHeight: CGFloat) -> CGRect {
        CGRect(
            x: minX,
            y: containerHeight - maxY,
            width: width,
            height: height
        )
    }
}
