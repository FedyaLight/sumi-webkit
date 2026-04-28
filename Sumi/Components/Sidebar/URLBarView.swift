//
//  URLBarView.swift
//  Sumi
//
//  Canonical Sumi browser URL bar hosted from the sidebar shell.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

enum URLBarPresentationMode {
    case sidebar
    case topBar

    var height: CGFloat {
        switch self {
        case .sidebar: 36
        case .topBar: 30
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .sidebar: 12
        case .topBar: 8
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .sidebar: 12
        case .topBar: 13
        }
    }
}

private enum URLBarHubInitialMode {
    case controls
    case permissions
}

struct URLBarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    let presentationMode: URLBarPresentationMode

    @State private var isHovering = false
    @State private var showCheckmark = false
    @State private var isHubPresented = false
    @State private var hubInitialMode: URLBarHubInitialMode = .controls
    @State private var hubModeRequestNonce = 0
    @State private var isZoomPopoverPresented = false
    @State private var zoomPopoverSource: ZoomPopoverSource = .toolbar
    @State private var zoomPopoverSize = CGSize(width: 252, height: 48)
    @State private var isZoomButtonHovering = false
    @State private var isZoomPopoverHovering = false
    @State private var zoomPopoverHideTimer: Timer?
    @State private var didConfigurePermissionIndicator = false
    @State private var didConfigurePermissionPrompt = false
    @StateObject private var permissionIndicatorViewModel = SumiPermissionIndicatorViewModel()
    @StateObject private var permissionPromptPresenter = SumiPermissionPromptPresenter()

    init(
        presentationMode: URLBarPresentationMode = .sidebar
    ) {
        self.presentationMode = presentationMode
    }

    var body: some View {
        let cornerRadius = sumiSettings.resolvedCornerRadius(
            presentationMode.cornerRadius
        )

        VStack(alignment: .leading, spacing: presentationMode == .sidebar ? 6 : 0) {
            HStack(spacing: 8) {
                leadingContent
                Spacer(minLength: 8)

                if let currentTab = currentTab {
                    trailingActions(for: currentTab)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .frame(
                maxWidth: .infinity,
                minHeight: presentationMode.height,
                maxHeight: presentationMode.height
            )
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: URLBarFramePreferenceKey.self,
                        value: proxy.frame(in: .named("WindowSpace"))
                    )
                }
            )
            .contentShape(Rectangle())
            .accessibilityIdentifier(
                presentationMode == .sidebar
                    ? "sidebar-urlbar"
                    : "topbar-urlbar"
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isHovering = hovering
                }
            }
            .onTapGesture {
                guard !isZoomButtonHovering else { return }
                let currentURL = currentTab?.url.absoluteString ?? ""
                browserManager.openCommandPalette(
                    in: windowState,
                    reason: .keyboard,
                    prefill: currentURL,
                    navigateCurrentTab: true
                )
            }
        }
        .onChange(of: browserManager.zoomPopoverRequest) { _, request in
            handleZoomPopoverRequest(request)
        }
        .onChange(of: browserManager.bookmarkEditorPresentationRequest) { _, request in
            handleBookmarkEditorPresentationRequest(request)
        }
        .onChange(of: currentTab?.id) { _, _ in
            DispatchQueue.main.async {
                closeZoomPopover()
                isHubPresented = false
                permissionPromptPresenter.closeForCurrentTabChange()
            }
        }
        .onChange(of: permissionPromptPresenter.isPresented) { _, isPresented in
            if isPresented {
                isHubPresented = false
            }
        }
        .onDisappear {
            invalidateZoomPopoverHideTimer()
            isHubPresented = false
            permissionPromptPresenter.clear()
        }
    }

    private var currentTab: Tab? {
        let currentTabId = windowState.currentTabId
        if windowState.isIncognito {
            return windowState.ephemeralTabs.first { $0.id == currentTabId }
        }
        guard let currentTabId else { return nil }
        return browserManager.tabManager.tab(for: currentTabId)
            ?? browserManager.currentTab(for: windowState)
    }

    private var effectiveProfileId: UUID? {
        windowState.currentProfileId ?? browserManager.currentProfile?.id
    }

    private var effectiveProfile: Profile? {
        if let profile = currentTab?.resolveProfile() {
            return profile
        }
        if let profileId = effectiveProfileId,
           let profile = browserManager.profileManager.profiles.first(where: { $0.id == profileId }) {
            return profile
        }
        return browserManager.currentProfile
    }

    private var siteControlsSnapshot: SiteControlsSnapshot {
        SiteControlsSnapshot.resolve(
            url: currentTab?.url,
            profile: effectiveProfile,
            showsAutoplayPermission: currentTab?.audioState.isPlayingAudio == true
        )
    }

    @ViewBuilder
    private var leadingContent: some View {
        if currentTab != nil {
            Text(displayURL)
                .font(.system(size: presentationMode.fontSize, weight: .medium))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            Image(systemName: "magnifyingglass")
                .font(.system(size: presentationMode.fontSize))
                .foregroundStyle(textColor)

            Text("Search or Enter URL...")
                .font(.system(size: presentationMode.fontSize, weight: .medium))
                .foregroundStyle(textColor)
        }
    }

    @ViewBuilder
    private func trailingActions(for currentTab: Tab) -> some View {
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

    private func copyLinkButton(for currentTab: Tab) -> some View {
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

    private func permissionIndicatorButton(for currentTab: Tab) -> some View {
        SumiPermissionIndicatorButton(viewModel: permissionIndicatorViewModel) {
            handlePermissionIndicatorClick()
        }
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

    private func zoomButton(for currentTab: Tab) -> some View {
        Button {
            toggleZoomPopoverFromToolbar(for: currentTab)
        } label: {
            Image(zoomButtonImageName(for: currentTab))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
        }
        .buttonStyle(URLBarButtonStyle())
        .help("Zoom")
        .onHover { hovering in
            isZoomButtonHovering = hovering
            updateZoomPopoverAutoCloseTimer()
        }
        .popover(isPresented: $isZoomPopoverPresented, arrowEdge: .bottom) {
            URLBarZoomPopoverView(
                currentTab: currentTab,
                onMouseOverChange: { hovering in
                    isZoomPopoverHovering = hovering
                    updateZoomPopoverAutoCloseTimer()
                }
            )
            .environmentObject(browserManager)
            .environment(windowState)
            .frame(width: zoomPopoverSize.width, height: zoomPopoverSize.height)
            .onDisappear {
                invalidateZoomPopoverHideTimer()
                isZoomPopoverHovering = false
            }
        }
    }

    private var hubButton: some View {
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

    private var backgroundColor: Color {
        isHovering ? tokens.fieldBackgroundHover : tokens.fieldBackground
    }

    private var textColor: Color {
        tokens.secondaryText
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private func shouldShowZoomButton(for tab: Tab) -> Bool {
        _ = browserManager.zoomStateRevision
        return URLBarZoomButtonVisibility.shouldShow(
            hasURL: isZoomButtonURLAvailable(for: tab),
            isEditing: windowState.isCommandPaletteVisible,
            isPopoverPresented: isZoomPopoverPresented,
            isDefaultZoom: browserManager.zoomManager.isDefaultZoom(for: tab.id)
        )
    }

    private func isZoomButtonURLAvailable(for tab: Tab) -> Bool {
        tab.url.scheme?.isEmpty == false
    }

    private func zoomButtonImageName(for tab: Tab) -> String {
        _ = browserManager.zoomStateRevision
        return browserManager.zoomManager.getZoomLevel(for: tab.id) < 1.0 ? "ZoomOut" : "ZoomIn"
    }

    private func toggleZoomPopoverFromToolbar(for tab: Tab) {
        isHubPresented = false
        zoomPopoverSource = .toolbar
        if isZoomPopoverPresented {
            closeZoomPopover()
        } else {
            isZoomPopoverPresented = true
            browserManager.requestZoomPopover(for: tab, in: windowState, source: .toolbar)
            updateZoomPopoverAutoCloseTimer()
        }
    }

    private func handleZoomPopoverRequest(_ request: ZoomPopoverRequest?) {
        guard let request,
              request.windowId == windowState.id,
              request.tabId == currentTab?.id
        else { return }

        isHubPresented = false
        zoomPopoverSource = request.source
        isZoomPopoverPresented = true
        updateZoomPopoverAutoCloseTimer()
    }

    private func handleBookmarkEditorPresentationRequest(_ request: SumiBookmarkEditorPresentationRequest?) {
        guard let request,
              request.windowID == windowState.id,
              request.tabID == currentTab?.id
        else { return }

        closeZoomPopover()
        isHubPresented = true
    }

    private func configurePermissionIndicatorIfNeeded() {
        guard !didConfigurePermissionIndicator else { return }
        permissionIndicatorViewModel.configure(
            coordinator: browserManager.permissionCoordinator,
            runtimeController: browserManager.runtimePermissionController,
            popupStore: browserManager.blockedPopupStore,
            externalSchemeStore: browserManager.externalSchemeSessionStore,
            indicatorEventStore: browserManager.permissionIndicatorEventStore
        )
        didConfigurePermissionIndicator = true
    }

    private func configurePermissionPromptIfNeeded() {
        guard !didConfigurePermissionPrompt else { return }
        permissionPromptPresenter.configure(
            coordinator: browserManager.permissionCoordinator,
            systemPermissionService: browserManager.systemPermissionService,
            externalAppResolver: browserManager.externalAppResolver
        )
        didConfigurePermissionPrompt = true
    }

    private func refreshPermissionIndicator(for tab: Tab) {
        configurePermissionIndicatorIfNeeded()
        permissionIndicatorViewModel.update(
            tab: tab,
            windowId: windowState.id,
            browserManager: browserManager
        )
    }

    private func refreshPermissionPrompt(for tab: Tab) {
        configurePermissionPromptIfNeeded()
        permissionPromptPresenter.update(
            tab: tab,
            windowState: windowState,
            browserManager: browserManager
        )
    }

    private func handlePermissionIndicatorClick() {
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

    private func permissionIndicatorTaskKey(for tab: Tab) -> String {
        [
            tab.id.uuidString.lowercased(),
            tab.currentPermissionPageId(),
            tab.url.absoluteString,
            tab.isAutoplayReloadRequired.description,
        ].joined(separator: "|")
    }

    private func updateZoomPopoverAutoCloseTimer() {
        invalidateZoomPopoverHideTimer()
        guard isZoomPopoverPresented,
              let interval = zoomPopoverSource.autoCloseInterval,
              !isZoomButtonHovering,
              !isZoomPopoverHovering
        else { return }

        zoomPopoverHideTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            Task { @MainActor in
                closeZoomPopover()
            }
        }
    }

    private func closeZoomPopover() {
        invalidateZoomPopoverHideTimer()
        isZoomPopoverPresented = false
        isZoomPopoverHovering = false
    }

    private func invalidateZoomPopoverHideTimer() {
        zoomPopoverHideTimer?.invalidate()
        zoomPopoverHideTimer = nil
    }

    private var displayURL: String {
        guard let currentTab else { return "" }
        if currentTab.representsSumiSettingsSurface {
            return String(localized: "Settings")
        }
        if currentTab.representsSumiHistorySurface {
            return String(localized: "History")
        }
        if currentTab.representsSumiBookmarksSurface {
            return String(localized: "Bookmarks")
        }
        return formatURL(currentTab.url)
    }

    private func formatURL(_ url: URL) -> String {
        if SumiSurface.isSettingsSurfaceURL(url) {
            return String(localized: "Settings")
        }
        if SumiSurface.isHistorySurfaceURL(url) {
            return String(localized: "History")
        }
        if SumiSurface.isBookmarksSurfaceURL(url) {
            return String(localized: "Bookmarks")
        }
        guard let host = url.host else {
            return url.absoluteString
        }

        return host.hasPrefix("www.")
            ? String(host.dropFirst(4))
            : host
    }

    private func copyURLToClipboard(_ urlString: String) {
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

    private func isCopyLinkAvailable(for tab: Tab) -> Bool {
        guard let scheme = tab.url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

struct URLBarZoomButtonVisibility {
    static func shouldShow(
        hasURL: Bool,
        isEditing: Bool,
        isPopoverPresented: Bool,
        isDefaultZoom: Bool
    ) -> Bool {
        hasURL && !isEditing && (!isDefaultZoom || isPopoverPresented)
    }
}

struct URLBarTrackingProtectionPresenter: Equatable {
    struct ShieldIcon: Equatable {
        let chromeIconName: String
        let fallbackSystemName: String
        let showsCheckmark: Bool
    }

    let rowTitle: String
    let rowSubtitle: String?
    let siteHost: String
    let isEnabled: Bool
    let siteOverride: SumiTrackingProtectionSiteOverride
    let isReloadRequired: Bool
    let shieldIcon: ShieldIcon
    let shieldAccessibilityLabel: String
    let shieldAccessibilityValue: String

    static func make(
        policy: SumiTrackingProtectionEffectivePolicy
    ) -> URLBarTrackingProtectionPresenter {
        make(
            policy: policy,
            siteOverride: .inherit,
            isReloadRequired: false
        )
    }

    static func make(
        policy: SumiTrackingProtectionEffectivePolicy,
        siteOverride: SumiTrackingProtectionSiteOverride,
        isReloadRequired: Bool
    ) -> URLBarTrackingProtectionPresenter {
        let isEnabled = policy.isEnabled

        return URLBarTrackingProtectionPresenter(
            rowTitle: "Tracking Protection",
            rowSubtitle: isReloadRequired ? "Reload required" : nil,
            siteHost: policy.host ?? "Current site",
            isEnabled: isEnabled,
            siteOverride: siteOverride,
            isReloadRequired: isReloadRequired,
            shieldIcon: ShieldIcon(
                chromeIconName: isEnabled ? "shield.fill" : "tracking-protection",
                fallbackSystemName: isEnabled ? "shield.fill" : "shield",
                showsCheckmark: isEnabled
            ),
            shieldAccessibilityLabel: isEnabled
                ? "Disable Tracking Protection for this site"
                : "Enable Tracking Protection for this site",
            shieldAccessibilityValue: isEnabled ? "On" : "Off"
        )
    }

    static func siteOverrideAfterToggle(
        for policy: SumiTrackingProtectionEffectivePolicy
    ) -> SumiTrackingProtectionSiteOverride {
        policy.isEnabled ? .disabled : .enabled
    }

    var visibleStrings: [String] {
        var strings = [
            rowTitle,
            siteHost,
        ]
        if let rowSubtitle {
            strings.append(rowSubtitle)
        }
        return strings
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

private struct URLBarZoomPopoverView: View {
    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    let currentTab: Tab
    let onMouseOverChange: (Bool) -> Void

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        let zoomManager = browserManager.zoomManager
        let tabId = currentTab.id
        let _ = browserManager.zoomStateRevision

        HStack(spacing: 0) {
            Text(zoomManager.getZoomPercentageDisplay(for: tabId))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tokens.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .frame(width: 69)
                .padding(.leading, 16)

            Button("Reset") {
                browserManager.resetZoomCurrentTab(in: windowState)
            }
            .buttonStyle(URLBarZoomPopoverButtonStyle(minWidth: 59))
            .help("Reset Zoom")
            .padding(.leading, 8)

            Button("Zoom Out", systemImage: "minus") {
                browserManager.zoomOutCurrentTab(in: windowState)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(URLBarZoomPopoverButtonStyle(width: 37))
            .help("Zoom Out")
            .disabled(zoomManager.isAtMinimumZoom(for: tabId))
            .padding(.leading, 8)

            Button("Zoom In", systemImage: "plus") {
                browserManager.zoomInCurrentTab(in: windowState)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(URLBarZoomPopoverButtonStyle(width: 37))
            .help("Zoom In")
            .disabled(zoomManager.isAtMaximumZoom(for: tabId))
            .padding(.leading, 1)
            .padding(.trailing, 16)
        }
        .frame(height: 48)
        .background(tokens.commandPaletteBackground)
        .onHover(perform: onMouseOverChange)
    }
}

struct URLBarZoomPopoverButtonStyle: ButtonStyle {
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    let width: CGFloat?
    let minWidth: CGFloat?

    init(width: CGFloat? = nil, minWidth: CGFloat? = nil) {
        self.width = width
        self.minWidth = minWidth
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(tokens.primaryText)
            .padding(.horizontal, width == nil ? 12 : 0)
            .frame(width: width, height: 28)
            .frame(minWidth: minWidth, minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { hovering in
                isHovering = hovering
            }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        ThemeChromeRecipeBuilder.urlBarPillFieldBackground(
            tokens: tokens,
            isPressed: isPressed,
            isHovering: isHovering,
            isEnabled: isEnabled
        )
    }
}

private struct SiteControlsSettingRowModel: Equatable, Identifiable {
    enum Kind: Equatable {
        case tracking(
            policy: SumiTrackingProtectionEffectivePolicy,
            siteOverride: SumiTrackingProtectionSiteOverride,
            reloadRequired: Bool
        )
        case cookies
        case permissions
        case localPage
    }

    let id: String
    let chromeIconName: String?
    let fallbackSystemName: String
    let title: String
    let subtitle: String?
    let kind: Kind

    var isDisabled: Bool {
        switch kind {
        case .tracking(_, _, _),
             .cookies,
             .permissions,
             .localPage:
            return false
        }
    }

    var isInteractive: Bool {
        switch kind {
        case .tracking(_, _, _),
             .cookies,
             .permissions:
            return true
        default:
            return false
        }
    }

    var showsDisclosure: Bool {
        switch kind {
        case .cookies, .permissions:
            return true
        default:
            return false
        }
    }

}

private struct SiteControlsSnapshot: Equatable {
    enum HubAnchorAppearance: Equatable {
        case zenPermissions
    }

    enum ReaderAvailability: Equatable {
        case disabledPlaceholder
        case available
    }

    enum SecurityState: Equatable {
        case secure
        case notSecure
        case localPage
        case internalPage

        var footerTitle: String {
            switch self {
            case .secure: return "Secure connection"
            case .notSecure: return "Connection not secure"
            case .localPage: return "Local page"
            case .internalPage: return "Page information"
            }
        }

        var chromeIconName: String? {
            switch self {
            case .secure:
                return "security"
            case .notSecure:
                return "security-broken"
            case .localPage:
                return nil
            case .internalPage:
                return nil
            }
        }

        var fallbackSystemName: String {
            switch self {
            case .secure: return "lock.fill"
            case .notSecure: return "lock.open.fill"
            case .localPage: return "doc.fill"
            case .internalPage: return "info.circle.fill"
            }
        }

        var showsFooterButton: Bool {
            self != .internalPage
        }

    }

    let hubAnchorAppearance: HubAnchorAppearance
    let securityState: SecurityState
    let readerAvailability: ReaderAvailability
    let settingsRows: [SiteControlsSettingRowModel]

    @MainActor
    static func resolve(
        url: URL?,
        profile: Profile?,
        showsAutoplayPermission: Bool = false,
        autoplayReloadRequired: Bool = false,
        permissionsSummary: String? = nil,
        trackingProtectionModule: SumiTrackingProtectionModule? = nil,
        trackingProtectionReloadRequired: Bool = false
    ) -> SiteControlsSnapshot {
        guard let url else {
            return SiteControlsSnapshot(
                hubAnchorAppearance: .zenPermissions,
                securityState: .internalPage,
                readerAvailability: .disabledPlaceholder,
                settingsRows: []
            )
        }

        let rawHost = url.host ?? url.absoluteString
        let displayHost = rawHost.hasPrefix("www.")
            ? String(rawHost.dropFirst(4))
            : rawHost
        let scheme = url.scheme?.lowercased() ?? ""

        let securityState: SecurityState
        switch scheme {
        case "https":
            securityState = .secure
        case "file":
            securityState = .localPage
        case "about", "data", "blob", "javascript", "sumi":
            securityState = .internalPage
        default:
            securityState = .notSecure
        }

        let settingsRows: [SiteControlsSettingRowModel]
        let permissionsRow = SiteControlsSettingRowModel(
            id: "permissions",
            chromeIconName: "permissions",
            fallbackSystemName: "line.3.horizontal.decrease.circle",
            title: SumiCurrentSitePermissionsStrings.rowTitle,
            subtitle: permissionsSummary ?? SumiCurrentSitePermissionsStrings.defaultSummary,
            kind: .permissions
        )
        switch securityState {
        case .secure, .notSecure:
            var rows: [SiteControlsSettingRowModel] = []
            _ = showsAutoplayPermission
            _ = autoplayReloadRequired
            _ = profile

            if let trackingPolicy = trackingProtectionModule?.effectivePolicyIfEnabled(for: url) {
                let siteOverride = trackingProtectionModule?.siteOverrideIfEnabled(for: url) ?? .inherit
                rows.append(
                    .init(
                        id: "tracking",
                        chromeIconName: trackingPolicy.isEnabled
                            ? nil
                            : "tracking-protection",
                        fallbackSystemName: trackingPolicy.isEnabled
                            ? "shield.fill"
                            : "shield",
                        title: "Tracking Protection",
                        subtitle: trackingProtectionReloadRequired ? "Reload required" : nil,
                        kind: .tracking(
                            policy: trackingPolicy,
                            siteOverride: siteOverride,
                            reloadRequired: trackingProtectionReloadRequired
                        )
                    )
                )
            }
            rows.append(
                .init(
                    id: "cookies",
                    chromeIconName: "cookies-fill",
                    fallbackSystemName: "network",
                    title: "Cookies & Site Data",
                    subtitle: displayHost,
                    kind: .cookies
                )
            )
            rows.append(permissionsRow)
            settingsRows = rows
        case .localPage:
            settingsRows = [
                .init(
                    id: "local",
                    chromeIconName: nil,
                    fallbackSystemName: "doc",
                    title: "Page Type",
                    subtitle: "Local file or bundled resource",
                    kind: .localPage
                ),
                permissionsRow,
            ]
        case .internalPage:
            settingsRows = [permissionsRow]
        }

        return SiteControlsSnapshot(
            hubAnchorAppearance: .zenPermissions,
            securityState: securityState,
            readerAvailability: .disabledPlaceholder,
            settingsRows: settingsRows
        )
    }
}

private struct URLBarHubPopover: View {
    @EnvironmentObject private var browserManager: BrowserManager
    @EnvironmentObject private var extensionSurfaceStore: BrowserExtensionSurfaceStore
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    @ObservedObject var bookmarkManager: SumiBookmarkManager

    let bookmarkPresentationRequest: SumiBookmarkEditorPresentationRequest?
    let currentTab: Tab?
    let profile: Profile?
    let profileId: UUID?
    let initialMode: URLBarHubInitialMode
    let modeRequestNonce: Int
    let onClose: () -> Void

    private enum Mode: Equatable {
        case controls
        case siteDataDetails
        case permissions
        case bookmark(SumiBookmarkEditorState)

        var preferredWidth: CGFloat {
            switch self {
            case .controls:
                return 234
            case .siteDataDetails,
                 .permissions,
                 .bookmark:
                return 392
            }
        }
    }

    private enum NavigationDirection {
        case forward
        case backward
    }

    @State private var refreshNonce = 0
    @State private var mode: Mode = .controls
    @State private var navigationDirection: NavigationDirection = .forward
    @State private var containerWidth: CGFloat = Mode.controls.preferredWidth
    @State private var bookmarkErrorMessage: String?
    @StateObject private var siteDataDetailsModel = URLBarSiteDataDetailsViewModel()
    @StateObject private var currentSitePermissionsModel = SumiCurrentSitePermissionsViewModel()

    private var snapshot: SiteControlsSnapshot {
        _ = refreshNonce
        return SiteControlsSnapshot.resolve(
            url: currentTab?.url,
            profile: activeProfile,
            showsAutoplayPermission: currentTab?.audioState.isPlayingAudio == true,
            autoplayReloadRequired: currentTab?.isAutoplayReloadRequired == true,
            permissionsSummary: permissionsTopLevelSummary,
            trackingProtectionModule: browserManager.trackingProtectionModule,
            trackingProtectionReloadRequired: currentTab?.isTrackingProtectionReloadRequired == true
        )
    }

    private var permissionsTopLevelSummary: String {
        SumiCurrentSitePermissionSummary.topLevelSubtitle(
            tab: currentTab,
            profile: activeProfile,
            runtimeController: browserManager.runtimePermissionController,
            blockedPopupStore: browserManager.blockedPopupStore,
            externalSchemeSessionStore: browserManager.externalSchemeSessionStore,
            indicatorEventStore: browserManager.permissionIndicatorEventStore
        )
    }

    private var showsExtensionSection: Bool {
        if #available(macOS 15.5, *) {
            let sumiScriptsEnabled = browserManager.userscriptsModule.isEnabled
            return !extensionSurfaceStore.enabledExtensions.isEmpty || sumiScriptsEnabled
        }

        return false
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            modeContent
                .id(modeIdentity)
                .transition(modeTransition)
        }
        .frame(width: containerWidth)
        .background(tokens.commandPaletteBackground)
        .clipped()
        .animation(.spring(response: 0.26, dampingFraction: 0.9), value: containerWidth)
        .onAppear {
            applyInitialMode(animated: false)
            handleBookmarkPresentationRequest(bookmarkPresentationRequest)
        }
        .onChange(of: bookmarkPresentationRequest) { _, request in
            handleBookmarkPresentationRequest(request)
        }
        .onChange(of: modeRequestNonce) { _, _ in
            applyInitialMode(animated: true)
        }
        .onChange(of: currentTab?.id) { _, _ in
            resetToControls()
            refreshNonce += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .sumiTabNavigationStateDidChange)) { notification in
            handleNavigationStateDidChange(notification)
        }
        .onReceive(browserManager.trackingProtectionModule.settingsChangesPublisherIfEnabled()) {
            _ in refreshNonce += 1
        }
    }

    @ViewBuilder
    private var modeContent: some View {
        switch mode {
        case .controls:
            controlsContent
        case .siteDataDetails:
            URLBarSiteDataDetailsView(
                model: siteDataDetailsModel,
                currentTab: currentTab,
                profile: activeProfile,
                onBack: {
                    setMode(.controls, direction: .backward)
                },
                onClose: onClose,
                onDidMutate: {
                    refreshNonce += 1
                }
            )
        case .permissions:
            SumiCurrentSitePermissionsView(
                model: currentSitePermissionsModel,
                currentTab: currentTab,
                profile: activeProfile,
                permissionCoordinator: browserManager.permissionCoordinator,
                runtimePermissionController: browserManager.runtimePermissionController,
                systemPermissionService: browserManager.systemPermissionService,
                blockedPopupStore: browserManager.blockedPopupStore,
                externalSchemeSessionStore: browserManager.externalSchemeSessionStore,
                permissionIndicatorEventStore: browserManager.permissionIndicatorEventStore,
                onBack: {
                    setMode(.controls, direction: .backward)
                },
                onClose: onClose,
                onOpenSiteSettings: {
                    browserManager.openSiteSettingsTab(
                        focusing: currentTab,
                        profile: activeProfile,
                        in: windowState
                    )
                    onClose()
                },
                onDidMutate: {
                    refreshNonce += 1
                }
            )
        case .bookmark(let state):
            URLBarBookmarkEditorView(
                state: state,
                currentTab: currentTab,
                folders: bookmarkManager.folders(),
                onClose: {
                    setMode(.controls, direction: .backward)
                },
                onDidMutate: {
                    refreshNonce += 1
                }
            )
            .id(state.id)
        }
    }

    private var controlsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            topActionRow
                .padding(.horizontal, 9)
                .padding(.top, 10)
                .padding(.bottom, bookmarkErrorMessage == nil ? 8 : 4)

            if let bookmarkErrorMessage {
                Text(bookmarkErrorMessage)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }

            if showsExtensionSection {
                Divider()
                    .padding(.horizontal, 8)
                extensionSection
                    .padding(.horizontal, 9)
                    .padding(.top, 9)
                    .padding(.bottom, 8)
            }

            if !snapshot.settingsRows.isEmpty {
                Divider()
                    .padding(.horizontal, 8)
                settingsSection
                    .padding(.horizontal, 9)
                    .padding(.top, 9)
                    .padding(.bottom, 8)
            }

            Divider()
                .padding(.horizontal, 8)

            footerRow
                .padding(.top, 8)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
    }

    private var modeIdentity: String {
        switch mode {
        case .controls:
            return "controls"
        case .siteDataDetails:
            return "site-data-details"
        case .permissions:
            return "permissions"
        case .bookmark(let state):
            return "bookmark-\(state.id)"
        }
    }

    private var modeTransition: AnyTransition {
        switch navigationDirection {
        case .forward:
            return .asymmetric(
                insertion: .offset(x: 28, y: 0).combined(with: .opacity),
                removal: .offset(x: -18, y: 0).combined(with: .opacity)
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }

    private func setMode(_ newMode: Mode, direction: NavigationDirection) {
        navigationDirection = direction
        containerWidth = mode.preferredWidth
        withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
            mode = newMode
            containerWidth = newMode.preferredWidth
        }
    }

    private func resetToControls() {
        navigationDirection = .backward
        mode = .controls
        containerWidth = Mode.controls.preferredWidth
    }

    private func applyInitialMode(animated: Bool) {
        let requestedMode: Mode = initialMode == .permissions ? .permissions : .controls
        guard requestedMode != mode else {
            containerWidth = requestedMode.preferredWidth
            return
        }

        let direction: NavigationDirection = requestedMode == .permissions ? .forward : .backward
        if animated {
            setMode(requestedMode, direction: direction)
        } else {
            navigationDirection = direction
            mode = requestedMode
            containerWidth = requestedMode.preferredWidth
        }
    }

    private var activeProfile: Profile? {
        if let profile {
            return profile
        }
        if let profile = currentTab?.resolveProfile() {
            return profile
        }
        if let profileId,
           let profile = browserManager.profileManager.profiles.first(where: { $0.id == profileId }) {
            return profile
        }
        return browserManager.currentProfile
    }

    @ViewBuilder
    private var extensionSection: some View {
        if #available(macOS 15.5, *) {
            VStack(alignment: .leading, spacing: 8) {
                HubSectionHeader(
                    title: "Extensions",
                    actionTitle: "Manage",
                    action: {
                        browserManager.openSettingsTab(selecting: .extensions, in: windowState)
                        onClose()
                    }
                )

                ExtensionActionView(
                    extensions: extensionSurfaceStore.enabledExtensions,
                    layout: .hubTiles
                )
                .environmentObject(browserManager)
                .environment(windowState)
            }
        }
    }

    private var topActionRow: some View {
        HStack(spacing: 8) {
            SumiHubHeaderButton(
                iconName: "share",
                fallbackSystemName: "square.and.arrow.up",
                help: "Share"
            ) {
                shareCurrentPage()
            }

            SumiHubHeaderButton(
                iconName: "reader-mode",
                fallbackSystemName: "doc.richtext",
                help: "Reader Mode",
                isEnabled: snapshot.readerAvailability == .available
            ) {
                handleReaderMode()
            }

            SumiHubHeaderButton(
                iconName: "camera",
                fallbackSystemName: "camera",
                help: "Screenshot"
            ) {
                captureCurrentPage()
            }

            SumiHubHeaderButton(
                iconName: isCurrentPageBookmarked ? "bookmark" : "bookmark-hollow",
                fallbackSystemName: isCurrentPageBookmarked ? "bookmark.fill" : "bookmark",
                help: isCurrentPageBookmarked ? "Bookmarked" : "Bookmark",
                isEnabled: bookmarkManager.canBookmark(currentTab),
                isActive: isCurrentPageBookmarked
            ) {
                showBookmarkEditor()
            }
        }
    }

    private var isCurrentPageBookmarked: Bool {
        _ = refreshNonce
        _ = bookmarkManager.revision
        guard let currentTab else { return false }
        return bookmarkManager.isBookmarked(currentTab.url)
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HubSectionHeader(
                title: "Settings",
                actionTitle: "More",
                action: {
                    browserManager.openSettingsTab(selecting: .privacy, in: windowState)
                }
            )

            VStack(spacing: 8) {
                ForEach(snapshot.settingsRows) { row in
                    HubSettingRow(
                        model: row,
                        trackingPresenter: trackingPresenter(for: row),
                        resetAction: resetAction(for: row)
                    ) {
                        handleSettingAction(row)
                    }
                }
            }
        }
    }

    private var footerRow: some View {
        HStack(spacing: 8) {
            if snapshot.securityState.showsFooterButton {
                SumiFooterSecurityStatus(
                    securityState: snapshot.securityState
                )
            }

            Menu {
                Button("Site Settings") {
                    browserManager.openSiteSettingsTab(
                        focusing: currentTab,
                        profile: activeProfile,
                        in: windowState
                    )
                    onClose()
                }
            } label: {
                SumiZenChromeIcon(
                    iconName: "menu",
                    fallbackSystemName: "ellipsis",
                    size: 14,
                    tint: tokens.primaryText
                )
                .frame(width: 36, height: 36)
                .background(tokens.fieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
    }

    private func handleSettingAction(_ row: SiteControlsSettingRowModel) {
        switch row.kind {
        case .tracking(let policy, _, _):
            setTrackingProtectionOverride(
                URLBarTrackingProtectionPresenter.siteOverrideAfterToggle(for: policy)
            )
        case .cookies:
            setMode(.siteDataDetails, direction: .forward)
        case .permissions:
            setMode(.permissions, direction: .forward)
        case .localPage:
            break
        }
    }

    private func setAutoplayPolicy(_ policy: SumiAutoplayPolicy, for tab: Tab) {
        guard let profile = activeProfile else { return }
        Task { @MainActor in
            do {
                try await SumiAutoplayPolicyStoreAdapter.shared.setPolicy(
                    policy,
                    for: tab.url,
                    profile: profile,
                    source: .user
                )
                tab.markAutoplayReloadRequiredIfNeeded(afterChangingPolicyFor: tab.url)
                rebuildCurrentTabAfterPermissionChange(tab)
                tab.updateAutoplayReloadRequirementForCurrentSite()
                refreshNonce += 1
            } catch {
                RuntimeDiagnostics.emit(
                    "[URLBar] Failed to update autoplay policy: \(error.localizedDescription)"
                )
            }
        }
    }

    private func resetAutoplayPolicy(for tab: Tab) {
        guard let profile = activeProfile else { return }
        Task { @MainActor in
            do {
                try await SumiAutoplayPolicyStoreAdapter.shared.resetPolicy(
                    for: tab.url,
                    profile: profile
                )
                tab.markAutoplayReloadRequiredIfNeeded(afterChangingPolicyFor: tab.url)
                rebuildCurrentTabAfterPermissionChange(tab)
                tab.updateAutoplayReloadRequirementForCurrentSite()
                refreshNonce += 1
            } catch {
                RuntimeDiagnostics.emit(
                    "[URLBar] Failed to reset autoplay policy: \(error.localizedDescription)"
                )
            }
        }
    }

    private func trackingPresenter(
        for row: SiteControlsSettingRowModel
    ) -> URLBarTrackingProtectionPresenter? {
        guard case .tracking(let policy, let siteOverride, let reloadRequired) = row.kind else {
            return nil
        }

        return URLBarTrackingProtectionPresenter.make(
            policy: policy,
            siteOverride: siteOverride,
            isReloadRequired: reloadRequired
        )
    }

    private func resetAction(
        for row: SiteControlsSettingRowModel
    ) -> (() -> Void)? {
        _ = row
        return nil
    }

    private func setTrackingProtectionOverride(
        _ override: SumiTrackingProtectionSiteOverride
    ) {
        guard let currentTab,
              let settings = browserManager.trackingProtectionModule.settingsIfEnabled()
        else { return }
        settings.setSiteOverride(override, for: currentTab.url)
        currentTab.markTrackingProtectionReloadRequiredIfNeeded(
            afterChangingOverrideFor: currentTab.url
        )
        refreshNonce += 1
    }

    private func rebuildCurrentTabAfterPermissionChange(_ tab: Tab) {
        browserManager.requireWebViewCoordinator().removeAllWebViews(for: tab)
        tab.performComprehensiveWebViewCleanup()
        tab.loadWebViewIfNeeded()

        if let webView = tab.existingWebView {
            browserManager.requireWebViewCoordinator().setWebView(
                webView,
                for: tab.id,
                in: windowState.id
            )
            tab.assignWebViewToWindow(webView, windowId: windowState.id)
        }

        browserManager.refreshCompositor(for: windowState)
    }

    private func shareCurrentPage() {
        guard let url = currentTab?.url else { return }
        guard let contentView = NSApp.keyWindow?.contentView else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
            return
        }

        let picker = NSSharingServicePicker(items: [url])
        let anchor = NSRect(
            x: contentView.bounds.midX,
            y: contentView.bounds.midY,
            width: 1,
            height: 1
        )
        picker.show(relativeTo: anchor, of: contentView, preferredEdge: .minY)
    }

    private func captureCurrentPage() {
        guard let currentTab,
              let webView = browserManager.getWebView(
                for: currentTab.id,
                in: windowState.id
              ) else {
            return
        }

        webView.takeSnapshot(with: nil) { image, _ in
            guard let image,
                  let tiffData = image.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmapRep.representation(
                    using: .png,
                    properties: [:]
                  ) else {
                return
            }

            let savePanel = NSSavePanel()
            savePanel.title = "Save Page Capture"
            savePanel.message = "Choose where to save the page snapshot"
            savePanel.nameFieldStringValue = suggestedSnapshotFilename(
                for: currentTab
            )
            savePanel.allowedContentTypes = [.png]
            savePanel.begin { result in
                guard result == .OK,
                      let destinationURL = savePanel.url else { return }
                try? pngData.write(to: destinationURL)
            }
        }
    }

    private func showBookmarkEditor() {
        guard let currentTab else { return }
        do {
            let editorState = try bookmarkManager.editorState(for: currentTab)
            bookmarkErrorMessage = nil
            refreshNonce += 1
            setMode(.bookmark(editorState), direction: .forward)
        } catch {
            bookmarkErrorMessage = error.localizedDescription
        }
    }

    private func handleBookmarkPresentationRequest(_ request: SumiBookmarkEditorPresentationRequest?) {
        guard let request,
              request.windowID == windowState.id,
              request.tabID == currentTab?.id
        else { return }

        showBookmarkEditor()
        browserManager.clearBookmarkEditorPresentationRequest(request)
    }

    private func handleNavigationStateDidChange(_ notification: Notification) {
        guard let tab = notification.object as? Tab,
              tab.id == currentTab?.id
        else {
            return
        }

        refreshNonce += 1
        if case .bookmark(let state) = mode,
           state.tabID == tab.id,
           state.pageURL.absoluteString != tab.url.absoluteString
        {
            resetToControls()
        }
    }

    private func handleReaderMode() {
        // Sumi does not expose a reader-mode pipeline yet.
    }

    private func suggestedSnapshotFilename(for tab: Tab) -> String {
        let rawTitle = tab.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = rawTitle.isEmpty ? "Sumi Capture" : rawTitle
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let sanitized = base.components(separatedBy: invalidCharacters)
            .joined(separator: "-")
        return "\(sanitized).png"
    }
}

private struct URLBarSiteDataDetailsView: View {
    @ObservedObject var model: URLBarSiteDataDetailsViewModel

    let currentTab: Tab?
    let profile: Profile?
    let onBack: () -> Void
    let onClose: () -> Void
    let onDidMutate: () -> Void

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var pendingDeletionEntry: SumiSiteDataEntry?

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var displayHost: String {
        let host = currentTab?.url.host ?? currentTab?.url.absoluteString ?? "This site"
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private var loadKey: String {
        [
            profile?.id.uuidString ?? "none",
            currentTab?.id.uuidString ?? "none",
            currentTab?.url.host ?? currentTab?.url.absoluteString ?? "none"
        ].joined(separator: "|")
    }

    var body: some View {
        ZStack {
            content

            if let entry = pendingDeletionEntry {
                URLBarSiteDataDeleteConfirmationView(
                    domain: entry.domain,
                    onCancel: {
                        pendingDeletionEntry = nil
                    },
                    onDelete: {
                        delete(entry)
                    }
                )
                .transition(
                    .scale(scale: 0.98, anchor: .center)
                        .combined(with: .opacity)
                )
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: pendingDeletionEntry?.id)
        .task(id: loadKey) {
            await model.load(url: currentTab?.url, profile: profile)
        }
        .onReceive(SumiSiteDataPolicyStore.shared.changesPublisher) { _ in
            Task {
                await model.load(url: currentTab?.url, profile: profile)
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 18) {
                intro
                entriesSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

            Divider()
                .padding(.horizontal, 8)

            HStack {
                Spacer(minLength: 0)
                Button("Done", action: onClose)
                    .buttonStyle(URLBarZoomPopoverButtonStyle(minWidth: 76))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            URLBarSiteDataIconButton(
                systemName: "chevron.left",
                help: "Back",
                action: onBack
            )

            VStack(alignment: .leading, spacing: 1) {
                Text("Cookies & Site Data")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tokens.primaryText)
                    .lineLimit(1)
                URLBarFadingText(
                    displayHost,
                    font: .system(size: 12, weight: .medium),
                    color: tokens.secondaryText
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            URLBarSiteDataIconButton(
                systemName: "xmark",
                help: "Close",
                action: onClose
            )
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Site data stored on this device")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tokens.primaryText)
            Text("Sites can store preferences, session data, and cached files on your device. This data is available to the site and its subdomains.")
                .font(.system(size: 13))
                .foregroundStyle(tokens.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Data from this site")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tokens.primaryText)

            if model.isLoading && model.entries.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading site data...")
                        .font(.system(size: 12))
                        .foregroundStyle(tokens.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .center)
            } else if model.entries.isEmpty {
                Text("No site data is stored for \(displayHost).")
                    .font(.system(size: 12.5))
                    .foregroundStyle(tokens.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.entries) { entry in
                        URLBarSiteDataEntryRow(
                            entry: entry,
                            summary: model.summary(for: entry),
                            policyState: model.policyState(for: entry),
                            isDeleting: model.deletingHosts.contains(entry.domain),
                            onDelete: {
                                pendingDeletionEntry = entry
                            },
                            onToggleBlockStorage: {
                                let state = model.policyState(for: entry)
                                Task {
                                    await model.setBlockStorage(
                                        !state.blockStorage,
                                        for: entry,
                                        url: currentTab?.url,
                                        profile: profile
                                    )
                                    onDidMutate()
                                }
                            },
                            onToggleDeleteOnClose: {
                                let state = model.policyState(for: entry)
                                Task {
                                    await model.setDeleteWhenAllWindowsClosed(
                                        !state.deleteWhenAllWindowsClosed,
                                        for: entry,
                                        url: currentTab?.url,
                                        profile: profile
                                    )
                                    onDidMutate()
                                }
                            }
                        )

                        if entry.id != model.entries.last?.id {
                            Divider()
                                .padding(.leading, 38)
                        }
                    }
                }
            }
        }
    }

    private func delete(_ entry: SumiSiteDataEntry) {
        pendingDeletionEntry = nil
        Task {
            await model.delete(
                entry: entry,
                url: currentTab?.url,
                profile: profile
            )
            onDidMutate()
        }
    }
}

private struct URLBarSiteDataDeleteConfirmationView: View {
    let domain: String
    let onCancel: () -> Void
    let onDelete: () -> Void

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.colorScheme) private var colorScheme

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(colorScheme == .dark ? 0.28 : 0.12)
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)

            VStack(spacing: 14) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(destructiveColor)
                    .clipShape(Circle())

                VStack(spacing: 6) {
                    Text("Delete cookies and site data?")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tokens.primaryText)
                        .multilineTextAlignment(.center)
                    Text("This will delete cookies and site data for \(domain).")
                        .font(.system(size: 12.5))
                        .foregroundStyle(tokens.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(URLBarSiteDataConfirmationButtonStyle(role: .secondary))

                    Button("Delete", action: onDelete)
                        .buttonStyle(URLBarSiteDataConfirmationButtonStyle(role: .destructive))
                }
            }
            .padding(18)
            .frame(maxWidth: 330)
            .background(tokens.commandPaletteBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(tokens.separator.opacity(0.65), lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.18), radius: 18, x: 0, y: 8)
            .padding(16)
        }
    }

    private var destructiveColor: Color {
        Color(red: 0.94, green: 0.05, blue: 0.16)
    }
}

private struct URLBarSiteDataConfirmationButtonStyle: ButtonStyle {
    enum Role {
        case secondary
        case destructive
    }

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    let role: Role

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1)
            .onHover { hovering in
                isHovering = hovering
            }
    }

    private var foregroundColor: Color {
        switch role {
        case .secondary:
            return tokens.primaryText
        case .destructive:
            return .white
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch role {
        case .secondary:
            return isPressed || isHovering
                ? tokens.fieldBackgroundHover
                : tokens.fieldBackground
        case .destructive:
            let base = Color(red: 0.94, green: 0.05, blue: 0.16)
            return isPressed || isHovering ? base.opacity(0.88) : base
        }
    }
}

private struct URLBarSiteDataEntryRow: View {
    let entry: SumiSiteDataEntry
    let summary: String
    let policyState: SumiSiteDataPolicyState
    let isDeleting: Bool
    let onDelete: () -> Void
    let onToggleBlockStorage: () -> Void
    let onToggleDeleteOnClose: () -> Void

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isTitleHovered = false
    @State private var isDeleteHovered = false

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                titleArea

                Button(action: onDelete) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isDeleteHovered ? tokens.fieldBackgroundHover : Color.clear)

                        if isDeleting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .frame(width: 32, height: 32)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(tokens.secondaryText)
                .disabled(isDeleting)
                .help("Delete data for \(entry.domain)")
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isDeleteHovered = hovering
                    }
                }
            }

            VStack(spacing: 6) {
                URLBarSiteDataActionButton(
                    title: policyState.blockStorage
                        ? "Allow saving data"
                        : "Block saving data",
                    systemName: policyState.blockStorage ? "checkmark.circle" : "nosign",
                    action: onToggleBlockStorage
                )
                URLBarSiteDataActionButton(
                    title: policyState.deleteWhenAllWindowsClosed
                        ? "Keep after all windows close"
                        : "Delete when all windows close",
                    systemName: policyState.deleteWhenAllWindowsClosed ? "checkmark.circle" : "clock.arrow.circlepath",
                    action: onToggleDeleteOnClose
                )
            }
            .disabled(isDeleting)
        }
        .padding(.vertical, 9)
    }

    private var titleArea: some View {
        HStack(spacing: 10) {
            URLBarSiteDataFavicon(domain: entry.domain)

            VStack(alignment: .leading, spacing: 2) {
                URLBarFadingText(
                    entry.domain,
                    font: .system(size: 13, weight: .medium),
                    color: tokens.primaryText
                )
                URLBarFadingText(
                    summary,
                    font: .system(size: 11.5),
                    color: tokens.secondaryText
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isTitleHovered ? tokens.fieldBackground.opacity(0.55) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isTitleHovered = hovering
            }
        }
    }
}

private struct URLBarSiteDataActionButton: View {
    let title: String
    let systemName: String
    let action: () -> Void

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isHovered = false

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .frame(width: 14, height: 14)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(tokens.primaryText)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .padding(.horizontal, 8)
            .background(isHovered ? tokens.fieldBackgroundHover : tokens.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

private struct URLBarSiteDataFavicon: View {
    let domain: String

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        Group {
            if let image = cachedFavicon {
                image
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(tokens.secondaryText)
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    @MainActor
    private var cachedFavicon: Image? {
        let normalizedDomain = domain.normalizedWebsiteDataDomain
        guard !normalizedDomain.isEmpty else { return nil }

        if let url = URL(string: "https://\(normalizedDomain)"),
           let key = SumiFaviconResolver.cacheKey(for: url),
           let image = Tab.getCachedFavicon(for: key) {
            return image
        }

        let manager = SumiFaviconSystem.shared.manager
        if let favicon = manager.getCachedFavicon(
            for: normalizedDomain,
            sizeCategory: .small,
            fallBackToSmaller: true
        ), let image = favicon.image {
            return Image(nsImage: image)
        }

        if let favicon = manager.getCachedFavicon(
            forDomainOrAnySubdomain: normalizedDomain,
            sizeCategory: .small,
            fallBackToSmaller: true
        ), let image = favicon.image {
            return Image(nsImage: image)
        }

        return nil
    }
}

private struct URLBarSiteDataIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isHovered = false

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tokens.primaryText)
                .frame(width: 34, height: 34)
                .background(isHovered ? tokens.fieldBackgroundHover : tokens.fieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

private struct URLBarFadingText: View {
    let text: String
    let font: Font
    let color: Color

    init(_ text: String, font: Font, color: Color) {
        self.text = text
        self.font = font
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .mask(
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 18)
                }
            )
    }
}

private struct HubSectionHeader: View {
    let title: String
    let actionTitle: String
    let action: () -> Void

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isHovering = false

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tokens.primaryText)
            Spacer(minLength: 0)
            Button(actionTitle, action: action)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tokens.secondaryText)
                .opacity(isHovering ? 0.92 : 0.55)
        }
        .onHover { isHovering = $0 }
    }
}

private struct SumiHubHeaderButton: View {
    let iconName: String
    let fallbackSystemName: String
    let help: String
    var isEnabled: Bool = true
    var isActive: Bool = false
    let action: () -> Void

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isHovered = false
    @State private var isPressed = false

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        Button(action: action) {
            SumiZenChromeIcon(
                iconName: iconName,
                fallbackSystemName: fallbackSystemName,
                size: 18,
                tint: iconTint
            )
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(backgroundFill)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(tokens.separator.opacity(0.75), lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .scaleEffect(buttonScale)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .help(help)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isEnabled else { return }
                    isPressed = true
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }

    private var backgroundFill: some ShapeStyle {
        LinearGradient(
            colors: ThemeChromeRecipeBuilder.urlBarHubVeilGradientColors(
                tokens: tokens,
                isActive: isActive,
                isHovered: isHovered
            ),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var iconTint: Color {
        tokens.primaryText
    }

    private var buttonScale: CGFloat {
        if isPressed && isHovered {
            return 0.97
        }
        if isHovered {
            return 1.03
        }
        return 1
    }
}

private struct SumiFooterSecurityStatus: View {
    let securityState: SiteControlsSnapshot.SecurityState

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        HStack(spacing: 8) {
            SumiZenChromeIcon(
                iconName: securityState.chromeIconName,
                fallbackSystemName: securityState.fallbackSystemName,
                size: 16,
                tint: labelColor
            )
            Text(securityState.footerTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(labelColor)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(tokens.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var labelColor: Color {
        securityState == .notSecure ? Color.red.opacity(0.9) : tokens.primaryText
    }
}

private struct SumiTrackingProtectionShieldIcon: View {
    let presenter: URLBarTrackingProtectionPresenter
    let size: CGFloat
    let tint: Color
    let checkTint: Color

    var body: some View {
        ZStack {
            if presenter.shieldIcon.showsCheckmark {
                Image(systemName: "shield.fill")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(tint)
                    .symbolRenderingMode(.monochrome)

                Image(systemName: "checkmark")
                    .font(.system(size: max(size * 0.44, 8), weight: .black))
                    .foregroundStyle(checkTint)
                    .offset(y: -1)
            } else {
                SumiZenChromeIcon(
                    iconName: presenter.shieldIcon.chromeIconName,
                    fallbackSystemName: presenter.shieldIcon.fallbackSystemName,
                    size: size,
                    tint: tint
                )
            }
        }
        .frame(width: size, height: size)
    }
}

private struct HubSettingRow: View {
    let model: SiteControlsSettingRowModel
    let trackingPresenter: URLBarTrackingProtectionPresenter?
    let resetAction: (() -> Void)?
    let action: () -> Void

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isHovered = false

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    init(
        model: SiteControlsSettingRowModel,
        trackingPresenter: URLBarTrackingProtectionPresenter? = nil,
        resetAction: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.model = model
        self.trackingPresenter = trackingPresenter
        self.resetAction = resetAction
        self.action = action
    }

    var body: some View {
        Group {
            if let trackingPresenter {
                Button(action: action) {
                    trackingRowContent(trackingPresenter)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if model.isInteractive && !model.isDisabled {
                Button(action: action) {
                    rowContent
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                rowContent
            }
        }
        .opacity(model.isDisabled ? 0.55 : 1)
        .contextMenu {
            if let resetAction {
                Button("Use Default", action: resetAction)
            }
        }
        .onHover { hovering in
            guard model.isInteractive && !model.isDisabled else {
                isHovered = false
                return
            }
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

    private func trackingRowContent(
        _ presenter: URLBarTrackingProtectionPresenter
    ) -> some View {
        HStack(spacing: 8) {
            trackingShieldCapsule(presenter)

            VStack(alignment: .leading, spacing: 2) {
                Text(presenter.rowTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tokens.primaryText)
                    .lineLimit(1)

                if let rowSubtitle = presenter.rowSubtitle {
                    Text(rowSubtitle)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(tokens.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .contentShape(Rectangle())
        .help(presenter.shieldAccessibilityLabel)
        .accessibilityLabel(presenter.shieldAccessibilityLabel)
        .accessibilityValue(presenter.shieldAccessibilityValue)
    }

    private func trackingShieldCapsule(
        _ presenter: URLBarTrackingProtectionPresenter
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(capsuleFill)
                .scaleEffect(capsuleScale)

            SumiTrackingProtectionShieldIcon(
                presenter: presenter,
                size: 17,
                tint: presenter.isEnabled ? Color.black.opacity(0.88) : iconTint,
                checkTint: Color.white
            )
        }
        .frame(width: 34, height: 34)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(capsuleFill)
                    .scaleEffect(capsuleScale)

                SumiZenChromeIcon(
                    iconName: model.chromeIconName,
                    fallbackSystemName: model.fallbackSystemName,
                    size: 16,
                    tint: iconTint
                )
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                URLBarFadingText(
                    model.title,
                    font: .system(size: 13, weight: .medium),
                    color: tokens.primaryText
                )
                if let subtitle = model.subtitle {
                    URLBarFadingText(
                        subtitle,
                        font: .system(size: 11.5),
                        color: tokens.secondaryText
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if model.showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tokens.secondaryText.opacity(0.78))
                    .frame(width: 14, height: 22)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var capsuleFill: Color {
        isHovered ? tokens.fieldBackgroundHover : tokens.fieldBackground
    }

    private var iconTint: Color {
        tokens.primaryText
    }

    private var capsuleScale: CGFloat {
        isHovered ? 1.05 : 1
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
