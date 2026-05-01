//
//  URLBarTrailingActions.swift
//  Sumi
//
//  Canonical Sumi browser URL bar hosted from the sidebar shell.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension URLBarView {
    @ViewBuilder
    func trailingActions(for currentTab: Tab) -> some View {
        let showsZoomButton = shouldShowZoomButton(for: currentTab)
        HStack(spacing: 6) {
            copyLinkButton(for: currentTab)
            hubButton
            if permissionIndicatorViewModel.state.isVisible {
                permissionIndicatorButton(for: currentTab)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.82).combined(with: .opacity),
                            removal: .scale(scale: 0.92).combined(with: .opacity)
                        )
                    )
            }
            if showsZoomButton {
                zoomButton(for: currentTab)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.82).combined(with: .opacity),
                            removal: .scale(scale: 0.92).combined(with: .opacity)
                        )
                    )
            }
        }
        .task(id: permissionIndicatorTaskKey(for: currentTab)) {
            refreshPermissionIndicator(for: currentTab)
            refreshPermissionPrompt(for: currentTab)
        }
        .onReceive(NotificationCenter.default.publisher(for: .sumiTabNavigationStateDidChange)) { notification in
            guard let tab = notification.object as? Tab,
                  tab.id == currentTab.id
            else { return }
            refreshPermissionIndicator(for: tab)
            refreshPermissionPrompt(for: tab)
        }
        .animation(.smooth(duration: 0.18), value: showsZoomButton)
        .animation(.smooth(duration: 0.18), value: permissionIndicatorViewModel.state.isVisible)
    }

    func copyLinkButton(for currentTab: Tab) -> some View {
        Button("Copy Link", systemImage: showCheckmark ? "checkmark" : "link") {
            copyURLToClipboard(currentTab.url.absoluteString)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(URLBarButtonStyle())
        .foregroundStyle(tokens.primaryText)
        .help("Copy Link")
        .contentTransition(.symbolEffect(.replace))
        .disabled(!isCopyLinkAvailable(for: currentTab))
    }

    var hubButton: some View {
        Button {
            hubInitialMode = .controls
            hubModeRequestNonce += 1
            isHubPresented.toggle()
        } label: {
            Group {
                switch siteControlsSnapshot.hubAnchorAppearance {
                case .zenPermissions:
                    SumiZenChromeIcon(
                        iconName: "permissions",
                        fallbackSystemName: "line.3.horizontal.decrease.circle",
                        size: 15,
                        tint: tokens.primaryText
                    )
                }
            }
            .frame(width: 15, height: 15)
        }
        .buttonStyle(URLBarButtonStyle())
        .help("Site Controls")
        .accessibilityIdentifier("urlbar-site-controls-button")
        .popover(isPresented: $isHubPresented, arrowEdge: .bottom) {
            URLBarHubPopover(
                bookmarkManager: browserManager.bookmarkManager,
                bookmarkPresentationRequest: browserManager.bookmarkEditorPresentationRequest,
                currentTab: currentTab,
                profile: effectiveProfile,
                profileId: effectiveProfileId,
                initialMode: hubInitialMode,
                modeRequestNonce: hubModeRequestNonce,
                onClose: { isHubPresented = false }
            )
            .environmentObject(browserManager)
            .environment(windowState)
        }
    }

    func copyURLToClipboard(_ urlString: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlString, forType: .string)

        withAnimation(.easeInOut(duration: 0.2)) {
            showCheckmark = true
        }

        windowState.isShowingCopyURLToast = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showCheckmark = false
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            windowState.isShowingCopyURLToast = false
        }
    }

    func isCopyLinkAvailable(for tab: Tab) -> Bool {
        guard let scheme = tab.url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

// MARK: - URL Bar Button Style
struct URLBarButtonStyle: ButtonStyle {
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.isEnabled) var isEnabled
    @State private var isHovering = false

    private let cornerRadius: CGFloat = 12
    private let size: CGFloat = 28

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(backgroundColor(isPressed: configuration.isPressed))
                .frame(width: size, height: size)

            configuration.label
                .foregroundStyle(tokens.primaryText)
        }
        .opacity(isEnabled ? 1.0 : 0.3)
        .contentTransition(.symbolEffect(.replace.upUp.byLayer, options: .nonRepeating))
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
