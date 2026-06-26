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

enum HistorySwipeDeferredWindowMutationKind: Hashable {
    case refreshCompositor
    case prepareVisibleWebViews
}

@MainActor
struct HistorySwipeWindowMutationQueue {
    private var recordsByWindowId: [UUID: DeferredHistorySwipeWindowMutations] = [:]

    mutating func enqueue(
        _ kind: HistorySwipeDeferredWindowMutationKind,
        for windowState: BrowserWindowState
    ) {
        var record = recordsByWindowId[windowState.id]
            ?? DeferredHistorySwipeWindowMutations(windowState: WeakBrowserWindowState(windowState))
        record.windowState = WeakBrowserWindowState(windowState)
        record.pendingKinds.insert(kind)
        recordsByWindowId[windowState.id] = record
    }

    mutating func takePendingMutations(for windowId: UUID) -> PendingMutations? {
        guard let record = recordsByWindowId.removeValue(forKey: windowId),
              let windowState = record.windowState.value
        else {
            return nil
        }

        return PendingMutations(
            windowState: windowState,
            pendingKinds: record.pendingKinds
        )
    }

    mutating func cancel(in windowId: UUID) {
        recordsByWindowId.removeValue(forKey: windowId)
    }

    struct PendingMutations {
        let windowState: BrowserWindowState
        let pendingKinds: Set<HistorySwipeDeferredWindowMutationKind>

        var needsVisibleWebViewPreparation: Bool {
            pendingKinds.contains(.prepareVisibleWebViews)
        }

        var needsCompositorRefresh: Bool {
            pendingKinds.contains(.prepareVisibleWebViews)
                || pendingKinds.contains(.refreshCompositor)
        }
    }
}

enum StartupNormalTabMaterializationPolicy {
    static func shouldDefer(
        appliedProtectionLevel: SumiProtectionLevel,
        hasFinishedStartupProtectionRestore: Bool
    ) -> Bool {
        appliedProtectionLevel != .off && !hasFinishedStartupProtectionRestore
    }
}

private final class WeakBrowserWindowState {
    weak var value: BrowserWindowState?

    init(_ value: BrowserWindowState) {
        self.value = value
    }
}

private struct DeferredHistorySwipeWindowMutations {
    var windowState: WeakBrowserWindowState
    var pendingKinds: Set<HistorySwipeDeferredWindowMutationKind> = []
}

@MainActor
enum StartupWorkspaceThemeResolver {
    static func resolve(
        userDefaults: UserDefaults = .standard,
        lastWindowSessionKey: String,
        modelContext: ModelContext
    ) -> WorkspaceTheme? {
        guard let snapshot = WindowSessionBootstrapOverride.resolvedSnapshot(
            userDefaults: userDefaults,
            lastWindowSessionKey: lastWindowSessionKey
        )?.snapshot,
              let currentSpaceId = snapshot.currentSpaceId
        else {
            return nil
        }

        return workspaceTheme(for: currentSpaceId, modelContext: modelContext)
    }

    static func workspaceTheme(
        for spaceId: UUID,
        modelContext: ModelContext
    ) -> WorkspaceTheme? {
        guard let spaces = try? modelContext.fetch(FetchDescriptor<SpaceEntity>()),
              let space = spaces.first(where: { $0.id == spaceId })
        else {
            return nil
        }

        return decodeWorkspaceTheme(from: space)
    }

    static func decodeWorkspaceTheme(from space: SpaceEntity) -> WorkspaceTheme {
        WorkspaceTheme.decode(space.workspaceThemeData ?? Data()) ?? .default
    }
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
    let folderEditorPopoverPresenter: FolderEditorPopoverPresenter
    let spaceEditorPopoverPresenter: SpaceEditorPopoverPresenter
    let shortcutEditorPopoverPresenter: ShortcutEditorPopoverPresenter
    var authenticationManager: AuthenticationManager
    var historyManager: HistoryManager
    var bookmarkManager: SumiBookmarkManager
    var recentlyClosedManager: RecentlyClosedManager
    var lastSessionWindowsStore: LastSessionWindowsStore
    var compositorManager: TabCompositorManager
    let tabSuspensionService: TabSuspensionService
    let backgroundMediaOptimizationService = SumiBackgroundMediaOptimizationService()
    var splitManager: SplitViewManager
    var workspaceThemeCoordinator: WorkspaceThemeCoordinator
    var findManager: FindManager
    let systemPermissionService: any SumiSystemPermissionService
    let permissionCoordinator: any SumiPermissionCoordinating
    private let geolocationProvider: (any SumiGeolocationProviding)?
    let runtimePermissionController: any SumiRuntimePermissionControlling
    let webKitPermissionBridge: SumiWebKitPermissionBridge
    let webKitGeolocationBridge: SumiWebKitGeolocationBridge
    let notificationPermissionBridge: SumiNotificationPermissionBridge
    let filePickerPermissionBridge: SumiFilePickerPermissionBridge
    let storageAccessPermissionBridge: SumiStorageAccessPermissionBridge
    let permissionIndicatorEventStore: SumiPermissionIndicatorEventStore
    let permissionRecentActivityStore: SumiPermissionRecentActivityStore
    let permissionSiteActivityStore: SumiPermissionSiteActivityStore
    let permissionCleanupService: SumiPermissionCleanupService
    let blockedPopupStore: SumiBlockedPopupStore
    let popupPermissionBridge: SumiPopupPermissionBridge
    let externalAppResolver: any SumiExternalAppResolving
    let externalSchemeSessionStore: SumiExternalSchemeSessionStore
    let externalSchemePermissionBridge: SumiExternalSchemePermissionBridge
    let permissionLifecycleController: SumiPermissionGrantLifecycleController
    let permissionSidebarPinningController = SumiPermissionSidebarPinningController()
    private var permissionEventOwner: SumiPermissionEventOwner?
    private var didPauseGeolocationForApplicationBackground = false
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
    let privacyService = BrowserPrivacyService()
    let liveFolderManager = SumiLiveFolderManager()
    private let floatingBarNavigationOwner = FloatingBarNavigationOwner()

    lazy var shellSelectionService = ShellSelectionService { [weak self] windowId in
        guard let self else { return [] }
        return self.splitManager.visibleTabIds(for: windowId)
    }
    lazy var tabCloseFallbackPlanner = BrowserTabCloseFallbackPlanner(
        selectionService: shellSelectionService
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
    let startupSessionCoordinator = SumiStartupSessionCoordinator()

    var auxiliaryWindowManager = AuxiliaryWindowManager()
    let glanceManager = GlanceManager()

    /// Shared with app shell / `ContentView` via `.environment`; retained strongly so routing never sees a dangling coordinator.
    /// After `SumiApp.setupApplicationLifecycle` runs, this must be set before any WebView routing or coordinator cleanup.
    var webViewCoordinator: WebViewCoordinator? {
        didSet {
            if oldValue?.browserManager === self {
                oldValue?.browserManager = nil
            }
            webViewCoordinator?.browserManager = self
            SumiBrowsingDataCleanupService.shared.destructiveCleanupPreparer = webViewCoordinator
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

    private var savedSidebarWidth: CGFloat = BrowserWindowState.sidebarDefaultWidth
    private var savedSidebarVisibility: Bool = true
    var isSwitchingProfile: Bool = false
    var startupLastSessionWindowSnapshots: [LastSessionWindowSnapshot]
    var startupLastSessionTabSnapshot: TabSnapshotRepository.Snapshot?
    var didConsumeStartupLastSessionRestoreOffer = false
    private var structuralChangeCancellable: AnyCancellable?
    private var tabManagerLoadObserverToken: NSObjectProtocol?
    private var browsingDataRetentionObserverToken: NSObjectProtocol?
    private var startupProtectionRestoreTask: Task<Void, Never>?
    private(set) var hasFinishedStartupProtectionRestore = false
    private var deferredStartupBackgroundTabIds: Set<UUID> = []
    private let windowTabActivationBatcher = WindowTabActivationBatcher()
    private var historySwipeWindowMutationQueue = HistorySwipeWindowMutationQueue()

    private func adoptProfileIfNeeded(
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
        // Explicit injection seams keep module-boundary tests focused without constructing optional runtimes at startup.
        adBlockingModule: SumiAdBlockingModule? = nil,
        protectionCoordinator: SumiProtectionCoordinator? = nil,
        extensionsModule: SumiExtensionsModule? = nil,
        userscriptsModule: SumiUserscriptsModule? = nil,
        boostsModule: SumiBoostsModule? = nil,
        systemPermissionService: (any SumiSystemPermissionService)? = nil,
        permissionCoordinator: (any SumiPermissionCoordinating)? = nil,
        geolocationProvider: (any SumiGeolocationProviding)? = nil,
        notificationService: (any SumiNotificationServicing)? = nil,
        runtimePermissionController: (any SumiRuntimePermissionControlling)? = nil,
        webKitPermissionBridge: SumiWebKitPermissionBridge? = nil,
        webKitGeolocationBridge: SumiWebKitGeolocationBridge? = nil,
        notificationPermissionBridge: SumiNotificationPermissionBridge? = nil,
        filePickerPanelPresenter: (any SumiFilePickerPanelPresenting)? = nil,
        filePickerPermissionBridge: SumiFilePickerPermissionBridge? = nil,
        storageAccessPermissionBridge: SumiStorageAccessPermissionBridge? = nil,
        permissionIndicatorEventStore: SumiPermissionIndicatorEventStore? = nil,
        permissionRecentActivityStore: SumiPermissionRecentActivityStore? = nil,
        permissionSiteActivityStore: SumiPermissionSiteActivityStore? = nil,
        permissionCleanupService: SumiPermissionCleanupService? = nil,
        blockedPopupStore: SumiBlockedPopupStore? = nil,
        popupPermissionBridge: SumiPopupPermissionBridge? = nil,
        externalAppResolver: (any SumiExternalAppResolving)? = nil,
        externalSchemeSessionStore: SumiExternalSchemeSessionStore? = nil,
        externalSchemePermissionBridge: SumiExternalSchemePermissionBridge? = nil
    ) {
        let startupTrace = StartupPerformanceTrace.browserManagerInitStarted()
        defer {
            StartupPerformanceTrace.browserManagerInitFinished(startupTrace)
        }

        // Phase 1: initialize all stored properties
        let startupModelContext = startupPersistence.mainContext
        let systemPermissionService = systemPermissionService ?? MacSumiSystemPermissionService()
        let persistentPermissionStore = SwiftDataPermissionStore(
            container: startupPersistence.container
        )
        let antiAbuseStore = SumiPermissionAntiAbuseStore()
        let permissionCoordinator = permissionCoordinator
            ?? SumiPermissionCoordinator(
                policyResolver: DefaultSumiPermissionPolicyResolver(
                    systemPermissionService: systemPermissionService
                ),
                persistentStore: persistentPermissionStore,
                antiAbuseStore: antiAbuseStore,
                sessionOwnerId: "browser"
            )
        let geolocationProvider = geolocationProvider
            ?? SumiGeolocationProvider(browserConfiguration: BrowserConfiguration.shared)
        let notificationService = notificationService ?? SumiNotificationService()
        let runtimePermissionController = runtimePermissionController
            ?? SumiRuntimePermissionController(geolocationProvider: geolocationProvider)
        let filePickerPanelPresenter = filePickerPanelPresenter ?? SumiFilePickerPanelPresenter()
        let permissionIndicatorEventStore = permissionIndicatorEventStore ?? SumiPermissionIndicatorEventStore()
        let permissionRecentActivityStore = permissionRecentActivityStore ?? SumiPermissionRecentActivityStore()
        let permissionSiteActivityStore = permissionSiteActivityStore ?? SumiPermissionSiteActivityStore.shared
        let permissionCleanupService = permissionCleanupService
            ?? SumiPermissionCleanupService(
                store: persistentPermissionStore,
                recentActivityStore: permissionRecentActivityStore,
                antiAbuseStore: antiAbuseStore
            )
        let blockedPopupStore = blockedPopupStore ?? SumiBlockedPopupStore()
        let externalAppResolver = externalAppResolver ?? SumiNSWorkspaceExternalAppResolver.shared
        let externalSchemeSessionStore = externalSchemeSessionStore ?? SumiExternalSchemeSessionStore()
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
        self.profileManager = ProfileManager(context: startupModelContext)
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

        self.tabManager = TabManager(browserManager: nil, context: startupModelContext)
        // settingsManager will be injected from SumiApp
        self.downloadManager = DownloadManager()
        self.downloadsPopoverPresenter = DownloadsPopoverPresenter()
        self.urlBarHubPopoverPresenter = URLBarHubPopoverPresenter()
        self.workspaceThemePickerPopoverPresenter = WorkspaceThemePickerPopoverPresenter()
        self.folderEditorPopoverPresenter = FolderEditorPopoverPresenter()
        self.spaceEditorPopoverPresenter = SpaceEditorPopoverPresenter()
        self.shortcutEditorPopoverPresenter = ShortcutEditorPopoverPresenter()
        self.authenticationManager = AuthenticationManager()
        // Initialize managers with current profile context for isolation
        self.historyManager = HistoryManager(context: startupModelContext, profileId: initialProfile?.id)
        self.bookmarkManager = SumiBookmarkManager()
        if let initialProfile {
            self.bookmarkManager.setFaviconPrefetchPartition(
                SumiFaviconSystem.shared.partition(profile: initialProfile)
            )
        }
        self.recentlyClosedManager = RecentlyClosedManager()
        self.lastSessionWindowsStore = LastSessionWindowsStore()
        self.startupLastSessionWindowSnapshots = self.lastSessionWindowsStore.snapshots
        self.startupLastSessionTabSnapshot = self.lastSessionWindowsStore.tabSnapshot
        self.compositorManager = TabCompositorManager()
        self.tabSuspensionService = TabSuspensionService(
            memoryMonitor: SumiMemoryPressureMonitor()
        )
        self.splitManager = SplitViewManager()
        self.workspaceThemeCoordinator = WorkspaceThemeCoordinator()
        self.findManager = FindManager()
        self.systemPermissionService = systemPermissionService
        self.permissionCoordinator = permissionCoordinator
        self.geolocationProvider = geolocationProvider
        self.runtimePermissionController = runtimePermissionController
        self.webKitPermissionBridge = webKitPermissionBridge
            ?? SumiWebKitPermissionBridge(
                coordinator: permissionCoordinator,
                runtimeController: runtimePermissionController
            )
        self.webKitGeolocationBridge = webKitGeolocationBridge
            ?? SumiWebKitGeolocationBridge(
                coordinator: permissionCoordinator,
                geolocationProvider: geolocationProvider
            )
        self.notificationPermissionBridge = notificationPermissionBridge
            ?? SumiNotificationPermissionBridge(
                coordinator: permissionCoordinator,
                notificationService: notificationService,
                indicatorEventStore: permissionIndicatorEventStore
            )
        let resolvedFilePickerPermissionBridge = filePickerPermissionBridge
            ?? SumiFilePickerPermissionBridge(
                coordinator: permissionCoordinator,
                panelPresenter: filePickerPanelPresenter,
                indicatorEventStore: permissionIndicatorEventStore
            )
        self.filePickerPermissionBridge = resolvedFilePickerPermissionBridge
        self.storageAccessPermissionBridge = storageAccessPermissionBridge
            ?? SumiStorageAccessPermissionBridge(
                coordinator: permissionCoordinator,
                indicatorEventStore: permissionIndicatorEventStore
            )
        self.permissionIndicatorEventStore = permissionIndicatorEventStore
        self.permissionRecentActivityStore = permissionRecentActivityStore
        self.permissionSiteActivityStore = permissionSiteActivityStore
        self.permissionCleanupService = permissionCleanupService
        self.blockedPopupStore = blockedPopupStore
        self.popupPermissionBridge = popupPermissionBridge
            ?? SumiPopupPermissionBridge(
                coordinator: permissionCoordinator,
                blockedPopupStore: blockedPopupStore,
                siteActivityStore: permissionSiteActivityStore
            )
        self.externalAppResolver = externalAppResolver
        self.externalSchemeSessionStore = externalSchemeSessionStore
        self.externalSchemePermissionBridge = externalSchemePermissionBridge
            ?? SumiExternalSchemePermissionBridge(
                coordinator: permissionCoordinator,
                appResolver: externalAppResolver,
                sessionStore: externalSchemeSessionStore
            )
        self.permissionLifecycleController = SumiPermissionGrantLifecycleController(
            coordinator: permissionCoordinator,
            geolocationProvider: geolocationProvider,
            filePickerBridge: resolvedFilePickerPermissionBridge,
            indicatorEventStore: permissionIndicatorEventStore,
            blockedPopupStore: blockedPopupStore,
            externalSchemeSessionStore: externalSchemeSessionStore
        )
        self.permissionEventOwner = SumiPermissionEventOwner(
            coordinator: permissionCoordinator,
            recentActivityStore: permissionRecentActivityStore,
            siteActivityStore: permissionSiteActivityStore,
            onEvent: { [weak self] _ in
                await self?.reconcilePermissionSidebarPins(reason: "permission-event")
            }
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

    func showBrowserExtensionsUnavailableAlert(
        extensionName: String? = nil,
        informativeText: String? = nil
    ) {
        let alert = NSAlert()
        alert.messageText = extensionName.map {
            "\($0) is currently unavailable"
        } ?? "Browser extensions are currently unavailable"
        alert.informativeText =
            informativeText
            ?? "Sumi could not open the requested extension action. Check Settings > Extensions to confirm the extension is installed, enabled, and supported on this macOS build."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    /// Called when TabManager finishes loading initial data from persistence
    private func handleTabManagerDataLoaded() {
        windowSessionService.handleTabManagerDataLoaded(delegate: self)
        liveFolderManager.startAfterTabRestore()
        reconcileStartupSessionIfPossible()
    }

    private func beginProtectionRestoreForStartupIfNeeded() {
        guard startupProtectionRestoreTask == nil else { return }
        startupProtectionRestoreTask = Task { @MainActor [weak self] in
            await self?.restoreProtectionForStartupIfNeeded()
        }
    }

    private func restoreProtectionForStartupIfNeeded() async {
        let startupTrace = StartupPerformanceTrace.protectionRestoreStarted()
        defer {
            StartupPerformanceTrace.protectionRestoreFinished(startupTrace)
            finishStartupProtectionRestore()
        }

        do {
            _ = try await protectionCoordinator.restoreAppliedLevelForStartup()
        } catch {
            RuntimeDiagnostics.debug(
                "Protection startup restore failed: \(error.localizedDescription)",
                category: "Protection"
            )
        }
    }

    private func finishStartupProtectionRestore() {
        guard !hasFinishedStartupProtectionRestore else { return }
        hasFinishedStartupProtectionRestore = true

        let deferredBackgroundTabs = deferredStartupBackgroundTabIds
        deferredStartupBackgroundTabIds.removeAll()
        for tabId in deferredBackgroundTabs {
            guard let tab = tabManager.tab(for: tabId) else { continue }
            prepareBackgroundTabIfNeeded(tab, in: nil)
        }

        for windowState in windowRegistry?.allWindows ?? [] {
            schedulePrepareVisibleWebViews(for: windowState)
            refreshCompositor(for: windowState)
        }

#if DEBUG
        Task { @MainActor in
            await Task.yield()
            StartupPerformanceTrace.postStartupIdlePoint()
        }
#endif
    }

    var shouldDeferNormalTabMaterializationDuringStartup: Bool {
        StartupNormalTabMaterializationPolicy.shouldDefer(
            appliedProtectionLevel: protectionCoordinator.settings.appliedLevel,
            hasFinishedStartupProtectionRestore: hasFinishedStartupProtectionRestore
        )
    }

    func canMaterializeNormalTabWebViewDuringStartup(_ tab: Tab) -> Bool {
        if ExtensionUtils.isExtensionOwnedURL(tab.url) || tab.webExtensionContextOverride != nil {
            return true
        }
        return !tab.requiresPrimaryWebView || !shouldDeferNormalTabMaterializationDuringStartup
    }

    enum ProfileSwitchContext {
        case userInitiated
        case spaceChange
        case windowActivation
        case recovery
    }

    actor ProfileOps { func run(_ body: @MainActor () async -> Void) async { await body() } }
    private let profileOps = ProfileOps()

    func switchToProfile(
        _ profile: Profile, context: ProfileSwitchContext = .userInitiated,
        in windowState: BrowserWindowState? = nil
    ) async {
        await profileOps.run { [weak self] in
            guard let self else { return }
            if self.isSwitchingProfile {
                RuntimeDiagnostics.emit {
                    "⏳ [BrowserManager] Ignoring concurrent profile switch request"
                }
                return
            }
            self.isSwitchingProfile = true
            defer { self.isSwitchingProfile = false }

            let previousProfile = self.currentProfile
            RuntimeDiagnostics.emit {
                "🔀 [BrowserManager] Switching to profile: \(profile.name) (\(profile.id.uuidString)) from: \(previousProfile?.name ?? "none")"
            }
            let animateTransition = context.shouldAnimateTransition

            let performUpdates = {
                self.auxiliaryWindowManager.closeAll(reason: .profileSwitch)

                if animateTransition {
                    self.isTransitioningProfile = true
                } else {
                    self.isTransitioningProfile = false
                }
                self.currentProfile = profile
                self.windowRegistry?.activeWindow?.currentProfileId = profile.id
                self.bookmarkManager.setFaviconPrefetchPartition(
                    SumiFaviconSystem.shared.partition(profile: profile)
                )
                self.extensionsModule.switchProfileIfLoaded(profile)
                // Update history filtering
                self.historyManager.switchProfile(profile.id)
                // TabManager awareness (updates currentTab/currentSpace visibility)
                self.tabManager.handleProfileSwitch()
            }

            if animateTransition {
                withAnimation(.easeInOut(duration: 0.35)) {
                    performUpdates()
                }
            } else {
                performUpdates()
            }

            if context.shouldProvideFeedback {
                self.showProfileSwitchToast(
                    to: profile,
                    in: windowState ?? self.windowRegistry?.activeWindow
                )
                NSHapticFeedbackManager.defaultPerformer.perform(
                    .generic, performanceTime: .drawCompleted)
            }

            if animateTransition {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    self?.isTransitioningProfile = false
                }
            }

            await self.runAutomaticPermissionCleanupIfNeeded(for: profile)
            self.scheduleAutomaticBrowsingDataCleanup(reason: "profile-switch")
        }
    }

    @discardableResult
    func runAutomaticPermissionCleanupIfNeeded(
        for profile: Profile?
    ) async -> SumiPermissionCleanupResult? {
        guard let profile else { return nil }
        let repository = SumiPermissionSettingsRepository(browserManager: self)
        return await repository.runAutomaticCleanupIfNeeded(
            profile: SumiPermissionSettingsProfileContext(profile: profile)
        )
    }

    func scheduleAutomaticBrowsingDataCleanup(
        reason: String,
        force: Bool = false,
        delayNanoseconds: UInt64? = nil
    ) {
        guard let sumiSettings else { return }
        SumiAutomaticBrowsingDataCleanupService.shared.scheduleIfNeeded(
            retentionPeriod: sumiSettings.browsingDataRetentionPeriod,
            historyManager: historyManager,
            profiles: profileManager.profiles,
            currentProfileId: currentProfile?.id,
            force: force,
            reason: reason,
            delayNanoseconds: delayNanoseconds
        )
    }

    func updateSidebarWidth(
        _ width: CGFloat,
        for windowState: BrowserWindowState,
        persist: Bool = true
    ) {
        let clampedWidth = BrowserWindowState.clampedSidebarWidth(width)
        windowState.sidebarWidth = clampedWidth
        windowState.savedSidebarWidth = clampedWidth
        windowState.sidebarContentWidth = BrowserWindowState.sidebarContentWidth(for: clampedWidth)
        savedSidebarWidth = clampedWidth
        if persist {
            schedulePersistWindowSession(for: windowState)
        }
    }

    func toggleSidebar() {
        if let windowState = sidebarToggleTargetWindowState() {
            toggleSidebar(for: windowState)
        } else {
            savedSidebarVisibility.toggle()
        }
    }

    func toggleSidebar(for windowState: BrowserWindowState) {
        windowState.isSidebarVisible.toggle()
        // Width stays the same whether visible or hidden.
        savedSidebarVisibility = windowState.isSidebarVisible
        savedSidebarWidth = windowState.savedSidebarWidth
        schedulePersistWindowSession(for: windowState, delayNanoseconds: 150_000_000)
    }

    private func sidebarToggleTargetWindowState() -> BrowserWindowState? {
        if let activeWindow = windowRegistry?.activeWindow {
            return activeWindow
        }

        guard let windowRegistry else {
            return nil
        }

        if let keyWindow = NSApp.keyWindow,
           let keyWindowState = windowRegistry.allWindows.first(where: { windowState in
               guard let browserWindow = windowState.window else { return false }
               if browserWindow === keyWindow {
                   return true
               }
               return browserWindow.childWindows?.contains(where: { $0 === keyWindow }) == true
           }) {
            windowRegistry.setActive(keyWindowState)
            return keyWindowState
        }

        if windowRegistry.allWindows.count == 1,
           let onlyWindow = windowRegistry.allWindows.first {
            windowRegistry.setActive(onlyWindow)
            return onlyWindow
        }

        return nil
    }

    // MARK: - Sidebar width access for overlays
    /// Returns the last saved sidebar width (used when sidebar is collapsed to size hover overlay)
    func getSavedSidebarWidth(for windowState: BrowserWindowState? = nil) -> CGFloat {
        if let state = windowState {
            return max(BrowserWindowState.sidebarMinimumWidth, state.savedSidebarWidth)
        }
        if let active = windowRegistry?.activeWindow {
            return max(BrowserWindowState.sidebarMinimumWidth, active.savedSidebarWidth)
        }
        return max(BrowserWindowState.sidebarMinimumWidth, savedSidebarWidth)
    }

    private var floatingBarActions: FloatingBarNavigationOwner.Actions {
        FloatingBarNavigationOwner.Actions(
            activePageTab: { windowState in
                self.activePageTab(for: windowState)
            },
            cancelEmptySplitPlaceholder: { windowState in
                self.splitManager.cancelEmptySplitPlaceholder(in: windowState)
            },
            commitEmptySplitPlaceholder: { tabId, windowState in
                self.splitManager.commitEmptySplitPlaceholder(tabId: tabId, in: windowState)
            },
            replaceEmptySplitPlaceholder: { tab, windowState in
                self.splitManager.replaceEmptySplitPlaceholder(with: tab, in: windowState)
            },
            selectTab: { tab, windowState in
                self.selectTab(tab, in: windowState)
            },
            createNewTabAfterSidebarInsertion: { windowState, url in
                _ = self.createNewTabAfterSidebarInsertion(in: windowState, url: url)
            },
            normalizeURL: { text in
                let template = self.sumiSettings?.resolvedSearchEngineTemplate
                    ?? SearchProvider.google.queryTemplate
                return normalizeURL(text, queryTemplate: template)
            },
            dismissWorkspaceThemePickerIfNeededDiscarding: {
                self.dismissWorkspaceThemePickerIfNeededDiscarding()
            },
            persistWindowSession: { windowState in
                self.persistWindowSession(for: windowState)
            },
            schedulePersistWindowSession: { windowState in
                self.schedulePersistWindowSession(for: windowState)
            }
        )
    }


    func focusFloatingBarForActiveWindow(
        prefill: String = "",
        navigateCurrentTab: Bool = false,
        presentationReason: FloatingBarPresentationReason = .keyboard
    ) {
        guard let activeWindow = windowRegistry?.activeWindow else { return }
        focusFloatingBar(
            in: activeWindow,
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
        floatingBarNavigationOwner.focus(
            in: windowState,
            prefill: prefill,
            navigateCurrentTab: navigateCurrentTab,
            presentationReason: presentationReason,
            actions: floatingBarActions
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
        floatingBarNavigationOwner.showNewTab(
            in: windowState,
            actions: floatingBarActions
        )
    }

    func openNewTabOrFloatingBar(in windowState: BrowserWindowState) {
        if let settings = sumiSettings,
           settings.newTabMode == .specificPage {
            let url = settings.resolvedNewTabPageURL.absoluteString
            createNewTab(in: windowState, url: url)
        } else {
            showNewTabFloatingBar(in: windowState)
        }
    }

    func spaceForSidebarActions(in windowState: BrowserWindowState) -> Space? {
        windowState.currentSpaceId
            .flatMap { spaceId in tabManager.spaces.first(where: { $0.id == spaceId }) }
            ?? tabManager.currentSpace
    }

    func createFolderInCurrentSpace(in windowState: BrowserWindowState) {
        guard let space = spaceForSidebarActions(in: windowState) else { return }
        _ = tabManager.createFolder(for: space.id)
    }

    func createRSSLiveFolderInCurrentSpace(in windowState: BrowserWindowState) {
        guard let space = spaceForSidebarActions(in: windowState),
              let feedURLString = promptForLiveFolderFeedURL() else {
            return
        }
        liveFolderManager.createRSSFolder(in: space.id, feedURLString: feedURLString)
    }

    func createGitHubPullRequestsLiveFolderInCurrentSpace(in windowState: BrowserWindowState) {
        guard let space = spaceForSidebarActions(in: windowState) else { return }
        liveFolderManager.createGitHubFolder(in: space.id, kind: .githubPullRequests)
    }

    func createGitHubIssuesLiveFolderInCurrentSpace(in windowState: BrowserWindowState) {
        guard let space = spaceForSidebarActions(in: windowState) else { return }
        liveFolderManager.createGitHubFolder(in: space.id, kind: .githubIssues)
    }

    private func promptForLiveFolderFeedURL() -> String? {
        let alert = NSAlert()
        alert.messageText = "New RSS Live Folder"
        alert.informativeText = "Enter an RSS or Atom feed URL."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "https://example.com/feed.xml"
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased()) else {
            return nil
        }
        return value
    }

    func updateFloatingBarDraft(
        in windowState: BrowserWindowState,
        text: String
    ) {
        floatingBarNavigationOwner.updateDraft(
            in: windowState,
            text: text,
            actions: floatingBarActions
        )
    }

    func dismissFloatingBar(
        in windowState: BrowserWindowState,
        preserveDraft: Bool,
        cancelEmptySplitPlaceholder: Bool = true
    ) {
        floatingBarNavigationOwner.dismiss(
            in: windowState,
            preserveDraft: preserveDraft,
            cancelEmptySplitPlaceholder: cancelEmptySplitPlaceholder,
            actions: floatingBarActions
        )
    }

    func dismissFloatingBarForActiveWindow(preserveDraft: Bool = true) {
        guard let activeWindow = windowRegistry?.activeWindow,
              activeWindow.isFloatingBarVisible
        else { return }

        dismissFloatingBar(in: activeWindow, preserveDraft: preserveDraft)
    }

    @discardableResult
    func dismissFloatingBarIfVisible(
        in windowId: UUID,
        preserveDraft: Bool = true
    ) -> Bool {
        guard let windowState = windowRegistry?.windows[windowId],
              windowState.isFloatingBarVisible
        else { return false }

        dismissFloatingBar(in: windowState, preserveDraft: preserveDraft)
        return true
    }

    func commitFloatingBarSuggestion(
        _ suggestion: SearchManager.SearchSuggestion,
        in windowState: BrowserWindowState,
        navigatesCurrentTab: Bool
    ) {
        floatingBarNavigationOwner.commitSuggestion(
            suggestion,
            in: windowState,
            navigatesCurrentTab: navigatesCurrentTab,
            actions: floatingBarActions
        )
    }

    func commitFloatingBarNavigation(
        to urlString: String,
        in windowState: BrowserWindowState,
        navigatesCurrentTab: Bool
    ) {
        floatingBarNavigationOwner.commitNavigation(
            to: urlString,
            in: windowState,
            navigatesCurrentTab: navigatesCurrentTab,
            actions: floatingBarActions
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
        floatingBarNavigationOwner.openSuggestion(
            suggestion,
            in: windowState,
            navigatesCurrentTab: navigatesCurrentTab,
            actions: floatingBarActions
        )
    }

    private func dismissFloatingBarAfterSelection(in windowState: BrowserWindowState) {
        floatingBarNavigationOwner.dismissAfterSelection(
            in: windowState,
            actions: floatingBarActions
        )
    }

    func sanitizeFloatingBarState(in windowState: BrowserWindowState) {
        floatingBarNavigationOwner.sanitize(
            in: windowState,
            hasValidCurrentSelection: hasValidCurrentSelection(in: windowState),
            actions: floatingBarActions
        )
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

    enum TabOpenActivationPolicy {
        case foreground(windowState: BrowserWindowState, loadPolicy: TabSelectionLoadPolicy)
        case background
    }

    struct TabOpenContext {
        let windowState: BrowserWindowState?
        let sourceTab: Tab?
        let preferredSpaceId: UUID?
        let regularInsertionIndex: Int?
        let activationPolicy: TabOpenActivationPolicy

        static func foreground(
            windowState: BrowserWindowState,
            sourceTab: Tab? = nil,
            preferredSpaceId: UUID? = nil,
            regularInsertionIndex: Int? = nil,
            loadPolicy: TabSelectionLoadPolicy = .deferred
        ) -> TabOpenContext {
            TabOpenContext(
                windowState: windowState,
                sourceTab: sourceTab,
                preferredSpaceId: preferredSpaceId,
                regularInsertionIndex: regularInsertionIndex,
                activationPolicy: .foreground(windowState: windowState, loadPolicy: loadPolicy)
            )
        }

        static func background(
            windowState: BrowserWindowState? = nil,
            sourceTab: Tab? = nil,
            preferredSpaceId: UUID? = nil,
            regularInsertionIndex: Int? = nil
        ) -> TabOpenContext {
            TabOpenContext(
                windowState: windowState,
                sourceTab: sourceTab,
                preferredSpaceId: preferredSpaceId,
                regularInsertionIndex: regularInsertionIndex,
                activationPolicy: .background
            )
        }
    }

    // MARK: - Tab Management (delegates to TabManager)
    func createNewTab() {
        if let activeWindow = windowRegistry?.activeWindow {
            _ = openNewTab(context: .foreground(windowState: activeWindow))
        } else {
            _ = tabManager.createNewTab()
        }
    }

    /// Create a new tab and set it as active in the specified window
    func createNewTab(in windowState: BrowserWindowState, url: String = SumiSurface.emptyTabURL.absoluteString) {
        _ = openNewTab(
            url: url,
            context: .foreground(windowState: windowState)
        )
    }

    @discardableResult
    func createNewTabAfterSidebarInsertion(
        in windowState: BrowserWindowState,
        url: String = SumiSurface.emptyTabURL.absoluteString
    ) -> Tab {
        guard !windowState.isIncognito else {
            return openNewTab(
                url: url,
                context: .foreground(windowState: windowState)
            )
        }

        let targetSpace = resolvedTabOpenSpace(
            for: .foreground(windowState: windowState)
        )
        let newTab = tabManager.createNewTab(
            url: url,
            in: targetSpace,
            activate: false
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + SidebarDropMotion.contentLayoutDuration) { [weak self, weak newTab] in
            guard let self, let newTab, self.tabManager.tab(for: newTab.id) != nil else { return }
            self.selectTab(newTab, in: windowState, loadPolicy: .deferred)
        }

        return newTab
    }

    @discardableResult
    func openNewTab(
        url: String = SumiSurface.emptyTabURL.absoluteString,
        context: TabOpenContext
    ) -> Tab {
        let resolvedWindowState = resolvedWindowState(for: context)

        if let resolvedWindowState,
           resolvedWindowState.isIncognito,
           let profile = resolvedWindowState.ephemeralProfile {
            let template = sumiSettings?.resolvedSearchEngineTemplate ?? SearchProvider.google.queryTemplate
            let normalizedURL = normalizeURL(url, queryTemplate: template)
            guard let resolvedUrl = URL(string: normalizedURL) else {
                return tabManager.createEphemeralTab(
                    url: SumiSurface.emptyTabURL,
                    in: resolvedWindowState,
                    profile: profile
                )
            }

            let previousTabId = resolvedWindowState.currentTabId
            let newTab = tabManager.createEphemeralTab(
                url: resolvedUrl,
                in: resolvedWindowState,
                profile: profile
            )

            switch context.activationPolicy {
            case .foreground(let windowState, let loadPolicy):
                selectTab(newTab, in: windowState, loadPolicy: loadPolicy)
            case .background:
                resolvedWindowState.currentTabId = previousTabId
                prepareBackgroundTabIfNeeded(
                    newTab,
                    in: resolvedWindowState
                )
            }

            return newTab
        }

        let targetSpace = resolvedTabOpenSpace(for: context)
        let shouldActivateInTabManager = false
        let regularInsertionIndex = context.regularInsertionIndex
            ?? tabManager.regularChildInsertionIndex(
                openedFrom: context.sourceTab,
                in: targetSpace
            )
        let newTab = tabManager.createNewTab(
            url: url,
            in: targetSpace,
            activate: shouldActivateInTabManager,
            regularInsertionIndex: regularInsertionIndex
        )

        switch context.activationPolicy {
        case .foreground(let windowState, let loadPolicy):
            selectTab(newTab, in: windowState, loadPolicy: loadPolicy)
        case .background:
            prepareBackgroundTabIfNeeded(
                newTab,
                in: resolvedWindowState
            )
        }

        return newTab
    }

    private func prepareBackgroundTabIfNeeded(
        _ tab: Tab,
        in windowState: BrowserWindowState?
    ) {
        guard tab.requiresPrimaryWebView else { return }
        guard canMaterializeNormalTabWebViewDuringStartup(tab) else {
            deferredStartupBackgroundTabIds.insert(tab.id)
            return
        }
        _ = windowState
        tab.loadWebViewIfNeeded()
    }

    func resolvedTabOpenSpace(for context: TabOpenContext) -> Space? {
        let resolvedWindowState = resolvedWindowState(for: context)

        if let preferredSpaceId = context.preferredSpaceId,
           let preferredSpace = tabManager.spaces.first(where: { $0.id == preferredSpaceId }) {
            return preferredSpace
        }

        if let windowSpaceId = resolvedWindowState?.currentSpaceId,
           let windowSpace = tabManager.spaces.first(where: { $0.id == windowSpaceId }) {
            return windowSpace
        }

        if let sourceSpaceId = context.sourceTab?.spaceId,
           let sourceSpace = tabManager.spaces.first(where: { $0.id == sourceSpaceId }) {
            return sourceSpace
        }

        if let profileId = resolvedWindowState?.currentProfileId,
           let profileSpace = tabManager.spaces.first(where: { $0.profileId == profileId }) {
            return profileSpace
        }

        if let sourceProfileId = context.sourceTab?.profileId,
           let sourceProfileSpace = tabManager.spaces.first(where: { $0.profileId == sourceProfileId }) {
            return sourceProfileSpace
        }

        return tabManager.currentSpace ?? tabManager.spaces.first
    }

    @discardableResult
    func createPopupTab(
        from sourceTab: Tab,
        webViewConfigurationOverride: WKWebViewConfiguration? = nil,
        activate: Bool = true
    ) -> Tab? {
        let sourceWindowState = windowState(containing: sourceTab)
        if sourceTab.isEphemeral || sourceWindowState?.isIncognito == true {
            guard let sourceWindowState,
                  let profile = sourceWindowState.ephemeralProfile,
                  let blankURL = URL(string: "about:blank")
            else {
                return nil
            }

            let previousTabId = sourceWindowState.currentTabId
            let popupTab = tabManager.createEphemeralTab(
                url: blankURL,
                in: sourceWindowState,
                profile: profile
            )
            popupTab.isPopupHost = true
            if let webViewConfigurationOverride {
                popupTab.applyWebViewConfigurationOverride(webViewConfigurationOverride)
            }
            if activate == false {
                sourceWindowState.currentTabId = previousTabId
            }
            return popupTab
        }

        let context = TabOpenContext.background(
            windowState: sourceWindowState,
            sourceTab: sourceTab,
            preferredSpaceId: sourceTab.spaceId
        )
        let targetSpace = resolvedTabOpenSpace(for: context)
        let insertionIndex = tabManager.regularChildInsertionIndex(
            openedFrom: sourceTab,
            in: targetSpace
        )
        return tabManager.createPopupTab(
            in: targetSpace,
            activate: activate,
            webViewConfigurationOverride: webViewConfigurationOverride,
            regularInsertionIndex: insertionIndex
        )
    }

    private func resolvedWindowState(for context: TabOpenContext) -> BrowserWindowState? {
        if let windowState = context.windowState {
            return windowState
        }

        if let sourceTab = context.sourceTab,
           let windowState = windowState(containing: sourceTab) {
            return windowState
        }

        return windowRegistry?.activeWindow
    }

    /// Opens Sumi settings as a normal browser tab (one per space), optionally focusing a pane.
    func openSettingsTab(selecting pane: SettingsTabs, in windowState: BrowserWindowState? = nil) {
        guard let windowState = windowState ?? windowRegistry?.activeWindow else { return }
        openNativeBrowserSurface(
            .settings,
            url: settingsSurfaceURL(for: pane),
            in: windowState
        )
    }

    func openSiteSettingsTab(
        focusing tab: Tab? = nil,
        in windowState: BrowserWindowState? = nil
    ) {
        guard let windowState = windowState ?? windowRegistry?.activeWindow else { return }
        let targetTab = tab ?? currentTab(for: windowState)
        let mainURL = targetTab?.extensionRuntimeCommittedMainDocumentURL
            ?? targetTab?.existingWebView?.url
            ?? targetTab?.url
        let origin = SumiPermissionOrigin(url: mainURL)
        let displayDomain = SumiCurrentSitePermissionsViewModel.displayDomain(
            for: origin,
            fallbackURL: mainURL
        )
        let filter = origin.isWebOrigin
            ? SumiSettingsSiteSettingsFilter(
                requestingOrigin: origin,
                topOrigin: origin,
                displayDomain: displayDomain
            )
            : nil

        openNativeBrowserSurface(
            .settings,
            url: privacySiteSettingsSurfaceURL(filter: filter),
            in: windowState
        )
    }

    private func settingsSurfaceURL(for pane: SettingsTabs) -> URL {
        switch pane {
        case .userScripts:
            return SumiSurface.settingsSurfaceURL(paneQuery: SettingsTabs.userScripts.paneQueryValue)
        default:
            return pane.settingsSurfaceURL
        }
    }

    private func privacySiteSettingsSurfaceURL(filter: SumiSettingsSiteSettingsFilter?) -> URL {
        var extraQueryItems = [URLQueryItem(name: "section", value: "siteSettings")]
        if let filter {
            if let origin = filter.requestingOriginIdentity, !origin.isEmpty {
                extraQueryItems.append(URLQueryItem(name: "origin", value: origin))
            }
            if let topOrigin = filter.topOriginIdentity, !topOrigin.isEmpty {
                extraQueryItems.append(URLQueryItem(name: "topOrigin", value: topOrigin))
            }
            if let site = filter.displayDomain, !site.isEmpty {
                extraQueryItems.append(URLQueryItem(name: "site", value: site))
            }
        }
        return SumiSurface.settingsSurfaceURL(
            paneQuery: SettingsTabs.privacy.paneQueryValue,
            extraQueryItems: extraQueryItems
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
        let targetSpace =
            windowState.currentSpaceId.flatMap { id in
                tabManager.spaces.first(where: { $0.id == id })
            }
            ?? tab.spaceId.flatMap { id in tabManager.spaces.first(where: { $0.id == id }) }
            ?? tabManager.currentSpace
        let insertIndex = tabManager.regularChildInsertionIndex(
            openedFrom: tab,
            in: targetSpace
        )

        let newTab = Tab(
            url: tab.url,
            name: tab.name,
            favicon: "globe",
            spaceId: targetSpace?.id,
            index: 0,
            browserManager: self
        )
        newTab.favicon = tab.favicon
        newTab.faviconIsTemplateGlobePlaceholder = tab.faviconIsTemplateGlobePlaceholder
        newTab.profileId = tab.profileId

        tabManager.addTab(newTab, regularInsertionIndex: insertIndex)
        selectTab(newTab, in: windowState)
    }

    func closeCurrentTab() {
        if let activeWindow = windowRegistry?.activeWindow,
            activeWindow.isFloatingBarVisible
        {
            return
        }
        if let activeWindow = windowRegistry?.activeWindow,
           glanceManager.activePreviewTab(for: activeWindow) != nil {
            glanceManager.dismissGlance()
            return
        }
        if let activeWindow = windowRegistry?.activeWindow,
           let currentTab = currentTab(for: activeWindow) {
            closeTab(currentTab, in: activeWindow)
        } else if let activeWindow = windowRegistry?.activeWindow {
            showEmptyState(in: activeWindow)
        }
    }

    func closeTab(_ tab: Tab, in windowState: BrowserWindowState) {
        if glanceManager.currentSession?.sourceTab?.id == tab.id {
            glanceManager.dismissGlance()
        }

        if windowState.isIncognito {
            closeIncognitoTab(tab, in: windowState)
            return
        }

        if tab.isShortcutLiveInstance {
            closeShortcutLiveTab(tab, in: windowState)
            return
        }

        let wasCurrent = windowState.currentTabId == tab.id
        let fallback = wasCurrent
            ? tabCloseFallbackPlanner.fallbackAfterClosingRegularTab(
                tab,
                in: windowState,
                tabStore: tabManager.runtimeStore
            )
            : nil
        if let fallback {
            selectTab(fallback, in: windowState)
            performImmediateVisualHandoffIfPossible(in: windowState)
        }
        tabManager.removeTab(tab.id)
        windowState.removeFromRegularTabHistory(tab.id)

        if wasCurrent {
            if fallback == nil {
                showEmptyState(in: windowState)
            }
        } else {
            persistWindowSession(for: windowState)
        }
    }
    isolated deinit {
        permissionEventOwner?.cancel()
        startupProtectionRestoreTask?.cancel()
        startupProtectionRestoreTask = nil
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
        windowSessionService.setupWindowState(windowState, delegate: self)
        extensionsModule.notifyWindowOpenedIfLoaded(windowState)
        reconcileStartupSessionIfPossible()
    }


    /// Set the active window state (called when a window gains focus)
    /// NOTE: This is called BY the WindowRegistry callback, so we don't call setActive again
    func setActiveWindowState(_ windowState: BrowserWindowState) {
        // DO NOT call windowRegistry?.setActive(windowState) here - that would cause infinite recursion!
        // This method is called FROM the onActiveWindowChange callback
        splitManager.refreshPublishedState(for: windowState.id)
        windowSessionService.setActiveWindowState(windowState, delegate: self)
        updateFindManagerCurrentTab()
        extensionsModule.notifyWindowFocusedIfLoaded(windowState)
        adoptProfileIfNeeded(for: windowState, context: .windowActivation)
        SumiNativeNowPlayingController.shared.scheduleRefresh(delayNanoseconds: 0)
        backgroundMediaOptimizationService.scheduleReconcile(reason: "window-activated")
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
                self?.windowState(displayingPermissionPageId: pageId)
            },
            reason: reason
        )
    }

    @MainActor
    private func windowState(displayingPermissionPageId pageId: String) -> BrowserWindowState? {
        guard let windowRegistry else { return nil }
        let normalizedPageId = pageId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if let activeWindow = windowRegistry.activeWindow,
           windowState(activeWindow, displaysPermissionPageId: normalizedPageId)
        {
            return activeWindow
        }

        return windowRegistry.allWindows.first {
            windowState($0, displaysPermissionPageId: normalizedPageId)
        }
    }

    @MainActor
    private func windowState(
        _ windowState: BrowserWindowState,
        displaysPermissionPageId pageId: String
    ) -> Bool {
        tabsForDisplay(in: windowState).contains { tab in
            tab.currentPermissionPageId()
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == pageId
        }
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
        applyTabSelection(
            tab,
            in: windowState,
            updateSpaceFromTab: true,
            updateTheme: true,
            rememberSelection: true,
            loadPolicy: loadPolicy
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
        let selectionApplication = WindowTabSelectionStateApplicator.apply(
            tab,
            to: windowState,
            updateSpaceFromTab: updateSpaceFromTab,
            rememberSelection: rememberSelection
        )

        let selectedTabChanged = selectionApplication.previousTabId != tab.id
        let requiresMaterialization = tab.isUnloaded && tab.requiresPrimaryWebView
        guard selectionApplication.stateDidChange || selectedTabChanged || requiresMaterialization else {
            return
        }

        SumiNativeNowPlayingController.shared.handleTabActivated(tab.id)
        tab.noteSuspensionAccess()
        dismissFloatingBarAfterSelection(in: windowState)
        splitManager.updateActiveSide(for: tab.id, in: windowState.id)

        syncWindowSpaceContext(in: windowState, animateTheme: updateTheme)

        if updateTheme && !windowState.isInteractiveSpaceTransition {
            if let currentSpace = space(for: windowState.currentSpaceId) {
                let animateWorkspaceTheme = selectionApplication.previousSpaceId != currentSpace.id
                updateWorkspaceTheme(
                    for: windowState,
                    to: currentSpace.workspaceTheme,
                    animate: animateWorkspaceTheme
                )
            } else {
                updateWorkspaceTheme(for: windowState, to: .default, animate: false)
            }
        }

        // Note: No need to track tab display ownership - each window shows its own current tab

        if tab.representsSumiSettingsSurface {
            sumiSettings?.applyNavigationFromSettingsSurfaceURL(tab.url)
        }

        // Load the tab in compositor if needed (reloads unloaded tabs)
        if tab.requiresPrimaryWebView {
            scheduleTabLoadIfNeeded(
                tab,
                in: windowState,
                loadPolicy: loadPolicy
            )
        }

        Task { @MainActor [weak tab] in
            guard let tab else { return }
            await tab.fetchFaviconForVisiblePresentation()
        }

        SumiNativeNowPlayingController.shared.scheduleRefresh(delayNanoseconds: 0)

        // Update find manager with new current tab
        updateFindManagerCurrentTab()

        schedulePrepareVisibleWebViews(for: windowState)
        refreshCompositor(for: windowState)

        let previousTab = selectionApplication.previousTabId.flatMap { previousId in
            tabManager.tab(for: previousId)
        }
        extensionsModule.notifyTabActivatedIfLoaded(newTab: tab, previous: previousTab)
        tabSuspensionService.scheduleProactiveTimerReconcile(reason: "tab-selection-changed")
        backgroundMediaOptimizationService.scheduleReconcile(reason: "tab-selection-changed")

        // Update global tab state for the active window
        if windowRegistry?.activeWindow?.id == windowState.id {
            // Only update the global state, don't trigger UI operations again
            tabManager.updateActiveTabState(tab)
        }
        if persistSelection {
            persistWindowSession(for: windowState)
        }
    }

    private func scheduleTabLoadIfNeeded(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        loadPolicy: TabSelectionLoadPolicy
    ) {
        if tab.isUnloaded {
            tab.beginLoadingPresentationIfNeeded()
        }

        guard canMaterializeNormalTabWebViewDuringStartup(tab) else { return }

        switch loadPolicy {
        case .immediate:
            materializeVisibleTabWebViewIfNeeded(tab, in: windowState)
        case .deferred:
            Task { @MainActor [weak self, weak tab] in
                guard let self, let tab else { return }
                await Task.yield()
                guard self.currentTab(for: windowState)?.id == tab.id else { return }
                self.materializeVisibleTabWebViewIfNeeded(tab, in: windowState)
                self.refreshCompositor(for: windowState)
            }
        }
    }

    func materializeVisibleTabWebViewIfNeeded(
        _ tab: Tab,
        in windowState: BrowserWindowState
    ) {
        compositorManager.markTabAccessed(tab.id)
        guard let webViewCoordinator else {
            tab.loadWebViewIfNeeded()
            return
        }
        if webViewCoordinator.getWebView(for: tab.id, in: windowState.id) == nil {
            _ = webViewCoordinator.getOrCreateWebView(for: tab, in: windowState.id)
        }
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
        guard !isBackForwardGestureActive(in: windowState) else {
            enqueueWindowMutationDuringHistorySwipe(
                .refreshCompositor,
                for: windowState
            )
            return
        }
        windowState.refreshCompositor()
    }

    @discardableResult
    func performImmediateVisualHandoffIfPossible(in windowState: BrowserWindowState) -> Bool {
        guard !isBackForwardGestureActive(in: windowState) else { return false }
        return webViewCoordinator?.performImmediateVisualHandoffIfPossible(in: windowState.id) ?? false
    }

    @discardableResult
    func prepareVisibleWebViews(for windowState: BrowserWindowState) -> Bool {
        guard let webViewCoordinator else { return false }
        return webViewCoordinator.prepareVisibleWebViews(
            for: windowState,
            browserManager: self
        )
    }

    func schedulePrepareVisibleWebViews(for windowState: BrowserWindowState) {
        guard !isBackForwardGestureActive(in: windowState) else {
            enqueueWindowMutationDuringHistorySwipe(
                .prepareVisibleWebViews,
                for: windowState
            )
            return
        }
        webViewCoordinator?.schedulePrepareVisibleWebViews(
            for: windowState,
            browserManager: self
        )
    }

    func space(for spaceId: UUID?) -> Space? {
        guard let spaceId else { return nil }
        return tabManager.spaces.first(where: { $0.id == spaceId })
    }

    private func syncWindowSpaceContext(in windowState: BrowserWindowState, animateTheme: Bool) {
        _ = animateTheme
        let currentSpace = space(for: windowState.currentSpaceId)
        let activeProfileId = sumiProfileRouter.activeProfileId(
            for: currentSpace,
            currentProfile: currentProfile
        )
        if windowState.currentProfileId != activeProfileId {
            windowState.currentProfileId = activeProfileId
        }
        updateProfileRuntimeStates(activeWindowState: windowState)
    }

    private func isBackForwardGestureActive(in windowState: BrowserWindowState) -> Bool {
        if webViewCoordinator?.hasActiveHistorySwipe(in: windowState.id) == true {
            return true
        }
        guard let current = currentTab(for: windowState) else { return false }
        return current.pendingMainFrameNavigationKind == .backForward
            || current.isFreezingNavigationStateDuringBackForwardGesture
    }

    func enqueueWindowMutationDuringHistorySwipe(
        _ kind: HistorySwipeDeferredWindowMutationKind,
        for windowState: BrowserWindowState
    ) {
        historySwipeWindowMutationQueue.enqueue(kind, for: windowState)
    }

    func flushWindowMutationsAfterHistorySwipe(in windowId: UUID) {
        guard let pendingMutations = historySwipeWindowMutationQueue.takePendingMutations(for: windowId) else {
            return
        }

        if pendingMutations.needsVisibleWebViewPreparation {
            _ = prepareVisibleWebViews(for: pendingMutations.windowState)
        }
        if pendingMutations.needsCompositorRefresh {
            pendingMutations.windowState.refreshCompositor()
        }
    }

    func cancelWindowMutationsAfterHistorySwipe(in windowId: UUID) {
        historySwipeWindowMutationQueue.cancel(in: windowId)
    }

    func hasValidCurrentSelection(in windowState: BrowserWindowState) -> Bool {
        shellSelectionService.hasValidCurrentSelection(
            in: windowState,
            tabStore: tabManager.runtimeStore
        )
    }

    /// Set active space for a specific window
    func setActiveSpace(_ space: Space, in windowState: BrowserWindowState) {
        let isSameSpace = windowState.currentSpaceId == space.id
        if isSameSpace,
           hasValidCurrentSelection(in: windowState),
           currentTab(for: windowState) != nil
        {
            floatingBarNavigationOwner.sanitize(
                in: windowState,
                hasValidCurrentSelection: true,
                actions: floatingBarActions
            )
            applySpaceContext(space, to: windowState)
            syncShortcutSelectionState(for: windowState)
            persistWindowSession(for: windowState)
            return
        }

        let selectedTargetTab = selectionTargetForSpaceActivation(
            in: space,
            windowState: windowState
        )
        let isActiveWindow = windowRegistry?.activeWindow?.id == windowState.id
        if isActiveWindow {
            tabManager.setActiveSpace(space, preferredTab: selectedTargetTab)
        }

        applySpaceContext(
            space,
            to: windowState
        )
        if windowState.spaceTransitionDestinationSpaceId == space.id {
            finishInteractiveSpaceTransition(to: space, in: windowState)
        } else if !windowState.isInteractiveSpaceTransition {
            updateWorkspaceTheme(for: windowState, to: space.workspaceTheme, animate: true)
        }

        if let selectedTargetTab {
            applyTabSelection(
                selectedTargetTab,
                in: windowState,
                updateSpaceFromTab: false,
                updateTheme: false,
                rememberSelection: true,
                persistSelection: false
            )
            performImmediateVisualHandoffIfPossible(in: windowState)
        } else {
            showEmptyState(in: windowState)
        }

        if isActiveWindow {
            adoptProfileIfNeeded(for: windowState, context: .spaceChange)
        }
        persistWindowSession(for: windowState)
        completePendingSplitGroupFocusIfReady(in: windowState, spaceId: space.id)
    }

    private func selectionTargetForSpaceActivation(
        in space: Space,
        windowState: BrowserWindowState
    ) -> Tab? {
        shellSelectionService.selectionTargetForSpaceActivation(
            in: space,
            windowState: windowState,
            tabStore: tabManager.runtimeStore
        )
    }

    private func applySpaceContext(
        _ space: Space,
        to windowState: BrowserWindowState
    ) {
        if windowState.currentSpaceId != space.id {
            windowState.currentSpaceId = space.id
        }
        let profileId = space.profileId ?? currentProfile?.id
        if windowState.currentProfileId != profileId {
            windowState.currentProfileId = profileId
        }
        updateProfileRuntimeStates(activeWindowState: windowState)
    }

    /// Validate and fix window states after tab/space mutations
    func validateWindowStates() {
        for (_, windowState) in windowRegistry?.windows ?? [:] {
            var needsUpdate = false
            // Check if current tab still exists
            if let currentTabId = windowState.currentTabId {
                if tabManager.tab(for: currentTabId) == nil {
                    windowState.currentTabId = nil
                    needsUpdate = true
                }
            }

            // Check if current space still exists
            if let currentSpaceId = windowState.currentSpaceId {
                if tabManager.spaces.first(where: { $0.id == currentSpaceId }) == nil {
                    windowState.currentSpaceId = tabManager.spaces.first?.id
                    needsUpdate = true
                }
            }

            if !windowState.isShowingEmptyState && !hasValidCurrentSelection(in: windowState) {
                if let currentSpace = space(for: windowState.currentSpaceId),
                   let preferred = preferredTabForSpace(currentSpace, in: windowState)
                {
                    applyTabSelection(
                        preferred,
                        in: windowState,
                        updateSpaceFromTab: false,
                        updateTheme: false,
                        rememberSelection: false,
                        persistSelection: false
                    )
                } else if let fallback = preferredTabForWindow(windowState) {
                    applyTabSelection(
                        fallback,
                        in: windowState,
                        updateSpaceFromTab: false,
                        updateTheme: false,
                        rememberSelection: false,
                        persistSelection: false
                    )
                } else {
                    showEmptyState(in: windowState)
                }
                needsUpdate = true
            }

            let previousShortcutSelection = windowState.currentShortcutPinId
            syncShortcutSelectionState(for: windowState)
            if previousShortcutSelection != windowState.currentShortcutPinId {
                needsUpdate = true
            }

            // If no current space, use the first available space
            if windowState.currentSpaceId == nil {
                windowState.currentSpaceId = tabManager.spaces.first?.id
                needsUpdate = true
            }

            if let currentSpace = space(for: windowState.currentSpaceId) {
                commitWorkspaceTheme(currentSpace.workspaceTheme, for: windowState)
                windowState.currentProfileId = currentSpace.profileId ?? currentProfile?.id
            } else if windowState.currentSpaceId == nil {
                commitWorkspaceTheme(.default, for: windowState)
                windowState.currentProfileId = currentProfile?.id
            }

            if needsUpdate {
                refreshCompositor(for: windowState)
                persistWindowSession(for: windowState)
            }
        }

        // Note: No need to clean up tab display owners since they're no longer used
    }

    func persistWindowSession(for windowState: BrowserWindowState) {
        persistWindowSessionNow(for: windowState)
    }

    func schedulePersistWindowSession(
        for windowState: BrowserWindowState,
        delayNanoseconds: UInt64 = 450_000_000
    ) {
        windowSessionService.schedulePersistWindowSession(
            for: windowState,
            delayNanoseconds: delayNanoseconds
        ) { [weak self] windowState in
            guard let self else {
                return
            }
            self.persistWindowSessionNow(for: windowState)
        }
    }

    func flushPendingWindowSessionPersistence() {
        windowSessionService.flushPendingWindowSessionPersistence { [weak self] windowState in
            guard let self else {
                return
            }
            persistWindowSessionNow(for: windowState)
        }
    }

    private func persistWindowSessionNow(for windowState: BrowserWindowState) {
        let signpostState = PerformanceTrace.beginInterval("WindowSession.persist")
        defer {
            PerformanceTrace.endInterval("WindowSession.persist", signpostState)
        }

        windowSessionService.persistWindowSession(for: windowState, delegate: self)
        refreshLastSessionWindowsStore(excludingWindowID: nil)
    }

    private func preferredTabForWindow(_ windowState: BrowserWindowState) -> Tab? {
        shellSelectionService.preferredTabForWindow(
            windowState,
            tabStore: tabManager.runtimeStore
        )
    }

    private func preferredRegularTabForWindow(_ windowState: BrowserWindowState) -> Tab? {
        shellSelectionService.preferredRegularTabForWindow(
            windowState,
            tabStore: tabManager.runtimeStore
        )
    }

    private func preferredTabForSpace(_ space: Space, in windowState: BrowserWindowState) -> Tab? {
        shellSelectionService.preferredTabForSpace(
            space,
            in: windowState,
            tabStore: tabManager.runtimeStore
        )
    }

    func syncShortcutSelectionState(for windowState: BrowserWindowState) {
        guard let currentTabId = windowState.currentTabId else {
            if !windowState.isShowingEmptyState {
                windowState.currentShortcutPinId = nil
                windowState.currentShortcutPinRole = nil
            }
            return
        }

        if let liveShortcutTab = tabManager.liveShortcutTabs(in: windowState.id)
            .first(where: { $0.id == currentTabId && $0.isShortcutLiveInstance })
        {
            windowState.currentShortcutPinId = liveShortcutTab.shortcutPinId
            windowState.currentShortcutPinRole = liveShortcutTab.shortcutPinRole
        } else {
            windowState.currentShortcutPinId = nil
            windowState.currentShortcutPinRole = nil
        }
    }

    private func closeShortcutLiveTab(_ tab: Tab, in windowState: BrowserWindowState) {
        guard tab.isShortcutLiveInstance else { return }
        if let group = tabManager.splitGroup(containing: tab.id)
            ?? tab.shortcutPinId.flatMap({ tabManager.splitGroup(containingPinId: $0) }) {
            if group.isShortcutHosted {
                captureClosedShortcutLiveInstance(tab, in: windowState)
                unloadShortcutHostedSplitGroup(group, in: windowState)
                return
            }
            if group.member(for: tab.id)?.isShortcutBacked == true
                || tab.shortcutPinId.flatMap({ group.member(forPinId: $0)?.isShortcutBacked }) == true {
                captureClosedShortcutLiveInstance(tab, in: windowState)
                restoreShortcutSplitMember(
                    tab.id,
                    from: group,
                    in: windowState,
                    preserveLiveInstance: false
                )
                return
            }
        }

        captureClosedShortcutLiveInstance(tab, in: windowState)

        let wasCurrent =
            windowState.currentTabId == tab.id
            || (tab.shortcutPinId != nil && windowState.currentShortcutPinId == tab.shortcutPinId)
        let fallback = wasCurrent
            ? tabCloseFallbackPlanner.fallbackAfterClosingShortcutLiveTab(
                tab,
                in: windowState,
                tabStore: tabManager.runtimeStore
            )
            : nil

        if let fallback {
            selectTab(fallback, in: windowState)
            performImmediateVisualHandoffIfPossible(in: windowState)
        }

        if let pinId = tab.shortcutPinId {
            tabManager.deactivateShortcutLiveTab(pinId: pinId, in: windowState.id)
        } else {
            tabManager.deactivateShortcutLiveTab(in: windowState.id)
        }

        guard wasCurrent else {
            persistWindowSession(for: windowState)
            return
        }

        if fallback != nil {
            persistWindowSession(for: windowState)
            return
        }

        windowState.currentShortcutPinId = nil
        windowState.currentShortcutPinRole = nil
        windowState.currentTabId = nil

        showEmptyState(in: windowState)
    }

    private func captureClosedShortcutLiveInstance(_ tab: Tab, in windowState: BrowserWindowState) {
        guard let pinId = tab.shortcutPinId,
              let pin = tabManager.shortcutPin(by: pinId)
        else {
            return
        }
        recentlyClosedManager.captureClosedShortcutLiveInstance(
            tab: tab,
            pin: pin,
            sourceWindowId: windowState.id
        )
    }

    private func closeIncognitoTab(_ tab: Tab, in windowState: BrowserWindowState) {
        tab.performComprehensiveWebViewCleanup()

        if let index = windowState.ephemeralTabs.firstIndex(where: { $0.id == tab.id }) {
            windowState.ephemeralTabs.remove(at: index)
        }

        if let nextTab = windowState.ephemeralTabs.last {
            selectTab(nextTab, in: windowState)
        } else {
            showEmptyState(in: windowState)
        }
    }

    func showEmptyState(in windowState: BrowserWindowState) {
        if let currentSpace = space(for: windowState.currentSpaceId),
           let selectableTab = selectionTargetForSpaceActivation(
                in: currentSpace,
                windowState: windowState
           ) {
            applyTabSelection(
                selectableTab,
                in: windowState,
                updateSpaceFromTab: false,
                updateTheme: false,
                rememberSelection: false
            )
            return
        }

        windowState.currentTabId = nil
        windowState.currentShortcutPinId = nil
        windowState.currentShortcutPinRole = nil
        windowState.isShowingEmptyState = true
        updateProfileRuntimeStates(activeWindowState: windowState)
        findManager.updateCurrentTab(nil)
        refreshCompositor(for: windowState)
        persistWindowSession(for: windowState)
        showNewTabFloatingBar(in: windowState)
    }

    private func updateProfileRuntimeStates(activeWindowState: BrowserWindowState? = nil) {
        let focusedWindow = activeWindowState ?? windowRegistry?.activeWindow
        let focusedWindowId = focusedWindow?.id

        for space in tabManager.spaces {
            let isFocusedSpace = focusedWindow?.currentSpaceId == space.id
            let hasRegularTabs = !tabManager.tabs(in: space).isEmpty
            let hasPinnedLiveShortcut: Bool
            if let windowId = focusedWindowId {
                hasPinnedLiveShortcut = tabManager.liveShortcutTabs(in: windowId)
                    .contains(where: { $0.spaceId == space.id && $0.shortcutPinRole != .essential })
            } else {
                hasPinnedLiveShortcut = false
            }
            let hasActiveShortcutSelection = focusedWindow?.selectedShortcutPinForSpace[space.id] != nil

            if isFocusedSpace {
                space.profileRuntimeState = hasRegularTabs || hasPinnedLiveShortcut || hasActiveShortcutSelection
                    ? .active
                    : .dormant
            } else if hasRegularTabs || hasPinnedLiveShortcut || hasActiveShortcutSelection {
                space.profileRuntimeState = .loadedInactive
            } else {
                space.profileRuntimeState = .dormant
            }
        }
    }
}

extension BrowserManager: WindowSessionServiceDelegate {
    func syncBrowserManagerSidebarCachesFromWindow(_ windowState: BrowserWindowState) {
        savedSidebarWidth = windowState.savedSidebarWidth
        savedSidebarVisibility = windowState.isSidebarVisible
    }
}

extension BrowserManager: SumiProfileRoutingSupport {}

extension BrowserManager: BrowserAppLifecycleHandling {
    func handleApplicationWillResignActive() {
        backgroundMediaOptimizationService.scheduleReconcile(reason: "app-will-resign-active")

        guard let geolocationProvider,
              geolocationProvider.currentState == .active
        else { return }

        didPauseGeolocationForApplicationBackground = geolocationProvider.pause() == .paused
    }

    func handleApplicationDidBecomeActive() {
        backgroundMediaOptimizationService.scheduleReconcile(reason: "app-did-become-active")

        guard didPauseGeolocationForApplicationBackground else { return }

        didPauseGeolocationForApplicationBackground = false
        _ = geolocationProvider?.resume()
    }

    func handleWindowVisibilityChanged(_ windowState: BrowserWindowState) {
        _ = windowState
        backgroundMediaOptimizationService.scheduleReconcile(reason: "window-visibility-changed")
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
    ExternalURLHandling, BrowserPersistenceHandling, WebViewLookup
{
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
        return indices.contains(index) ? self[index] : nil
    }
}
