import SwiftUI
import WebKit

struct URLBarHubControlsView: View {
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.resolvedThemeContext) private var themeContext

    let browserContext: URLBarHubBrowserContext
    @ObservedObject var bookmarkManager: SumiBookmarkManager
    @ObservedObject var pageActionOwner: URLBarHubPageActionOwner
    @ObservedObject var currentSitePermissionsModel: SumiCurrentSitePermissionsViewModel
    @ObservedObject var refreshCoordinator: URLBarHubRefreshCoordinator

    let currentTab: Tab?
    let activeProfile: Profile?
    let snapshot: SiteControlsSnapshot
    let showsExtensionSection: Bool
    let showsBoostsSection: Bool
    let currentSiteBoosts: [SumiBoost]
    let currentActiveBoostId: UUID?
    let unpinnedEnabledExtensionActions:
        [BrowserExtensionToolbarDisplayRecord]
    let permissionDependencies: SumiCurrentSitePermissionsViewModel.LoadDependencies
    let readerModeIsActive: Bool
    let bookmarkErrorMessage: String?
    let screenshotOptions: URLBarHubScreenshotOptions
    let onScreenshotOptionsChange: (URLBarHubScreenshotOptions) -> Void
    let onSetMode: (URLBarHubNavigationModel.Mode, URLBarHubNavigationModel.NavigationDirection) -> Void
    let onClose: () -> Void
    let onReloadPermissionsImmediately: () async -> Void
    let onHandleReaderMode: () -> Void
    let onShowBookmarkEditor: () -> Void
    let onBookmarkError: (String) -> Void

    @State private var isHoveringExtensions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topActionRow
                .padding(.horizontal, 9)
                .padding(.top, 10)
                .padding(.bottom, bookmarkErrorMessage == nil ? 8 : 4)

            if let bookmarkErrorMessage {
                Text(bookmarkErrorMessage)
                    .font(URLBarHubTypography.bookmarkError)
                    .foregroundStyle(URLBarHubOverlayStyle.bookmarkErrorText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }

            if showsExtensionSection {
                Divider()
                    .padding(.horizontal, 9)
                extensionSection
                    .padding(.horizontal, 9)
                    .padding(.top, 9)
                    .padding(.bottom, 8)
            }

            if !snapshot.settingsRows.isEmpty || !currentSitePermissionsModel.rows.isEmpty {
                Divider()
                    .padding(.horizontal, 9)
                settingsSection
                    .padding(.horizontal, 9)
                    .padding(.top, 9)
                    .padding(.bottom, 8)
            }

            if snapshot.securityState.showsFooterButton {
                Divider()
                    .padding(.horizontal, 8)

                footerRow
                    .padding(.top, 8)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private var extensionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HubSectionHeader(
                title: "Extensions",
                actionTitle: "Manage",
                action: {
                    browserContext.openExtensionSettings(windowState)
                    onClose()
                },
                isSectionHovered: isHoveringExtensions
            )

            browserContext.extensionActions.hubTiles(
                unpinnedEnabledExtensionActions,
                windowState,
                activeProfile?.id
            )
            .environment(windowState)
        }
        .contentShape(Rectangle())
        .sidebarHover($isHoveringExtensions)
    }

    private var topActionRow: some View {
        HStack(spacing: 8) {
            SumiHubHeaderButton(
                iconName: isCurrentPageBookmarked ? "bookmark" : "bookmark-hollow",
                fallbackSystemName: isCurrentPageBookmarked ? "bookmark.fill" : "bookmark",
                help: isCurrentPageBookmarked ? "Bookmarked" : "Bookmark",
                isEnabled: bookmarkManager.canBookmark(currentTab),
                isActive: isCurrentPageBookmarked
            ) {
                onShowBookmarkEditor()
            }

            SumiHubHeaderButton(
                iconName: "camera",
                fallbackSystemName: "camera",
                help: "Screenshot (\(screenshotOptions.scale.label))",
                isEnabled: !pageActionOwner.isCapturingScreenshot
            ) {
                pageActionOwner.captureCurrentPageUsingSavedSettings(
                    currentTab: currentTab,
                    windowState: windowState,
                    webViewProvider: browserContext.webView,
                    options: screenshotOptions
                )
            }
            .contextMenu {
                Button("Screenshot Settings...") {
                    pageActionOwner.presentScreenshotSettings(
                        currentTab: currentTab,
                        windowState: windowState,
                        webViewProvider: browserContext.webView,
                        options: screenshotOptions,
                        themeContext: themeContext
                    ) { options in
                        onScreenshotOptionsChange(options)
                    }
                }
            }

            SumiHubHeaderButton(
                iconName: "reader-mode",
                fallbackSystemName: "doc.richtext",
                help: readerModeIsActive ? "Hide Reader" : "Reader Mode",
                isEnabled: snapshot.readerAvailability == .available,
                isActive: readerModeIsActive
            ) {
                onHandleReaderMode()
            }

            SumiHubHeaderButton(
                iconName: "share",
                fallbackSystemName: "square.and.arrow.up",
                help: "Share"
            ) {
                pageActionOwner.shareCurrentPage(
                    currentTab: currentTab,
                    windowState: windowState,
                    presentSharingServicePicker: browserContext.presentSharingServicePicker
                )
            }
            .background(URLBarHubShareAnchorView(anchor: pageActionOwner.shareButtonAnchor))
        }
    }

    private var isCurrentPageBookmarked: Bool {
        let _ = refreshCoordinator.refreshNonce
        let _ = bookmarkManager.revision
        guard let currentTab else { return false }
        return bookmarkManager.isBookmarked(currentTab.url)
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HubSectionHeader(title: "Settings")

            VStack(spacing: 8) {
                ForEach(snapshot.settingsRows) { row in
                    HubSettingRow(
                        model: row,
                        resetAction: nil
                    ) {
                        handleSettingAction(row)
                    }
                }
            }

            permissionsInlineSection
        }
    }

    private var footerRow: some View {
        HStack(spacing: 8) {
            SumiFooterSecurityStatus(
                securityState: snapshot.securityState
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsBoostsSection {
                SumiFooterBoostButton(
                    boosts: currentSiteBoosts,
                    activeBoostId: currentActiveBoostId,
                    action: openBoostFromFooter,
                    createAction: createBoost,
                    toggleAction: toggleBoost,
                    editAction: editBoost
                )
                .frame(width: 42)
            }

            SumiFooterSiteSettingsButton(
                siteSettingsAction: openSiteSettings,
                clearSiteDataAction: openSiteDataDetails,
                resetPermissionsAction: resetPermissionsToDefault
            )
            .frame(width: 42)
        }
    }

    @ViewBuilder
    private var permissionsInlineSection: some View {
        if !currentSitePermissionsModel.rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(SumiCurrentSitePermissionsStrings.rowTitle)
                    .font(URLBarHubTypography.sectionHeaderTitle)
                    .foregroundStyle(URLBarHubNativeStyle.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 8) {
                    ForEach(currentSitePermissionsModel.rows) { row in
                        URLHubPermissionInlineRow(
                            row: row,
                            onCycle: {
                                cyclePermission(row)
                            },
                            onSelect: { option in
                                selectPermission(option, for: row)
                            },
                            onOpenSystemSettings: {
                                openSystemSettings(for: row)
                            }
                        )
                    }
                }
            }
        }
    }

    private func cyclePermission(_ row: SumiCurrentSitePermissionRow) {
        guard let nextOption = URLBarPermissionInlineCycleResolver.nextOption(for: row) else { return }
        selectPermission(nextOption, for: row)
    }

    private func selectPermission(
        _ option: SumiCurrentSitePermissionOption,
        for row: SumiCurrentSitePermissionRow
    ) {
        Task { @MainActor in
            await currentSitePermissionsModel.select(
                option,
                for: row,
                profile: activeProfile,
                dependencies: permissionDependencies,
                onAutoplayChanged: {
                    currentTab?.markAutoplayReloadRequiredIfNeeded(afterChangingPolicyFor: currentTab?.url)
                    currentTab?.updateAutoplayReloadRequirementForCurrentSite()
                }
            )
            await onReloadPermissionsImmediately()
            refreshCoordinator.scheduleCoalescedRefresh()
        }
    }

    private func openSystemSettings(for row: SumiCurrentSitePermissionRow) {
        Task { @MainActor in
            await currentSitePermissionsModel.openSystemSettings(
                for: row,
                systemPermissionService: browserContext.permission.systemPermissionService
            )
        }
    }

    private func openSiteSettings() {
        browserContext.openSiteSettings(currentTab, windowState)
        onClose()
    }

    private func openSiteDataDetails() {
        onSetMode(.siteDataDetails, .forward)
    }

    private func resetPermissionsToDefault() {
        Task { @MainActor in
            await currentSitePermissionsModel.resetCurrentSite(
                profile: activeProfile,
                dependencies: permissionDependencies
            )
            await onReloadPermissionsImmediately()
            refreshCoordinator.scheduleCoalescedRefresh()
        }
    }

    private func handleSettingAction(_ row: SiteControlsSettingRowModel) {
        switch row.kind {
        case .protection:
            guard row.isInteractive else { return }
            onSetMode(.protectionDetails, .forward)
        case .safariContentBlockers(let state, _):
            guard state.isInteractive else { return }
            setSafariContentBlockerSiteOverride(
                state.isEnabledForSite ? .disabled : .inherit
            )
        case .cookies:
            onSetMode(.siteDataDetails, .forward)
        case .localPage:
            break
        }
    }

    private func setSafariContentBlockerSiteOverride(
        _ override: SumiSafariContentBlockerSiteOverride
    ) {
        guard let currentTab else { return }
        browserContext.setSafariContentBlockerSiteOverride(
            override,
            currentTab.url
        )
        refreshCoordinator.scheduleCoalescedRefresh()
    }

    private func createBoost() {
        guard let currentTab else { return }
        do {
            try browserContext.createBoostAndOpenEditor(currentTab, activeProfile, windowState)
            onClose()
        } catch {
            onBookmarkError(error.localizedDescription)
        }
    }

    private func toggleBoost(_ boost: SumiBoost) {
        browserContext.toggleActiveBoost(boost, activeProfile?.isEphemeral == true)
        refreshCoordinator.scheduleCoalescedRefresh()
    }

    private func editBoost(_ boost: SumiBoost) {
        guard let currentTab else { return }
        browserContext.presentBoostEditor(boost, currentTab, activeProfile, windowState)
        onClose()
    }

    private func openBoostFromFooter() {
        if let activeBoost = currentSiteBoosts.first(where: { $0.id == currentActiveBoostId }) {
            editBoost(activeBoost)
        } else if let boost = currentSiteBoosts.first {
            editBoost(boost)
        } else {
            createBoost()
        }
    }
}

private struct HubSectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?
    var isSectionHovered: Bool = true

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(URLBarHubTypography.sectionHeaderTitle)
                .foregroundStyle(URLBarHubNativeStyle.primaryText)
            Spacer(minLength: 0)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(URLBarHubTypography.sectionHeaderAction)
                    .foregroundStyle(isHovering ? URLBarHubNativeStyle.secondaryText : URLBarHubNativeStyle.tertiaryText)
                    .opacity(isSectionHovered ? 1 : 0)
                    .allowsHitTesting(isSectionHovered)
                    .animation(.easeInOut(duration: 0.15), value: isSectionHovered)
            }
        }
        .sidebarHover($isHovering)
    }
}

private struct SumiHubHeaderButton: View {
    let iconName: String
    let fallbackSystemName: String
    let help: String
    var isEnabled: Bool = true
    var isActive: Bool = false
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

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
                    .stroke(borderColor, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .scaleEffect(buttonScale)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : URLBarHubNativeStyle.popoverActionDisabledAlpha)
        .help(help)
        .sidebarHover { hovering in
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

    private var backgroundFill: Color {
        if isActive {
            return URLBarHubNativeStyle.accentBackground
        }
        if isPressed || isHovered {
            return URLBarHubNativeStyle.hoveredControlBackground
        }
        return URLBarHubNativeStyle.controlBackground
    }

    private var iconTint: Color {
        isActive ? URLBarHubNativeStyle.accentText : URLBarHubNativeStyle.primaryText
    }

    private var borderColor: Color {
        isActive ? URLBarHubNativeStyle.accentBackground : URLBarHubNativeStyle.separator
    }

    private var buttonScale: CGFloat {
        if isPressed {
            return 0.97
        }
        return 1
    }
}
