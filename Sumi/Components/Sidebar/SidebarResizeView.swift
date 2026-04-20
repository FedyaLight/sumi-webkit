//
//  SidebarResizeView.swift
//  Sumi
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI

struct SidebarResizeView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isResizing = false
    @State private var isHovering = false
    @State private var startingWidth: CGFloat = 0
    @State private var startingMouseX: CGFloat = 0
    @State private var dragSessionID: String = UUID().uuidString
    @State private var hoverTask: Task<Void, Never>?
    private let minWidth: CGFloat = BrowserWindowState.sidebarMinimumWidth
    private let maxWidth: CGFloat = BrowserWindowState.sidebarMaximumWidth

    private var sitsOnRight: Bool {
        false
    }

    private var indicatorOffset: CGFloat {
        sitsOnRight ? 3 : -3
    }

    private var hitAreaOffset: CGFloat {
        sitsOnRight ? 5 : -5
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        ZStack {
            if isHovering || isResizing {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tokens.accent.opacity(isResizing ? 0.14 : 0.08))
                        .frame(width: 8)
                        .frame(maxHeight: .infinity)

                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tokens.accent.opacity(isResizing ? 0.95 : 0.82))
                        .frame(width: 2, height: 50)
                }
                .offset(x: indicatorOffset)
                .animation(.easeInOut(duration: 0.15), value: isResizing)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
                .padding(.vertical, 20)
            }

            Rectangle()
                .fill(Color.clear)
                .frame(width: 12)
                .padding(.vertical, 30)
                .offset(x: hitAreaOffset)
                .contentShape(.interaction, .rect)
                .onHover { hovering in
                    guard windowState.isSidebarVisible else { return }

                    hoverTask?.cancel()

                    if hovering && !isResizing {
                        hoverTask = Task {
                            try? await Task.sleep(for: .seconds(0.1))
                            guard !Task.isCancelled else { return }
                            isHovering = true
                            NSCursor.resizeLeftRight.set()
                        }
                    } else {
                        isHovering = false
                        if !isResizing {
                            NSCursor.arrow.set()
                        }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { value in
                            guard windowState.isSidebarVisible else { return }

                            if !isResizing {
                                startingWidth = windowState.sidebarWidth
                                startingMouseX = value.startLocation.x
                                isResizing = true
                                NSCursor.resizeLeftRight.set()
                            }

                            let currentMouseX = value.location.x
                            let mouseMovement = sitsOnRight ? (startingMouseX - currentMouseX) : (currentMouseX - startingMouseX)
                            let newWidth = startingWidth + mouseMovement
                            let clampedWidth = max(minWidth, min(maxWidth, newWidth))

                            browserManager.updateSidebarWidth(
                                clampedWidth,
                                for: windowState,
                                persist: false
                            )
                        }
                        .onEnded { _ in
                            isResizing = false
                            browserManager.persistWindowSession(for: windowState)

                            if isHovering {
                                NSCursor.resizeLeftRight.set()
                            } else {
                                NSCursor.arrow.set()
                            }
                        }
                )
        }
        .frame(width: 8)
    }
}
