//
//  SidebarHeader.swift
//  Sumi
//
//

import AppKit
import SwiftUI

@MainActor
struct SidebarHeaderBrowserContext {
    let navigationToolbarContext: NavigationToolbarBrowserContext
    let urlBarBrowserContext: URLBarBrowserContext
    let toggleSidebar: () -> Void
}

/// Header section of the sidebar (window controls, navigation buttons, URL bar)
struct SidebarHeader: View {
    let browserContext: SidebarHeaderBrowserContext
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.sumiSettings) var sumiSettings

    var body: some View {
        VStack(spacing: 8) {
            controlStrip
            sidebarURLBar
        }
    }

    private var controlStrip: some View {
        HStack(spacing: SidebarChromeMetrics.controlSpacing) {
            SidebarWindowControlsView(
                toggleSidebar: browserContext.toggleSidebar
            )
                .environment(windowState)
                .frame(maxWidth: .infinity, alignment: .leading)

            NavButtonsView(
                browserContext: browserContext.navigationToolbarContext
            )
            .environment(windowState)
        }
        .padding(.leading, SidebarChromeMetrics.controlLeadingPadding)
        .padding(.trailing, SidebarChromeMetrics.contentHorizontalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: SidebarChromeMetrics.controlStripHeight)
    }

    private var sidebarURLBar: some View {
        URLBarView(
            browserContext: browserContext.urlBarBrowserContext,
            presentationMode: .sidebar
        )
        .environment(windowState)
        .padding(.horizontal, SidebarChromeMetrics.contentHorizontalPadding)
    }
}

// MARK: - Sidebar Window Controls
struct SidebarWindowControlsView: View {
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.sidebarPresentationContext) private var sidebarPresentationContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBrowserWindowFullScreen = false
    let toggleSidebar: () -> Void

    var body: some View {
        HStack(spacing: SidebarChromeMetrics.controlSpacing) {
            trafficLightCluster

            if sumiSettings.showSidebarToggleButton {
                Button(
                    "Toggle Sidebar",
                    systemImage: sumiSettings.sidebarPosition.shellEdge.toggleSidebarSymbolName,
                    action: toggleSidebar
                )
                .labelStyle(.iconOnly)
                .font(.system(size: SidebarChromeMetrics.navigationIconSize, weight: .medium))
                .buttonStyle(NavButtonStyle(
                    diameter: SidebarChromeMetrics.navigationButtonSize,
                    hoverTracking: .sidebarSession
                ))
                .sidebarAppKitPrimaryAction(action: toggleSidebar)
            }
        }
        .onAppear(perform: syncFullScreenWindowControls)
        .onChange(of: browserWindowIdentity) { _, _ in
            syncFullScreenWindowControls()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) {
            handleFullScreenNotification($0)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) {
            handleFullScreenNotification($0)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) {
            handleFullScreenNotification($0)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) {
            handleFullScreenNotification($0)
        }
    }

    @ViewBuilder
    private var trafficLightCluster: some View {
        BrowserWindowTrafficLights(
            actionProvider: .browserWindow(windowState.shellWindow(in: windowRegistry)),
            presentation: trafficLightPresentation,
            travelProgress: trafficLightTravelProgress
        )
        .animation(
            SidebarMotionPolicy.dockedLayoutAnimation(
                for: sidebarMotionMode,
                isShowing: windowState.isSidebarVisible
            ),
            value: trafficLightTravelProgress
        )
    }

    private var trafficLightPresentation: BrowserWindowTrafficLightPresentation {
        SidebarTrafficLightPresentationPolicy.presentation(
            isBrowserWindowFullScreen: isBrowserWindowFullScreen,
            mode: sidebarPresentationContext.mode,
            isSidebarVisible: windowState.isSidebarVisible,
            overlayUsesTravel: SidebarMotionPolicy.overlayUsesTravel(for: sidebarMotionMode)
        )
    }

    private var trafficLightTravelProgress: CGFloat {
        SidebarTrafficLightPresentationPolicy.travelProgress(
            mode: sidebarPresentationContext.mode,
            shellEdge: sidebarPresentationContext.shellEdge,
            isSidebarVisible: windowState.isSidebarVisible
        )
    }

    private var sidebarMotionMode: SidebarMotionPolicy.Mode {
        SidebarMotionPolicy.currentMode(
            reduceMotion: reduceMotion,
            energySaverReducesMotion: sumiSettings.shouldReduceChromeMotion
        )
    }

    private var browserWindowIdentity: ObjectIdentifier? {
        windowState.shellWindow(in: windowRegistry).map { ObjectIdentifier($0) }
    }

    private func handleFullScreenNotification(_ notification: Notification) {
        guard let notificationWindow = notification.object as? NSWindow,
              notificationWindow === windowState.shellWindow(in: windowRegistry)
        else { return }

        switch notification.name {
        case NSWindow.willEnterFullScreenNotification, NSWindow.didEnterFullScreenNotification:
            isBrowserWindowFullScreen = true
            syncNativeWindowButtonsForCurrentFullScreenState()
        case NSWindow.willExitFullScreenNotification:
            notificationWindow.setNativeStandardWindowButtonsForBrowserFullScreenChromeVisible(false)
        case NSWindow.didExitFullScreenNotification:
            isBrowserWindowFullScreen = false
            syncNativeWindowButtonsForCurrentFullScreenState()
        default:
            isBrowserWindowFullScreen = notificationWindow.styleMask.contains(.fullScreen)
            syncNativeWindowButtonsForCurrentFullScreenState()
        }
    }

    private func syncFullScreenWindowControls() {
        isBrowserWindowFullScreen =
            windowState.shellWindow(in: windowRegistry)?.styleMask.contains(.fullScreen) == true
        syncNativeWindowButtonsForCurrentFullScreenState()
    }

    private func syncNativeWindowButtonsForCurrentFullScreenState() {
        windowState.shellWindow(in: windowRegistry)?
            .setNativeStandardWindowButtonsForBrowserFullScreenChromeVisible(isBrowserWindowFullScreen)
    }
}
