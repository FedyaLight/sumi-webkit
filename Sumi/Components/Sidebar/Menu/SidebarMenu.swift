//
//  SidebarMenu.swift
//  Sumi
//
//  Created by Maciek Bagiński on 23/09/2025.
//

import SwiftUI

enum SidebarPosition: String, CaseIterable, Identifiable {
    case left
    case right
    var id: String { rawValue }
}

struct SidebarMenu: View {
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sidebarPresentationContext) private var sidebarPresentationContext
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            tabs
            VStack {
                switch windowState.selectedSidebarMenuSection {
                case .history:
                    SidebarMenuHistoryTab()
                case .downloads:
                    SidebarMenuDownloadsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .ignoresSafeArea()
    }
    
    var tabs: some View {
        let cornerRadius = sumiSettings.resolvedCornerRadius(18)
        return VStack {
            HStack(spacing: 0) {
                SidebarSystemWindowControlsHost(
                    presentationMode: sidebarPresentationContext.mode,
                    window: windowState.window
                )
                .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SidebarChromeMetrics.horizontalPadding)
            .frame(height: SidebarChromeMetrics.controlStripHeight)
            
            Spacer()
            VStack(spacing: 20) {
                SidebarMenuTab(
                    image: "clock",
                    activeImage: "clock.fill",
                    title: "History",
                    isActive: windowState.selectedSidebarMenuSection == .history,
                    action: {
                        windowState.selectedSidebarMenuSection = .history
                        browserManager.persistWindowSession(for: windowState)
                    }
                )
                SidebarMenuTab(
                    image: "arrow.down.circle",
                    activeImage: "arrow.down.circle.fill",
                    title: "Downloads",
                    isActive: windowState.selectedSidebarMenuSection == .downloads,
                    action: {
                        windowState.selectedSidebarMenuSection = .downloads
                        browserManager.persistWindowSession(for: windowState)
                    }
                )
            }
            
            Spacer()
            HStack {
                Button("Back", systemImage: "arrow.backward") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        windowState.isSidebarMenuVisible = false
                        let restoredWidth = BrowserWindowState.clampedSidebarWidth(windowState.savedSidebarWidth)
                        windowState.sidebarWidth = restoredWidth
                        windowState.sidebarContentWidth = BrowserWindowState.sidebarContentWidth(for: restoredWidth)
                    }
                    browserManager.persistWindowSession(for: windowState)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(NavButtonStyle())
                .foregroundStyle(tokens.primaryText)
                Spacer()
            }
            .padding(.horizontal, SidebarChromeMetrics.horizontalPadding)
            .padding(.bottom, 8)
        }
        .frame(width: 110)
        .frame(maxHeight: .infinity)
        .background(menuBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(menuBorderColor, lineWidth: 1)
        }
    }

    private var menuBackground: Color {
        tokens.panelBackground
    }

    private var menuBorderColor: Color {
        tokens.separator.opacity(0.65)
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}
