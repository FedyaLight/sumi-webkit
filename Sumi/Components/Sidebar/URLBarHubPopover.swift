//
//  URLBarHubPopover.swift
//  Sumi
//
//  Canonical Sumi browser URL bar hosted from the sidebar shell.
//

import Combine
import SwiftUI
import SumiWebRuntime

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
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry

    let browserContext: URLBarHubBrowserContext
    @ObservedObject var bookmarkManager: SumiBookmarkManager

    let currentTab: Tab?
    let profile: Profile?
    let profileId: UUID?
    let adblockZapperStore: SumiAdblockZapperStore
    let onClose: () -> Void
    let onContentSizeChange: (CGSize) -> Void

    @StateObject private var navigation = URLBarHubNavigationModel()
    @StateObject private var refreshCoordinator = URLBarHubRefreshCoordinator()
    @State private var permissionsSession = URLBarHubPermissionsSession()
    @State private var bookmarkErrorMessage: String?
    @State private var readerModeIsActive = false
    @StateObject private var pageActionOwner = URLBarHubPageActionOwner()
    @AppStorage("URLBarHubScreenshotQualityScale") private var screenshotQualityScale = URLBarHubScreenshotQuality.twoX.rawValue
    @AppStorage("URLBarHubScreenshotCaptureTarget") private var screenshotCaptureTarget = URLBarHubScreenshotCaptureTarget.visiblePage.rawValue
    @AppStorage("URLBarHubScreenshotDestination") private var screenshotDestination = URLBarHubScreenshotDestination.askEveryTime.rawValue
    @StateObject private var siteDataDetailsModel: URLBarSiteDataDetailsViewModel
    @StateObject private var currentSitePermissionsModel = SumiCurrentSitePermissionsViewModel()

    @MainActor
    init(
        browserContext: URLBarHubBrowserContext,
        currentTab: Tab?,
        profile: Profile?,
        profileId: UUID?,
        onClose: @escaping () -> Void,
        onContentSizeChange: @escaping (CGSize) -> Void
    ) {
        self.browserContext = browserContext
        self.bookmarkManager = browserContext.bookmarkManager
        self.currentTab = currentTab
        self.profile = profile
        self.profileId = profileId
        self.adblockZapperStore = browserContext.adblockZapperStore
        self.onClose = onClose
        self.onContentSizeChange = onContentSizeChange
        self._siteDataDetailsModel = StateObject(
            wrappedValue: URLBarSiteDataDetailsViewModel(
                cleanupService: browserContext.cleanupService,
                profileWebsiteDataMutationService: browserContext.profileWebsiteDataMutationService,
                policyStore: browserContext.siteDataPolicyStore,
                enforcementService: browserContext.siteDataPolicyEnforcementService,
                faviconService: browserContext.faviconService
            )
        )
    }

    private var snapshot: SiteControlsSnapshot {
        let _ = refreshCoordinator.refreshNonce
        return browserContext.siteControlsSnapshot(
            currentTab?.url,
            activeProfile,
            currentTab?.isProtectionReloadRequired == true,
            currentTab?.isSafariContentBlockerReloadRequired == true
        )
    }

    private var showsExtensionSection: Bool {
        let sumiScriptsEnabled = browserContext.extensionActions.sumiScriptsManagerEnabled()
        return !unpinnedEnabledExtensionActions.isEmpty
            || sumiScriptsEnabled
    }

    private var showsBoostsSection: Bool {
        browserContext.canBoost(currentTab?.url)
    }

    private var currentSiteBoosts: [SumiBoost] {
        _ = refreshCoordinator.refreshNonce
        return browserContext.changedBoosts(currentTab?.url, activeProfile?.id)
    }

    private var currentActiveBoostId: UUID? {
        _ = refreshCoordinator.refreshNonce
        return browserContext.activeBoostId(currentTab?.url, activeProfile?.id)
    }

    private var unpinnedEnabledExtensionActions: [InstalledExtension] {
        browserContext.extensionSurfaceStore.enabledExtensions
            .filter(\.hasAction)
            .filter { browserContext.extensionActions.isPinnedToToolbar($0.id) == false }
    }

    private var permissionDependencies: SumiCurrentSitePermissionsViewModel.LoadDependencies {
        browserContext.permissionDependencies
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
            "\(browserContext.permission.siteActivityRevision())",
        ].joined(separator: "|")
    }

    private var readerModeLoadKey: String {
        [
            currentTab?.id.uuidString ?? "none",
            currentTab?.url.absoluteString ?? "none",
            "\(refreshCoordinator.refreshNonce)",
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

    var body: some View {
        ZStack(alignment: .topLeading) {
            modeContent
                .id(navigation.mode.identity)
                .frame(width: navigation.mode.preferredWidth, alignment: .topLeading)
                .transition(navigation.modeTransition)
        }
        .frame(width: navigation.containerWidth)
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
        .animation(URLBarHubNavigationModel.modeAnimation, value: navigation.containerWidth)
        .onAppear {
            pageActionOwner.windowRegistry = windowRegistry
            browserContext.extensionActions.ensureActionMetadataLoadedIfNeeded()
            handleBookmarkPresentationRequest(browserContext.bookmarkPresentationRequest)
        }
        .task(id: permissionsLoadKey) {
            await reloadPermissionsImmediately()
        }
        .task(id: readerModeLoadKey) {
            await reloadReaderModeState()
        }
        .onChange(of: browserContext.bookmarkPresentationRequest) { _, request in
            handleBookmarkPresentationRequest(request)
        }
        .onChange(of: currentTab?.id) { _, _ in
            navigation.resetToControls()
            readerModeIsActive = false
            refreshCoordinator.scheduleCoalescedRefresh()
            schedulePermissionsReloadAfterStoreChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sumiTabNavigationStateDidChange)) { notification in
            handleNavigationStateDidChange(notification)
        }
        .onReceive(browserContext.protectionSettingsChanges) {
            _ in refreshCoordinator.scheduleCoalescedRefresh()
        }
        .onReceive(browserContext.protectionSitePolicyChanges) {
            _ in refreshCoordinator.scheduleCoalescedRefresh()
        }
        .onReceive(browserContext.blockedPopupChanges) { _ in
            schedulePermissionsReloadAfterStoreChange()
        }
        .onReceive(browserContext.externalSchemeChanges) { _ in
            schedulePermissionsReloadAfterStoreChange()
        }
        .onReceive(browserContext.indicatorEventChanges) { _ in
            schedulePermissionsReloadAfterStoreChange()
        }
        .onReceive(browserContext.permissionSiteActivityChanges) { _ in
            schedulePermissionsReloadAfterStoreChange()
        }
        .onReceive(browserContext.boostChanges) { _ in
            refreshCoordinator.scheduleCoalescedRefresh()
        }
        .onReceive(audioStatePublisher) { _ in
            schedulePermissionsReloadAfterStoreChange()
        }
        .onDisappear {
            permissionsSession.cancel()
            refreshCoordinator.cancel()
        }
        .onPreferenceChange(URLBarHubPopoverContentSizePreferenceKey.self) { size in
            onContentSizeChange(size)
        }
    }

    @ViewBuilder
    private var modeContent: some View {
        switch navigation.mode {
        case .controls:
            URLBarHubControlsView(
                browserContext: browserContext,
                bookmarkManager: bookmarkManager,
                pageActionOwner: pageActionOwner,
                currentSitePermissionsModel: currentSitePermissionsModel,
                refreshCoordinator: refreshCoordinator,
                currentTab: currentTab,
                activeProfile: activeProfile,
                snapshot: snapshot,
                showsExtensionSection: showsExtensionSection,
                showsBoostsSection: showsBoostsSection,
                currentSiteBoosts: currentSiteBoosts,
                currentActiveBoostId: currentActiveBoostId,
                unpinnedEnabledExtensionActions: unpinnedEnabledExtensionActions,
                permissionDependencies: permissionDependencies,
                readerModeIsActive: readerModeIsActive,
                bookmarkErrorMessage: bookmarkErrorMessage,
                screenshotOptions: screenshotOptions,
                onScreenshotOptionsChange: { options in
                    screenshotCaptureTarget = options.target.rawValue
                    screenshotDestination = options.destination.rawValue
                    screenshotQualityScale = options.scale.rawValue
                },
                onSetMode: { mode, direction in
                    navigation.setMode(mode, direction: direction)
                },
                onClose: onClose,
                onReloadPermissionsImmediately: reloadPermissionsImmediately,
                onHandleReaderMode: handleReaderMode,
                onShowBookmarkEditor: showBookmarkEditor,
                onBookmarkError: { message in
                    bookmarkErrorMessage = message
                }
            )
        case .protectionDetails:
            URLBarHubProtectionSection(
                coordinator: browserContext.protectionCoordinator,
                zapperStore: adblockZapperStore,
                currentTab: currentTab,
                webViewProvider: {
                    guard let currentTab else { return nil }
                    return browserContext.webView(currentTab, windowState)
                },
                onBack: {
                    navigation.setMode(.controls, direction: .backward)
                },
                onClose: onClose,
                onDidMutate: {
                    currentTab?.markProtectionReloadRequiredIfNeeded(
                        afterChangingPolicyFor: currentTab?.url
                    )
                    refreshCoordinator.scheduleCoalescedRefresh()
                }
            )
        case .siteDataDetails:
            URLBarSiteDataDetailsView(
                model: siteDataDetailsModel,
                currentTab: currentTab,
                profile: activeProfile,
                onBack: {
                    navigation.setMode(.controls, direction: .backward)
                },
                onClose: onClose,
                onDidMutate: {
                    refreshCoordinator.scheduleCoalescedRefresh()
                }
            )
        case .bookmark(let state):
            URLBarBookmarkEditorView(
                bookmarkManager: bookmarkManager,
                state: state,
                currentTab: currentTab,
                folders: bookmarkManager.folders(),
                onClose: {
                    navigation.setMode(.controls, direction: .backward)
                },
                onDidMutate: {
                    refreshCoordinator.scheduleCoalescedRefresh()
                }
            )
            .id(state.id)
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
           let profile = browserContext.profiles().first(where: { $0.id == profileId }) {
            return profile
        }
        return browserContext.currentProfile()
    }

    private func reloadPermissionsImmediately() async {
        await permissionsSession.reloadImmediately {
            await reloadPermissions()
        }
    }

    private func schedulePermissionsReloadAfterStoreChange() {
        permissionsSession.scheduleReloadAfterStoreChange(
            reload: { await reloadPermissions() },
            onDidReload: { refreshCoordinator.scheduleCoalescedRefresh() }
        )
    }

    private func reloadPermissions() async {
        let currentWebView = currentTab.flatMap { browserContext.webView($0, windowState) }
        await currentSitePermissionsModel.load(
            context: SumiCurrentSitePermissionsViewModel.context(
                tab: currentTab,
                profile: activeProfile,
                webView: currentWebView
            ),
            webView: currentWebView,
            profile: activeProfile,
            reloadRequired: currentTab?.isAutoplayReloadRequired == true,
            autoplayInUse: currentTab?.audioState.isPlayingAudio == true,
            dependencies: permissionDependencies,
            systemSnapshotMode: .none
        )
    }

    private func reloadReaderModeState() async {
        guard let currentTab,
              let webView = browserContext.webView(currentTab, windowState)
        else {
            readerModeIsActive = false
            return
        }

        readerModeIsActive = await SumiReaderModeService.isReaderModeActive(on: webView)
    }

    private func showBookmarkEditor() {
        guard let currentTab else { return }
        do {
            let editorState = try bookmarkManager.editorState(for: currentTab)
            bookmarkErrorMessage = nil
            refreshCoordinator.scheduleCoalescedRefresh()
            navigation.setMode(.bookmark(editorState), direction: .forward)
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
        browserContext.clearBookmarkEditorPresentationRequest(request)
    }

    private func handleNavigationStateDidChange(_ notification: Notification) {
        guard let tab = notification.object as? Tab,
              tab.id == currentTab?.id
        else {
            return
        }

        refreshCoordinator.scheduleCoalescedRefresh()
        schedulePermissionsReloadAfterStoreChange()
        if case .bookmark(let state) = navigation.mode,
           state.tabID == tab.id,
           state.pageURL.absoluteString != tab.url.absoluteString {
            navigation.resetToControls()
        }
    }

    private func handleReaderMode() {
        guard let currentTab,
              let webView = browserContext.webView(currentTab, windowState)
        else {
            return
        }

        Task { @MainActor in
            do {
                try await SumiReaderModeService.toggleReaderMode(
                    on: webView,
                    tab: currentTab
                )
            } catch {
                RuntimeDiagnostics.debug(category: "ReaderMode") {
                    "URL bar reader mode toggle failed: \(error.localizedDescription)"
                }
            }
            readerModeIsActive = await SumiReaderModeService.isReaderModeActive(on: webView)
            onClose()
        }
    }
}
