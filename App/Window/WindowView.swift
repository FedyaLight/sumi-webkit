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
    /// Above web-column chrome (~3500) and ``SidebarHoverOverlayView`` (~5000); below command palette and dialogs.
    static let workspaceThemePicker: Double = 7_000
    static let commandPalette: Double = 9_000
    /// Glance preview: above palette, below blocking dialogs.
    static let peek: Double = 10_000
    /// Modal dialogs (quit, settings paths, etc.) must stay above the theme editor.
    static let dialog: Double = 11_000
    /// Drag ghost only.
    static let sidebarDragPreview: Double = 20_000
}

/// Main window view that orchestrates the browser UI layout
struct WindowView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.sumiSettings) var sumiSettings
    @StateObject private var hoverSidebarManager = HoverSidebarManager()
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

            // Hover-reveal Sidebar overlay (slides in over web content)
            chromeThemeScope {
                SidebarHoverOverlayView()
                    .environmentObject(hoverSidebarManager)
                    .environment(windowState)
            }

            chromeThemeScope {
                workspaceThemePickerHost
                    .zIndex(WindowTransientChromeZIndex.workspaceThemePicker)
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
            chromeThemeScope {
                PeekOverlayView()
                    .zIndex(WindowTransientChromeZIndex.peek)
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
        .onReceive(NotificationCenter.default.publisher(for: .applicationDidChangeEffectiveAppearance)) { _ in
            Task { @MainActor in
                effectiveAppearanceRevision &+= 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .windowDidChangeEffectiveAppearance)) { notification in
            guard let window = notification.object as? NSWindow,
                  window === windowState.window
            else { return }
            Task { @MainActor in
                effectiveAppearanceRevision &+= 1
            }
        }
        .preferredColorScheme(preferredColorScheme)
    }

    // MARK: - Layout Components

    @ViewBuilder
    private func WindowBackground() -> some View {
        ZStack {
            windowBackgroundColor
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            SpaceGradientBackgroundView()
        }
        .backgroundDraggable()
        .environment(windowState)
    }

    @ViewBuilder
    private func SidebarWebViewStack() -> some View {
        let sidebarVisible = windowState.isSidebarVisible
        
        HStack(spacing: 0) {
            SidebarDockedSpacer()
            WebContent()
        }
        .padding(.trailing, 8)
        .padding(.leading, sidebarVisible ? 0 : 8)
    }

    @ViewBuilder
    private func SidebarDockedSpacer() -> some View {
        Color.clear
            .frame(width: windowState.isSidebarVisible ? windowState.sidebarWidth : 0)
            .accessibilityHidden(true)
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
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var preferredColorScheme: ColorScheme? {
        switch sumiSettings.windowSchemeMode {
        case .auto:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
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

    private var windowBackgroundColor: Color {
        resolvedThemeContext.tokens(settings: sumiSettings).windowBackground
    }

    @ViewBuilder
    private var workspaceThemePickerHost: some View {
        if let session = browserManager.workspaceThemePickerSession,
           session.hostWindowID == windowState.id
        {
            WorkspaceThemePickerOverlay(session: session)
                .id(session.id)
                .environmentObject(browserManager)
                .environment(windowState)
                .environment(\.sumiSettings, sumiSettings)
                .environment(\.resolvedThemeContext, resolvedThemeContext)
        }
    }
}

private extension ColorScheme {
    /// Resolves AppKit effective appearance to SwiftUI for window-scheme **auto** (follow system).
    init(effectiveAppearance appearance: NSAppearance) {
        let best = appearance.bestMatch(from: [.darkAqua, .aqua])
        self = best == .darkAqua ? .dark : .light
    }
}

private extension Notification.Name {
    static let applicationDidChangeEffectiveAppearance = Notification.Name(
        rawValue: "NSApplicationDidChangeEffectiveAppearanceNotification"
    )
    static let windowDidChangeEffectiveAppearance = Notification.Name(
        rawValue: "NSWindowDidChangeEffectiveAppearanceNotification"
    )
}

private struct SidebarTransientRecoveryAnchorView: NSViewRepresentable {
    let handle: SidebarTransientInteractionHandle

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        handle.attach(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        handle.attach(nsView)
    }
}

/// Panel entrance aligned with ``SumiEmojiPickerAppearModifier``: spring scale + slide; anchor may use x &lt; 0 so the pivot sits over the sidebar (outside the panel’s bounds).
private struct WorkspaceThemePickerPanelDropModifier: ViewModifier {
    let scaleAnchor: UnitPoint
    private static let slidePixels: CGFloat = -18

    @State private var presented = false

    func body(content: Content) -> some View {
        content
            .opacity(presented ? 1 : 0)
            .scaleEffect(presented ? 1 : SumiEmojiPickerMetrics.appearScale, anchor: scaleAnchor)
            .offset(x: presented ? 0 : Self.slidePixels, y: 0)
            .onAppear {
                presented = false
                DispatchQueue.main.async {
                    withAnimation(
                        .spring(
                            response: SumiEmojiPickerMetrics.appearSpringResponse,
                            dampingFraction: SumiEmojiPickerMetrics.appearSpringDamping
                        )
                    ) {
                        presented = true
                    }
                }
            }
    }
}

struct WorkspaceThemePickerOverlay: View {
    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @ObservedObject var session: WorkspaceThemePickerSession
    var sidebarRecoveryCoordinator: SidebarHostRecoveryHandling = SidebarHostRecoveryCoordinator.shared
    @State private var allowsOutsideDismiss = false
    @State private var transientSurfacesInteractive = true
    @State private var dismissLifecyclePrepared = false
    @State private var recoveryAnchorHandle = SidebarTransientInteractionHandle()
    @State private var shieldHandle = SidebarTransientInteractionHandle()
    @State private var panelHandle = SidebarTransientInteractionHandle()

    var body: some View {
        GeometryReader { proxy in
            let layout = WorkspaceThemePickerOverlayLayout(
                windowSize: proxy.size,
                sidebarWidth: resolvedSidebarWidth
            )

            let panelWidth = GradientEditorView.panelWidth
            let scaleAnchorX = (layout.sidebarHorizontalCenterX - layout.panelLeadingInset) / max(panelWidth, 1)
            // Vertical pivot ≈ window midline expressed in panel-height units (sidebar spans full height).
            let anchorYUnit = min(1, max(0, (proxy.size.height * 0.5) / 560))
            let panelScaleAnchor = UnitPoint(x: scaleAnchorX, y: anchorYUnit)

            ZStack(alignment: .topLeading) {
                SidebarTransientRecoveryAnchorView(handle: recoveryAnchorHandle)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)

                MouseEventShieldView(
                    onClick: dismissOverlay,
                    isInteractive: transientSurfacesInteractive,
                    handle: shieldHandle
                )
                .frame(
                    width: layout.interactionFrame.width,
                    height: layout.interactionFrame.height
                )
                .offset(
                    x: layout.interactionFrame.minX,
                    y: layout.interactionFrame.minY
                )

                // Size to the panel only so clicks outside the editor reach `MouseEventShieldView` (full-window HStack used to swallow them).
                BlockingInteractionSurface(
                    isInteractive: transientSurfacesInteractive,
                    handle: panelHandle
                ) {
                    GradientEditorView(
                        workspaceTheme: Binding(
                            get: { session.draftTheme },
                            set: { session.draftTheme = $0 }
                        ),
                        onThemeChange: { _ in
                            browserManager.previewWorkspaceThemePickerDraft(sessionID: session.id)
                        }
                    )
                }
                .frame(width: GradientEditorView.panelWidth, alignment: .topLeading)
                .padding(.leading, layout.panelLeadingInset)
                .modifier(WorkspaceThemePickerPanelDropModifier(scaleAnchor: panelScaleAnchor))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .accessibilityIdentifier("workspace-theme-picker-overlay")
        }
        .transition(.asymmetric(insertion: .identity, removal: .opacity))
        .onAppear {
            allowsOutsideDismiss = false
            transientSurfacesInteractive = true
            dismissLifecyclePrepared = false
            session.presentationSource?.coordinator?.updateHandles(
                [shieldHandle, panelHandle],
                for: session.transientSessionToken
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + WorkspaceThemePickerOverlayChrome.outsideDismissDelay) {
                allowsOutsideDismiss = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
            guard let window = note.object as? NSWindow,
                  window === windowState.window
            else { return }
            browserManager.dismissWorkspaceThemePickerDiscarding(sessionID: session.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            browserManager.dismissWorkspaceThemePickerIfNeededDiscarding()
        }
        .onDisappear {
            prepareTransientDismissal()
            session.presentationSource?.coordinator?.updateHandles(
                [shieldHandle, panelHandle],
                for: session.transientSessionToken
            )
            if let coordinator = session.presentationSource?.coordinator,
               let transientSessionToken = session.transientSessionToken
            {
                coordinator.finishSession(
                    transientSessionToken,
                    reason: "WorkspaceThemePickerOverlay.onDisappear"
                ) {
                    browserManager.finalizeWorkspaceThemePickerDismiss(session)
                }
            } else {
                browserManager.finalizeWorkspaceThemePickerDismiss(session)
                Self.performDismissRecovery(
                    in: windowState.window,
                    anchor: recoveryAnchor,
                    using: sidebarRecoveryCoordinator
                )
                windowState.scheduleSidebarInputRehydrate(reason: "WorkspaceThemePickerOverlay.fallback")
            }
        }
    }

    static func performDismissRecovery(
        in window: NSWindow?,
        anchor: NSView?,
        using coordinator: SidebarHostRecoveryHandling
    ) {
        coordinator.recover(in: window)
        coordinator.recover(anchor: anchor)
    }

    private var resolvedSidebarWidth: CGFloat {
        if windowState.isSidebarVisible {
            return windowState.sidebarWidth
        }

        return SidebarPresentationContext.collapsedSidebarWidth(
            sidebarWidth: windowState.sidebarWidth,
            savedSidebarWidth: windowState.savedSidebarWidth
        )
    }

    private var recoveryAnchor: NSView? {
        recoveryAnchorHandle.view ?? shieldHandle.view ?? panelHandle.view
    }

    private func dismissOverlay() {
        guard allowsOutsideDismiss else { return }
        prepareTransientDismissal()
        browserManager.dismissWorkspaceThemePicker(sessionID: session.id)
    }

    private func prepareTransientDismissal() {
        guard dismissLifecyclePrepared == false else { return }
        dismissLifecyclePrepared = true
        transientSurfacesInteractive = false
        shieldHandle.disarm()
        panelHandle.disarm()
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
