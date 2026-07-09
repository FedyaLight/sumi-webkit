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
class BrowserManager: ObservableObject {
    static let lastWindowSessionKey = "sumi.windowSession.last.v3"
    @Published var zoomStateRevision: Int = 0
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
    let adblockZapperStore: SumiAdblockZapperStore
    let extensionsModule: SumiExtensionsModule
    let userscriptsModule: SumiUserscriptsModule
    let boostsModule: SumiBoostsModule
    /// Process-level sidebar hit-testing recovery after transient AppKit UI.
    let sidebarHostRecoveryCoordinator: SidebarHostRecoveryHandling
    var extensionSurfaceStore: BrowserExtensionSurfaceStore {
        extensionsModule.surfaceStore
    }
    var tabManager: TabManager
    var profileManager: ProfileManager
    var downloadManager: DownloadManager
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
    let browserConfiguration: BrowserConfiguration
    let dataServices: BrowserManagerDataServices
    let browsingDataCleanupService: SumiBrowsingDataCleanupService
    let permissionRuntime: BrowserManagerPermissionRuntime
    var zoomManager = ZoomManager()
    weak var sumiSettings: SumiSettingsService? {
        didSet {
            downloadManager.settings = sumiSettings
            tabSuspensionService.rebuildProactiveTimers(reason: "settings-attached")
            backgroundMediaOptimizationService.scheduleReconcile(reason: "settings-attached")
            reconcileStartupSessionIfPossible()
            automaticDataCleanupOwner.scheduleAutomaticBrowsingDataCleanup(reason: "settings-attached")
        }
    }
    weak var keyboardShortcutManager: KeyboardShortcutManager?
    let sumiProfileRouter = SumiProfileRouter()
    let liveFolderManager = SumiLiveFolderManager()
    let permissionSiteSettingsRoutingOwner = BrowserPermissionSiteSettingsRoutingOwner()
    lazy var sidebarCommandService = BrowserSidebarCommandService(browserManager: self)

    lazy var shellSelectionService = ShellSelectionService { [weak self] windowId in
        guard let self else { return [] }
        return self.splitManager.visibleTabIds(for: windowId)
    }
    lazy var tabLifecycleService = BrowserTabLifecycleService(browserManager: self)
    // Phase 5A / N2 / T3 / T8 capability bags — BM holds bags; bags hold owners.
    lazy var privacyBundle = BrowserPrivacyBundle(browserManager: self)
    lazy var urlBarBundle = BrowserURLBarBundle(browserManager: self)
    lazy var windowSessionBundle = BrowserWindowSessionBundle(
        browserManager: self,
        startupSessionRestoreOwner: startupSessionRestoreOwner
    )
    lazy var chromeBundle = BrowserChromeBundle(browserManager: self)
    lazy var historyBundle = BrowserHistoryBundle(browserManager: self)
    lazy var bookmarkBundle = BrowserBookmarkBundle(browserManager: self)
    lazy var profileLifecycleBundle = BrowserProfileLifecycleBundle(browserManager: self)
    lazy var extensionBridgeBundle = BrowserExtensionBridgeBundle(browserManager: self)

    /// Compatibility forwards — prefer `*Bundle` for new call sites.
    var urlBarCommands: BrowserURLBarCommands { urlBarBundle.commands }
    var chromeCommands: BrowserChromeCommands { chromeBundle.commands }
    var windowSpaceStateOwner: BrowserWindowSpaceStateOwner {
        windowSessionBundle.spaceStateOwner
    }
    var windowTabContextOwner: BrowserWindowTabContextOwner {
        windowSessionBundle.tabContextOwner
    }
    var windowVisualMutationOwner: BrowserWindowVisualMutationOwner {
        windowSessionBundle.visualMutationOwner
    }
    var windowScopedNavigationOwner: BrowserWindowScopedNavigationOwner {
        windowSessionBundle.scopedNavigationOwner
    }
    var sidebarActionOwner: BrowserSidebarActionOwner {
        chromeBundle.sidebarActionOwner
    }
    var sidebarPresentationOwner: BrowserSidebarPresentationOwner {
        chromeBundle.sidebarPresentationOwner
    }
    var workspaceThemeTransitionOwner: BrowserWorkspaceThemeTransitionOwner {
        chromeBundle.workspaceThemeTransitionOwner
    }
    var workspaceThemeEditorOwner: BrowserWorkspaceThemeEditorOwner {
        chromeBundle.workspaceThemeEditorOwner
    }
    var nativeSurfaceRoutingOwner: BrowserNativeSurfaceRoutingOwner {
        chromeBundle.nativeSurfaceRoutingOwner
    }
    var zoomCommandOwner: BrowserZoomCommandOwner {
        chromeBundle.zoomCommandOwner
    }
    var sharingPickerPresentationOwner: BrowserSharingPickerPresentationOwner {
        chromeBundle.sharingPickerPresentationOwner
    }
    var nativeDialogPresentationOwner: BrowserNativeDialogPresentationOwner {
        chromeBundle.nativeDialogPresentationOwner
    }
    var windowStateValidationOwner: BrowserWindowStateValidationOwner {
        windowSessionBundle.windowStateValidationOwner
    }
    private var permissionSidebarPinningOwner: BrowserPermissionSidebarPinningOwner {
        privacyBundle.permissionSidebarPinningOwner
    }
    var historyNavigationOwner: BrowserHistoryNavigationOwner {
        historyBundle.historyNavigationOwner
    }
    var historyMenuOwner: BrowserHistoryMenuOwner {
        historyBundle.historyMenuOwner
    }
    var bookmarkCommandOwner: BrowserBookmarkCommandOwner {
        bookmarkBundle.bookmarkCommandOwner
    }
    lazy var shutdownCleanupOwner = BrowserShutdownCleanupOwner(
        browserManager: self
    )
    lazy var keyboardShortcutCommandOwner = BrowserKeyboardShortcutCommandOwner(
        browserManager: self
    )
    var floatingBarRoutingOwner: BrowserFloatingBarRoutingOwner {
        urlBarBundle.floatingBarRoutingOwner
    }
    var floatingBarBrowserContextOwner: BrowserFloatingBarBrowserContextOwner {
        urlBarBundle.floatingBarBrowserContextOwner
    }
    var urlBarContextOwner: BrowserURLBarContextOwner { urlBarBundle.contextOwner }
    var activePageRoutingOwner: BrowserActivePageRoutingOwner {
        urlBarBundle.activePageRoutingOwner
    }
    var windowSessionCommands: BrowserWindowSessionCommands { windowSessionBundle.commands }
    lazy var webViewCloseRouter = BrowserWebViewCloseRouter(
        browserManager: self
    )
    var automaticDataCleanupOwner: BrowserAutomaticDataCleanupOwner {
        privacyBundle.automaticDataCleanupOwner
    }
    lazy var notificationPresenter = BrowserNotificationPresenter(
        browserManager: self
    )
    lazy var appCommandRouter = BrowserAppCommandRouter(
        dependencies: .live(browserManager: self)
    )
    lazy var shortcutActionRouter = BrowserShortcutActionRouter(
        dependencies: .live(browserManager: self)
    )
    var extensionBridgeAdapter: BrowserExtensionBridgeAdapter {
        extensionBridgeBundle.adapter
    }
    let shellRuntime = BrowserShellRuntime()
    lazy var webViewRoutingService = BrowserWebViewRoutingService(
        tabLookup: { [weak self] tabId in
            self?.tabManager.tabCollectionMembershipOwner.tab(for: tabId)
        },
        coordinatorProvider: { [weak self] in
            self?.shellRuntime.webViewCoordinator
        }
    )
    var windowSessionService = WindowSessionService(
        lastWindowSessionKey: BrowserManager.lastWindowSessionKey
    )
    let startupSessionRestoreOwner: BrowserStartupSessionRestoreOwner

    var auxiliaryWindowManager = AuxiliaryWindowManager()
    private var profileSwitchTransitionOwner: BrowserProfileSwitchTransitionOwner {
        profileLifecycleBundle.profileSwitchTransitionOwner
    }
    let glanceManager = GlanceManager()

    /// Shared with app shell / `ContentView` via `.environment`; retained strongly so routing never sees a dangling coordinator.
    /// After `SumiApp.setupApplicationLifecycle` runs, this must be set before any WebView routing or coordinator cleanup.
    var webViewCoordinator: WebViewCoordinator? {
        get { shellRuntime.webViewCoordinator }
        set { shellRuntime.bindWebViewCoordinator(newValue) }
    }

    /// Use for cleanup and cross-window operations; fails fast if the coordinator was not wired (e.g. tests forgot to assign `webViewCoordinator`).
    var windowRegistry: WindowRegistry? {
        get { shellRuntime.windowRegistry }
        set { shellRuntime.bindWindowRegistry(newValue) }
    }

    /// App-shell owned factory for AppKit-created browser windows.
    var windowShellContentViewFactory: BrowserWindowShellService.ContentViewFactory? {
        get { shellRuntime.windowShellContentViewFactory }
        set { shellRuntime.windowShellContentViewFactory = newValue }
    }

    private lazy var initializationWiringOwner = BrowserManagerInitializationWiringOwner(
        attachShellRuntime: { [weak self] in
            guard let self else { return }
            self.attachShellRuntime()
        },
        attachRuntimeWiring: { [weak self] in
            guard let self else { return AnyCancellable {} }
            return BrowserManagerRuntimeWiring.attach(to: self)
        },
        handleTabManagerDataLoaded: { [weak self] in
            self?.handleTabManagerDataLoaded()
        },
        scheduleBrowsingDataRetentionCleanup: { [weak self] in
            self?.automaticDataCleanupOwner.scheduleAutomaticBrowsingDataCleanup(
                reason: "retention-setting-changed",
                force: true,
                delayNanoseconds: 0
            )
        },
        beginProtectionRestoreForStartupIfNeeded: { [weak self] in
            self?.beginProtectionRestoreForStartupIfNeeded()
        }
    )
    private(set) var startupProtectionRuntime: BrowserStartupProtectionRuntime!
    var windowHistorySessionOwner: BrowserWindowHistorySessionOwner {
        windowSessionBundle.historySessionOwner
    }
    var recentlyClosedRestoreOwner: BrowserRecentlyClosedRestoreOwner {
        windowSessionBundle.recentlyClosedRestoreOwner
    }
    var windowSessionActivationOwner: BrowserWindowSessionActivationOwner {
        windowSessionBundle.activationOwner
    }
    var startupPolicyOwner: BrowserStartupPolicyOwner {
        profileLifecycleBundle.startupPolicyOwner
    }

    func adoptProfileIfNeeded(
        for windowState: BrowserWindowState, context: ProfileSwitchContext
    ) {
        sumiProfileRouter.adoptProfileIfNeeded(
            for: windowState,
            context: context,
            support: self
        )
    }

    init(
        moduleRegistry: SumiModuleRegistry = .shared,
        startupPersistence: BrowserManagerStartupPersistence = .production,
        browserConfiguration: BrowserConfiguration = .shared,
        // Explicit injection seams keep module-boundary tests focused without constructing optional runtimes at startup.
        adBlockingModule: SumiAdBlockingModule? = nil,
        protectionCoordinator: SumiProtectionCoordinator? = nil,
        adblockZapperStore: SumiAdblockZapperStore? = nil,
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
        permissionSiteActivityStore: SumiPermissionSiteActivityStore? = nil,
        permissionCleanupService: SumiPermissionCleanupService? = nil,
        blockedPopupStore: SumiBlockedPopupStore? = nil,
        externalAppResolver: any SumiExternalAppResolving = SumiNSWorkspaceExternalAppResolver(),
        externalSchemeSessionStore: SumiExternalSchemeSessionStore? = nil,
        permissionBridgeOverrides: BrowserPermissionBridgeRegistry.Overrides = BrowserPermissionBridgeRegistry.Overrides(),
        sidebarHostRecoveryCoordinator: SidebarHostRecoveryHandling = SidebarHostRecoveryCoordinator()
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
        self.sidebarHostRecoveryCoordinator = sidebarHostRecoveryCoordinator
        let resolvedAdBlockingModule = adBlockingModule
            ?? SumiAdBlockingModule(moduleRegistry: moduleRegistry)
        self.adBlockingModule = resolvedAdBlockingModule
        self.protectionCoordinator = protectionCoordinator
            ?? SumiProtectionCoordinator(
                settings: SumiProtectionSettings(userDefaults: moduleRegistry.userDefaults),
                adBlockingModule: resolvedAdBlockingModule,
                bundleUpdateStatusStore: SumiProtectionBundleUpdateStatusStore(
                    userDefaults: moduleRegistry.userDefaults
                )
            )
        SumiProtectionCoordinator.bindShared(self.protectionCoordinator)
        self.adblockZapperStore = adblockZapperStore
            ?? SumiAdblockZapperStore(userDefaults: moduleRegistry.userDefaults)
        self.userscriptsModule = userscriptsModule
            ?? SumiUserscriptsModule(
                moduleRegistry: moduleRegistry,
                context: startupModelContext
            )
        self.boostsModule = boostsModule ?? SumiBoostsModule(
            moduleRegistry: moduleRegistry,
            storeFactory: { SumiBoostStore() }
        )
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
                browserConfiguration: browserConfiguration,
                initialProfileProvider: { initialProfile }
            )

        self.tabManager = TabManager(
            context: startupModelContext,
            faviconService: resolvedDataServices.faviconService,
            faviconImageService: resolvedDataServices.faviconImageService,
            visitedLinkStore: resolvedDataServices.visitedLinkStore
        )
        // settingsManager will be injected from SumiApp
        self.downloadManager = DownloadManager()
        self.authenticationManager = AuthenticationManager()
        // Initialize managers with current profile context for isolation
        self.historyManager = HistoryManager(
            context: startupModelContext,
            profileId: initialProfile?.id,
            faviconCleaner: resolvedDataServices.historyFaviconCleaner,
            visitedLinkStore: resolvedDataServices.historyVisitedLinkStore
        )
        self.bookmarkManager = Self.makeBookmarkManager(
            faviconService: resolvedDataServices.faviconService,
            initialProfile: initialProfile
        )
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
        self.browserConfiguration = browserConfiguration
        self.dataServices = resolvedDataServices
        self.browsingDataCleanupService = resolvedDataServices.browsingDataCleanupService
        self.nativeNowPlayingController = nowPlayingController
        self.permissionRuntime = Self.makePermissionRuntime(
            PermissionRuntimeBootstrap(
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
                permissionSiteActivityStore: permissionSiteActivityStore
                    ?? SumiPermissionSiteActivityStore(),
                permissionCleanupService: permissionCleanupService,
                blockedPopupStore: blockedPopupStore,
                externalAppResolver: externalAppResolver,
                externalSchemeSessionStore: externalSchemeSessionStore,
                permissionBridgeOverrides: permissionBridgeOverrides
            )
        )
        startPermissionEventObservation()
        self.startupProtectionRuntime = BrowserStartupProtectionRuntime(
            browserManager: self
        )

        initializationWiringOwner.finishInitializationWiring()
    }

    private static func makeBookmarkManager(
        faviconService: any BrowserFaviconServicing,
        initialProfile: Profile?
    ) -> SumiBookmarkManager {
        let bookmarkManager = SumiBookmarkManager(faviconService: faviconService)
        if let initialProfile {
            bookmarkManager.setFaviconPrefetchPartition(
                faviconService.partition(profile: initialProfile)
            )
        }
        return bookmarkManager
    }

    private struct PermissionRuntimeBootstrap {
        let startupPersistence: BrowserManagerStartupPersistence
        let browserConfiguration: BrowserConfiguration
        let systemPermissionService: (any SumiSystemPermissionService)?
        let permissionCoordinator: (any SumiPermissionCoordinating)?
        let geolocationProvider: (any SumiGeolocationProviding)?
        let notificationService: (any SumiNotificationServicing)?
        let runtimePermissionController: (any SumiRuntimePermissionControlling)?
        let filePickerPanelPresenter: (any SumiFilePickerPanelPresenting)?
        let permissionIndicatorEventStore: SumiPermissionIndicatorEventStore?
        let permissionRecentActivityStore: SumiPermissionRecentActivityStore?
        let permissionSiteActivityStore: SumiPermissionSiteActivityStore
        let permissionCleanupService: SumiPermissionCleanupService?
        let blockedPopupStore: SumiBlockedPopupStore?
        let externalAppResolver: any SumiExternalAppResolving
        let externalSchemeSessionStore: SumiExternalSchemeSessionStore?
        let permissionBridgeOverrides: BrowserPermissionBridgeRegistry.Overrides
    }

    private static func makePermissionRuntime(
        _ bootstrap: PermissionRuntimeBootstrap
    ) -> BrowserManagerPermissionRuntime {
        BrowserManagerPermissionRuntime(
            dependencies: BrowserManagerPermissionRuntime.Dependencies(
                startupPersistence: bootstrap.startupPersistence,
                browserConfiguration: bootstrap.browserConfiguration,
                systemPermissionService: bootstrap.systemPermissionService,
                permissionCoordinator: bootstrap.permissionCoordinator,
                geolocationProvider: bootstrap.geolocationProvider,
                notificationService: bootstrap.notificationService,
                runtimePermissionController: bootstrap.runtimePermissionController,
                filePickerPanelPresenter: bootstrap.filePickerPanelPresenter,
                permissionIndicatorEventStore: bootstrap.permissionIndicatorEventStore,
                permissionRecentActivityStore: bootstrap.permissionRecentActivityStore,
                permissionSiteActivityStore: bootstrap.permissionSiteActivityStore,
                permissionCleanupService: bootstrap.permissionCleanupService,
                blockedPopupStore: bootstrap.blockedPopupStore,
                externalAppResolver: bootstrap.externalAppResolver,
                externalSchemeSessionStore: bootstrap.externalSchemeSessionStore,
                permissionBridgeOverrides: bootstrap.permissionBridgeOverrides
            )
        )
    }

    private func startPermissionEventObservation() {
        permissionRuntime.startPermissionEventObservation { [weak self] _ in
            await self?.permissionSidebarPinningOwner.reconcile(reason: "permission-event")
        }
    }

    private func attachShellRuntime() {
        shellRuntime.attach(
            releaseWebViewCoordinator: { [weak self] coordinator in
                guard self != nil else { return }
                coordinator?.detachVisiblePreparationRuntimeContext()
                coordinator?.detachInitialDocumentRuntimeContext()
                coordinator?.detachShutdownRuntimeContext()
                coordinator?.detachBrowserRuntimeContext()
            },
            adoptWebViewCoordinator: { [weak self] coordinator in
                guard let self else { return }
                guard let coordinator else { return }
                coordinator.attachBrowserRuntimeContext(
                    BrowserWebViewRuntimeFactory.browserRuntimeContext(
                        for: self
                    )
                )
                coordinator.attachInitialDocumentRuntimeContext(
                    BrowserWebViewRuntimeFactory.initialDocumentContext(
                        for: self
                    )
                )
                coordinator.attachShutdownRuntimeContext(
                    BrowserWebViewRuntimeFactory.shutdownContext(
                        for: self
                    )
                )
                coordinator.attachVisiblePreparationRuntimeContext(
                    BrowserWebViewRuntimeFactory.visiblePreparationContext(
                        for: self
                    )
                )
            },
            setDestructiveCleanupPreparer: { [weak self] coordinator in
                self?.browsingDataCleanupService.destructiveCleanupPreparer = coordinator
            },
            windowRegistryChanged: { [weak self] registry in
                guard let self else { return }
                self.glanceManager.windowRegistry = registry
                self.splitManager.windowRegistry = registry
                Task { @MainActor [weak self] in
                    await self?.permissionSidebarPinningOwner.reconcile(reason: "window-registry-updated")
                }
                self.backgroundMediaOptimizationService.scheduleReconcile(reason: "window-registry-updated")
                self.reconcileStartupSessionIfPossible()
            }
        )
    }

    /// Called when TabManager finishes loading initial data from persistence
    private func handleTabManagerDataLoaded() {
        windowSessionService.handleTabManagerDataLoaded(runtime: WindowSessionRuntimeFactory.make(for: self))
        liveFolderManager.startAfterTabRestore()
        reconcileStartupSessionIfPossible()
    }

    private func beginProtectionRestoreForStartupIfNeeded() {
        startupProtectionRuntime.beginProtectionRestoreForStartupIfNeeded()
    }

    func reconcileStartupSessionIfPossible() {
        startupSessionRestoreOwner.reconcileIfReady(
            hasLoadedInitialTabData: { [weak self] in
                self?.tabManager.hasLoadedInitialData ?? false
            },
            startupMode: { [weak self] in
                self?.sumiSettings?.startupMode
            },
            startupWindow: { [weak self] in
                self?.startupPolicyOwner.firstRegularWindowForStartupPolicy
            },
            applyStartupPolicy: { [weak self] mode in
                self?.startupPolicyOwner.applyStartupPolicy(mode)
            }
        )
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

    private var tabSelectionActions: BrowserTabSelectionOwner.Actions {
        BrowserTabSelectionOwner.liveActions(for: self)
    }

    func duplicateCurrentTab() {
        guard let activeWindow = windowRegistry?.activeWindow,
              let currentTab = activePageRoutingOwner.currentTabForActiveWindow() else {
            return
        }
        tabLifecycleService.opening.duplicateTab(currentTab, in: activeWindow)
    }

    isolated deinit {
        permissionRuntime.cancelPermissionEventObservation()
        startupProtectionRuntime.cancelProtectionRestoreTask()
        windowSessionService.cancelPendingWindowSessionPersistence()
        initializationWiringOwner.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Window State Management

    // MARK: - Window-Aware Tab Operations

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
        tabLifecycleService.selection.selectTab(
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
        tabLifecycleService.selection.requestUserTabActivation(
            tab,
            in: windowState,
            loadPolicy: loadPolicy,
            actions: tabSelectionActions
        )
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
        tabLifecycleService.selection.applyTabSelection(
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
        tabLifecycleService.selection.materializeVisibleTabWebViewIfNeeded(
            tab,
            in: windowState,
            actions: tabSelectionActions
        )
    }

    func syncShortcutSelectionState(for windowState: BrowserWindowState) {
        tabLifecycleService.selection.syncShortcutSelectionState(
            for: windowState,
            actions: tabSelectionActions
        )
    }

    func showEmptyState(
        in windowState: BrowserWindowState,
        presentNewTabFloatingBar: Bool = false
    ) {
        tabLifecycleService.selection.showEmptyState(
            in: windowState,
            actions: tabSelectionActions
        )

        if presentNewTabFloatingBar && windowState.isShowingEmptyState {
            floatingBarRoutingOwner.showNewTabFloatingBar(in: windowState)
        }
    }

    // MARK: - Find Bar Routing

    func showFindBar() {
        let session = activePageRoutingOwner.activeFindSession()
        findManager.showFindBar(for: session.tab, in: session.windowId)
    }

    func updateFindManagerCurrentTab() {
        let session = activePageRoutingOwner.activeFindSession()
        findManager.updateCurrentTab(session.tab, in: session.windowId)
    }

}

extension BrowserManager: SumiProfileRoutingSupport {}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
