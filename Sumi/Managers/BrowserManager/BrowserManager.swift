//
//  BrowserManager.swift
//  Sumi
//
//

import AppKit
import Combine
import SwiftData
import SwiftUI
import WebKit

@MainActor
protocol BrowserAppLifecycleHandling: AnyObject {
    func handleApplicationWillResignActive()
    func handleApplicationDidBecomeActive()
}

@MainActor
class BrowserManager: ObservableObject {
    static let lastWindowSessionKey = "sumi.windowSession.last.v3"
    @Published var zoomStateRevision: Int = 0
    @Published var zoomPopoverRequest: ZoomPopoverRequest?
    @Published var bookmarkEditorPresentationRequest: SumiBookmarkEditorPresentationRequest?
    @Published var currentProfile: Profile?
    // Indicates an in-progress animated profile transition for coordinating UI
    @Published var isTransitioningProfile: Bool = false

    @Published var workspaceThemePickerSession: WorkspaceThemePickerSession?
    @Published var nativeModalPresentation: BrowserNativeModalPresentation?
    @Published var tabStructuralRevision: UInt = 0

    var modelContext: ModelContext
    let startupWorkspaceTheme: WorkspaceTheme?
    let moduleRegistry: SumiModuleRegistry
    let adBlockingModule: SumiAdBlockingModule
    let protectionCoordinator: SumiProtectionCoordinator
    let extensionsModule: SumiExtensionsModule
    let userscriptsModule: SumiUserscriptsModule
    let boostsModule: SumiBoostsModule
    var extensionSurfaceStore: BrowserExtensionSurfaceStore {
        extensionsModule.surfaceStore
    }
    var tabManager: TabManager
    var profileManager: ProfileManager
    var downloadManager: DownloadManager
    let downloadsPopoverPresenter: DownloadsPopoverPresenter
    let urlBarHubPopoverPresenter: URLBarHubPopoverPresenter
    let workspaceThemePickerPopoverPresenter: WorkspaceThemePickerPopoverPresenter
    var authenticationManager: AuthenticationManager
    var historyManager: HistoryManager
    var bookmarkManager: SumiBookmarkManager
    var recentlyClosedManager: RecentlyClosedManager
    var lastSessionWindowsStore: LastSessionWindowsStore {
        didSet {
            startupSessionRestoreOwner.reload(from: lastSessionWindowsStore)
        }
    }
    var compositorManager: TabCompositorManager
    let tabSuspensionService: TabSuspensionService
    let backgroundMediaOptimizationService = SumiBackgroundMediaOptimizationService()
    let nativeNowPlayingController: any SumiNativeNowPlayingRuntimeControlling
    var splitManager: SplitViewManager
    var workspaceThemeCoordinator: WorkspaceThemeCoordinator
    var findManager: FindManager
    let dataServices: BrowserManagerDataServices
    let browsingDataCleanupService: SumiBrowsingDataCleanupService
    let permissionRuntime: BrowserManagerPermissionRuntime
    /// App-shell owned factory for AppKit-created browser windows.
    typealias WindowShellContentViewFactory = @MainActor (
        BrowserManager,
        WindowRegistry,
        WebViewCoordinator,
        BrowserWindowState?
    ) -> NSView
    var windowShellContentViewFactory: WindowShellContentViewFactory?
    var zoomManager = ZoomManager()
    weak var sumiSettings: SumiSettingsService? {
        didSet {
            downloadManager.settings = sumiSettings
            tabSuspensionService.rebuildProactiveTimers(reason: "settings-attached")
            backgroundMediaOptimizationService.scheduleReconcile(reason: "settings-attached")
            reconcileStartupSessionIfPossible()
            scheduleAutomaticBrowsingDataCleanup(reason: "settings-attached")
        }
    }
    weak var keyboardShortcutManager: KeyboardShortcutManager?
    let sumiProfileRouter = SumiProfileRouter()
    let profileMaintenanceService = SumiProfileMaintenanceService()
    let windowShellService = BrowserWindowShellService()
    let workspaceAppearanceService = WorkspaceAppearanceService()
    let liveFolderManager = SumiLiveFolderManager()
    private let permissionSiteSettingsRoutingOwner = BrowserPermissionSiteSettingsRoutingOwner()
    private let tabSelectionOwner = BrowserTabSelectionOwner()
    lazy var sidebarEditorPresentationOwner = BrowserSidebarEditorPresentationOwner(
        dependencies: .live(browserManager: self)
    )
    lazy var sidebarShortcutPromotionOwner = BrowserSidebarShortcutPromotionOwner(
        dependencies: .live(browserManager: self)
    )
    lazy var sidebarTabCommandOwner = BrowserSidebarTabCommandOwner(
        dependencies: .live(browserManager: self)
    )
    lazy var sidebarSplitShortcutRoutingOwner = BrowserSidebarSplitShortcutRoutingOwner(
        dependencies: .live(browserManager: self)
    )
    lazy var sidebarSpaceTransitionRoutingOwner = BrowserSidebarSpaceTransitionRoutingOwner(
        dependencies: .live(browserManager: self)
    )
    lazy var sidebarCommandRoutingOwner = BrowserSidebarCommandRoutingOwner(
        dependencies: .live(browserManager: self)
    )

    lazy var shellSelectionService = ShellSelectionService { [weak self] windowId in
        guard let self else { return [] }
        return self.splitManager.visibleTabIds(for: windowId)
    }
    private lazy var windowSpaceStateOwner = BrowserWindowSpaceStateOwner(
        dependencies: .live(browserManager: self)
    )
    lazy var tabCloseFallbackPlanner = BrowserTabCloseFallbackPlanner(
        selectionService: shellSelectionService
    )
    lazy var shortcutLiveTabCloseOwner = BrowserShortcutLiveTabCloseOwner(
        dependencies: .live(browserManager: self)
    )
    private lazy var tabCloseOrchestrationOwner = BrowserTabCloseOrchestrationOwner(
        dependencies: .live(browserManager: self)
    )
    lazy var tabOpeningOwner = BrowserTabOpeningOwner(
        dependencies: .live(browserManager: self)
    )
    lazy var nativeSurfaceRoutingOwner = BrowserNativeSurfaceRoutingOwner(
        dependencies: .live(browserManager: self)
    )
    lazy var historyNavigationOwner = BrowserHistoryNavigationOwner(
        dependencies: .live(browserManager: self)
    )
    lazy var nativeDialogPresentationOwner = BrowserNativeDialogPresentationOwner(
        dependencies: .live(browserManager: self)
    )
    private lazy var floatingBarRoutingOwner = BrowserFloatingBarRoutingOwner(
        dependencies: .live(browserManager: self)
    )
    lazy var floatingBarBrowserContextOwner = BrowserFloatingBarBrowserContextOwner(
        dependencies: .live(browserManager: self)
    )
    private lazy var browserActionOwner = BrowserActionOwner(
        dependencies: .live(browserManager: self)
    )
    lazy var webViewRoutingService = BrowserWebViewRoutingService(
        tabLookup: { [weak self] tabId in
            self?.tabManager.tab(for: tabId)
        },
        coordinatorLookup: { [weak self] in
            self?.webViewCoordinator
        }
    )
    lazy var windowSessionService = WindowSessionService(
        lastWindowSessionKey: Self.lastWindowSessionKey
    )
    let startupSessionRestoreOwner: BrowserStartupSessionRestoreOwner

    var auxiliaryWindowManager = AuxiliaryWindowManager()
    private lazy var profileSwitchTransitionOwner = BrowserProfileSwitchTransitionOwner(
        host: self,
        dependencies: .live(browserManager: self)
    )
    let glanceManager = GlanceManager()

    /// Shared with app shell / `ContentView` via `.environment`; retained strongly so routing never sees a dangling coordinator.
    /// After `SumiApp.setupApplicationLifecycle` runs, this must be set before any WebView routing or coordinator cleanup.
    var webViewCoordinator: WebViewCoordinator? {
        didSet {
            if oldValue?.browserManager === self {
                oldValue?.browserManager = nil
            }
            webViewCoordinator?.browserManager = self
            browsingDataCleanupService.destructiveCleanupPreparer = webViewCoordinator
        }
    }

    /// Use for cleanup and cross-window operations; fails fast if the coordinator was not wired (e.g. tests forgot to assign `webViewCoordinator`).
    func requireWebViewCoordinator() -> WebViewCoordinator {
        guard let webViewCoordinator else {
            preconditionFailure(
                "BrowserManager.webViewCoordinator is nil. Assign it from SumiApp.setupApplicationLifecycle (or in unit tests) before WebView operations."
            )
        }
        return webViewCoordinator
    }

    weak var windowRegistry: WindowRegistry? {
        didSet {
            // Update GlanceManager's windowRegistry reference when this changes
            glanceManager.windowRegistry = windowRegistry
            splitManager.windowRegistry = windowRegistry
            Task { @MainActor [weak self] in
                await self?.reconcilePermissionSidebarPins(reason: "window-registry-updated")
            }
            backgroundMediaOptimizationService.scheduleReconcile(reason: "window-registry-updated")
            reconcileStartupSessionIfPossible()
        }
    }

    private let sidebarPresentationStateOwner = BrowserSidebarPresentationStateOwner()
    var isSwitchingProfile: Bool = false
    private var structuralChangeCancellable: AnyCancellable?
    private var tabManagerLoadObserverToken: NSObjectProtocol?
    private var browsingDataRetentionObserverToken: NSObjectProtocol?
    private var startupProtectionRuntime: BrowserStartupProtectionRuntime!
    private let windowTabActivationBatcher = WindowTabActivationBatcher()
    private lazy var windowVisualMutationOwner = BrowserWindowVisualMutationOwner(
        dependencies: .live(browserManager: self)
    )
    lazy var windowHistorySessionOwner = BrowserWindowHistorySessionOwner(
        dependencies: .live(browserManager: self)
    )
    private lazy var windowSessionActivationOwner = BrowserWindowSessionActivationOwner(
        dependencies: .live(browserManager: self)
    )

    private func adoptProfileIfNeeded(
        for windowState: BrowserWindowState, context: ProfileSwitchContext
    ) {
        sumiProfileRouter.adoptProfileIfNeeded(
            for: windowState,
            context: context,
            support: self
        )
    }

    func adoptProfileForSpaceChange(_ windowState: BrowserWindowState) {
        adoptProfileIfNeeded(for: windowState, context: .spaceChange)
    }

    func adoptProfileForWindowActivation(_ windowState: BrowserWindowState) {
        adoptProfileIfNeeded(for: windowState, context: .windowActivation)
    }

    init(
        moduleRegistry: SumiModuleRegistry = .shared,
        startupPersistence: BrowserManagerStartupPersistence = .production,
        browserConfiguration: BrowserConfiguration = .shared,
        // Explicit injection seams keep module-boundary tests focused without constructing optional runtimes at startup.
        adBlockingModule: SumiAdBlockingModule? = nil,
        protectionCoordinator: SumiProtectionCoordinator? = nil,
        extensionsModule: SumiExtensionsModule? = nil,
        userscriptsModule: SumiUserscriptsModule? = nil,
        boostsModule: SumiBoostsModule? = nil,
        browsingDataCleanupService: SumiBrowsingDataCleanupService? = nil,
        dataServices: BrowserManagerDataServices = .production,
        nowPlayingController: any SumiNativeNowPlayingRuntimeControlling =
            SumiNativeNowPlayingController(),
        systemPermissionService: (any SumiSystemPermissionService)? = nil,
        permissionCoordinator: (any SumiPermissionCoordinating)? = nil,
        geolocationProvider: (any SumiGeolocationProviding)? = nil,
        notificationService: (any SumiNotificationServicing)? = nil,
        runtimePermissionController: (any SumiRuntimePermissionControlling)? = nil,
        filePickerPanelPresenter: (any SumiFilePickerPanelPresenting)? = nil,
        permissionIndicatorEventStore: SumiPermissionIndicatorEventStore? = nil,
        permissionRecentActivityStore: SumiPermissionRecentActivityStore? = nil,
        permissionSiteActivityStore: SumiPermissionSiteActivityStore = .shared,
        permissionCleanupService: SumiPermissionCleanupService? = nil,
        blockedPopupStore: SumiBlockedPopupStore? = nil,
        externalAppResolver: any SumiExternalAppResolving = SumiNSWorkspaceExternalAppResolver.shared,
        externalSchemeSessionStore: SumiExternalSchemeSessionStore? = nil,
        permissionBridgeOverrides: BrowserPermissionBridgeRegistry.Overrides = BrowserPermissionBridgeRegistry.Overrides()
    ) {
        let startupTrace = StartupPerformanceTrace.browserManagerInitStarted()
        defer {
            StartupPerformanceTrace.browserManagerInitFinished(startupTrace)
        }
        let resolvedDataServices = browsingDataCleanupService.map {
            dataServices.replacing(browsingDataCleanupService: $0)
        } ?? dataServices

        // Phase 1: initialize all stored properties
        let startupModelContext = startupPersistence.mainContext
        self.modelContext = startupModelContext
        self.moduleRegistry = moduleRegistry
        let resolvedAdBlockingModule = adBlockingModule
            ?? SumiAdBlockingModule(moduleRegistry: moduleRegistry)
        self.adBlockingModule = resolvedAdBlockingModule
        self.protectionCoordinator = protectionCoordinator
            ?? SumiProtectionCoordinator(
                settings: SumiProtectionSettings(userDefaults: moduleRegistry.userDefaults),
                adBlockingModule: resolvedAdBlockingModule
            )
        self.userscriptsModule = userscriptsModule
            ?? SumiUserscriptsModule(
                moduleRegistry: moduleRegistry,
                context: startupModelContext
            )
        self.boostsModule = boostsModule ?? SumiBoostsModule()
        self.startupWorkspaceTheme = StartupWorkspaceThemeResolver.resolve(
            lastWindowSessionKey: Self.lastWindowSessionKey,
            modelContext: startupModelContext
        )
        self.profileManager = ProfileManager(
            context: startupModelContext,
            faviconService: resolvedDataServices.faviconService,
            visitedLinkStore: resolvedDataServices.visitedLinkStore
        )
        // Ensure at least one profile exists and set current immediately for manager initialization
        self.profileManager.ensureDefaultProfile()
        let initialProfile = self.profileManager.profiles.first
        self.currentProfile = initialProfile
        self.extensionsModule = extensionsModule
            ?? SumiExtensionsModule(
                moduleRegistry: moduleRegistry,
                context: startupModelContext,
                initialProfileProvider: { initialProfile }
            )

        self.tabManager = TabManager(
            browserManager: nil,
            context: startupModelContext,
            faviconService: resolvedDataServices.faviconService,
            faviconImageService: resolvedDataServices.faviconImageService,
            visitedLinkStore: resolvedDataServices.visitedLinkStore
        )
        // settingsManager will be injected from SumiApp
        self.downloadManager = DownloadManager()
        self.downloadsPopoverPresenter = DownloadsPopoverPresenter()
        self.urlBarHubPopoverPresenter = URLBarHubPopoverPresenter()
        self.workspaceThemePickerPopoverPresenter = WorkspaceThemePickerPopoverPresenter()
        self.authenticationManager = AuthenticationManager()
        // Initialize managers with current profile context for isolation
        self.historyManager = HistoryManager(
            context: startupModelContext,
            profileId: initialProfile?.id,
            dependencies: resolvedDataServices.historyManagerDependencies
        )
        self.bookmarkManager = SumiBookmarkManager(
            faviconService: resolvedDataServices.faviconService
        )
        if let initialProfile {
            self.bookmarkManager.setFaviconPrefetchPartition(
                resolvedDataServices.faviconService.partition(profile: initialProfile)
            )
        }
        self.recentlyClosedManager = RecentlyClosedManager()
        self.lastSessionWindowsStore = LastSessionWindowsStore()
        self.startupSessionRestoreOwner = BrowserStartupSessionRestoreOwner(
            lastSessionWindowsStore: self.lastSessionWindowsStore
        )
        self.compositorManager = TabCompositorManager()
        self.tabSuspensionService = TabSuspensionService(
            memoryMonitor: SumiMemoryPressureMonitor()
        )
        self.splitManager = SplitViewManager()
        self.workspaceThemeCoordinator = WorkspaceThemeCoordinator()
        self.findManager = FindManager()
        self.dataServices = resolvedDataServices
        self.browsingDataCleanupService = resolvedDataServices.browsingDataCleanupService
        self.nativeNowPlayingController = nowPlayingController
        self.permissionRuntime = BrowserManagerPermissionRuntime(
            dependencies: .live(
                startupPersistence: startupPersistence,
                browserConfiguration: browserConfiguration,
                systemPermissionService: systemPermissionService,
                permissionCoordinator: permissionCoordinator,
                geolocationProvider: geolocationProvider,
                notificationService: notificationService,
                runtimePermissionController: runtimePermissionController,
                filePickerPanelPresenter: filePickerPanelPresenter,
                permissionIndicatorEventStore: permissionIndicatorEventStore,
                permissionRecentActivityStore: permissionRecentActivityStore,
                permissionSiteActivityStore: permissionSiteActivityStore,
                permissionCleanupService: permissionCleanupService,
                blockedPopupStore: blockedPopupStore,
                externalAppResolver: externalAppResolver,
                externalSchemeSessionStore: externalSchemeSessionStore,
                permissionBridgeOverrides: permissionBridgeOverrides
            )
        )
        self.permissionRuntime.startPermissionEventObservation { [weak self] _ in
            await self?.reconcilePermissionSidebarPins(reason: "permission-event")
        }
        self.startupProtectionRuntime = BrowserStartupProtectionRuntime(
            dependencies: .live(browserManager: self)
        )

        // Phase 2: wire dependencies and perform side effects (safe to use self)
        structuralChangeCancellable = BrowserManagerRuntimeWiring.attach(to: self)

        tabManagerLoadObserverToken = NotificationCenter.default.addObserver(
            forName: .tabManagerDidLoadInitialData,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTabManagerDataLoaded()
            }
        }

        browsingDataRetentionObserverToken = NotificationCenter.default.addObserver(
            forName: .sumiBrowsingDataRetentionChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleAutomaticBrowsingDataCleanup(
                    reason: "retention-setting-changed",
                    force: true,
                    delayNanoseconds: 0
                )
            }
        }

        beginProtectionRestoreForStartupIfNeeded()
    }

    /// Called when TabManager finishes loading initial data from persistence
    private func handleTabManagerDataLoaded() {
        windowSessionService.handleTabManagerDataLoaded(delegate: self)
        liveFolderManager.startAfterTabRestore()
        reconcileStartupSessionIfPossible()
    }

    private func beginProtectionRestoreForStartupIfNeeded() {
        startupProtectionRuntime.beginProtectionRestoreForStartupIfNeeded()
    }

    #if DEBUG
        func drainProtectionRuntimeTasksForTests(cancel: Bool = false) async {
            await startupProtectionRuntime.drainProtectionRestoreTaskForTests(cancel: cancel)
            await adBlockingModule.drainRuleListTasksForTests(cancel: cancel)
            await extensionsModule.drainSafariContentBlockerRuntimeForTests(cancel: cancel)
        }

        func drainBrowserRuntimeTasksForTests(cancel: Bool = false) async {
            await drainProtectionRuntimeTasksForTests(cancel: cancel)
            await dataServices.faviconService.drainRuntimeTasksForTests(cancel: cancel)
        }
    #endif

    var hasFinishedStartupProtectionRestore: Bool {
        startupProtectionRuntime.hasFinishedProtectionRestore
    }

    var shouldDeferNormalTabMaterializationDuringStartup: Bool {
        startupProtectionRuntime.shouldDeferNormalTabMaterializationDuringStartup
    }

    func canMaterializeNormalTabWebViewDuringStartup(_ tab: Tab) -> Bool {
        startupProtectionRuntime.canMaterializeNormalTabWebViewDuringStartup(tab)
    }

    func deferBackgroundTabUntilStartupReady(_ tab: Tab) {
        startupProtectionRuntime.deferBackgroundTabUntilStartupReady(tab)
    }

    func prepareBackgroundTabAfterStartupProtectionRestore(_ tab: Tab) {
        browserActionOwner.prepareBackgroundTabIfNeeded(tab, in: nil)
    }

    enum ProfileSwitchContext {
        case userInitiated
        case spaceChange
        case windowActivation
        case recovery
    }

    func switchToProfile(
        _ profile: Profile, context: ProfileSwitchContext = .userInitiated,
        in windowState: BrowserWindowState? = nil
    ) async {
        await profileSwitchTransitionOwner.switchToProfile(
            profile,
            context: context,
            in: windowState
        )
    }

    func updateSidebarWidth(
        _ width: CGFloat,
        for windowState: BrowserWindowState,
        persist: Bool = true
    ) {
        sidebarPresentationStateOwner.updateSidebarWidth(width, for: windowState)
        if persist {
            schedulePersistWindowSession(for: windowState)
        }
    }

    func updateSavedSidebarVisibility(_ isVisible: Bool) {
        sidebarPresentationStateOwner.updateSavedSidebarVisibility(isVisible)
    }

    func toggleSavedSidebarVisibility() {
        sidebarPresentationStateOwner.toggleSavedSidebarVisibility()
    }

    func updateSavedSidebarWidth(_ width: CGFloat) {
        sidebarPresentationStateOwner.updateSavedSidebarWidth(width)
    }

    func toggleSidebar() {
        browserActionOwner.toggleSidebar()
    }

    func toggleSidebar(for windowState: BrowserWindowState) {
        browserActionOwner.toggleSidebar(for: windowState)
    }

    // MARK: - Sidebar width access for overlays
    /// Returns the last saved sidebar width (used when sidebar is collapsed to size hover overlay)
    func getSavedSidebarWidth(for windowState: BrowserWindowState? = nil) -> CGFloat {
        sidebarPresentationStateOwner.savedSidebarWidth(
            for: windowState,
            activeWindow: windowRegistry?.activeWindow
        )
    }

    private var tabSelectionActions: BrowserTabSelectionOwner.Actions {
        BrowserTabSelectionOwner.liveActions(for: self)
    }

    func focusFloatingBarForActiveWindow(
        prefill: String = "",
        navigateCurrentTab: Bool = false,
        presentationReason: FloatingBarPresentationReason = .keyboard
    ) {
        floatingBarRoutingOwner.focusFloatingBarForActiveWindow(
            prefill: prefill,
            navigateCurrentTab: navigateCurrentTab,
            presentationReason: presentationReason
        )
    }

    func focusFloatingBar(
        in windowState: BrowserWindowState,
        prefill: String = "",
        navigateCurrentTab: Bool = false,
        presentationReason: FloatingBarPresentationReason = .keyboard
    ) {
        floatingBarRoutingOwner.focusFloatingBar(
            in: windowState,
            prefill: prefill,
            navigateCurrentTab: navigateCurrentTab,
            presentationReason: presentationReason
        )
    }

    func focusFloatingBar(
        in windowState: BrowserWindowState,
        prefill: String,
        navigateCurrentTab: Bool
    ) {
        focusFloatingBar(
            in: windowState,
            prefill: prefill,
            navigateCurrentTab: navigateCurrentTab,
            presentationReason: .keyboard
        )
    }

    func showNewTabFloatingBar(in windowState: BrowserWindowState) {
        floatingBarRoutingOwner.showNewTabFloatingBar(in: windowState)
    }

    func openNewTabOrFloatingBar(in windowState: BrowserWindowState) {
        floatingBarRoutingOwner.openNewTabOrFloatingBar(in: windowState)
    }

    func spaceForSidebarActions(in windowState: BrowserWindowState) -> Space? {
        browserActionOwner.spaceForSidebarActions(in: windowState)
    }

    func createFolderInCurrentSpace(in windowState: BrowserWindowState) {
        browserActionOwner.createFolderInCurrentSpace(in: windowState)
    }

    func createRSSLiveFolderInCurrentSpace(in windowState: BrowserWindowState) {
        browserActionOwner.createRSSLiveFolderInCurrentSpace(in: windowState)
    }

    func createGitHubPullRequestsLiveFolderInCurrentSpace(in windowState: BrowserWindowState) {
        browserActionOwner.createGitHubPullRequestsLiveFolderInCurrentSpace(in: windowState)
    }

    func createGitHubIssuesLiveFolderInCurrentSpace(in windowState: BrowserWindowState) {
        browserActionOwner.createGitHubIssuesLiveFolderInCurrentSpace(in: windowState)
    }

    func updateFloatingBarDraft(
        in windowState: BrowserWindowState,
        text: String
    ) {
        floatingBarRoutingOwner.updateFloatingBarDraft(
            in: windowState,
            text: text
        )
    }

    func dismissFloatingBar(
        in windowState: BrowserWindowState,
        preserveDraft: Bool,
        cancelEmptySplitPlaceholder: Bool = true
    ) {
        floatingBarRoutingOwner.dismissFloatingBar(
            in: windowState,
            preserveDraft: preserveDraft,
            cancelEmptySplitPlaceholder: cancelEmptySplitPlaceholder
        )
    }

    func dismissFloatingBarForActiveWindow(preserveDraft: Bool = true) {
        floatingBarRoutingOwner.dismissFloatingBarForActiveWindow(preserveDraft: preserveDraft)
    }

    @discardableResult
    func dismissFloatingBarIfVisible(
        in windowId: UUID,
        preserveDraft: Bool = true
    ) -> Bool {
        floatingBarRoutingOwner.dismissFloatingBarIfVisible(
            in: windowId,
            preserveDraft: preserveDraft
        )
    }

    func floatingBarCommitNavigatesCurrentTab(in windowState: BrowserWindowState) -> Bool {
        floatingBarRoutingOwner.floatingBarCommitNavigatesCurrentTab(in: windowState)
    }

    func commitFloatingBarSuggestion(
        _ suggestion: SearchManager.SearchSuggestion,
        in windowState: BrowserWindowState,
        navigatesCurrentTab: Bool
    ) {
        floatingBarRoutingOwner.commitFloatingBarSuggestion(
            suggestion,
            in: windowState,
            navigatesCurrentTab: navigatesCurrentTab
        )
    }

    func commitFloatingBarNavigation(
        to urlString: String,
        in windowState: BrowserWindowState,
        navigatesCurrentTab: Bool
    ) {
        floatingBarRoutingOwner.commitFloatingBarNavigation(
            to: urlString,
            in: windowState,
            navigatesCurrentTab: navigatesCurrentTab
        )
    }

    func openFloatingBarSuggestion(
        _ suggestion: SearchManager.SearchSuggestion,
        in windowState: BrowserWindowState
    ) {
        openFloatingBarSuggestion(
            suggestion,
            in: windowState,
            navigatesCurrentTab: windowState.floatingBarDraftNavigatesCurrentTab
        )
    }

    func openFloatingBarSuggestion(
        _ suggestion: SearchManager.SearchSuggestion,
        in windowState: BrowserWindowState,
        navigatesCurrentTab: Bool
    ) {
        floatingBarRoutingOwner.openFloatingBarSuggestion(
            suggestion,
            in: windowState,
            navigatesCurrentTab: navigatesCurrentTab
        )
    }

    func dismissFloatingBarAfterSelection(in windowState: BrowserWindowState) {
        floatingBarRoutingOwner.dismissFloatingBarAfterSelection(in: windowState)
    }

    func sanitizeFloatingBarState(in windowState: BrowserWindowState) {
        floatingBarRoutingOwner.sanitizeFloatingBarState(in: windowState)
    }

    func showFindBar() {
        findManager.showFindBar(for: activePageTabForActiveWindow())
    }

    func updateFindManagerCurrentTab() {
        // Update the current tab for find manager
        findManager.updateCurrentTab(activePageTabForActiveWindow())
    }

    enum TabSelectionLoadPolicy: Equatable {
        case immediate
        case deferred
    }

    typealias TabOpenActivationPolicy = BrowserTabOpenActivationPolicy
    typealias TabOpenContext = BrowserTabOpenContext

    // MARK: - Tab Management (delegates to TabManager)
    func createNewTab() {
        browserActionOwner.createNewTab()
    }

    /// Create a new tab and set it as active in the specified window
    func createNewTab(in windowState: BrowserWindowState, url: String = SumiSurface.emptyTabURL.absoluteString) {
        browserActionOwner.createNewTab(in: windowState, url: url)
    }

    @discardableResult
    func createNewTabAfterSidebarInsertion(
        in windowState: BrowserWindowState,
        url: String = SumiSurface.emptyTabURL.absoluteString
    ) -> Tab {
        browserActionOwner.createNewTabAfterSidebarInsertion(in: windowState, url: url)
    }

    @discardableResult
    func openNewTab(
        url: String = SumiSurface.emptyTabURL.absoluteString,
        context: TabOpenContext
    ) -> Tab {
        browserActionOwner.openNewTab(url: url, context: context)
    }

    func resolvedTabOpenSpace(for context: TabOpenContext) -> Space? {
        browserActionOwner.resolvedTabOpenSpace(for: context)
    }

    @discardableResult
    func createPopupTab(
        from sourceTab: Tab,
        webViewConfigurationOverride: WKWebViewConfiguration? = nil,
        activate: Bool = true
    ) -> Tab? {
        browserActionOwner.createPopupTab(
            from: sourceTab,
            webViewConfigurationOverride: webViewConfigurationOverride,
            activate: activate
        )
    }

    /// Opens Sumi settings as a normal browser tab (one per space), optionally focusing a pane.
    func openSettingsTab(selecting pane: SettingsTabs, in windowState: BrowserWindowState? = nil) {
        guard let windowState = windowState ?? windowRegistry?.activeWindow else { return }
        openNativeBrowserSurface(
            .settings,
            url: permissionSiteSettingsRoutingOwner.settingsSurfaceURL(for: pane),
            in: windowState
        )
    }

    func openSiteSettingsTab(
        focusing tab: Tab? = nil,
        in windowState: BrowserWindowState? = nil
    ) {
        guard let windowState = windowState ?? windowRegistry?.activeWindow else { return }
        let targetTab = tab ?? currentTab(for: windowState)

        openNativeBrowserSurface(
            .settings,
            url: permissionSiteSettingsRoutingOwner.privacySiteSettingsSurfaceURL(focusing: targetTab),
            in: windowState
        )
    }

    func duplicateCurrentTab() {
        guard let activeWindow = windowRegistry?.activeWindow,
              let currentTab = currentTabForActiveWindow() else {
            return
        }
        duplicateTab(currentTab, in: activeWindow)
    }

    func duplicateTab(_ tab: Tab, in windowState: BrowserWindowState) {
        browserActionOwner.duplicateTab(tab, in: windowState)
    }

    func closeCurrentTab() {
        tabCloseOrchestrationOwner.closeCurrentTab()
    }

    func closeTab(_ tab: Tab, in windowState: BrowserWindowState) {
        tabCloseOrchestrationOwner.closeTab(tab, in: windowState)
    }
    isolated deinit {
        permissionRuntime.cancelPermissionEventObservation()
        startupProtectionRuntime.cancelProtectionRestoreTask()
        windowSessionService.cancelPendingWindowSessionPersistence()
        if let token = tabManagerLoadObserverToken {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = browsingDataRetentionObserverToken {
            NotificationCenter.default.removeObserver(token)
        }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Window State Management

    /// Register a new window state and attach browser services (`WindowSessionService`, extensions).
    /// Window ↔ `NSWindow` association is owned by `BrowserWindowBridge` for SwiftUI scene windows
    /// and by `BrowserWindowShellService` for BrowserManager-created windows.
    func setupWindowState(_ windowState: BrowserWindowState) {
        windowSessionActivationOwner.setupWindowState(windowState)
    }

    /// Set the active window state (called when a window gains focus)
    /// NOTE: This is called BY the WindowRegistry callback, so we don't call setActive again
    func setActiveWindowState(_ windowState: BrowserWindowState) {
        // DO NOT call windowRegistry?.setActive(windowState) here - that would cause infinite recursion!
        // This method is called FROM the onActiveWindowChange callback
        windowSessionActivationOwner.setActiveWindowState(windowState)
    }

    // MARK: - Window-Aware Tab Operations

    /// Get the current tab for a specific window
    func currentTab(for windowState: BrowserWindowState) -> Tab? {
        guard !windowState.isAwaitingInitialSessionResolution else { return nil }
        return shellSelectionService.currentTab(
            for: windowState,
            tabStore: tabManager.runtimeStore
        )
    }

    @MainActor
    private func reconcilePermissionSidebarPins(reason: String) async {
        let state = await permissionCoordinator.stateSnapshot()
        permissionSidebarPinningController.reconcile(
            activeQueries: Array(state.activeQueriesByPageId.values),
            windowForPageId: { [weak self] pageId in
                self?.permissionSiteSettingsRoutingOwner.windowState(
                    displayingPermissionPageId: pageId,
                    in: self?.windowRegistry,
                    tabsForDisplay: { windowState in
                        self?.tabsForDisplay(in: windowState) ?? []
                    }
                )
            },
            reason: reason
        )
    }

    func windowState(containing tab: Tab) -> BrowserWindowState? {
        guard let windowRegistry else { return nil }
        return windowRegistry.windows.values.first { windowState in
            if windowState.isIncognito {
                return windowState.ephemeralTabs.contains(where: { $0.id == tab.id })
            }

            if windowState.currentTabId == tab.id {
                return true
            }

            if tabManager.liveShortcutTabs(in: windowState.id).contains(where: { $0.id == tab.id }) {
                return true
            }

            if splitManager.visibleTabIds(for: windowState.id).contains(tab.id) {
                return true
            }

            return false
        }
    }

    /// Select a tab in the active window (convenience method for sidebar clicks)
    func selectTab(_ tab: Tab) {
        guard let activeWindow = windowRegistry?.activeWindow else {
            RuntimeDiagnostics.emit {
                "⚠️ [BrowserManager] No active window for tab selection"
            }
            return
        }
        selectTab(tab, in: activeWindow)
    }

    /// Select a tab in a specific window
    func selectTab(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        loadPolicy: TabSelectionLoadPolicy = .immediate
    ) {
        tabSelectionOwner.selectTab(
            tab,
            in: windowState,
            loadPolicy: loadPolicy,
            actions: tabSelectionActions
        )
    }

    func requestUserTabActivation(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        loadPolicy: TabSelectionLoadPolicy = .immediate
    ) {
        windowTabActivationBatcher.requestActivation(
            tabId: tab.id,
            in: windowState.id,
            loadPolicy: loadPolicy
        ) { [weak self] windowId, activation in
            guard let self,
                  let windowState = self.windowRegistry?.windows[windowId],
                  let tab = self.resolvedTab(for: activation.tabId, in: windowState)
            else {
                return
            }

            self.applyTabSelection(
                tab,
                in: windowState,
                updateSpaceFromTab: true,
                updateTheme: true,
                rememberSelection: true,
                loadPolicy: activation.loadPolicy
            )
        }
    }

    private func resolvedTab(for tabId: UUID, in windowState: BrowserWindowState) -> Tab? {
        tabManager.tab(for: tabId)
            ?? windowState.ephemeralTabs.first(where: { $0.id == tabId })
    }

    func applyTabSelection(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        updateSpaceFromTab: Bool,
        updateTheme: Bool,
        rememberSelection: Bool,
        persistSelection: Bool = true
    ) {
        applyTabSelection(
            tab,
            in: windowState,
            updateSpaceFromTab: updateSpaceFromTab,
            updateTheme: updateTheme,
            rememberSelection: rememberSelection,
            persistSelection: persistSelection,
            loadPolicy: .immediate
        )
    }

    func applyTabSelection(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        updateSpaceFromTab: Bool,
        updateTheme: Bool,
        rememberSelection: Bool,
        persistSelection: Bool = true,
        loadPolicy: TabSelectionLoadPolicy
    ) {
        tabSelectionOwner.applyTabSelection(
            tab,
            in: windowState,
            updateSpaceFromTab: updateSpaceFromTab,
            updateTheme: updateTheme,
            rememberSelection: rememberSelection,
            persistSelection: persistSelection,
            loadPolicy: loadPolicy,
            actions: tabSelectionActions
        )
    }

    func materializeVisibleTabWebViewIfNeeded(
        _ tab: Tab,
        in windowState: BrowserWindowState
    ) {
        tabSelectionOwner.materializeVisibleTabWebViewIfNeeded(
            tab,
            in: windowState,
            actions: tabSelectionActions
        )
    }

    /// Get tabs that should be displayed in a specific window
    func tabsForDisplay(in windowState: BrowserWindowState) -> [Tab] {
        shellSelectionService.tabsForDisplay(
            in: windowState,
            tabStore: tabManager.runtimeStore
        )
    }

    func isTabDisplayedInAnyWindow(_ tabId: UUID) -> Bool {
        guard let windowRegistry else { return false }
        for windowState in windowRegistry.windows.values {
            if tabsForDisplay(in: windowState).contains(where: { $0.id == tabId }) {
                return true
            }
        }
        return false
    }

    func windowScopedMediaCandidateTabs(in windowState: BrowserWindowState) -> [Tab] {
        shellSelectionService.windowScopedMediaCandidateTabs(
            in: windowState,
            tabStore: tabManager.runtimeStore
        )
    }

    /// Refresh compositor for a specific window
    func refreshCompositor(for windowState: BrowserWindowState) {
        windowVisualMutationOwner.refreshCompositor(for: windowState)
    }

    @discardableResult
    func performImmediateVisualHandoffIfPossible(in windowState: BrowserWindowState) -> Bool {
        windowVisualMutationOwner.performImmediateVisualHandoffIfPossible(in: windowState)
    }

    @discardableResult
    func prepareVisibleWebViews(for windowState: BrowserWindowState) -> Bool {
        windowVisualMutationOwner.prepareVisibleWebViews(for: windowState)
    }

    func schedulePrepareVisibleWebViews(for windowState: BrowserWindowState) {
        windowVisualMutationOwner.schedulePrepareVisibleWebViews(for: windowState)
    }

    func space(for spaceId: UUID?) -> Space? {
        windowSpaceStateOwner.space(for: spaceId)
    }

    func syncWindowSpaceContext(
        in windowState: BrowserWindowState,
        animateTheme: Bool
    ) {
        windowSpaceStateOwner.syncWindowSpaceContext(
            in: windowState,
            animateTheme: animateTheme
        )
    }

    func selectionTargetForSpaceActivation(
        in space: Space,
        windowState: BrowserWindowState
    ) -> Tab? {
        windowSpaceStateOwner.selectionTargetForSpaceActivation(
            in: space,
            windowState: windowState
        )
    }

    func updateProfileRuntimeStates(activeWindowState: BrowserWindowState?) {
        windowSpaceStateOwner.updateProfileRuntimeStates(activeWindowState: activeWindowState)
    }

    func enqueueWindowMutationDuringHistorySwipe(
        _ kind: HistorySwipeDeferredWindowMutationKind,
        for windowState: BrowserWindowState
    ) {
        windowVisualMutationOwner.enqueueWindowMutationDuringHistorySwipe(kind, for: windowState)
    }

    func flushWindowMutationsAfterHistorySwipe(in windowId: UUID) {
        windowVisualMutationOwner.flushWindowMutationsAfterHistorySwipe(in: windowId)
    }

    func cancelWindowMutationsAfterHistorySwipe(in windowId: UUID) {
        windowVisualMutationOwner.cancelWindowMutationsAfterHistorySwipe(in: windowId)
    }

    func hasValidCurrentSelection(in windowState: BrowserWindowState) -> Bool {
        windowSpaceStateOwner.hasValidCurrentSelection(in: windowState)
    }

    /// Set active space for a specific window
    func setActiveSpace(
        _ space: Space,
        in windowState: BrowserWindowState,
        completingTransition identity: SpaceTransitionIdentity? = nil
    ) {
        windowSpaceStateOwner.setActiveSpace(
            space,
            in: windowState,
            completingTransition: identity
        )
    }

    /// Validate and fix window states after tab/space mutations
    func validateWindowStates() {
        windowSpaceStateOwner.validateWindowStates()
    }

    func persistWindowSession(for windowState: BrowserWindowState) {
        windowSessionActivationOwner.persistWindowSession(for: windowState)
    }

    func schedulePersistWindowSession(
        for windowState: BrowserWindowState,
        delayNanoseconds: UInt64 = 450_000_000
    ) {
        windowSessionActivationOwner.schedulePersistWindowSession(
            for: windowState,
            delayNanoseconds: delayNanoseconds
        )
    }

    func flushPendingWindowSessionPersistence() {
        windowSessionActivationOwner.flushPendingWindowSessionPersistence()
    }

    func syncShortcutSelectionState(for windowState: BrowserWindowState) {
        tabSelectionOwner.syncShortcutSelectionState(
            for: windowState,
            actions: tabSelectionActions
        )
    }

    func showEmptyState(in windowState: BrowserWindowState) {
        tabSelectionOwner.showEmptyState(
            in: windowState,
            actions: tabSelectionActions
        )
    }
}

extension BrowserManager: WindowSessionServiceDelegate {
    func syncBrowserManagerSidebarCachesFromWindow(_ windowState: BrowserWindowState) {
        sidebarPresentationStateOwner.syncFromWindow(windowState)
    }
}

extension BrowserManager: SumiProfileRoutingSupport {}

extension BrowserManager: BrowserAppLifecycleHandling {
    func handleApplicationWillResignActive() {
        windowSessionActivationOwner.handleApplicationWillResignActive()
    }

    func handleApplicationDidBecomeActive() {
        windowSessionActivationOwner.handleApplicationDidBecomeActive()
    }

    func handleWindowVisibilityChanged(_ windowState: BrowserWindowState) {
        windowSessionActivationOwner.handleWindowVisibilityChanged(windowState)
    }
}

// MARK: - WebView routing (delegates to BrowserWebViewRoutingService / WebViewCoordinator)

extension BrowserManager {
    func getWebView(for tabId: UUID, in windowId: UUID) -> WKWebView? {
        webViewRoutingService.webView(for: tabId, in: windowId)
    }

    func syncTabAcrossWindows(_ tabId: UUID, originatingWebView: WKWebView? = nil) {
        webViewRoutingService.syncTabAcrossWindows(
            tabId,
            originatingWebView: originatingWebView
        )
    }

    func reloadTabAcrossWindows(_ tabId: UUID) {
        webViewRoutingService.reloadTabAcrossWindows(tabId)
    }

    func setMuteState(_ muted: Bool, for tabId: UUID) {
        webViewRoutingService.setMuteState(muted, for: tabId)
    }
}

extension BrowserManager: BrowserCommandRouting, WindowCommandRouting, BrowserWindowLifecycleHandling,
    ExternalURLHandling, BrowserPersistenceHandling, WebViewLookup {
    func flushRuntimeStatePersistenceAwaitingResult() async -> Int {
        await tabManager.flushRuntimeStatePersistenceAwaitingResult()
    }

    func persistFullReconcileAwaitingResult(reason: String) async -> Bool {
        await tabManager.persistFullReconcileAwaitingResult(reason: reason)
    }

    func webView(for tabId: UUID, in windowId: UUID) -> WKWebView? {
        getWebView(for: tabId, in: windowId)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
