//
//  URLBarPermissionViews.swift
//  Sumi
//
//  Canonical Sumi browser URL bar hosted from the sidebar shell.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension URLBarView {
    func permissionIndicatorButton(for currentTab: Tab) -> some View {
        let action = { handlePermissionIndicatorClick() }

        return SumiPermissionIndicatorButton(viewModel: permissionIndicatorViewModel, action: action)
        .sidebarAppKitPrimaryAction(action: action)
        .popover(isPresented: $permissionPromptPresenter.isPresented, arrowEdge: .bottom) {
            if let viewModel = permissionPromptPresenter.viewModel {
                SumiPermissionPromptView(viewModel: viewModel)
                    .environmentObject(browserManager)
                    .environment(windowState)
            } else {
                EmptyView()
            }
        }
    }

    func configurePermissionIndicatorIfNeeded() {
        permissionIndicatorViewModel.configure(
            coordinator: browserManager.permissionCoordinator,
            runtimeController: browserManager.runtimePermissionController,
            popupStore: browserManager.blockedPopupStore,
            externalSchemeStore: browserManager.externalSchemeSessionStore,
            indicatorEventStore: browserManager.permissionIndicatorEventStore
        )
    }

    func configurePermissionPromptIfNeeded() {
        permissionPromptPresenter.configure(
            coordinator: browserManager.permissionCoordinator,
            systemPermissionService: browserManager.systemPermissionService,
            externalAppResolver: browserManager.externalAppResolver
        )
    }

    func refreshPermissionIndicator(for tab: Tab) {
        configurePermissionIndicatorIfNeeded()
        permissionIndicatorViewModel.update(
            tab: tab,
            windowId: windowState.id,
            browserManager: browserManager
        )
    }

    func refreshPermissionPrompt(for tab: Tab) {
        configurePermissionPromptIfNeeded()
        permissionPromptPresenter.update(
            tab: tab,
            windowState: windowState,
            browserManager: browserManager
        )
    }

    func handlePermissionIndicatorClick() {
        closeZoomPopover()
        if permissionPromptPresenter.presentFromIndicatorClick() {
            isHubPresented = false
            return
        }

        if permissionIndicatorViewModel.state.prefersRuntimeControlsSurface {
            hubInitialMode = .permissions
        } else {
            hubInitialMode = .controls
        }
        hubModeRequestNonce += 1
        isHubPresented = true
    }

    func permissionIndicatorTaskKey(for tab: Tab) -> String {
        [
            tab.id.uuidString.lowercased(),
            tab.currentPermissionPageId(),
            tab.url.absoluteString,
            tab.isAutoplayReloadRequired.description,
        ].joined(separator: "|")
    }

}

private struct SumiPermissionIndicatorButton: View {
    @ObservedObject var viewModel: SumiPermissionIndicatorViewModel
    let action: () -> Void

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var state: SumiPermissionIndicatorState {
        viewModel.state
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                SumiZenChromeIcon(
                    iconName: state.icon.chromeIconName,
                    fallbackSystemName: state.icon.fallbackSystemName,
                    size: 15,
                    tint: iconTint
                )
                .frame(width: 15, height: 15)

                if state.visualStyle == .systemWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(tokens.secondaryText)
                        .offset(x: 5, y: -5)
                        .accessibilityHidden(true)
                } else if let badgeCount = state.badgeCount, badgeCount > 1 {
                    Text(min(badgeCount, 99).description)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(badgeTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(minWidth: 10, minHeight: 10)
                        .padding(.horizontal, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(badgeFill)
                        )
                        .offset(x: 7, y: -7)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 15, height: 15)
        }
        .buttonStyle(
            URLBarPermissionIndicatorButtonStyle(
                visualStyle: state.visualStyle
            )
        )
        .frame(width: 28, height: 28)
        .help(state.title)
        .accessibilityIdentifier("urlbar-permission-indicator")
        .accessibilityLabel(Text(state.accessibilityLabel))
    }

    private var iconTint: Color {
        switch state.visualStyle {
        case .active, .reloadRequired:
            return tokens.primaryText
        case .attention:
            return tokens.primaryText
        case .blocked:
            return tokens.secondaryText
        case .systemWarning:
            return tokens.primaryText
        case .neutral:
            return tokens.primaryText
        }
    }

    private var badgeFill: Color {
        switch state.visualStyle {
        case .active,
             .attention,
             .blocked,
             .systemWarning,
             .reloadRequired,
             .neutral:
            return tokens.secondaryText.opacity(0.82)
        }
    }

    private var badgeTextColor: Color {
        switch state.visualStyle {
        case .active,
             .attention,
             .blocked,
             .systemWarning,
             .reloadRequired,
             .neutral:
            return tokens.fieldBackground
        }
    }
}

private struct URLBarPermissionIndicatorButtonStyle: ButtonStyle {
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    let visualStyle: SumiPermissionIndicatorVisualStyle

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(backgroundColor(isPressed: configuration.isPressed))
                .frame(width: 28, height: 28)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(borderColor, lineWidth: 0.75)
                }

            configuration.label
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .scaleEffect(configuration.isPressed && isEnabled ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        guard isEnabled else { return .clear }
        if isPressed {
            return tokens.fieldBackgroundHover.opacity(0.96)
        }
        if isHovering {
            return tokens.fieldBackgroundHover.opacity(0.88)
        }
        switch visualStyle {
        case .active, .attention, .systemWarning, .reloadRequired:
            return tokens.fieldBackgroundHover.opacity(0.74)
        case .blocked:
            return tokens.secondaryText.opacity(0.10)
        case .neutral:
            return .clear
        }
    }

    private var borderColor: Color {
        guard isEnabled else { return .clear }
        switch visualStyle {
        case .active, .blocked, .systemWarning, .reloadRequired:
            return tokens.secondaryText.opacity(0.20)
        case .attention, .neutral:
            return .clear
        }
    }
}
