//
//  SidebarHeader.swift
//  Sumi
//
//  Created by Aether on 15/11/2025.
//

import AppKit
import SwiftUI

/// Header section of the sidebar (window controls, navigation buttons, URL bar)
struct SidebarHeader: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject private var extensionSurfaceStore: BrowserExtensionSurfaceStore
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

            NavButtonsView()
                .environmentObject(browserManager)
                .environment(windowState)

            extensionActionCluster

            Spacer(minLength: 0)
        }
        .padding(.horizontal, SidebarChromeMetrics.horizontalPadding)
        .frame(height: SidebarChromeMetrics.controlStripHeight)
    }

    @ViewBuilder
    private var extensionActionCluster: some View {
        let enabledExtensions = extensionSurfaceStore.enabledExtensions
        let totalActions = browserManager.extensionsModule.orderedPinnedToolbarSlots(
            enabledExtensions: enabledExtensions.filter { $0.isEnabled },
            sumiScriptsManagerEnabled: browserManager.userscriptsModule.isEnabled
        ).count

        if totalActions > 0 {
            GeometryReader { proxy in
                let visibleCount = ExtensionActionVisibility.visibleCount(
                    totalActions: totalActions,
                    availableWidth: proxy.size.width
                )

                ExtensionActionView(
                    extensions: enabledExtensions,
                    visibleActionLimit: visibleCount
                )
                .environmentObject(browserManager)
                .environment(windowState)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: 32)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sidebarURLBar: some View {
        URLBarView(presentationMode: .sidebar)
        .environmentObject(browserManager)
        .environment(windowState)
        .padding(.horizontal, 8)
    }
}

// MARK: - Sidebar Window Controls
struct SidebarWindowControlsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
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
        if shouldRenderTrafficLightsInSidebarHeader {
            BrowserWindowTrafficLights(
                actionProvider: .browserWindow(windowState.window)
            )
        }
    }

    private var shouldRenderTrafficLightsInSidebarHeader: Bool {
        isBrowserWindowFullScreen == false
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
