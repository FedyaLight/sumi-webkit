//
//  SidebarResizeView.swift
//  Sumi
//
//

import SwiftUI

struct SidebarResizeView: View {
    let sidebarPosition: SidebarPosition
    let onResize: (_ width: CGFloat, _ windowState: BrowserWindowState, _ persist: Bool) -> Void
    let onEndResize: (_ windowState: BrowserWindowState) -> Void
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isResizing = false
    @State private var isHovering = false
    @State private var startingWidth: CGFloat = 0
    @State private var startingMouseX: CGFloat = 0
    @State private var lastAppliedWidth: CGFloat = 0
    private let minWidth: CGFloat = BrowserWindowState.sidebarMinimumWidth
    private let maxWidth: CGFloat = BrowserWindowState.sidebarMaximumWidth

    init(
        sidebarPosition: SidebarPosition = .left,
        onResize: @escaping (_ width: CGFloat, _ windowState: BrowserWindowState, _ persist: Bool) -> Void,
        onEndResize: @escaping (_ windowState: BrowserWindowState) -> Void
    ) {
        self.sidebarPosition = sidebarPosition
        self.onResize = onResize
        self.onEndResize = onEndResize
    }

    private var shellEdge: SidebarShellEdge {
        sidebarPosition.shellEdge
    }

    private var indicatorOffset: CGFloat {
        shellEdge.resizeIndicatorOffset
    }

    private var hitAreaOffset: CGFloat {
        shellEdge.resizeHitAreaOffset
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        ZStack {
            indicator

            Rectangle()
                .fill(Color.clear)
                .frame(width: SidebarResizeMetrics.hitAreaWidth)
                .padding(.vertical, SidebarResizeMetrics.hitAreaVerticalInset)
                .offset(x: hitAreaOffset)
                .contentShape(.interaction, .rect)
                .onHover { hovering in
                    guard windowState.isSidebarVisible else { return }
                    isHovering = hovering || isResizing
                }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { value in
                            guard windowState.isSidebarVisible else { return }

                            if !isResizing {
                                startingWidth = windowState.sidebarWidth
                                startingMouseX = value.startLocation.x
                                lastAppliedWidth = startingWidth
                                isResizing = true
                            }

                            let currentMouseX = value.location.x
                            let mouseMovement = shellEdge.resizeDelta(
                                startingMouseX: startingMouseX,
                                currentMouseX: currentMouseX
                            )
                            let newWidth = startingWidth + mouseMovement
                            let clampedWidth = max(minWidth, min(maxWidth, newWidth))
                                .rounded(.toNearestOrAwayFromZero)
                            guard clampedWidth != lastAppliedWidth else { return }
                            lastAppliedWidth = clampedWidth

                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                onResize(clampedWidth, windowState, false)
                            }
                        }
                        .onEnded { _ in
                            isResizing = false
                            lastAppliedWidth = 0
                            onEndResize(windowState)
                        }
                )
        }
        .frame(width: SidebarResizeMetrics.hitAreaWidth)
        .chromeCursor(.resizeLeftRight, isEnabled: windowState.isSidebarVisible)
        .accessibilityLabel("Resize sidebar")
        .accessibilityHint("Drag horizontally to change the sidebar width.")
    }

    @ViewBuilder
    private var indicator: some View {
        if isHovering || isResizing {
            ZStack {
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .separatorColor).opacity(isResizing ? 0.48 : 0.30))
                    .frame(width: SidebarResizeMetrics.indicatorWidth)
                    .frame(maxHeight: .infinity)

                Capsule(style: .continuous)
                    .fill(tokens.accent.opacity(isResizing ? 0.82 : 0.46))
                    .frame(
                        width: SidebarResizeMetrics.grabberWidth,
                        height: SidebarResizeMetrics.grabberHeight
                    )
            }
            .offset(x: indicatorOffset)
            .padding(.vertical, SidebarResizeMetrics.hitAreaVerticalInset)
            .animation(.easeInOut(duration: 0.12), value: isHovering)
            .animation(.easeInOut(duration: 0.08), value: isResizing)
        }
    }
}
