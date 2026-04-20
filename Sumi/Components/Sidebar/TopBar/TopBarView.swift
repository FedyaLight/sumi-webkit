//
//  TopBarView.swift
//  Sumi
//
//  Created by Assistant on 23/09/2025.
//

import AppKit
import SwiftUI

enum TopBarMetrics {
    static let height: CGFloat = 40
    static let horizontalPadding: CGFloat = 6
    static let verticalPadding: CGFloat = 5
}

struct TopBarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @StateObject private var tabWrapper = ObservableTabWrapper()
    @State private var previousTabId: UUID? = nil

    var body: some View {
        let cornerRadius: CGFloat = {
            if #available(macOS 26.0, *) {
                return 8
            } else {
                return 8
            }
        }()

        ZStack {
            // Main content
            ZStack {
                HStack(spacing: 8) {
                    navigationControls

                    // URL bar uses the same translucent veil as the sidebar; the strip behind it is opaque `toolbarBackground`, so the pill reads as neutral glass on a solid bar (not over the page gradient).
                    URLBarView(presentationMode: .topBar)
                        .environmentObject(browserManager)
                        .environment(windowState)

                    Spacer()

                }

            }
            .padding(.horizontal, TopBarMetrics.horizontalPadding)
            .padding(.vertical, TopBarMetrics.verticalPadding)
            .frame(maxWidth: .infinity)
            .frame(height: TopBarMetrics.height)
            .background(topBarBackgroundColor)
            .animation(
                shouldAnimateColorChange ? .easeInOut(duration: 0.3) : nil,
                value: topBarBackgroundColor
            )
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: cornerRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: cornerRadius,
                    style: .continuous
                )
            )
            .overlay(alignment: .bottom) {
                // 1px bottom border - lighter when dark, darker when light
                Rectangle()
                    .fill(bottomBorderColor)
                    .frame(height: 1)
                    .animation(
                        shouldAnimateColorChange
                            ? .easeInOut(duration: 0.3) : nil,
                        value: bottomBorderColor
                    )
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(
                        key: URLBarFramePreferenceKey.self,
                        value: geometry.frame(in: .named("WindowSpace"))
                    )
            }
        )
        .onAppear {
            tabWrapper.setContext(
                browserManager: browserManager,
                windowState: windowState
            )
            updateCurrentTab()
            // Initialize previousTabId to current tab so first color change doesn't animate
            previousTabId = browserManager.currentTab(for: windowState)?.id
        }
        .onChange(of: browserManager.currentTab(for: windowState)?.id) {
            oldId,
            newId in
            DispatchQueue.main.async {
                previousTabId = oldId
                updateCurrentTab()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    previousTabId = newId
                }
            }
        }
    }

    private var navigationControls: some View {
        HStack(spacing: 4) {
            Button("Go Back", systemImage: "chevron.backward", action: goBack)
                .labelStyle(.iconOnly)
                .buttonStyle(NavButtonStyle())
                .disabled(!tabWrapper.canGoBack)
                .opacity(tabWrapper.canGoBack ? 1.0 : 0.4)
                .sumiAppKitContextMenu(entries: {
                    NavigationHistoryContextMenuEntries.make(
                        historyType: .back,
                        windowState: windowState,
                        browserManager: browserManager
                    )
                })

            Button(
                "Go Forward",
                systemImage: "chevron.right",
                action: goForward
            )
            .labelStyle(.iconOnly)
            .buttonStyle(NavButtonStyle())
            .disabled(!tabWrapper.canGoForward)
            .opacity(tabWrapper.canGoForward ? 1.0 : 0.4)
            .sumiAppKitContextMenu(entries: {
                NavigationHistoryContextMenuEntries.make(
                    historyType: .forward,
                    windowState: windowState,
                    browserManager: browserManager
                )
            })

            Button(
                "Reload",
                systemImage: "arrow.clockwise",
                action: refreshCurrentTab
            )
            .labelStyle(.iconOnly)
            .buttonStyle(NavButtonStyle())
        }
    }

    private func updateCurrentTab() {
        tabWrapper.updateTab(browserManager.currentTab(for: windowState))
    }

    private func goBack() {
        if let tab = tabWrapper.tab,
            let webView = browserManager.getWebView(
                for: tab.id,
                in: windowState.id
            )
        {
            webView.goBack()
        } else {
            tabWrapper.tab?.goBack()
        }
    }

    private func goForward() {
        if let tab = tabWrapper.tab,
            let webView = browserManager.getWebView(
                for: tab.id,
                in: windowState.id
            )
        {
            webView.goForward()
        } else {
            tabWrapper.tab?.goForward()
        }
    }

    private func refreshCurrentTab() {
        tabWrapper.tab?.refresh()
    }

    // Determine if we should animate color changes (within same tab) or snap (tab switch)
    private var shouldAnimateColorChange: Bool {
        let currentTabId = browserManager.currentTab(for: windowState)?.id
        return currentTabId == previousTabId
    }

    private var topBarBackgroundColor: Color {
        tokens.toolbarBackground
    }

    private var navButtonColor: Color {
        tokens.primaryText.opacity(0.92)
    }

    private var bottomBorderColor: Color {
        tokens.separator
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}
