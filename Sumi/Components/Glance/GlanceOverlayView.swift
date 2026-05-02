//
//  GlanceOverlayView.swift
//  Sumi
//
//  Created by Jonathan Caudill on 24/09/2025.
//

import SwiftUI
import AppKit

struct GlanceOverlayView: View {
    @EnvironmentObject private var glanceManager: GlanceManager
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(BrowserWindowState.self) private var windowState
    @State private var webView: GlanceWebView?

    private var session: GlanceSession? {
        glanceManager.currentSession
    }

    private var currentSpaceColor: Color {
        tokens.accent
    }

    var body: some View {
        ZStack {
            backgroundOverlay

            if session != nil {
                glanceContent()
                    .zIndex(1000)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(tokens.commandPaletteBackground)
                    .frame(width: 600, height: 400)
                    .zIndex(1000)
            }
        }
        .zIndex(9999)
        .allowsHitTesting(true)
        .accessibilityIdentifier("glance-overlay")
        .onDisappear {
            webView = nil
        }
    }

    @ViewBuilder
    private var backgroundOverlay: some View {
        Color.black.opacity(0.3)
            .contentShape(Rectangle())
            .allowsHitTesting(true)
            .onTapGesture {
                glanceManager.dismissGlance(reason: .close)
            }
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    @ViewBuilder
    private func glanceContent() -> some View {
        GeometryReader { geometry in
            let frame = calculateLayout(geometry: geometry)

            ZStack {
                tokens.commandPaletteBackground

                webViewContainer()
                    .frame(width: frame.width, height: frame.height)

                // Action buttons positioned outside the main content but within the scaled area
                actionButtons()
                    .position(
                        x: frame.width + 30,
                        y: 80
                    )
            }
            .frame(width: frame.width, height: frame.height) // Extend frame to include buttons
            .position(
                x: frame.minX + (frame.width / 2),
                y: geometry.size.height / 2
            )
        }
    }

    @ViewBuilder
    private func webViewContainer() -> some View {
        Group {
            if webView != nil {
                webView
                    .allowsHitTesting(true)
            } else {
                tokens.commandPaletteBackground
            }
        }
        .allowsHitTesting(true)
        .onAppear {
            if webView == nil {
                if let preCreatedWebView = glanceManager.webView {
                    webView = preCreatedWebView
                } else {
                    let glanceWebView = glanceManager.createWebView()
                    webView = glanceWebView
                    glanceManager.updateWebView(glanceWebView)
                }
            }
        }
    }

    @ViewBuilder
    private func actionButtons() -> some View {
        VStack(spacing: 12) {
            // Close button
            actionButton(
                icon: "xmark",
                action: { glanceManager.dismissGlance(reason: .close) },
                color: currentSpaceColor,
                accessibilityID: "glance-close"
            )

            // Split view button (disabled if already in split view)
            actionButton(
                icon: "square.split.2x1",
                action: { glanceManager.moveToSplitView() },
                color: currentSpaceColor,
                disabled: !glanceManager.canEnterSplitView,
                accessibilityID: "glance-send-to-split"
            )

            // New tab button
            actionButton(
                icon: "plus.square.on.square",
                action: { glanceManager.moveToNewTab() },
                color: currentSpaceColor,
                accessibilityID: "glance-open-in-tab"
            )
        }
    }

    @ViewBuilder
    private func actionButton(
        icon: String,
        action: @escaping () -> Void,
        color: Color,
        disabled: Bool = false,
        accessibilityID: String? = nil
    ) -> some View {
        HoverButton(icon: icon, action: action, color: color, disabled: disabled, accessibilityID: accessibilityID)
    }

    // MARK: - Hover Button
    private struct HoverButton: View {
        @Environment(\.colorScheme) var colorScheme
        let icon: String
        let action: () -> Void
        let color: Color
        let disabled: Bool
        let accessibilityID: String?
        @State private var isHovering = false

        var body: some View {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(disabled ? Color.gray : color)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color(nsColor: colorScheme == .dark ? NSColor.white : NSColor.black))
                            .opacity(disabled ? 0.5 : (isHovering ? 0.85 : 1.0))
                    )
                    .overlay(
                        Circle()
                            .stroke(color.opacity(disabled ? 0.3 : (isHovering ? 0.8 : 0.6)), lineWidth: 1)
                    )
            }
            .disabled(disabled)
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier(accessibilityID ?? "glance-action")
            .scaleEffect(disabled ? 0.9 : 1.0)
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .animation(.easeInOut(duration: 0.12), value: isHovering)
            .animation(.easeInOut(duration: 0.1), value: disabled)
        }
    }

    // MARK: - Layout Calculation

    private func calculateLayout(geometry: GeometryProxy) -> CGRect {
        let windowSize = geometry.size

        // Compute the visible web content area by excluding the sidebar width
        let sidebarWidth: CGFloat = windowState.isSidebarVisible ? windowState.sidebarWidth : 0
        let webAreaWidth = max(0, windowSize.width - sidebarWidth)

        let webViewHeight = windowSize.height - 10 // Full height PLUS 10pts

        // Center within the web area (excluding sidebar) with 60pt margins
        let horizontalMargin: CGFloat = 60
        let glanceWidth = max(0, webAreaWidth - (horizontalMargin * 2))
        let glanceXWithinWebArea = (webAreaWidth - glanceWidth) / 2 // equals horizontalMargin

        let glanceX = sidebarWidth + glanceXWithinWebArea

        return CGRect(
            x: glanceX,
            y: 0,
            width: glanceWidth,
            height: webViewHeight
        )
    }
}
