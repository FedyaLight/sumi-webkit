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
        if currentTab.representsSumiNativeSurface {
            EmptyView()
        } else {
            let showsZoomIndicator = shouldShowZoomIndicator(for: currentTab)
            let permissionIndicatorState = permissionIndicatorDisplayState(for: currentTab)
            HStack(spacing: 6) {
                urlBarExtensionActions
                if showsZoomIndicator {
                    zoomIndicator(for: currentTab)
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.82).combined(with: .opacity),
                                removal: .scale(scale: 0.92).combined(with: .opacity)
                            )
                        )
                }
                copyLinkButton(for: currentTab)
                hubButton
                if permissionIndicatorState.isVisible {
                    permissionIndicatorButton(for: currentTab, state: permissionIndicatorState)
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.82).combined(with: .opacity),
                                removal: .scale(scale: 0.92).combined(with: .opacity)
                            )
                        )
                }
            }
            .fixedSize(horizontal: true, vertical: false)
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
            .animation(.smooth(duration: 0.18), value: showsZoomIndicator)
            .animation(.smooth(duration: 0.18), value: permissionIndicatorState.isVisible)
        }
    }

    @ViewBuilder
    var urlBarExtensionActions: some View {
        if ExtensionActionPlacement.resolve(totalActions: orderedExtensionActionCount) == .urlBar {
            browserContext.extensionActions.compactStrip(
                extensionDisplayModel.snapshot.enabledExtensions,
                extensionDisplayModel.snapshot.pinnedExtensionIDs,
                windowState,
                extensionToolbarProfileID
            )
            .environment(windowState)
            .accessibilityIdentifier("urlbar-extension-action-strip")
        }
    }

    var orderedExtensionActionCount: Int {
        let pinnedIDs = Set(extensionDisplayModel.snapshot.pinnedExtensionIDs)
        return extensionDisplayModel.snapshot.enabledExtensions.count {
            $0.hasAction && pinnedIDs.contains($0.id)
        }
    }

    func copyLinkButton(for currentTab: Tab) -> some View {
        let url = activePageURL ?? currentTab.url
        let action = {
            _ = browserContext.copyURLToClipboard(url.absoluteString, windowState)
        }
        let isAvailable = isCopyLinkAvailable(for: url)

        return Button("Copy Link", systemImage: "link", action: action)
        .labelStyle(.iconOnly)
        .buttonStyle(URLBarButtonStyle())
        .foregroundStyle(tokens.primaryText)
        .help("Copy Link")
        .disabled(!isAvailable)
        .sidebarAppKitPrimaryAction(isEnabled: isAvailable, action: action)
    }

    var hubButton: some View {
        let action = {
            browserContext.toggleURLBarHubPopover(windowState)
        }

        return Button(action: action) {
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
        .background(
            URLBarHubPopoverAnchorView(
                presenter: browserContext.hubPopoverPresenter,
                browserContext: browserContext.hub,
                windowState: windowState,
                settings: sumiSettings,
                windowRegistry: windowRegistry,
                themeContext: themeContext,
                currentTab: currentTab,
                profile: effectiveProfile,
                profileId: effectiveProfileId
            )
            .allowsHitTesting(false)
        )
        .sidebarAppKitPrimaryAction(action: action)
    }

    func isCopyLinkAvailable(for url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

// MARK: - URL Bar Button Style
struct URLBarButtonStyle: ButtonStyle {
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens
    @Environment(\.isEnabled) var isEnabled
    @State private var isHovering = false

    private let cornerRadius: CGFloat = 12
    private let size: CGFloat = 28

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
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
        .sidebarHover($isHovering)
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
