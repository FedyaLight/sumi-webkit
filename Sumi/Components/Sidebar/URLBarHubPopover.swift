//
//  URLBarHubPopover.swift
//  Sumi
//
//  Canonical Sumi browser URL bar hosted from the sidebar shell.
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import WebKit

private struct URLBarHubPopoverContentSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
private struct URLBarHubNativeBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            NativeChromeMaterialBackground(role: .popover)

            if reduceTransparency {
                URLBarHubNativeStyle.backgroundFallback
            }
        }
    }
}

struct URLBarHubPopover: View {
    @EnvironmentObject private var browserManager: BrowserManager
    @EnvironmentObject private var extensionSurfaceStore: BrowserExtensionSurfaceStore
    @Environment(BrowserWindowState.self) private var windowState

    @ObservedObject var bookmarkManager: SumiBookmarkManager

    let bookmarkPresentationRequest: SumiBookmarkEditorPresentationRequest?
    let currentTab: Tab?
    let profile: Profile?
    let profileId: UUID?
    let onClose: () -> Void
    let onContentSizeChange: (CGSize) -> Void

    private enum Mode: Equatable {
        case controls
        case siteDataDetails
        case bookmark(SumiBookmarkEditorState)

        var preferredWidth: CGFloat {
            switch self {
            case .controls:
                return 234
            case .siteDataDetails,
                 .bookmark:
                return 392
            }
        }
    }

    private enum NavigationDirection {
        case forward
        case backward
    }

    private static let modeAnimation = Animation.spring(
        response: 0.3,
        dampingFraction: 0.88,
        blendDuration: 0.08
    )

    @State private var refreshNonce = 0
    @State private var coalescedRefreshTask: Task<Void, Never>?
    @State private var mode: Mode = .controls
    @State private var navigationDirection: NavigationDirection = .forward
    @State private var containerWidth: CGFloat = Mode.controls.preferredWidth
    @State private var bookmarkErrorMessage: String?
    @State private var scheduledPermissionsReloadTask: Task<Void, Never>?
    @State private var readerModeIsActive = false
    @State private var isCapturingScreenshot = false
    @StateObject private var shareButtonAnchor = URLBarHubShareAnchorStore()
    @AppStorage("URLBarHubScreenshotQualityScale") private var screenshotQualityScale = URLBarHubScreenshotQuality.twoX.rawValue
    @AppStorage("URLBarHubScreenshotCaptureTarget") private var screenshotCaptureTarget = URLBarHubScreenshotCaptureTarget.visiblePage.rawValue
    @AppStorage("URLBarHubScreenshotDestination") private var screenshotDestination = URLBarHubScreenshotDestination.askEveryTime.rawValue
    @StateObject private var siteDataDetailsModel = URLBarSiteDataDetailsViewModel()
    @StateObject private var currentSitePermissionsModel = SumiCurrentSitePermissionsViewModel()

    private var snapshot: SiteControlsSnapshot {
        _ = refreshNonce
        let start = Date()
        let resolved = SiteControlsSnapshot.resolve(
            url: currentTab?.url,
            profile: activeProfile,
            protectionCoordinator: browserManager.protectionCoordinator,
            protectionBrowserRestartRequired: browserManager.protectionCoordinator.settings.browserRestartRequired,
            protectionReloadRequired: currentTab?.isProtectionReloadRequired == true
        )
        currentTab?.lastProtectionURLHubSummaryDuration = Date().timeIntervalSince(start)
        return resolved
    }

    private var showsExtensionSection: Bool {
        let sumiScriptsEnabled = browserManager.userscriptsModule.isEnabled
        return !unpinnedEnabledExtensionActions.isEmpty
            || sumiScriptsEnabled
    }

    private var showsBoostsSection: Bool {
        browserManager.boostsModule.canBoost(url: currentTab?.url)
    }

    private var currentSiteBoosts: [SumiBoost] {
        _ = refreshNonce
        return browserManager.boostsModule.changedBoosts(
            for: currentTab?.url,
            profileId: activeProfile?.id
        )
    }

    private var currentActiveBoostId: UUID? {
        _ = refreshNonce
        return browserManager.boostsModule.activeBoostId(
            for: currentTab?.url,
            profileId: activeProfile?.id
        )
    }

    private var unpinnedEnabledExtensionActions: [InstalledExtension] {
        extensionSurfaceStore.enabledExtensions
            .filter(\.hasAction)
            .filter { browserManager.extensionsModule.isPinnedToToolbar($0.id) == false }
    }

    private var permissionDependencies: SumiCurrentSitePermissionsViewModel.LoadDependencies {
        SumiCurrentSitePermissionsViewModel.LoadDependencies(
            coordinator: browserManager.permissionCoordinator,
            systemPermissionService: browserManager.systemPermissionService,
            runtimeController: browserManager.runtimePermissionController,
            autoplayStore: SumiAutoplayPolicyStoreAdapter.shared,
            blockedPopupStore: browserManager.blockedPopupStore,
            externalSchemeSessionStore: browserManager.externalSchemeSessionStore,
            indicatorEventStore: browserManager.permissionIndicatorEventStore,
            siteActivityStore: browserManager.permissionSiteActivityStore
        )
    }

    private var permissionsLoadKey: String {
        [
            activeProfile?.id.uuidString ?? "none",
            activeProfile?.isEphemeral == true ? "ephemeral" : "persistent",
            currentTab?.id.uuidString ?? "none",
            currentTab?.currentPermissionPageId() ?? "none",
            currentTab?.url.absoluteString ?? "none",
            currentTab?.isAutoplayReloadRequired == true ? "autoplay-reload" : "autoplay-ready",
            currentTab?.audioState.isPlayingAudio == true ? "audio-playing" : "audio-idle",
            "\(browserManager.permissionSiteActivityStore.revision)",
        ].joined(separator: "|")
    }

    private var readerModeLoadKey: String {
        [
            currentTab?.id.uuidString ?? "none",
            currentTab?.url.absoluteString ?? "none",
            "\(refreshNonce)",
        ].joined(separator: "|")
    }

    private var audioStatePublisher: AnyPublisher<SumiWebViewAudioState, Never> {
        guard let currentTab else {
            return Empty<SumiWebViewAudioState, Never>().eraseToAnyPublisher()
        }
        return currentTab.$audioState
            .removeDuplicates()
            .dropFirst()
            .eraseToAnyPublisher()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            modeContent
                .id(modeIdentity)
                .frame(width: mode.preferredWidth, alignment: .topLeading)
                .transition(modeTransition)
        }
        .frame(width: containerWidth)
        .background(URLBarHubNativeBackground())
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: URLBarHubPopoverContentSizePreferenceKey.self,
                    value: proxy.size
                )
            }
        )
        .clipped()
        .animation(Self.modeAnimation, value: containerWidth)
        .onAppear {
            browserManager.extensionsModule
                .ensureActionSurfaceMetadataLoadedIfNeeded()
            handleBookmarkPresentationRequest(bookmarkPresentationRequest)
        }
        .task(id: permissionsLoadKey) {
            await reloadPermissionsImmediately()
        }
        .task(id: readerModeLoadKey) {
            await reloadReaderModeState()
        }
        .onChange(of: bookmarkPresentationRequest) { _, request in
            handleBookmarkPresentationRequest(request)
        }
        .onChange(of: currentTab?.id) { _, _ in
            resetToControls()
            readerModeIsActive = false
            scheduleCoalescedRefresh()
            schedulePermissionsReloadAfterStoreChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sumiTabNavigationStateDidChange)) { notification in
            handleNavigationStateDidChange(notification)
        }
        .onReceive(browserManager.protectionCoordinator.settings.changesPublisher) {
            _ in scheduleCoalescedRefresh()
        }
        .onReceive(browserManager.protectionCoordinator.sitePolicyChangesPublisher()) {
            _ in scheduleCoalescedRefresh()
        }
        .onReceive(browserManager.blockedPopupStore.objectWillChange) { _ in
            schedulePermissionsReloadAfterStoreChange()
        }
        .onReceive(browserManager.externalSchemeSessionStore.objectWillChange) { _ in
            schedulePermissionsReloadAfterStoreChange()
        }
        .onReceive(browserManager.permissionIndicatorEventStore.objectWillChange) { _ in
            schedulePermissionsReloadAfterStoreChange()
        }
        .onReceive(browserManager.permissionSiteActivityStore.objectWillChange) { _ in
            schedulePermissionsReloadAfterStoreChange()
        }
        .onReceive(browserManager.boostsModule.store.changesPublisher) { _ in
            scheduleCoalescedRefresh()
        }
        .onReceive(audioStatePublisher) { _ in
            schedulePermissionsReloadAfterStoreChange()
        }
        .onDisappear {
            scheduledPermissionsReloadTask?.cancel()
            scheduledPermissionsReloadTask = nil
        }
        .onPreferenceChange(URLBarHubPopoverContentSizePreferenceKey.self) { size in
            onContentSizeChange(size)
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
                    scheduleCoalescedRefresh()
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
                    scheduleCoalescedRefresh()
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

    private var modeIdentity: String {
        switch mode {
        case .controls:
            return "controls"
        case .siteDataDetails:
            return "site-data-details"
        case .bookmark(let state):
            return "bookmark-\(state.id)"
        }
    }

    private var modeTransition: AnyTransition {
        switch navigationDirection {
        case .forward:
            return .asymmetric(
                insertion: Self.submenuInsertionTransition,
                removal: Self.rootRemovalTransition
            )
        case .backward:
            return .asymmetric(
                insertion: Self.rootInsertionTransition,
                removal: Self.submenuRemovalTransition
            )
        }
    }

    private static var submenuInsertionTransition: AnyTransition {
        .offset(x: 24, y: 0)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.985, anchor: .trailing))
    }

    private static var rootRemovalTransition: AnyTransition {
        .offset(x: -14, y: 0)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.995, anchor: .leading))
    }

    private static var rootInsertionTransition: AnyTransition {
        .offset(x: -18, y: 0)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.99, anchor: .leading))
    }

    private static var submenuRemovalTransition: AnyTransition {
        .offset(x: 24, y: 0)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.985, anchor: .trailing))
    }

    private func setMode(_ newMode: Mode, direction: NavigationDirection) {
        navigationDirection = direction
        containerWidth = mode.preferredWidth
        withAnimation(Self.modeAnimation) {
            mode = newMode
            containerWidth = newMode.preferredWidth
        }
    }

    private func resetToControls() {
        navigationDirection = .backward
        mode = .controls
        containerWidth = Mode.controls.preferredWidth
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
                extensions: unpinnedEnabledExtensionActions,
                layout: .hubTiles
            )
            .environmentObject(browserManager)
            .environment(windowState)
        }
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
                showBookmarkEditor()
            }

            SumiHubHeaderButton(
                iconName: "camera",
                fallbackSystemName: "camera",
                help: "Screenshot (\(screenshotQuality.label))",
                isEnabled: !isCapturingScreenshot
            ) {
                captureCurrentPageUsingSavedSettings()
            }
            .contextMenu {
                Button("Screenshot Settings...", action: presentScreenshotSettings)
            }

            SumiHubHeaderButton(
                iconName: "reader-mode",
                fallbackSystemName: "doc.richtext",
                help: readerModeIsActive ? "Hide Reader" : "Reader Mode",
                isEnabled: snapshot.readerAvailability == .available,
                isActive: readerModeIsActive
            ) {
                handleReaderMode()
            }

            SumiHubHeaderButton(
                iconName: "share",
                fallbackSystemName: "square.and.arrow.up",
                help: "Share"
            ) {
                shareCurrentPage()
            }
            .background(URLBarHubShareAnchorView(anchor: shareButtonAnchor))
        }
    }

    private var screenshotQuality: URLBarHubScreenshotQuality {
        URLBarHubScreenshotQuality(rawValue: screenshotQualityScale) ?? .oneX
    }

    private var screenshotOptions: URLBarHubScreenshotOptions {
        URLBarHubScreenshotOptions(
            target: URLBarHubScreenshotCaptureTarget(rawValue: screenshotCaptureTarget) ?? .visiblePage,
            destination: URLBarHubScreenshotDestination(rawValue: screenshotDestination) ?? .askEveryTime,
            scale: screenshotQuality
        )
    }

    private var isCurrentPageBookmarked: Bool {
        _ = refreshNonce
        _ = bookmarkManager.revision
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
                        resetAction: resetAction(for: row)
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
                    .font(.system(size: 12, weight: .semibold))
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

    private func reloadPermissionsImmediately() async {
        scheduledPermissionsReloadTask?.cancel()
        scheduledPermissionsReloadTask = nil
        await reloadPermissions()
    }

    private func schedulePermissionsReloadAfterStoreChange() {
        scheduledPermissionsReloadTask?.cancel()
        scheduledPermissionsReloadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            await reloadPermissions()
            scheduleCoalescedRefresh()
            scheduledPermissionsReloadTask = nil
        }
    }

    private func reloadPermissions() async {
        await currentSitePermissionsModel.load(
            tab: currentTab,
            profile: activeProfile,
            dependencies: permissionDependencies,
            systemSnapshotMode: .none
        )
    }

    private func reloadReaderModeState() async {
        guard let currentTab,
              let webView = browserManager.getWebView(
                for: currentTab.id,
                in: windowState.id
              )
        else {
            readerModeIsActive = false
            return
        }

        readerModeIsActive = await SumiReaderModeService.isReaderModeActive(on: webView)
    }

    private func cyclePermission(_ row: SumiCurrentSitePermissionRow) {
        guard let nextOption = nextInlineOption(for: row) else { return }
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
            await reloadPermissionsImmediately()
            scheduleCoalescedRefresh()
        }
    }

    private func nextInlineOption(
        for row: SumiCurrentSitePermissionRow
    ) -> SumiCurrentSitePermissionOption? {
        let proposed: SumiCurrentSitePermissionOption
        switch row.kind {
        case .autoplay:
            switch row.currentOption ?? .default {
            case .default, .ask:
                proposed = .blockAll
            case .blockAll, .blockAudible, .block:
                proposed = .allowAll
            case .allowAll, .allow:
                proposed = .blockAll
            }
        case .popups:
            switch row.currentOption ?? .default {
            case .default, .ask:
                proposed = .block
            case .block:
                proposed = .allow
            case .allow:
                proposed = .block
            case .allowAll, .blockAudible, .blockAll:
                proposed = .block
            }
        case .sitePermission, .externalScheme:
            switch row.currentOption ?? .ask {
            case .ask, .default:
                proposed = .block
            case .block:
                proposed = .allow
            case .allow:
                proposed = .block
            case .allowAll, .blockAudible, .blockAll:
                proposed = .block
            }
        case .externalApps, .filePicker:
            return nil
        }

        return row.availableOptions.contains(proposed) ? proposed : row.availableOptions.first
    }

    private func openSystemSettings(for row: SumiCurrentSitePermissionRow) {
        Task { @MainActor in
            await currentSitePermissionsModel.openSystemSettings(
                for: row,
                systemPermissionService: browserManager.systemPermissionService
            )
        }
    }

    private func openSiteSettings() {
        browserManager.openSiteSettingsTab(
            focusing: currentTab,
            in: windowState
        )
        onClose()
    }

    private func openSiteDataDetails() {
        setMode(.siteDataDetails, direction: .forward)
    }

    private func resetPermissionsToDefault() {
        Task { @MainActor in
            await currentSitePermissionsModel.resetCurrentSite(
                profile: activeProfile,
                dependencies: permissionDependencies
            )
            await reloadPermissionsImmediately()
            scheduleCoalescedRefresh()
        }
    }


    private func handleSettingAction(_ row: SiteControlsSettingRowModel) {
        switch row.kind {
        case .protection(let plan, _):
            guard plan.requestedLevel != .off else { return }
            setProtectionOverride(
                plan.siteOverride == .disabled ? .inherit : .disabled
            )
        case .cookies:
            setMode(.siteDataDetails, direction: .forward)
        case .localPage:
            break
        }
    }

    private func resetAction(
        for row: SiteControlsSettingRowModel
    ) -> (() -> Void)? {
        _ = row
        return nil
    }

    private func setProtectionOverride(
        _ override: SumiAdblockSiteOverride
    ) {
        guard let currentTab else { return }
        browserManager.protectionCoordinator.setSiteOverride(override, for: currentTab.url)
        currentTab.markProtectionReloadRequiredIfNeeded(
            afterChangingPolicyFor: currentTab.url
        )
        scheduleCoalescedRefresh()
    }

    private func createBoost() {
        guard let currentTab else { return }
        do {
            try browserManager.boostsModule.createBoostAndOpenEditor(
                tab: currentTab,
                profile: activeProfile,
                windowState: windowState
            )
            onClose()
        } catch {
            bookmarkErrorMessage = error.localizedDescription
        }
    }

    private func toggleBoost(_ boost: SumiBoost) {
        browserManager.boostsModule.toggleActiveBoost(
            boost,
            isEphemeral: activeProfile?.isEphemeral == true
        )
        scheduleCoalescedRefresh()
    }

    private func editBoost(_ boost: SumiBoost) {
        guard let currentTab else { return }
        browserManager.boostsModule.presentEditor(
            boost: boost,
            tab: currentTab,
            profile: activeProfile,
            windowState: windowState
        )
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

    private func shareCurrentPage() {
        guard let url = currentTab?.url else { return }
        let source = windowState.sidebarTransientSessionCoordinator.preparedPresentationSource(
            window: windowState.window,
            ownerView: shareButtonAnchor.view
        )
        browserManager.presentSharingServicePicker([url], source: source)
    }

    private func captureCurrentPageUsingSavedSettings() {
        guard let currentTab,
              let webView = browserManager.getWebView(
                for: currentTab.id,
                in: windowState.id
              ),
              !isCapturingScreenshot else {
            return
        }

        captureCurrentPage(
            currentTab: currentTab,
            webView: webView,
            options: screenshotOptions
        )
    }

    private func presentScreenshotSettings() {
        guard let currentTab,
              let webView = browserManager.getWebView(
                for: currentTab.id,
                in: windowState.id
              ),
              !isCapturingScreenshot else {
            return
        }

        URLBarHubScreenshotSettingsPresenter.present(
            initial: screenshotOptions,
            window: windowState.window
        ) { options in
            guard let options else { return }
            screenshotCaptureTarget = options.target.rawValue
            screenshotDestination = options.destination.rawValue
            screenshotQualityScale = options.scale.rawValue
            captureCurrentPage(currentTab: currentTab, webView: webView, options: options)
        }
    }

    private func captureCurrentPage(
        currentTab: Tab,
        webView: WKWebView,
        options: URLBarHubScreenshotOptions
    ) {
        guard !isCapturingScreenshot else { return }
        isCapturingScreenshot = true

        switch options.target {
        case .visiblePage:
            saveCurrentPageCapture(
                currentTab: currentTab,
                webView: webView,
                rect: webView.bounds,
                options: options
            )

        case .selectedArea:
            URLBarHubScreenshotRegionSelector.selectRegion(in: webView) { rect in
                guard let rect else {
                    isCapturingScreenshot = false
                    return
                }

                saveCurrentPageCapture(
                    currentTab: currentTab,
                    webView: webView,
                    rect: rect,
                    options: options
                )
            }
        }
    }

    private func saveCurrentPageCapture(
        currentTab: Tab,
        webView: WKWebView,
        rect: CGRect,
        options: URLBarHubScreenshotOptions
    ) {
        let suggestedFilename = URLBarHubSnapshotActions.suggestedFilename(
            for: currentTab,
            quality: options.scale
        )

        switch options.destination {
        case .askEveryTime:
            askForScreenshotDestination(
                suggestedFilename: suggestedFilename
            ) { destinationURL in
                guard let destinationURL else {
                    isCapturingScreenshot = false
                    return
                }

                writeCurrentPageCapture(
                    webView: webView,
                    rect: rect,
                    options: options,
                    destinationURL: destinationURL
                )
            }

        case .downloads:
            writeCurrentPageCapture(
                webView: webView,
                rect: rect,
                options: options,
                destinationURL: DownloadFileUtilities.uniqueDestination(for: suggestedFilename)
            )
        }
    }

    private func askForScreenshotDestination(
        suggestedFilename: String,
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        let savePanel = NSSavePanel()
        savePanel.title = "Save Page Capture"
        savePanel.message = "Choose where to save the page snapshot"
        savePanel.nameFieldStringValue = suggestedFilename
        savePanel.allowedContentTypes = [.png]

        let panelCompletion: (NSApplication.ModalResponse) -> Void = { result in
            guard result == .OK,
                  let destinationURL = savePanel.url else {
                completion(nil)
                return
            }
            completion(destinationURL)
        }

        if let window = windowState.window {
            savePanel.beginSheetModal(for: window, completionHandler: panelCompletion)
        } else {
            savePanel.begin(completionHandler: panelCompletion)
        }
    }

    private func writeCurrentPageCapture(
        webView: WKWebView,
        rect: CGRect,
        options: URLBarHubScreenshotOptions,
        destinationURL: URL
    ) {
        URLBarHubScreenshotCapture.writeVisibleSnapshot(
            of: webView,
            rect: rect,
            quality: options.scale,
            to: destinationURL
        ) { _ in
            isCapturingScreenshot = false
        }
    }

    private func showBookmarkEditor() {
        guard let currentTab else { return }
        do {
            let editorState = try bookmarkManager.editorState(for: currentTab)
            bookmarkErrorMessage = nil
            scheduleCoalescedRefresh()
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

        scheduleCoalescedRefresh()
        schedulePermissionsReloadAfterStoreChange()
        if case .bookmark(let state) = mode,
           state.tabID == tab.id,
           state.pageURL.absoluteString != tab.url.absoluteString
        {
            resetToControls()
        }
    }

    private func handleReaderMode() {
        guard let currentTab,
              let webView = browserManager.getWebView(
                for: currentTab.id,
                in: windowState.id
              )
        else {
            return
        }

        Task { @MainActor in
            try? await SumiReaderModeService.toggleReaderMode(
                on: webView,
                tab: currentTab
            )
            readerModeIsActive = await SumiReaderModeService.isReaderModeActive(on: webView)
            onClose()
        }
    }

    private func scheduleCoalescedRefresh() {
        coalescedRefreshTask?.cancel()
        coalescedRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard !Task.isCancelled else { return }
            refreshNonce += 1
        }
    }
}

private struct HubSectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(URLBarHubNativeStyle.primaryText)
            Spacer(minLength: 0)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isHovering ? URLBarHubNativeStyle.secondaryText : URLBarHubNativeStyle.tertiaryText)
            }
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

private final class URLBarHubShareAnchorStore: ObservableObject {
    weak var view: NSView?
}

private struct URLBarHubShareAnchorView: NSViewRepresentable {
    let anchor: URLBarHubShareAnchorStore

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        _ = nsView
    }
}
