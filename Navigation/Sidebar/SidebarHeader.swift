//
//  SidebarHeader.swift
//  Sumi
//
//

import AppKit
import SwiftUI

/// Header section of the sidebar (window controls, navigation buttons, URL bar)
struct SidebarHeader: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) var sumiSettings

    var body: some View {
        VStack(spacing: 8) {
            controlStrip
            sidebarURLBar
        }
    }

    private var controlStrip: some View {
        HStack(spacing: SidebarChromeMetrics.controlSpacing) {
            SidebarWindowControlsView()
                .environmentObject(browserManager)
                .environment(windowState)
                .frame(maxWidth: .infinity, alignment: .leading)

            NavButtonsView(
                browserContext: NavigationToolbarBrowserContext.live(
                    browserManager: browserManager,
                    windowState: windowState
                )
            )
            .environment(windowState)
        }
        .padding(.horizontal, SidebarChromeMetrics.horizontalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: SidebarChromeMetrics.controlStripHeight)
    }

    private var sidebarURLBar: some View {
        URLBarView(browserManager: browserManager, presentationMode: .sidebar)
        .environment(windowState)
        .padding(.horizontal, 8)
    }
}

// MARK: - Sidebar Window Controls
struct SidebarWindowControlsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.sidebarPresentationContext) private var sidebarPresentationContext
    @State private var isBrowserWindowFullScreen = false

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
                .buttonStyle(NavButtonStyle(diameter: SidebarChromeMetrics.navigationButtonSize))
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
            actionProvider: .browserWindow(windowState.window),
            isVisible: shouldRenderTrafficLightsInSidebarHeader
        )
    }

    private var shouldRenderTrafficLightsInSidebarHeader: Bool {
        isBrowserWindowFullScreen == false && sidebarPresentationShowsTrafficLights
    }

    private var sidebarPresentationShowsTrafficLights: Bool {
        switch sidebarPresentationContext.mode {
        case .docked:
            return windowState.isSidebarVisible
        case .collapsedVisible:
            return true
        case .collapsedHidden:
            return false
        }
    }

    private var browserWindowIdentity: ObjectIdentifier? {
        windowState.window.map { ObjectIdentifier($0) }
    }

    private func toggleSidebar() {
        browserManager.toggleSidebar(for: windowState)
    }

    private func handleFullScreenNotification(_ notification: Notification) {
        guard let notificationWindow = notification.object as? NSWindow,
              notificationWindow === windowState.window
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
        isBrowserWindowFullScreen = windowState.window?.styleMask.contains(.fullScreen) == true
        syncNativeWindowButtonsForCurrentFullScreenState()
    }

    private func syncNativeWindowButtonsForCurrentFullScreenState() {
        windowState.window?.setNativeStandardWindowButtonsForBrowserFullScreenChromeVisible(isBrowserWindowFullScreen)
    }
}
