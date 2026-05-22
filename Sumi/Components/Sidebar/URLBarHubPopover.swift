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
    @State private var mode: Mode = .controls
    @State private var navigationDirection: NavigationDirection = .forward
    @State private var containerWidth: CGFloat = Mode.controls.preferredWidth
    @State private var bookmarkErrorMessage: String?
    @State private var scheduledPermissionsReloadTask: Task<Void, Never>?
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
        return !extensionSurfaceStore.enabledExtensions.isEmpty || sumiScriptsEnabled
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
            handleBookmarkPresentationRequest(bookmarkPresentationRequest)
        }
        .task(id: permissionsLoadKey) {
            await reloadPermissionsImmediately()
        }
        .onChange(of: bookmarkPresentationRequest) { _, request in
            handleBookmarkPresentationRequest(request)
        }
        .onChange(of: currentTab?.id) { _, _ in
            resetToControls()
            refreshNonce += 1
            schedulePermissionsReloadAfterStoreChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sumiTabNavigationStateDidChange)) { notification in
            handleNavigationStateDidChange(notification)
        }
        .onReceive(browserManager.protectionCoordinator.settings.changesPublisher) {
            _ in refreshNonce += 1
        }
        .onReceive(browserManager.protectionCoordinator.sitePolicyChangesPublisher()) {
            _ in refreshNonce += 1
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

            if !snapshot.settingsRows.isEmpty || !currentSitePermissionsModel.rows.isEmpty {
                Divider()
                    .padding(.horizontal, 8)
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
                extensions: extensionSurfaceStore.enabledExtensions,
                layout: .hubTiles
            )
            .environmentObject(browserManager)
            .environment(windowState)
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
            refreshNonce += 1
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
            refreshNonce += 1
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
            refreshNonce += 1
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
        refreshNonce += 1
    }

    private func shareCurrentPage() {
        guard let url = currentTab?.url else { return }
        let source = windowState.sidebarTransientSessionCoordinator.preparedPresentationSource(
            window: windowState.window
        )
        browserManager.presentSharingServicePicker([url], source: source)
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
        schedulePermissionsReloadAfterStoreChange()
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

    @State private var pendingDeletionEntry: SumiSiteDataEntry?

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
                    .foregroundStyle(URLBarHubNativeStyle.primaryText)
                    .lineLimit(1)
                URLBarFadingText(
                    displayHost,
                    font: .system(size: 12, weight: .medium),
                    color: URLBarHubNativeStyle.secondaryText
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
                .foregroundStyle(URLBarHubNativeStyle.primaryText)
            Text("Sites can store preferences, session data, and cached files on your device. This data is available to the site and its subdomains.")
                .font(.system(size: 13))
                .foregroundStyle(URLBarHubNativeStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Data from this site")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(URLBarHubNativeStyle.primaryText)

            if model.isLoading && model.entries.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading site data...")
                        .font(.system(size: 12))
                        .foregroundStyle(URLBarHubNativeStyle.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .center)
            } else if model.entries.isEmpty {
                Text("No site data is stored for \(displayHost).")
                    .font(.system(size: 12.5))
                    .foregroundStyle(URLBarHubNativeStyle.secondaryText)
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

    @Environment(\.colorScheme) private var colorScheme

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
                        .foregroundStyle(URLBarHubNativeStyle.primaryText)
                        .multilineTextAlignment(.center)
                    Text("This will delete cookies and site data for \(domain).")
                        .font(.system(size: 12.5))
                        .foregroundStyle(URLBarHubNativeStyle.secondaryText)
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
            .background(URLBarHubNativeStyle.backgroundFallback)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(URLBarHubNativeStyle.separator, lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.18), radius: 18, x: 0, y: 8)
            .padding(16)
        }
    }

    private var destructiveColor: Color {
        URLBarHubNativeStyle.destructiveBackground
    }
}

private struct URLBarSiteDataConfirmationButtonStyle: ButtonStyle {
    enum Role {
        case secondary
        case destructive
    }

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    let role: Role

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
            return URLBarHubNativeStyle.primaryText
        case .destructive:
            return .white
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch role {
        case .secondary:
            return isPressed || isHovering
                ? URLBarHubNativeStyle.hoveredControlBackground
                : URLBarHubNativeStyle.controlBackground
        case .destructive:
            let base = URLBarHubNativeStyle.destructiveBackground
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

    @State private var isTitleHovered = false
    @State private var isDeleteHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                titleArea

                Button(action: onDelete) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isDeleteHovered ? URLBarHubNativeStyle.hoveredControlBackground : Color.clear)

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
                .foregroundStyle(URLBarHubNativeStyle.secondaryText)
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
                    color: URLBarHubNativeStyle.primaryText
                )
                URLBarFadingText(
                    summary,
                    font: .system(size: 11.5),
                    color: URLBarHubNativeStyle.secondaryText
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
                .fill(isTitleHovered ? URLBarHubNativeStyle.hoveredControlBackground : Color.clear)
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

    @State private var isHovered = false

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
            .foregroundStyle(URLBarHubNativeStyle.primaryText)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .padding(.horizontal, 8)
            .background(isHovered ? URLBarHubNativeStyle.hoveredControlBackground : URLBarHubNativeStyle.controlBackground)
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

    var body: some View {
        Group {
            if let image = cachedFavicon {
                image
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(URLBarHubNativeStyle.secondaryText)
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

        return nil
    }
}

private struct URLBarSiteDataIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(URLBarHubNativeStyle.primaryText)
                .frame(width: 34, height: 34)
                .background(isHovered ? URLBarHubNativeStyle.hoveredControlBackground : URLBarHubNativeStyle.controlBackground)
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
                    .stroke(URLBarHubNativeStyle.separator, lineWidth: 0.5)
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

    private var backgroundFill: Color {
        if isPressed || isHovered || isActive {
            return URLBarHubNativeStyle.hoveredControlBackground
        }
        return URLBarHubNativeStyle.controlBackground
    }

    private var iconTint: Color {
        URLBarHubNativeStyle.primaryText
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
                .lineLimit(1)
                .minimumScaleFactor(0.86)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(URLBarHubNativeStyle.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var labelColor: Color {
        securityState == .notSecure ? URLBarHubNativeStyle.destructiveText : URLBarHubNativeStyle.primaryText
    }
}

private struct SumiFooterSiteSettingsButton: View {
    let siteSettingsAction: () -> Void
    let clearSiteDataAction: () -> Void
    let resetPermissionsAction: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: siteSettingsAction) {
            Image(systemName: "gearshape")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(URLBarHubNativeStyle.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(isHovered ? URLBarHubNativeStyle.hoveredControlBackground : URLBarHubNativeStyle.controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Site Settings")
        .accessibilityLabel("Site Settings")
        .accessibilityIdentifier("urlhub-site-settings-button")
        .contextMenu {
            Button("Site Settings", action: siteSettingsAction)
            Button("Clear Site Data", action: clearSiteDataAction)
            Divider()
            Button("Reset Permissions to Default", action: resetPermissionsAction)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

private struct URLHubPermissionInlineRow: View {
    private enum IconState {
        case neutral
        case on
        case off
    }

    private struct IconVisual {
        let iconName: String?
        let fallbackSystemName: String
        let showsSlash: Bool
    }

    let row: SumiCurrentSitePermissionRow
    let onCycle: () -> Void
    let onSelect: (SumiCurrentSitePermissionOption) -> Void
    let onOpenSystemSettings: () -> Void

    @State private var isHovered = false

    private var canCycle: Bool {
        row.isEditable && row.disabledReason == nil && !row.availableOptions.isEmpty
    }

    private var iconState: IconState {
        switch row.currentOption {
        case .allow, .allowAll:
            return .on
        case .block, .blockAudible, .blockAll:
            return .off
        case .ask, .default, nil:
            return .neutral
        }
    }

    var body: some View {
        Group {
            if canCycle {
                Button(action: onCycle) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .opacity(row.disabledReason == nil ? 1 : 0.55)
        .contextMenu {
            if !row.availableOptions.isEmpty {
                ForEach(row.availableOptions, id: \.self) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        Label(
                            option.title,
                            systemImage: option == row.currentOption ? "checkmark" : "circle"
                        )
                    }
                }
            }
            if row.showsSystemSettingsAction {
                Divider()
                Button("Open System Settings", action: onOpenSystemSettings)
            }
        }
        .onHover { hovering in
            guard canCycle else {
                isHovered = false
                return
            }
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityIdentifier("urlhub-permission-row-\(row.id)")
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconCapsuleFill)
                    .scaleEffect(isHovered ? 1.05 : 1)

                ZStack {
                    SumiZenChromeIcon(
                        iconName: iconVisual.iconName,
                        fallbackSystemName: iconVisual.fallbackSystemName,
                        size: 16,
                        tint: URLBarHubNativeStyle.primaryText
                    )

                    if iconVisual.showsSlash {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(URLBarHubNativeStyle.primaryText)
                            .frame(width: 2, height: 23)
                            .rotationEffect(.degrees(-42))
                            .shadow(color: URLBarHubNativeStyle.controlBackground, radius: 0, x: 1, y: 0)
                    }
                }
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                URLBarFadingText(
                    row.title,
                    font: .system(size: 13, weight: .medium),
                    color: URLBarHubNativeStyle.primaryText
                )
                if let status = row.statusLines.first {
                    URLBarFadingText(
                        status,
                        font: .system(size: 11.5),
                        color: URLBarHubNativeStyle.secondaryText
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var iconCapsuleFill: Color {
        if isHovered {
            return URLBarHubNativeStyle.hoveredControlBackground
        }
        switch iconState {
        case .on:
            return URLBarHubNativeStyle.hoveredControlBackground
        case .neutral, .off:
            return URLBarHubNativeStyle.controlBackground
        }
    }

    private var iconVisual: IconVisual {
        switch iconState {
        case .neutral:
            return IconVisual(
                iconName: row.iconName,
                fallbackSystemName: row.fallbackSystemName,
                showsSlash: false
            )
        case .on:
            return filledIconVisual
        case .off:
            return blockedIconVisual
        }
    }

    private var filledIconVisual: IconVisual {
        switch row.kind {
        case .sitePermission(let permissionType):
            return filledIconVisual(for: permissionType)
        case .popups:
            return IconVisual(iconName: "popup-fill", fallbackSystemName: "rectangle.on.rectangle.fill", showsSlash: false)
        case .externalScheme:
            return IconVisual(iconName: nil, fallbackSystemName: "arrow.up.forward.square.fill", showsSlash: false)
        case .autoplay:
            return IconVisual(iconName: "autoplay-media-fill", fallbackSystemName: "play.rectangle.fill", showsSlash: false)
        case .externalApps:
            return IconVisual(iconName: nil, fallbackSystemName: "arrow.up.forward.square.fill", showsSlash: false)
        case .filePicker:
            return IconVisual(iconName: nil, fallbackSystemName: "doc.badge.plus.fill", showsSlash: false)
        }
    }

    private func filledIconVisual(
        for permissionType: SumiPermissionType
    ) -> IconVisual {
        switch permissionType {
        case .camera:
            return IconVisual(iconName: "camera-fill", fallbackSystemName: "camera.fill", showsSlash: false)
        case .microphone:
            return IconVisual(iconName: "microphone-fill", fallbackSystemName: "mic.fill", showsSlash: false)
        case .cameraAndMicrophone:
            return IconVisual(iconName: "permissions-fill", fallbackSystemName: "video.fill", showsSlash: false)
        case .geolocation:
            return IconVisual(iconName: "location", fallbackSystemName: "location.fill", showsSlash: false)
        case .notifications:
            return IconVisual(iconName: nil, fallbackSystemName: "bell.fill", showsSlash: false)
        case .screenCapture:
            return IconVisual(iconName: "screen", fallbackSystemName: "display", showsSlash: false)
        case .popups:
            return IconVisual(iconName: "popup-fill", fallbackSystemName: "rectangle.on.rectangle.fill", showsSlash: false)
        case .externalScheme:
            return IconVisual(iconName: nil, fallbackSystemName: "arrow.up.forward.square.fill", showsSlash: false)
        case .autoplay:
            return IconVisual(iconName: "autoplay-media-fill", fallbackSystemName: "play.rectangle.fill", showsSlash: false)
        case .storageAccess:
            return IconVisual(iconName: "cookies-fill", fallbackSystemName: "externaldrive.fill", showsSlash: false)
        case .filePicker:
            return IconVisual(iconName: nil, fallbackSystemName: "doc.badge.plus.fill", showsSlash: false)
        }
    }

    private var blockedIconVisual: IconVisual {
        switch row.kind {
        case .sitePermission(let permissionType):
            return blockedIconVisual(for: permissionType)
        case .popups:
            return IconVisual(iconName: "popup", fallbackSystemName: "rectangle.on.rectangle", showsSlash: true)
        case .externalScheme:
            return IconVisual(iconName: "open", fallbackSystemName: "arrow.up.forward.square", showsSlash: true)
        case .autoplay:
            return IconVisual(iconName: "autoplay-media", fallbackSystemName: "play.rectangle", showsSlash: true)
        case .externalApps:
            return IconVisual(iconName: "open", fallbackSystemName: "arrow.up.forward.square", showsSlash: true)
        case .filePicker:
            return IconVisual(iconName: nil, fallbackSystemName: "doc.badge.plus", showsSlash: true)
        }
    }

    private func blockedIconVisual(
        for permissionType: SumiPermissionType
    ) -> IconVisual {
        switch permissionType {
        case .geolocation:
            return IconVisual(iconName: "location", fallbackSystemName: "location.fill", showsSlash: true)
        case .notifications:
            return IconVisual(iconName: "desktop-notification-blocked", fallbackSystemName: "bell.slash", showsSlash: false)
        case .screenCapture:
            return IconVisual(iconName: "screen-blocked", fallbackSystemName: "display", showsSlash: false)
        case .autoplay:
            return IconVisual(iconName: "autoplay-media", fallbackSystemName: "play.rectangle", showsSlash: true)
        case .storageAccess:
            return IconVisual(iconName: "cookies-fill", fallbackSystemName: "externaldrive", showsSlash: true)
        default:
            return IconVisual(iconName: row.iconName, fallbackSystemName: row.fallbackSystemName, showsSlash: true)
        }
    }
}

private struct HubSettingRow: View {
    let model: SiteControlsSettingRowModel
    let resetAction: (() -> Void)?
    let action: () -> Void

    @State private var isHovered = false

    init(
        model: SiteControlsSettingRowModel,
        resetAction: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.model = model
        self.resetAction = resetAction
        self.action = action
    }

    var body: some View {
        Group {
            if model.isInteractive && !model.isDisabled {
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
        .accessibilityIdentifier("urlhub-setting-row-\(model.id)")
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
                    color: URLBarHubNativeStyle.primaryText
                )
                if let subtitle = model.subtitle {
                    URLBarFadingText(
                        subtitle,
                        font: .system(size: 11.5),
                        color: URLBarHubNativeStyle.secondaryText
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if model.showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(URLBarHubNativeStyle.secondaryText)
                    .frame(width: 14, height: 22)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var capsuleFill: Color {
        isHovered ? URLBarHubNativeStyle.hoveredControlBackground : URLBarHubNativeStyle.controlBackground
    }

    private var iconTint: Color {
        URLBarHubNativeStyle.primaryText
    }

    private var capsuleScale: CGFloat {
        isHovered ? 1.05 : 1
    }
}
