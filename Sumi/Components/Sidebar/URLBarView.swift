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

struct URLBarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    let presentationMode: URLBarPresentationMode

    @State private var isHovering = false
    @State private var showCheckmark = false
    @State private var isHubPresented = false
    @State private var isZoomPopoverPresented = false
    @State private var zoomPopoverSource: ZoomPopoverSource = .toolbar
    @State private var zoomPopoverSize = CGSize(width: 252, height: 48)
    @State private var isZoomButtonHovering = false
    @State private var isZoomPopoverHovering = false
    @State private var zoomPopoverHideTimer: Timer?

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
            }
        }
        .onDisappear {
            invalidateZoomPopoverHideTimer()
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

    private var siteControlsSnapshot: SiteControlsSnapshot {
            SiteControlsSnapshot.resolve(
                url: currentTab?.url,
                profileId: effectiveProfileId,
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
        .animation(.smooth(duration: 0.18), value: showsZoomButton)
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
                profileId: effectiveProfileId,
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

private struct URLBarZoomPopoverButtonStyle: ButtonStyle {
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
        case autoplay(AutoplayOverrideState)
        case trackingPlaceholder
        case cookies
        case localPage
    }

    let id: String
    let chromeIconName: String?
    let fallbackSystemName: String
    let title: String
    let subtitle: String
    let kind: Kind

    var isDisabled: Bool {
        switch kind {
        case .trackingPlaceholder:
            return true
        default:
            return false
        }
    }

    var isInteractive: Bool {
        switch kind {
        case .autoplay:
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

    static func resolve(
        url: URL?,
        profileId: UUID?,
        showsAutoplayPermission: Bool = false
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
        switch securityState {
        case .secure, .notSecure:
            let hasAutoplayOverride = SitePermissionOverridesStore.shared
                .hasAutoplayOverride(for: url, profileId: profileId)

            var rows: [SiteControlsSettingRowModel] = []
            if showsAutoplayPermission || hasAutoplayOverride {
                let autoplayState = SitePermissionOverridesStore.shared.autoplayState(
                    for: url,
                    profileId: profileId
                )
                rows.append(
                    .init(
                        id: "autoplay",
                        chromeIconName: autoplayState.chromeIconName,
                        fallbackSystemName: autoplayState == .allow
                            ? "play.rectangle"
                            : "play.rectangle.fill",
                        title: "Autoplay",
                        subtitle: autoplayState.subtitle,
                        kind: .autoplay(autoplayState)
                    )
                )
            }

            rows.append(
                .init(
                    id: "tracking",
                    chromeIconName: "tracking-protection",
                    fallbackSystemName: "hand.raised.fill",
                    title: "Tracking Protection",
                    subtitle: "Unavailable",
                    kind: .trackingPlaceholder
                )
            )
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
            ]
        case .internalPage:
            settingsRows = []
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
    let profileId: UUID?
    let onClose: () -> Void

    private enum Mode: Equatable {
        case controls
        case bookmark(SumiBookmarkEditorState)
    }

    @State private var refreshNonce = 0
    @State private var mode: Mode = .controls
    @State private var bookmarkErrorMessage: String?

    private var snapshot: SiteControlsSnapshot {
        _ = refreshNonce
        return SiteControlsSnapshot.resolve(
            url: currentTab?.url,
            profileId: profileId,
            showsAutoplayPermission: currentTab?.audioState.isPlayingAudio == true
        )
    }

    private var showsExtensionSection: Bool {
        if #available(macOS 15.5, *) {
            let sumiScriptsEnabled = browserManager.sumiScriptsManager.isEnabled
            return !extensionSurfaceStore.enabledExtensions.isEmpty || sumiScriptsEnabled
        }

        return false
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        Group {
            switch mode {
            case .controls:
                controlsContent
            case .bookmark(let state):
                URLBarBookmarkEditorView(
                    state: state,
                    currentTab: currentTab,
                    folders: bookmarkManager.folders(),
                    onClose: {
                        mode = .controls
                    },
                    onDidMutate: {
                        refreshNonce += 1
                    }
                )
                .id(state.id)
            }
        }
        .frame(width: modeWidth)
        .background(tokens.commandPaletteBackground)
        .animation(nil, value: mode)
        .onAppear {
            handleBookmarkPresentationRequest(bookmarkPresentationRequest)
        }
        .onChange(of: bookmarkPresentationRequest) { _, request in
            handleBookmarkPresentationRequest(request)
        }
        .onChange(of: currentTab?.id) { _, _ in
            mode = .controls
            refreshNonce += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .sumiTabNavigationStateDidChange)) { notification in
            handleNavigationStateDidChange(notification)
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

    private var modeWidth: CGFloat {
        switch mode {
        case .controls:
            return 234
        case .bookmark:
            return 392
        }
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
                    browserManager.openSettingsTab(selecting: .general, in: windowState)
                }
            )

            VStack(spacing: 8) {
                ForEach(snapshot.settingsRows) { row in
                    HubSettingRow(model: row) {
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
                Button("Clear Site Data") {
                    clearCurrentSiteData()
                    onClose()
                }

                Divider()

                Button("Site Settings") {
                    browserManager.openSettingsTab(selecting: .general, in: windowState)
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
        guard let currentTab else { return }

        switch row.kind {
        case .autoplay:
            _ = SitePermissionOverridesStore.shared.toggleAutoplay(
                for: currentTab.url,
                profileId: profileId
            )
            rebuildCurrentTabAfterPermissionChange(currentTab)
            refreshNonce += 1
        case .trackingPlaceholder,
             .cookies,
             .localPage:
            break
        }
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

    private func clearCurrentSiteData() {
        browserManager.clearCurrentPageCookies()
        browserManager.clearCurrentPageCache()
        browserManager.hardReloadCurrentPage()
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
            mode = .bookmark(editorState)
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
            mode = .controls
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

private struct SumiZenChromeIcon: View {
    let iconName: String?
    let fallbackSystemName: String
    let size: CGFloat
    var tint: Color

    var body: some View {
        if let iconName,
           let image = SumiZenFolderIconCatalog.chromeImage(named: iconName) {
            SumiZenBundledIconView(
                image: image,
                size: size,
                tint: tint
            )
        } else {
            Image(systemName: fallbackSystemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
        }
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

private struct HubSettingRow: View {
    let model: SiteControlsSettingRowModel
    let action: () -> Void

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isHovered = false

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        Group {
            if model.isInteractive && !model.isDisabled {
                Button(action: action) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .opacity(model.isDisabled ? 0.55 : 1)
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
                Text(model.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tokens.primaryText)
                Text(model.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(tokens.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
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
