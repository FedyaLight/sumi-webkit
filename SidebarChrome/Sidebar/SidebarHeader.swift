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
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.sidebarPresentationContext) private var sidebarPresentationContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    }

    @ViewBuilder
    private var trafficLightCluster: some View {
        BrowserWindowTrafficLights(
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
            isBrowserWindowFullScreen:
                windowState.presentationState.nativeDisplayMode == .fullScreen,
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

}
