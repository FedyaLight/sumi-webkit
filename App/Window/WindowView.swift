//
//  WindowView.swift
//  Sumi
//
//

import AppKit
import SwiftUI

/// Relative stacking for full-window transient chrome (higher draws above lower).
private enum WindowTransientChromeZIndex {
    static let findInPage: Double = 3_500
    static let glance: Double = 8_000
    static let glanceFindInPage: Double = 8_500
    /// Collapsed sidebar must sit above Glance so tab/space switching never dismisses or blocks it.
    static let collapsedSidebar: Double = 8_750
    /// Floating bar must stay above Glance so URL editing keeps targeting the preview page.
    static let floatingBar: Double = 9_000
    /// Drag ghost only.
    static let sidebarDragPreview: Double = 20_000
}

/// Main window view that orchestrates the browser UI layout
struct WindowView: View {
    @EnvironmentObject private var glanceManager: GlanceManager
    @EnvironmentObject private var nowPlayingController: SumiNativeNowPlayingController
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.sumiSettings) var sumiSettings
    @StateObject private var hoverSidebarManager = HoverSidebarManager()
    @State private var dockedSidebarLayout = DockedSidebarLayoutState()
    /// Bumps when system/window effective appearance changes so `globalColorScheme` refreshes while in auto mode.
    @State private var effectiveAppearanceRevision: UInt = 0
    private let browserContext: WindowViewBrowserContext
    private let sidebarDragState: SidebarDragState

    init(
        browserContext: WindowViewBrowserContext,
        sidebarDragState: SidebarDragState
    ) {
        self.browserContext = browserContext
        self.sidebarDragState = sidebarDragState
    }

    var body: some View {
        GeometryReader { windowProxy in
            let windowChromeSize = windowProxy.size

            ZStack {
                chromeThemeScope {
                    windowBackground()
                }
                .sumiAppKitContextMenu(entries: {
                    [
                        .action(
                            SidebarContextMenuAction(
                                title: "Customize Space Gradient...",
                                systemImage: "paintpalette",
                                isEnabled: browserContext.hasCurrentSpace,
                                classification: .presentationOnly,
                                action: {
                                    browserContext.showGradientEditor(
                                        source: windowState.resolveSidebarPresentationSource()
                                    )
                                }
                            )
                        ),
                    ]
                })

                sidebarWebViewStack(windowChromeSize: windowChromeSize)

                // Collapsed hover-reveal sidebar overlay. Docked sidebar is a real layout column.
                if shouldRenderCollapsedSidebarOverlay {
                    chromeThemeScope {
                        SidebarHoverOverlayView(
                            resolvedThemeContext: resolvedThemeContext,
                            chromeBackgroundResolvedThemeContext: resolvedThemeContext,
                            windowChromeSize: windowChromeSize,
                            browserContext: browserContext.sidebarBrowserContext,
                            hostActions: browserContext.sidebarHostActions,
                            structuralInvalidation: browserContext.sidebarStructuralInvalidation,
                            sidebarDragState: sidebarDragState
                        )
                            .environmentObject(hoverSidebarManager)
                            .environment(windowState)
                            .zIndex(WindowTransientChromeZIndex.collapsedSidebar)
                    }
                }

                // Floating bar is full-window chrome so its floating position is stable in both
                // docked and collapsed sidebar layouts.
                chromeThemeScope {
                    FloatingBarChromeHost(
                        browserContext: browserContext.floatingBarBrowserContext,
                        windowState: windowState,
                        sumiSettings: sumiSettings,
                        resolvedThemeContext: resolvedThemeContext,
                        colorScheme: nativeSurfaceColorScheme,
                        isPresented: windowState.isFloatingBarVisible && !transientChromeModalSuppressed
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(WindowTransientChromeZIndex.floatingBar)
                }

                // Glance overlay for external link previews
                if shouldRenderGlanceOverlay {
                    chromeThemeScope {
                        GlanceOverlayView()
                            .environmentObject(glanceManager)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .zIndex(WindowTransientChromeZIndex.glance)
                    }
                }

                if let glanceFindInPageSession,
                   let contentFrame = glanceFindInPageSession.contentFrameInWindowSpace {
                    chromeThemeScope {
                        FindInPageChromeHost(
                            findManager: browserContext.findManager,
                            windowRegistry: windowRegistry,
                            windowState: windowState,
                            sumiSettings: sumiSettings,
                            resolvedThemeContext: resolvedThemeContext,
                            colorScheme: nativeSurfaceColorScheme,
                            isModalSuppressed: transientChromeModalSuppressed
                        )
                        .frame(width: max(contentFrame.width, 0), height: max(contentFrame.height, 0))
                        .position(x: contentFrame.midX, y: contentFrame.midY)
                        .zIndex(WindowTransientChromeZIndex.glanceFindInPage)
                    }
                }

                chromeThemeScope {
                    SidebarFloatingDragPreview(
                        sidebarDragState: sidebarDragState,
                        browserContext: SidebarFloatingDragPreviewContext(
                            currentProfileID: {
                                browserContext.currentProfileID()
                            },
                            essentialPins: { profileId in
                                browserContext.essentialPins(profileId: profileId)
                            }
                        )
                    )
                        .environment(windowState)
                        .environment(\.sumiSettings, sumiSettings)
                        .zIndex(WindowTransientChromeZIndex.sidebarDragPreview)
                        .allowsHitTesting(false)
                }
            }
        }
        // System feedback toast - top trailing corner
        .overlay(alignment: .topTrailing) {
            toastOverlay
        }
        .sheet(item: nativeModalPresentationBinding) { presentation in
            nativeModalContent(for: presentation)
        }
        // Lifecycle management
        .onAppear {
            syncDockedSidebarLayout(isVisible: windowState.isSidebarVisible, animated: false)
            hoverSidebarManager.sidebarPosition = sumiSettings.sidebarPosition
            browserContext.attachHoverSidebarManager(hoverSidebarManager, windowState: windowState)
            hoverSidebarManager.windowRegistry = windowRegistry
            hoverSidebarManager.start()
            revealCollapsedSidebarForPinnedTransientIfNeeded()
        }
        .onChange(of: windowState.isSidebarVisible) { _, isVisible in
            syncDockedSidebarLayout(isVisible: isVisible, animated: true)
            Task { @MainActor in
                await Task.yield()
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
        .environmentObject(browserContext.browserManagerForUnmigratedChildren)
        .environmentObject(glanceManager)
        .environmentObject(browserContext.splitManager)
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
        .onChange(of: sumiSettings.showBrowserToasts) { _, isEnabled in
            if !isEnabled {
                windowState.dismissToast()
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
        .environment(\.colorScheme, nativeSurfaceColorScheme)
    }

    private var shouldRenderCollapsedSidebarOverlay: Bool {
        !windowState.isSidebarVisible && !dockedSidebarLayout.shouldRender
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
    private func windowBackground() -> some View {
        SpaceGradientBackgroundView(
            surface: .toolbarChrome,
            nativeMaterialRole: .nativeGlassChrome
        )
        .backgroundDraggable(sidebarDragState: sidebarDragState)
        .environment(windowState)
    }

    @ViewBuilder
    private func sidebarWebViewStack(windowChromeSize: CGSize) -> some View {
        let sidebarVisible = windowState.isSidebarVisible
        let horizontalInsets = chromeGeometry.contentEdgeInsets
        let sidebarPosition = sumiSettings.sidebarPosition
        let shellEdge = sidebarPosition.shellEdge
        let rendersDockedSidebar = dockedSidebarLayout.rendersDockedSidebar(isVisible: sidebarVisible)
        let layoutProgress = dockedSidebarLayout.layoutProgress(isVisible: sidebarVisible)
        let leftLayoutProgress = rendersDockedSidebar && shellEdge.isLeft ? layoutProgress : 0
        let rightLayoutProgress = rendersDockedSidebar && shellEdge.isRight ? layoutProgress : 0

        HStack(spacing: 0) {
            if rendersDockedSidebar && shellEdge.isLeft {
                sidebarDockedColumn(
                    sidebarPosition: sidebarPosition,
                    layoutProgress: layoutProgress,
                    windowChromeSize: windowChromeSize
                )
            }

            webContent()
                .scaleEffect(glanceWebContentScale)
                .opacity(glanceWebContentOpacity)
                .transaction { transaction in
                    if suppressesGlanceWebContentAnimation {
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
                }
                .animation(glanceWebContentAnimation, value: glanceWebContentIsDimmed)

            if rendersDockedSidebar && shellEdge.isRight {
                sidebarDockedColumn(
                    sidebarPosition: sidebarPosition,
                    layoutProgress: layoutProgress,
                    windowChromeSize: windowChromeSize
                )
            }
        }
        .padding(.leading, horizontalInsets.leading * (1 - leftLayoutProgress))
        .padding(.trailing, horizontalInsets.trailing * (1 - rightLayoutProgress))
    }

    @ViewBuilder
    private func sidebarDockedColumn(
        sidebarPosition: SidebarPosition,
        layoutProgress: CGFloat,
        windowChromeSize: CGSize
    ) -> some View {
        let presentationContext = SidebarPresentationContext.docked(
            sidebarWidth: windowState.sidebarWidth,
            sidebarPosition: sidebarPosition
        )
        let layoutWidth = presentationContext.sidebarWidth * layoutProgress

        SidebarColumnRepresentable(
            browserContext: browserContext.sidebarBrowserContext,
            hostActions: browserContext.sidebarHostActions,
            structuralInvalidation: browserContext.sidebarStructuralInvalidation,
            windowState: windowState,
            windowRegistry: windowRegistry,
            sumiSettings: sumiSettings,
            nowPlayingController: nowPlayingController,
            resolvedThemeContext: resolvedThemeContext,
            chromeBackgroundResolvedThemeContext: resolvedThemeContext,
            windowChromeSize: windowChromeSize,
            sidebarDragState: sidebarDragState,
            presentationContext: presentationContext
        )
        .id("docked-sidebar-column")
        .frame(width: presentationContext.sidebarWidth)
        .frame(maxHeight: .infinity)
        .opacity(min(max(layoutProgress * 2, 0), 1))
        .frame(width: max(layoutWidth, 0), alignment: presentationContext.shellEdge.overlayAlignment)
        .clipped()
    }

    private func syncDockedSidebarLayout(isVisible: Bool, animated: Bool) {
        let animation = SidebarMotionPolicy.dockedLayoutAnimation(
            for: SidebarMotionPolicy.currentMode(reduceMotion: effectiveReduceMotion),
            isShowing: isVisible
        )

        if isVisible {
            dockedSidebarLayout.beginShow()
            if animated, let animation {
                withAnimation(animation) {
                    dockedSidebarLayout.show()
                }
            } else {
                dockedSidebarLayout.show()
            }
            return
        }

        if animated, let animation {
            let generation = dockedSidebarLayout.beginAnimatedHide()

            withAnimation(animation, completionCriteria: .logicallyComplete) {
                dockedSidebarLayout.hide()
            } completion: {
                dockedSidebarLayout.completeAnimatedHide(
                    generation: generation,
                    isVisible: windowState.isSidebarVisible
                )
            }
        } else {
            dockedSidebarLayout.hideImmediately()
        }
    }

    @ViewBuilder
    private func webContent() -> some View {
        ZStack(alignment: .top) {
            WebsiteView(
                browserContext: browserContext.websiteViewBrowserContext(
                    sidebarDragState: sidebarDragState
                ),
                nativeSurfaceRootBuilders: browserContext.websiteNativeSurfaceRootBuilders,
                sidebarDragState: sidebarDragState
            )
                .zIndex(2000)

            if let currentTab = browserContext.currentTab(for: windowState) {
                HStack {
                    Spacer()
                    SumiWindowProgressBar(tab: currentTab) { tab in
                        browserContext.workspaceTheme(for: tab.spaceId) ?? windowState.workspaceTheme
                    }
                    .frame(width: 200, height: 12)
                    .offset(y: -BrowserChromeGeometry.elementSeparation / 2 - 6)
                    Spacer()
                }
                .zIndex(2010)
            }

            // Find-in-page stays in the browser window's responder chain so window controls keep active appearance.
            FindInPageChromeHost(
                findManager: browserContext.findManager,
                windowRegistry: windowRegistry,
                windowState: windowState,
                sumiSettings: sumiSettings,
                resolvedThemeContext: resolvedThemeContext,
                colorScheme: nativeSurfaceColorScheme,
                isModalSuppressed: transientChromeModalSuppressed,
                isSuppressed: findChromeBelongsToGlance
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .zIndex(WindowTransientChromeZIndex.findInPage)
        }
        .padding(.top, chromeGeometry.contentEdgeInsets.top)
        .padding(.bottom, chromeGeometry.contentEdgeInsets.bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transientChromeModalSuppressed: Bool {
        browserContext.isNativeModalPresented(in: windowState.id)
    }

    private var nativeModalPresentationBinding: Binding<BrowserNativeModalPresentation?> {
        Binding(
            get: {
                guard let presentation = browserContext.nativeModalPresentation,
                      presentation.windowID == windowState.id
                else {
                    return nil
                }
                return presentation
            },
            set: { newValue in
                if newValue == nil {
                    browserContext.nativeModalPresentationBindingDismissed(
                        for: windowState.id
                    )
                }
            }
        )
    }

    @ViewBuilder
    private func nativeModalContent(
        for presentation: BrowserNativeModalPresentation
    ) -> some View {
        switch presentation.kind {
        case .browsingData:
            SumiBrowsingDataDialog(browserManager: browserContext.browserManagerForUnmigratedChildren)
        case .basicAuth(let session):
            BasicAuthDialog(
                model: session.model,
                onSubmit: { username, password, rememberCredential in
                    session.submit(
                        username: username,
                        password: password,
                        rememberCredential: rememberCredential
                    )
                },
                onCancel: {
                    session.cancel()
                }
            )
        case .notice(let notice):
            BrowserNoticeSheet(notice: notice) {
                browserContext.dismissNativeModalPresentation()
            }
        }
    }

    private var appKitGlobalAppearance: NSAppearance {
        windowState.window?.effectiveAppearance ?? NSApplication.shared.effectiveAppearance
    }

    private var globalColorScheme: ColorScheme {
        switch sumiSettings.windowSchemeMode {
        case .auto:
            _ = effectiveAppearanceRevision
            return ColorScheme(effectiveAppearance: appKitGlobalAppearance)
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    private var toastOverlay: some View {
        ZStack(alignment: .topTrailing) {
            if sumiSettings.showBrowserToasts, let toast = windowState.toast {
                chromeThemeScope {
                    BrowserToastView(toast: toast)
                        .onTapGesture {
                            windowState.dismissToast(id: toast.id)
                        }
                        .accessibilityAddTraits(.isButton)
                }
                .transition(effectiveReduceMotion ? .opacity : .toast)
            }
        }
        .padding(10)
        .animation(toastAnimation, value: windowState.toast?.id)
    }

    private var toastAnimation: Animation {
        effectiveReduceMotion ? .easeOut(duration: 0.08) : .smooth(duration: 0.18)
    }

    private var glanceWebContentIsDimmed: Bool {
        guard presentedGlanceSession != nil else { return false }
        return glanceManager.phase == .opening || glanceManager.phase == .open || glanceManager.phase == .closing
    }

    private var glanceWebContentScale: CGFloat {
        glanceWebContentIsDimmed && !effectiveReduceMotion ? 0.97 : 1
    }

    private var glanceWebContentOpacity: Double {
        guard glanceWebContentIsDimmed else { return 1 }
        return effectiveReduceMotion ? 0.75 : 0.3
    }

    private var glanceWebContentAnimation: Animation? {
        guard !suppressesGlanceWebContentAnimation else { return nil }
        return effectiveReduceMotion ? Animation.easeOut(duration: 0.08) : Animation.smooth(duration: 0.35)
    }

    private var suppressesGlanceWebContentAnimation: Bool {
        glanceManager.phase == .promoting
    }

    private var effectiveReduceMotion: Bool {
        reduceMotion || sumiSettings.shouldReduceChromeMotion
    }

    private var presentedGlanceSession: GlanceSession? {
        glanceManager.presentedSession(for: windowState)
    }

    private var shouldRenderGlanceOverlay: Bool {
        glanceManager.currentSession?.windowId == windowState.id
    }

    private var activeGlanceSession: GlanceSession? {
        glanceManager.activeSession(for: windowState)
    }

    private var findChromeBelongsToGlance: Bool {
        guard let activeGlanceSession else { return false }
        return browserContext.findCurrentTabId() == activeGlanceSession.previewTab.id
    }

    private var glanceFindInPageSession: GlanceSession? {
        guard findChromeBelongsToGlance else { return nil }
        return activeGlanceSession
    }

    private var resolvedThemeContext: ResolvedThemeContext {
        windowState.resolvedThemeContext(
            global: globalColorScheme,
            settings: sumiSettings
        )
    }

    private var nativeSurfaceColorScheme: ColorScheme {
        resolvedThemeContext.nativeSurfaceColorScheme
    }

    private var chromeGeometry: BrowserChromeGeometry {
        BrowserChromeGeometry(settings: sumiSettings)
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
