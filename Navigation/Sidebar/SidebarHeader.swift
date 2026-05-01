//
//  SidebarHeader.swift
//  Sumi
//
//  Created by Aether on 15/11/2025.
//

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
        if #available(macOS 15.5, *) {
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
    @Environment(\.sidebarPresentationContext) private var sidebarPresentationContext
    @Environment(\.sumiSettings) private var sumiSettings

    var body: some View {
        HStack(spacing: SidebarChromeMetrics.controlSpacing) {
            trafficLightCluster

            if sumiSettings.showSidebarToggleButton {
                Button("Toggle Sidebar", systemImage: sumiSettings.sidebarPosition.shellEdge.toggleSidebarSymbolName) {
                    browserManager.toggleSidebar(for: windowState)
                }
                .labelStyle(.iconOnly)
                .font(.system(size: SidebarChromeMetrics.navigationIconSize, weight: .medium))
                .buttonStyle(NavButtonStyle(diameter: SidebarChromeMetrics.navigationButtonSize))
            }
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
        sidebarPresentationContext.mode != .collapsedHidden
    }
}
