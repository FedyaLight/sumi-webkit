//
//  URLBarZoomIndicator.swift
//  Sumi
//
//  URL bar zoom percentage pill shown when zoom is not 100%.
//

import AppKit
import SwiftUI
import WebKit

struct URLBarZoomButtonVisibility {
    static func shouldShow(
        hasURL: Bool,
        isEditing: Bool,
        isDefaultZoom: Bool
    ) -> Bool {
        hasURL && !isEditing && !isDefaultZoom
    }
}

extension URLBarView {
    func zoomIndicator(for currentTab: Tab) -> some View {
        let percentage = zoomPercentageDisplay(for: currentTab)
        let action = {
            browserContext.zoom.resetCurrentTab(windowState)
        }

        return Button(action: action) {
            Text(percentage)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(URLBarZoomIndicatorStyle())
        .help("Reset zoom to 100%")
        .accessibilityLabel("Zoom \(percentage). Reset zoom to 100%.")
        .fixedSize(horizontal: true, vertical: false)
        .sidebarAppKitPrimaryAction(action: action)
    }

    func shouldShowZoomIndicator(for tab: Tab) -> Bool {
        let _ = browserContext.zoom.stateRevision
        return URLBarZoomButtonVisibility.shouldShow(
            hasURL: isZoomIndicatorURLAvailable(for: tab),
            isEditing: windowState.isFloatingBarVisible,
            isDefaultZoom: browserContext.zoom.manager.isDefaultZoom(for: tab.id)
        )
    }

    func isZoomIndicatorURLAvailable(for tab: Tab) -> Bool {
        tab.url.scheme?.isEmpty == false
    }

    func zoomPercentageDisplay(for tab: Tab) -> String {
        let _ = browserContext.zoom.stateRevision
        return browserContext.zoom.manager.getZoomPercentageDisplay(for: tab.id)
    }
}

struct URLBarZoomIndicatorStyle: ButtonStyle {
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tokens.primaryText)
            .padding(.horizontal, 8)
            .frame(minWidth: 44, minHeight: 28, maxHeight: 28)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .opacity(isEnabled ? 1 : 0.3)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        ThemeChromeRecipeBuilder.urlBarToolbarIconButtonBackground(
            tokens: tokens,
            isHovering: isHovering,
            isPressed: isPressed,
            isEnabled: isEnabled
        )
    }
}
