//
//  WindowView.swift
//  Sumi
//
//  Created by Maciek Bagiński on 30/07/2025.
//  Updated by Aether Aurelia on 15/11/2025.
//

import AppKit
import SwiftUI

/// Relative stacking for full-window transient chrome (higher draws above lower).
private enum WindowTransientChromeZIndex {
    static let commandPalette: Double = 9_000
    /// Glance preview: above palette, below blocking dialogs.
    static let peek: Double = 10_000
    /// Modal dialogs (quit, settings paths, etc.) must stay above app chrome.
    static let dialog: Double = 11_000
    /// Drag ghost only.
    static let sidebarDragPreview: Double = 20_000
}

/// Main window view that orchestrates the browser UI layout
struct WindowView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject private var peekManager: PeekManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(CommandPalette.self) private var commandPalette
    @Environment(\.sumiSettings) var sumiSettings
    @StateObject private var hoverSidebarManager = HoverSidebarManager()
    @ObservedObject private var sidebarDragState = SidebarDragState.shared
    /// Bumps when system/window effective appearance changes so `globalColorScheme` refreshes while in auto mode.
    @State private var effectiveAppearanceRevision: UInt = 0

    var body: some View {
        ZStack {
            chromeThemeScope {
                WindowBackground()
            }
            .sumiAppKitContextMenu(entries: {
                [
                    .action(
                        SidebarContextMenuAction(
                            title: "Customize Space Gradient...",
                            systemImage: "paintpalette",
                            isEnabled: browserManager.tabManager.currentSpace != nil,
                            classification: .presentationOnly,
                            action: {
                            browserManager.showGradientEditor(
                                source: windowState.resolveSidebarPresentationSource()
                            )
                            }
                        )
                    )
                ]
            })

            SidebarWebViewStack()

            // Collapsed hover-reveal sidebar overlay. Docked sidebar is a real layout column.
            if !windowState.isSidebarVisible {
                chromeThemeScope {
                    SidebarHoverOverlayView()
                        .environmentObject(hoverSidebarManager)
                        .environment(windowState)
                }
            }

            chromeThemeScope {
                CommandPaletteView()
                    .zIndex(WindowTransientChromeZIndex.commandPalette)
            }
            chromeThemeScope {
                DialogView()
                    .zIndex(WindowTransientChromeZIndex.dialog)
            }

            // Peek overlay for external link previews
            if peekManager.isActive || peekManager.currentSession != nil {
                chromeThemeScope {
                    PeekOverlayView()
                        .zIndex(WindowTransientChromeZIndex.peek)
                }
            }

            if SidebarDragVisualSurfacePolicy.shouldRenderParentWindowFloatingPreview(
                isSidebarVisible: windowState.isSidebarVisible,
                isCollapsedOverlayRevealed: sidebarHoverOverlayRevealed
            ) {
                chromeThemeScope {
                    SidebarFloatingDragPreview()
                        .environmentObject(browserManager)
                        .environment(windowState)
                        .environment(\.sumiSettings, sumiSettings)
                        .zIndex(WindowTransientChromeZIndex.sidebarDragPreview)
                        .allowsHitTesting(false)
                }
            }

        }
        // System notification toasts - top trailing corner
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 8) {
                // Profile switch toast
                if windowState.isShowingProfileSwitchToast,
                   let toast = windowState.profileSwitchToast
                {
                    chromeThemeScope {
                        ProfileSwitchToastView(toast: toast)
                            .environment(windowState)
                            .environmentObject(browserManager)
                    }
                }

                // Tab closure toast
                if browserManager.showTabClosureToast && browserManager.tabClosureToastCount > 0 {
                    chromeThemeScope {
                        TabClosureToast()
                            .environmentObject(browserManager)
                    }
                }

                // Copy URL toast
                if windowState.isShowingCopyURLToast {
                    chromeThemeScope {
                        CopyURLToast()
                            .environment(windowState)
                    }
                }
            }
            .padding(10)
            // Animate toast insertions/removals
            .animation(.smooth(duration: 0.25), value: windowState.isShowingProfileSwitchToast)
            .animation(.smooth(duration: 0.25), value: browserManager.showTabClosureToast)
            .animation(.smooth(duration: 0.25), value: windowState.isShowingCopyURLToast)
        }
        // Lifecycle management
        .onAppear {
            hoverSidebarManager.sidebarPosition = sumiSettings.sidebarPosition
            hoverSidebarManager.attach(browserManager: browserManager, windowState: windowState)
            hoverSidebarManager.windowRegistry = windowRegistry
            hoverSidebarManager.start()
        }
        .onChange(of: windowState.isSidebarVisible) { _, _ in
            Task { @MainActor in
                hoverSidebarManager.refreshMonitoring()
            }
        }
        .onChange(of: windowRegistry.activeWindowId) { _, _ in
            Task { @MainActor in
                hoverSidebarManager.refreshMonitoring()
            }
        }
        .onChange(of: sumiSettings.sidebarPosition) { _, newPosition in
            Task { @MainActor in
                hoverSidebarManager.sidebarPosition = newPosition
                hoverSidebarManager.refreshMonitoring()
            }
        }
        .onDisappear {
            hoverSidebarManager.stop()
        }
        .environmentObject(browserManager)
        .environmentObject(browserManager.splitManager)
        .environmentObject(hoverSidebarManager)
        .environment(\.resolvedThemeContext, resolvedThemeContext)
        .coordinateSpace(name: "WindowSpace")
        .onPreferenceChange(URLBarFramePreferenceKey.self) { frame in
            Task { @MainActor in
                windowState.urlBarFrame = frame
            }
        }
        .onChange(of: sumiSettings.windowSchemeMode) { _, _ in
            Task { @MainActor in
                effectiveAppearanceRevision &+= 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sumiApplicationDidChangeEffectiveAppearance)) { _ in
            Task { @MainActor in
                effectiveAppearanceRevision &+= 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sumiWindowDidChangeEffectiveAppearance)) { notification in
            guard let window = notification.object as? NSWindow,
                  window === windowState.window
            else { return }
            Task { @MainActor in
                effectiveAppearanceRevision &+= 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sumiShouldHideCollapsedSidebarOverlay)) { _ in
            hoverSidebarManager.setOverlayVisibility(
                false,
                animationDuration: SidebarHoverOverlayMetrics.revealAnimationDuration
            )
        }
        // Keep Sumi's theme override inside SwiftUI so AppKit chrome stays stable while custom
        // sidebar chrome resolves its appearance from SwiftUI state.
        .environment(\.colorScheme, globalColorScheme)
    }

    // MARK: - Layout Components

    private var sidebarHoverOverlayRevealed: Bool {
        SidebarHoverOverlayRevealPolicy.isOverlayRevealed(
            isOverlayVisible: hoverSidebarManager.isOverlayVisible,
            transientUIPinsHoverSidebar: transientUIPinsHoverSidebar,
            sidebarDragPinsHoverSidebar: sidebarDragPinsHoverSidebar
        )
    }

    private var transientUIPinsHoverSidebar: Bool {
        SidebarHoverOverlayTransientPinningPolicy.shouldPinHoverSidebar(
            transientWindowID: windowState.sidebarTransientSessionCoordinator.currentPresentationWindowID,
            currentWindowID: windowState.id,
            isSidebarVisible: windowState.isSidebarVisible
        )
    }

    private var sidebarDragPinsHoverSidebar: Bool {
        SidebarHoverOverlayDragPinningPolicy.shouldPinHoverSidebar(
            activeWindowID: windowRegistry.activeWindowId,
            currentWindowID: windowState.id,
            isSidebarVisible: windowState.isSidebarVisible,
            isDragging: sidebarDragState.isDragging,
            isInternalDragSession: sidebarDragState.isInternalDragSession
        )
    }

    @ViewBuilder
    private func WindowBackground() -> some View {
        SpaceGradientBackgroundView(surface: .toolbarChrome)
        .backgroundDraggable()
        .environment(windowState)
    }

    @ViewBuilder
    private func SidebarWebViewStack() -> some View {
        let sidebarVisible = windowState.isSidebarVisible
        let elementSeparation = BrowserChromeGeometry.elementSeparation
        let sidebarPosition = sumiSettings.sidebarPosition
        let shellEdge = sidebarPosition.shellEdge
        
        HStack(spacing: 0) {
            if sidebarVisible && shellEdge.isLeft {
                SidebarDockedColumn(sidebarPosition: sidebarPosition)
            }

            WebContent()

            if sidebarVisible && shellEdge.isRight {
                SidebarDockedColumn(sidebarPosition: sidebarPosition)
            }
        }
        .padding(.leading, sidebarVisible && shellEdge.isLeft ? 0 : elementSeparation)
        .padding(.trailing, sidebarVisible && shellEdge.isRight ? 0 : elementSeparation)
    }

    @ViewBuilder
    private func SidebarDockedColumn(sidebarPosition: SidebarPosition) -> some View {
        let presentationContext = SidebarPresentationContext.docked(
            sidebarWidth: windowState.sidebarWidth,
            sidebarPosition: sidebarPosition
        )

        SidebarColumnRepresentable(
            browserManager: browserManager,
            windowState: windowState,
            windowRegistry: windowRegistry,
            commandPalette: commandPalette,
            sumiSettings: sumiSettings,
            resolvedThemeContext: resolvedThemeContext,
            presentationContext: presentationContext
        )
        .id("docked-sidebar-column")
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
        .frame(width: presentationContext.sidebarWidth)
        .frame(maxHeight: .infinity)
        .alwaysArrowCursor()
    }

    @ViewBuilder
    private func WebContent() -> some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                WebsiteLoadingIndicator()
                    .zIndex(3000)
                
                WebsiteView()
                    .zIndex(2000)
            }

            // Find-in-page lives only over the web column so it never intercepts sidebar hover/clicks.
            chromeThemeScope {
                FindInPageChromeHitTestingWrapper(
                    findManager: browserManager.findManager,
                    windowStateID: windowState.id,
                    themeContext: resolvedThemeContext
                )
                .environmentObject(browserManager)
                .zIndex(3500)
            }
        }
        .padding(.bottom, BrowserChromeGeometry.elementSeparation)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appKitGlobalAppearance: NSAppearance {
        windowState.window?.effectiveAppearance ?? NSApplication.shared.effectiveAppearance
    }

    private var globalColorScheme: ColorScheme {
        switch sumiSettings.windowSchemeMode {
        case .auto:
            let _ = effectiveAppearanceRevision
            return ColorScheme(effectiveAppearance: appKitGlobalAppearance)
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private var resolvedThemeContext: ResolvedThemeContext {
        windowState.resolvedThemeContext(
            global: globalColorScheme,
            settings: sumiSettings
        )
    }

    @ViewBuilder
    private func chromeThemeScope<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        content()
            .environment(\.resolvedThemeContext, resolvedThemeContext)
    }
}

private extension ColorScheme {
    /// Resolves AppKit effective appearance to SwiftUI for window-scheme **auto** (follow system).
    init(effectiveAppearance appearance: NSAppearance) {
        let best = appearance.bestMatch(from: [.darkAqua, .aqua])
        self = best == .darkAqua ? .dark : .light
    }
}

// MARK: - Profile Switch Toast View
private struct ProfileSwitchToastView: View {
    let toast: BrowserManager.ProfileSwitchToast
    @Environment(BrowserWindowState.self) private var windowState
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        ToastView {
            ToastContent(icon: "person.crop.circle", text: "Switched to \(toast.toProfile.name)")
        }
        .transition(.toast)
        .onAppear {
            // Auto-dismiss after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                browserManager.hideProfileSwitchToast(for: windowState)
            }
        }
        .onTapGesture {
            browserManager.hideProfileSwitchToast(for: windowState)
        }
    }
}
