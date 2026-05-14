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
    static let findInPage: Double = 3_500
    static let commandPalette: Double = 9_000
    /// Glance preview: above palette, below blocking dialogs.
    static let glance: Double = 10_000
    /// Modal dialogs (quit, settings paths, etc.) must stay above app chrome.
    static let dialog: Double = 11_000
    /// Drag ghost only.
    static let sidebarDragPreview: Double = 20_000
}

/// Main window view that orchestrates the browser UI layout
struct WindowView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(CommandPalette.self) private var commandPalette
    @Environment(\.sumiSettings) var sumiSettings
    @StateObject private var hoverSidebarManager = HoverSidebarManager()
    @State private var shouldRenderDockedSidebar = false
    @State private var dockedSidebarLayoutProgress: CGFloat = 0
    @State private var dockedSidebarLayoutGeneration: UInt64 = 0
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
            if shouldRenderCollapsedSidebarOverlay {
                chromeThemeScope {
                    SidebarHoverOverlayView(
                        resolvedThemeContext: sidebarResolvedThemeContext,
                        chromeBackgroundResolvedThemeContext: resolvedThemeContext
                    )
                        .environmentObject(hoverSidebarManager)
                        .environment(windowState)
                }
            }

            // Command palette is full-window chrome so its floating position is stable in both
            // docked and collapsed sidebar layouts.
            chromeThemeScope {
                CommandPaletteChromeHost(
                    browserManager: browserManager,
                    windowState: windowState,
                    commandPalette: commandPalette,
                    sumiSettings: sumiSettings,
                    resolvedThemeContext: resolvedThemeContext,
                    colorScheme: globalColorScheme,
                    isPresented: windowState.isCommandPaletteVisible && !transientChromeModalSuppressed
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(WindowTransientChromeZIndex.commandPalette)
            }

            chromeThemeScope {
                DialogView()
                    .zIndex(WindowTransientChromeZIndex.dialog)
            }

            // Glance overlay for external link previews
            if browserManager.glanceManager.isActive || browserManager.glanceManager.currentSession != nil {
                chromeThemeScope {
                    GlanceOverlayView()
                        .environmentObject(browserManager.glanceManager)
                        .zIndex(WindowTransientChromeZIndex.glance)
                }
            }

            chromeThemeScope {
                SidebarFloatingDragPreview()
                    .environmentObject(browserManager)
                    .environment(windowState)
                    .environment(\.sumiSettings, sumiSettings)
                    .zIndex(WindowTransientChromeZIndex.sidebarDragPreview)
                    .allowsHitTesting(false)
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
            windowState.window?.hideNativeStandardWindowButtonsForBrowserChrome()
            syncDockedSidebarLayout(isVisible: windowState.isSidebarVisible, animated: false)
            hoverSidebarManager.sidebarPosition = sumiSettings.sidebarPosition
            hoverSidebarManager.attach(browserManager: browserManager, windowState: windowState)
            hoverSidebarManager.windowRegistry = windowRegistry
            hoverSidebarManager.start()
            revealCollapsedSidebarForPinnedTransientIfNeeded()
        }
        .onChange(of: windowState.isSidebarVisible) { _, isVisible in
            syncDockedSidebarLayout(isVisible: isVisible, animated: true)
            Task { @MainActor in
                await Task.yield()
                windowState.window?.hideNativeStandardWindowButtonsForBrowserChrome()
                hoverSidebarManager.refreshMonitoring()
                revealCollapsedSidebarForPinnedTransientIfNeeded()
            }
        }
        .onChange(of: windowRegistry.activeWindowId) { _, _ in
            Task { @MainActor in
                hoverSidebarManager.refreshMonitoring()
                revealCollapsedSidebarForPinnedTransientIfNeeded()
            }
        }
        .onChange(of: windowState.sidebarInteractionState.freezesSidebarHoverState) { _, _ in
            revealCollapsedSidebarForPinnedTransientIfNeeded()
        }
        .onChange(of: sumiSettings.sidebarPosition) { _, newPosition in
            Task { @MainActor in
                hoverSidebarManager.sidebarPosition = newPosition
                hoverSidebarManager.refreshMonitoring()
                revealCollapsedSidebarForPinnedTransientIfNeeded()
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
                await Task.yield()
                guard windowState.urlBarFrame != frame else { return }
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
        .onReceive(NotificationCenter.default.publisher(for: .sumiMemoryPressureReceived)) { _ in
            hoverSidebarManager.releaseOverlayHostForMemoryPressure()
        }
        // Keep Sumi's theme override inside SwiftUI so AppKit chrome stays stable while custom
        // sidebar chrome resolves its appearance from SwiftUI state.
        .environment(\.colorScheme, globalColorScheme)
    }

    private var shouldRenderCollapsedSidebarOverlay: Bool {
        !windowState.isSidebarVisible && !shouldRenderDockedSidebar
    }

    // MARK: - Layout Components

    private func revealCollapsedSidebarForPinnedTransientIfNeeded() {
        guard !windowState.isSidebarVisible,
              windowRegistry.activeWindowId == windowState.id,
              windowState.sidebarInteractionState.freezesSidebarHoverState,
              windowState.sidebarTransientSessionCoordinator.hasPinnedTransientUI(for: windowState.id)
        else {
            return
        }

        hoverSidebarManager.requestOverlayReveal(
            animationDuration: SidebarHoverOverlayMetrics.revealAnimationDuration
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
        let rendersDockedSidebar = sidebarVisible || shouldRenderDockedSidebar
        let layoutProgress = sidebarVisible && !shouldRenderDockedSidebar && dockedSidebarLayoutProgress == 0
            ? 1
            : dockedSidebarLayoutProgress
        let leftLayoutProgress = rendersDockedSidebar && shellEdge.isLeft ? layoutProgress : 0
        let rightLayoutProgress = rendersDockedSidebar && shellEdge.isRight ? layoutProgress : 0
        
        HStack(spacing: 0) {
            if rendersDockedSidebar && shellEdge.isLeft {
                SidebarDockedColumn(
                    sidebarPosition: sidebarPosition,
                    layoutProgress: layoutProgress
                )
            }

            WebContent()

            if rendersDockedSidebar && shellEdge.isRight {
                SidebarDockedColumn(
                    sidebarPosition: sidebarPosition,
                    layoutProgress: layoutProgress
                )
            }
        }
        .padding(.leading, elementSeparation * (1 - leftLayoutProgress))
        .padding(.trailing, elementSeparation * (1 - rightLayoutProgress))
    }

    @ViewBuilder
    private func SidebarDockedColumn(sidebarPosition: SidebarPosition, layoutProgress: CGFloat) -> some View {
        let presentationContext = SidebarPresentationContext.docked(
            sidebarWidth: windowState.sidebarWidth,
            sidebarPosition: sidebarPosition
        )
        let layoutWidth = presentationContext.sidebarWidth * layoutProgress

        SidebarColumnRepresentable(
            browserManager: browserManager,
            windowState: windowState,
            windowRegistry: windowRegistry,
            commandPalette: commandPalette,
            sumiSettings: sumiSettings,
            resolvedThemeContext: sidebarResolvedThemeContext,
            chromeBackgroundResolvedThemeContext: resolvedThemeContext,
            presentationContext: presentationContext
        )
        .id("docked-sidebar-column")
        .frame(width: presentationContext.sidebarWidth)
        .frame(maxHeight: .infinity)
        .opacity(min(max(layoutProgress * 2, 0), 1))
        .frame(width: max(layoutWidth, 0), alignment: presentationContext.shellEdge.overlayAlignment)
        .clipped()
        .alwaysArrowCursor()
    }

    private func syncDockedSidebarLayout(isVisible: Bool, animated: Bool) {
        dockedSidebarLayoutGeneration &+= 1
        let generation = dockedSidebarLayoutGeneration
        let animation = CollapsedSidebarOverlayAnimation.dockedLayoutAnimation(isShowing: isVisible)

        if isVisible {
            shouldRenderDockedSidebar = true
            if animated {
                withAnimation(animation) {
                    dockedSidebarLayoutProgress = 1
                }
            } else {
                dockedSidebarLayoutProgress = 1
            }
            return
        }

        if animated {
            shouldRenderDockedSidebar = true
            let startingProgress = dockedSidebarLayoutProgress
            if startingProgress <= 0 {
                dockedSidebarLayoutProgress = 1
            }

            withAnimation(animation) {
                dockedSidebarLayoutProgress = 0
            }

            Task { @MainActor in
                try? await Task.sleep(
                    nanoseconds: UInt64(CollapsedSidebarOverlayAnimation.dockedLayoutUnmountDelay * 1_000_000_000)
                )
                guard generation == dockedSidebarLayoutGeneration,
                      !windowState.isSidebarVisible
                else { return }
                shouldRenderDockedSidebar = false
            }
        } else {
            dockedSidebarLayoutProgress = 0
            shouldRenderDockedSidebar = false
        }
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

            // Find-in-page stays in the browser window's responder chain so window controls keep active appearance.
            FindInPageChromeHost(
                browserManager: browserManager,
                findManager: browserManager.findManager,
                windowRegistry: windowRegistry,
                windowState: windowState,
                sumiSettings: sumiSettings,
                resolvedThemeContext: resolvedThemeContext,
                colorScheme: globalColorScheme
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .zIndex(WindowTransientChromeZIndex.findInPage)
        }
        .padding(.bottom, BrowserChromeGeometry.elementSeparation)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transientChromeModalSuppressed: Bool {
        browserManager.dialogManager.isPresented(in: windowState.window)
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

    private var sidebarResolvedThemeContext: ResolvedThemeContext {
        let context = resolvedThemeContext
        guard windowState.isInteractiveSpaceTransition else {
            return context
        }

        let frozenTheme = windowState.previousWorkspaceTheme ?? windowState.displayedWorkspaceTheme
        var frozen = context
        frozen.chromeColorScheme = context.sourceChromeColorScheme
        frozen.sourceChromeColorScheme = context.sourceChromeColorScheme
        frozen.targetChromeColorScheme = context.sourceChromeColorScheme
        frozen.workspaceTheme = frozenTheme
        frozen.sourceWorkspaceTheme = frozenTheme
        frozen.targetWorkspaceTheme = frozenTheme
        frozen.isInteractiveTransition = false
        frozen.transitionProgress = 1.0
        return frozen
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
