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
    func permissionIndicatorButton(
        for currentTab: Tab,
        state: SumiPermissionIndicatorState
    ) -> some View {
        let action = { handlePermissionIndicatorClick() }

        return SumiPermissionIndicatorButton(state: state, action: action)
        .sidebarAppKitPrimaryAction(action: action)
        .popover(isPresented: $permissionPromptPresenter.isPresented, arrowEdge: .bottom) {
            if let viewModel = permissionPromptPresenter.viewModel {
                SumiPermissionPromptView(viewModel: viewModel)
                    .environment(windowState)
            } else {
                EmptyView()
            }
        }
        .popover(isPresented: $isPermissionIndicatorPopoverPresented, arrowEdge: .bottom) {
            SumiPermissionIndicatorActionPopover(
                state: state,
                runtimeModel: permissionRuntimeControlsModel,
                onRuntimeAction: { actionKind in
                    await performPermissionRuntimeAction(actionKind)
                },
                onOpenSiteSettings: {
                    openPermissionIndicatorSiteSettings(focusing: currentTab)
                }
            )
            .environment(windowState)
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
            browserManager.closeURLBarHubPopover(in: windowState)
            closePermissionIndicatorPopover()
            return
        }

        browserManager.closeURLBarHubPopover(in: windowState)
        if isPermissionIndicatorPopoverPresented {
            closePermissionIndicatorPopover()
        } else {
            configurePermissionIndicatorPopover()
            isPermissionIndicatorPopoverPresented = true
        }
    }

    func closePermissionIndicatorPopover() {
        isPermissionIndicatorPopoverPresented = false
        permissionRuntimeControlsModel.clear()
    }

    func configurePermissionIndicatorPopover() {
        guard let currentTab else {
            permissionRuntimeControlsModel.clear()
            return
        }

        permissionRuntimeControlsModel.load(
            pageContext: permissionRuntimeControlsPageContext(for: currentTab),
            runtimeController: browserManager.runtimePermissionController,
            reloadRequired: currentTab.isAutoplayReloadRequired,
            onRuntimeStateChanged: {
                refreshPermissionIndicator(for: currentTab)
            }
        )
    }

    func performPermissionRuntimeAction(
        _ actionKind: SumiPermissionRuntimeControl.Action.Kind
    ) async {
        _ = await permissionRuntimeControlsModel.perform(actionKind)
        if let currentTab {
            refreshPermissionIndicator(for: currentTab)
        }
    }

    func openPermissionIndicatorSiteSettings(focusing tab: Tab) {
        closePermissionIndicatorPopover()
        browserManager.openSiteSettingsTab(
            focusing: tab,
            in: windowState
        )
    }

    func permissionRuntimeControlsPageContext(
        for tab: Tab
    ) -> SumiPermissionRuntimeControlsViewModel.PageContext? {
        guard let context = SumiCurrentSitePermissionsViewModel.context(
            tab: tab,
            profile: effectiveProfile
        ),
              context.isSupportedWebOrigin
        else { return nil }

        return SumiPermissionRuntimeControlsViewModel.PageContext(
            tabId: context.tabId,
            pageId: context.pageId,
            navigationOrPageGeneration: context.navigationOrPageGeneration,
            displayDomain: context.displayDomain,
            currentWebView: { [weak tab] in
                tab?.existingWebView
            },
            isCurrentPage: { [weak tab] tabId, pageId, navigationOrPageGeneration in
                guard let tab else { return false }
                return tab.id.uuidString.lowercased() == tabId
                    && tab.currentPermissionPageId() == pageId
                    && String(tab.extensionRuntimeDocumentSequence) == navigationOrPageGeneration
            },
            reloadPage: { [weak tab] in
                guard let tab,
                      tab.existingWebView != nil
                else { return false }
                tab.refresh()
                tab.updateAutoplayReloadRequirementForCurrentSite()
                return true
            },
            isGeolocationStillAllowed: {
                let decision = await browserManager.permissionCoordinator.queryPermissionState(
                    context.securityContext(for: .geolocation)
                )
                return decision.outcome == .granted || decision.state == .allow
            },
            clearGeolocationGrantForVisit: {
                await browserManager.permissionCoordinator.resetTransientDecisions(
                    profilePartitionId: context.profilePartitionId,
                    pageId: context.pageId,
                    requestingOrigin: context.origin,
                    topOrigin: context.origin,
                    reason: "runtime-stop-geolocation-from-indicator"
                )
            }
        )
    }

    func permissionIndicatorTaskKey(for tab: Tab) -> String {
        [
            tab.id.uuidString.lowercased(),
            tab.currentPermissionPageId(),
            tab.url.absoluteString,
            tab.isAutoplayReloadRequired.description,
        ].joined(separator: "|")
    }

    func permissionIndicatorDisplayState(for currentTab: Tab) -> SumiPermissionIndicatorState {
        if browserManager.urlBarHubPopoverPresenter.isPresented(in: windowState) {
            return .hidden
        }

        let state = permissionIndicatorViewModel.state
        guard !state.isVisible,
              let promptViewModel = permissionPromptPresenter.viewModel
        else {
            return state
        }

        return promptIndicatorState(for: promptViewModel, currentTab: currentTab)
    }

    func promptIndicatorState(
        for viewModel: SumiPermissionPromptViewModel,
        currentTab: Tab
    ) -> SumiPermissionIndicatorState {
        let category: SumiPermissionIndicatorCategory = viewModel.isSystemBlocked
            ? .systemBlocked
            : .pendingRequest
        let visualStyle: SumiPermissionIndicatorVisualStyle = viewModel.isSystemBlocked
            ? .systemWarning
            : .attention
        let priority: SumiPermissionIndicatorPriority
        switch category {
        case .systemBlocked:
            priority = viewModel.permissionType.isSensitivePowerful
                ? .systemBlockedSensitive
                : .genericPermissionsFallback
        case .pendingRequest:
            priority = viewModel.permissionType.isSensitivePowerful
                ? .pendingSensitiveRequest
                : .genericPermissionsFallback
        case .hidden,
             .activeRuntime,
             .blockedEvent,
             .storedException,
             .reloadRequired,
             .mixed:
            priority = .genericPermissionsFallback
        }

        return SumiPermissionIndicatorState.visible(
            category: category,
            primaryPermissionType: viewModel.permissionType,
            relatedPermissionTypes: viewModel.permissionTypes,
            displayDomain: viewModel.displayDomain,
            tabId: currentTab.id.uuidString.lowercased(),
            pageId: currentTab.currentPermissionPageId(),
            priority: priority,
            visualStyle: visualStyle,
            badgeCount: viewModel.permissionTypes.count > 1 ? viewModel.permissionTypes.count : nil
        )
    }
}

private struct SumiPermissionIndicatorActionPopover: View {
    let state: SumiPermissionIndicatorState
    @ObservedObject var runtimeModel: SumiPermissionRuntimeControlsViewModel
    let onRuntimeAction: (SumiPermissionRuntimeControl.Action.Kind) async -> Void
    let onOpenSiteSettings: () -> Void

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if runtimeModel.hasVisibleContent {
                SumiPermissionRuntimeControlsView(
                    model: runtimeModel,
                    onAction: onRuntimeAction
                )
            } else {
                Text("Manage this permission from site settings.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(tokens.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            Button(action: onOpenSiteSettings) {
                Label("Site Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(SumiPermissionIndicatorFooterButtonStyle())
            .accessibilityIdentifier("urlbar-permission-indicator-site-settings")
        }
        .padding(10)
        .frame(width: 286)
        .background(NativeChromeMaterialBackground(role: .popover))
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tokens.fieldBackground)
                SumiZenChromeIcon(
                    iconName: state.icon.chromeIconName,
                    fallbackSystemName: state.icon.fallbackSystemName,
                    size: 16,
                    tint: tokens.primaryText
                )
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tokens.primaryText)
                    .lineLimit(1)

                Text(state.displayDomain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(tokens.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    private var headerTitle: String {
        if state.category == .mixed {
            return "Site permissions"
        }
        return state.primaryPermissionType?.indicatorDisplayName ?? "Permissions"
    }
}

private struct SumiPermissionIndicatorFooterButtonStyle: ButtonStyle {
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(tokens.primaryText)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .opacity(isEnabled ? 1 : tokens.popoverActionDisabledAlpha)
            .onHover { hovering in
                isHovered = hovering
            }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        ThemeChromeRecipeBuilder.urlBarPillFieldBackground(
            tokens: tokens,
            isPressed: isPressed,
            isHovering: isHovered,
            isEnabled: isEnabled
        )
    }
}

private struct SumiPermissionIndicatorButton: View {
    let state: SumiPermissionIndicatorState
    let action: () -> Void

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
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
