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
            SpaceGradientBackgroundView(surface: .toolbarChrome)
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
