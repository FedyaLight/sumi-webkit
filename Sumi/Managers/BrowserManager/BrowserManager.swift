//
//  BrowserManager.swift
//  Sumi
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import AppKit
import Combine
import SwiftData
import SwiftUI
import WebKit

struct WindowTabSelectionTargetState: Equatable {
    enum ShortcutMemoryUpdate: Equatable {
        case none
        case set(spaceId: UUID, pinId: UUID)
        case clear(spaceId: UUID)
    }

    enum RegularTabMemoryUpdate: Equatable {
        case none
        case set(spaceId: UUID, tabId: UUID)
    }

    let currentTabId: UUID?
    let currentSpaceId: UUID?
    let currentShortcutPinId: UUID?
    let currentShortcutPinRole: ShortcutPinRole?
    let isShowingEmptyState: Bool
    let shortcutMemoryUpdate: ShortcutMemoryUpdate
    let regularTabMemoryUpdate: RegularTabMemoryUpdate
}

enum WindowTabSelectionPolicy {
    static func targetState(
        tabId: UUID,
        tabSpaceId: UUID?,
        isShortcutLiveInstance: Bool,
        shortcutPinId: UUID?,
        shortcutPinRole: ShortcutPinRole?,
        currentSpaceId: UUID?,
        updateSpaceFromTab: Bool,
        rememberSelection: Bool
    ) -> WindowTabSelectionTargetState {
        var resolvedSpaceId = currentSpaceId
        if updateSpaceFromTab,
           let tabSpaceId,
           currentSpaceId != tabSpaceId,
           !(isShortcutLiveInstance && shortcutPinRole == .essential) {
            resolvedSpaceId = tabSpaceId
        }

        let resolvedShortcutPinId = isShortcutLiveInstance ? shortcutPinId : nil
        let resolvedShortcutPinRole = isShortcutLiveInstance ? shortcutPinRole : nil

        let shortcutMemoryUpdate: WindowTabSelectionTargetState.ShortcutMemoryUpdate
        if rememberSelection, let resolvedSpaceId {
            if isShortcutLiveInstance,
               shortcutPinRole != .essential,
               let shortcutPinId {
                shortcutMemoryUpdate = .set(spaceId: resolvedSpaceId, pinId: shortcutPinId)
            } else if !isShortcutLiveInstance {
                shortcutMemoryUpdate = .clear(spaceId: resolvedSpaceId)
            } else {
                shortcutMemoryUpdate = .none
            }
        } else {
            shortcutMemoryUpdate = .none
        }

        let regularTabMemoryUpdate: WindowTabSelectionTargetState.RegularTabMemoryUpdate
        if rememberSelection, let resolvedSpaceId, !isShortcutLiveInstance {
            regularTabMemoryUpdate = .set(spaceId: resolvedSpaceId, tabId: tabId)
        } else {
            regularTabMemoryUpdate = .none
        }

        return WindowTabSelectionTargetState(
            currentTabId: tabId,
            currentSpaceId: resolvedSpaceId,
            currentShortcutPinId: resolvedShortcutPinId,
            currentShortcutPinRole: resolvedShortcutPinRole,
            isShowingEmptyState: false,
            shortcutMemoryUpdate: shortcutMemoryUpdate,
            regularTabMemoryUpdate: regularTabMemoryUpdate
        )
    }
}

enum HistorySwipeDeferredWindowMutationKind: Hashable {
    case refreshCompositor
    case prepareVisibleWebViews
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
        WorkspaceTheme.decode(space.workspaceThemeData ?? Data())
            ?? WorkspaceTheme(gradient: SpaceGradient.decode(space.gradientData))
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

    // Tab closure undo notification
    @Published var showTabClosureToast: Bool = false
    @Published var tabClosureToastCount: Int = 0
    @Published var workspaceThemePickerSession: WorkspaceThemePickerSession?
    @Published var tabStructuralRevision: UInt = 0

    var modelContext: ModelContext
    let startupWorkspaceTheme: WorkspaceTheme?
    let moduleRegistry: SumiModuleRegistry
    let trackingProtectionModule: SumiTrackingProtectionModule
    let adBlockingModule: SumiAdBlockingModule
    let extensionsModule: SumiExtensionsModule
    let userscriptsModule: SumiUserscriptsModule
    var extensionSurfaceStore: BrowserExtensionSurfaceStore {
        extensionsModule.surfaceStore
    }
    var tabManager: TabManager
    var profileManager: ProfileManager
    var dialogManager: DialogManager
    var downloadManager: DownloadManager
    let downloadsPopoverPresenter: DownloadsPopoverPresenter
    let workspaceThemePickerPopoverPresenter: WorkspaceThemePickerPopoverPresenter
    var authenticationManager: AuthenticationManager
    var historyManager: HistoryManager
    var bookmarkManager: SumiBookmarkManager
    var recentlyClosedManager: RecentlyClosedManager
    var lastSessionWindowsStore: LastSessionWindowsStore
    var compositorManager: TabCompositorManager
    let tabSuspensionService: TabSuspensionService
    var splitManager: SplitViewManager
    var workspaceThemeCoordinator: WorkspaceThemeCoordinator
    var findManager: FindManager
    let systemPermissionService: any SumiSystemPermissionService
    let permissionCoordinator: any SumiPermissionCoordinating
    let runtimePermissionController: any SumiRuntimePermissionControlling
    let webKitPermissionBridge: SumiWebKitPermissionBridge
    let webKitGeolocationBridge: SumiWebKitGeolocationBridge
    let notificationPermissionBridge: SumiNotificationPermissionBridge
    let filePickerPermissionBridge: SumiFilePickerPermissionBridge
    let storageAccessPermissionBridge: SumiStorageAccessPermissionBridge
    let permissionIndicatorEventStore: SumiPermissionIndicatorEventStore
    let permissionRecentActivityStore: SumiPermissionRecentActivityStore
    let permissionCleanupService: SumiPermissionCleanupService
    let blockedPopupStore: SumiBlockedPopupStore
    let popupPermissionBridge: SumiPopupPermissionBridge
    let externalAppResolver: any SumiExternalAppResolving
    let externalSchemeSessionStore: SumiExternalSchemeSessionStore
    let externalSchemePermissionBridge: SumiExternalSchemePermissionBridge
    let permissionLifecycleController: SumiPermissionGrantLifecycleController
    let permissionSidebarPinningController = SumiPermissionSidebarPinningController()
    private var permissionRecentActivityTask: Task<Void, Never>?
    private var permissionSidebarPinningTask: Task<Void, Never>?
    var zoomManager = ZoomManager()
    weak var sumiSettings: SumiSettingsService? {
        didSet {
            tabSuspensionService.rebuildProactiveTimers(reason: "settings-attached")
            reconcileStartupSessionIfPossible()
        }
    }
    let sumiProfileRouter = SumiProfileRouter()
    let profileMaintenanceService = SumiProfileMaintenanceService()
    let windowShellService = BrowserWindowShellService()
    let workspaceAppearanceService = WorkspaceAppearanceService()
    let privacyService = BrowserPrivacyService()

    lazy var shellSelectionService = ShellSelectionService { [weak self] windowId in
        guard let self else { return (nil, nil) }
        return (
            left: self.splitManager.leftTabId(for: windowId),
            right: self.splitManager.rightTabId(for: windowId)
        )
    }
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

    var externalMiniWindowManager = ExternalMiniWindowManager()
    @Published var glanceManager = GlanceManager()

    /// Shared with app shell / `ContentView` via `.environment`; retained strongly so routing never sees a dangling coordinator.
    /// After `SumiApp.setupApplicationLifecycle` runs, this must be set before any WebView routing or coordinator cleanup.
    var webViewCoordinator: WebViewCoordinator? {
        didSet {
            if oldValue?.browserManager === self {
                oldValue?.browserManager = nil
            }
            webViewCoordinator?.browserManager = self
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
    private var pendingWindowSessionPersistTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingWindowSessionPersistStates: [UUID: BrowserWindowState] = [:]
    private var pendingUserActivationsByWindow: [UUID: PendingUserTabActivation] = [:]
    private var userActivationFlushScheduledWindows: Set<UUID> = []
    private var deferredHistorySwipeWindowMutationsByWindow: [UUID: DeferredHistorySwipeWindowMutations] = [:]

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
        // Explicit injection seams keep module-boundary tests focused without constructing optional runtimes at startup.
        trackingProtectionModule: SumiTrackingProtectionModule? = nil,
        adBlockingModule: SumiAdBlockingModule? = nil,
        extensionsModule: SumiExtensionsModule? = nil,
        userscriptsModule: SumiUserscriptsModule? = nil,
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
        permissionCleanupService: SumiPermissionCleanupService? = nil,
        blockedPopupStore: SumiBlockedPopupStore? = nil,
        popupPermissionBridge: SumiPopupPermissionBridge? = nil,
        externalAppResolver: (any SumiExternalAppResolving)? = nil,
        externalSchemeSessionStore: SumiExternalSchemeSessionStore? = nil,
        externalSchemePermissionBridge: SumiExternalSchemePermissionBridge? = nil
    ) {
        // Phase 1: initialize all stored properties
        let startupModelContext = SumiStartupPersistence.shared.container.mainContext
        let systemPermissionService = systemPermissionService ?? MacSumiSystemPermissionService()
        let persistentPermissionStore = SwiftDataPermissionStore(
            container: SumiStartupPersistence.shared.container
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
        self.trackingProtectionModule = trackingProtectionModule
            ?? SumiTrackingProtectionModule(moduleRegistry: moduleRegistry)
        self.adBlockingModule = adBlockingModule
            ?? SumiAdBlockingModule(moduleRegistry: moduleRegistry)
        self.userscriptsModule = userscriptsModule
            ?? SumiUserscriptsModule(
                moduleRegistry: moduleRegistry,
                context: startupModelContext
            )
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
        self.dialogManager = DialogManager()
        self.downloadManager = DownloadManager()
        self.downloadsPopoverPresenter = DownloadsPopoverPresenter()
        self.workspaceThemePickerPopoverPresenter = WorkspaceThemePickerPopoverPresenter()
        self.authenticationManager = AuthenticationManager()
        // Initialize managers with current profile context for isolation
        self.historyManager = HistoryManager(context: startupModelContext, profileId: initialProfile?.id)
        self.bookmarkManager = SumiBookmarkManager()
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
        self.permissionCleanupService = permissionCleanupService
        self.blockedPopupStore = blockedPopupStore
        self.popupPermissionBridge = popupPermissionBridge
            ?? SumiPopupPermissionBridge(
                coordinator: permissionCoordinator,
                blockedPopupStore: blockedPopupStore
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
        self.permissionRecentActivityTask = Task { @MainActor [permissionCoordinator, permissionRecentActivityStore] in
            let events = await permissionCoordinator.events()
            for await event in events {
                permissionRecentActivityStore.record(event)
            }
        }
        self.permissionSidebarPinningTask = Task { @MainActor [weak self, permissionCoordinator] in
            let events = await permissionCoordinator.events()
            for await _ in events {
                await self?.reconcilePermissionSidebarPins(reason: "permission-event")
            }
        }

        // Phase 2: wire dependencies and perform side effects (safe to use self)
        self.compositorManager.browserManager = self
        self.tabSuspensionService.attach(browserManager: self)
        self.splitManager.browserManager = self
        self.splitManager.windowRegistry = self.windowRegistry
        // Note: settingsManager will be injected later, so we skip initialization here
        self.tabManager.browserManager = self
        self.tabManager.reattachBrowserManager(self)
        self.downloadManager.browserManager = self
        self.extensionsModule.attach(browserManager: self)
        self.userscriptsModule.attach(browserManager: self)
        bindTabManagerStructuralUpdates()
        self.externalMiniWindowManager.attach(browserManager: self)
        self.glanceManager.attach(browserManager: self)
        self.authenticationManager.attach(browserManager: self)

        self.dialogManager.onWillPresentModal = { [weak self] in
            self?.requestCollapsedSidebarOverlayDismissal()
            self?.dismissWorkspaceThemePickerIfNeededDiscarding()
        }

        tabManagerLoadObserverToken = NotificationCenter.default.addObserver(
            forName: .tabManagerDidLoadInitialData,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTabManagerDataLoaded()
            }
        }
    }

    private func bindTabManagerStructuralUpdates() {
        structuralChangeCancellable = tabManager.structuralChanges
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.tabStructuralRevision &+= 1
                self?.tabSuspensionService.scheduleProactiveTimerReconcile(
                    reason: "tab-structure-changed"
                )
            }
    }

    func showBrowserExtensionsUnavailableAlert(
        extensionName: String? = nil
    ) {
        let alert = NSAlert()
        alert.messageText = extensionName.map {
            "\($0) is currently unavailable"
        } ?? "Browser extensions are currently unavailable"
        alert.informativeText =
            "Sumi could not open the requested Safari extension action. Check Settings > Extensions to confirm the extension is installed, enabled, and supported on this macOS build."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    /// Called when TabManager finishes loading initial data from persistence
    private func handleTabManagerDataLoaded() {
        windowSessionService.handleTabManagerDataLoaded(delegate: self)
        reconcileStartupSessionIfPossible()
    }

    // MARK: - Profile Switching
    struct ProfileSwitchToast: Equatable {
        let toProfile: Profile
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
                if animateTransition {
                    self.isTransitioningProfile = true
                } else {
                    self.isTransitioningProfile = false
                }
                self.currentProfile = profile
                self.windowRegistry?.activeWindow?.currentProfileId = profile.id
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


    func focusFloatingBarForActiveWindow(
        prefill: String = "",
        navigateCurrentTab: Bool = false
    ) {
        guard let activeWindow = windowRegistry?.activeWindow else { return }
        focusFloatingBar(
            in: activeWindow,
            prefill: prefill,
            navigateCurrentTab: navigateCurrentTab
        )
    }

    func focusFloatingBar(
        in windowState: BrowserWindowState,
        prefill: String = "",
        navigateCurrentTab: Bool = false
    ) {
        let shouldOverrideDraft = !prefill.isEmpty
            || windowState.floatingBarDraftText.isEmpty
            || navigateCurrentTab
        if shouldOverrideDraft {
            windowState.floatingBarDraftText = prefill
            windowState.floatingBarDraftNavigatesCurrentTab = navigateCurrentTab
        }
        windowState.floatingBarPresentationReason = .keyboard
        windowState.isFloatingBarVisible = true
        dismissWorkspaceThemePickerIfNeededDiscarding()
        persistWindowSession(for: windowState)
    }

    func showNewTabFloatingBar(in windowState: BrowserWindowState) {
        windowState.floatingBarDraftText = ""
        windowState.floatingBarDraftNavigatesCurrentTab = false
        windowState.floatingBarPresentationReason = .emptySpace
        windowState.isFloatingBarVisible = true
        dismissWorkspaceThemePickerIfNeededDiscarding()
        persistWindowSession(for: windowState)
    }

    func updateFloatingBarDraft(
        in windowState: BrowserWindowState,
        text: String
    ) {
        guard windowState.floatingBarDraftText != text else { return }
        windowState.floatingBarDraftText = text
        schedulePersistWindowSession(for: windowState)
    }

    func dismissFloatingBar(
        in windowState: BrowserWindowState,
        preserveDraft: Bool
    ) {
        windowState.floatingBarPresentationReason = .none
        windowState.isFloatingBarVisible = false
        if !preserveDraft {
            windowState.floatingBarDraftText = ""
            windowState.floatingBarDraftNavigatesCurrentTab = false
        }
        persistWindowSession(for: windowState)
    }

    func openFloatingBarSuggestion(
        _ suggestion: SearchManager.SearchSuggestion,
        in windowState: BrowserWindowState
    ) {
        switch suggestion.type {
        case .tab(let existingTab):
            selectTab(existingTab, in: windowState)
            RuntimeDiagnostics.debug(
                "Switched to existing tab: \(existingTab.name)",
                category: "FloatingBar"
            )
        case .history(let historyEntry):
            if windowState.floatingBarDraftNavigatesCurrentTab,
               currentTab(for: windowState) != nil
            {
                currentTab(for: windowState)?.loadURL(historyEntry.url.absoluteString)
                RuntimeDiagnostics.debug(
                    "Navigated current tab to history URL: \(historyEntry.url)",
                    category: "FloatingBar"
                )
            } else {
                createNewTab(in: windowState, url: historyEntry.url.absoluteString)
                RuntimeDiagnostics.debug(
                    "Created new tab from history in window \(windowState.id)",
                    category: "FloatingBar"
                )
            }
        case .bookmark(let bookmark):
            if windowState.floatingBarDraftNavigatesCurrentTab,
               currentTab(for: windowState) != nil
            {
                currentTab(for: windowState)?.loadURL(bookmark.url.absoluteString)
                RuntimeDiagnostics.debug(
                    "Navigated current tab to bookmark URL: \(bookmark.url)",
                    category: "FloatingBar"
                )
            } else {
                createNewTab(in: windowState, url: bookmark.url.absoluteString)
                RuntimeDiagnostics.debug(
                    "Created new tab from bookmark in window \(windowState.id)",
                    category: "FloatingBar"
                )
            }
        case .url, .search:
            if windowState.floatingBarDraftNavigatesCurrentTab,
               currentTab(for: windowState) != nil
            {
                currentTab(for: windowState)?.navigateToURL(suggestion.text)
                RuntimeDiagnostics.debug(
                    "Navigated current tab to: \(suggestion.text)",
                    category: "FloatingBar"
                )
            } else {
                let template = sumiSettings?.resolvedSearchEngineTemplate ?? SearchProvider.google.queryTemplate
                let resolved = normalizeURL(suggestion.text, queryTemplate: template)
                createNewTab(in: windowState, url: resolved)
                RuntimeDiagnostics.debug(
                    "Created new tab in window \(windowState.id)",
                    category: "FloatingBar"
                )
            }
        }
    }

    private func dismissFloatingBarAfterSelection(in windowState: BrowserWindowState) {
        let preserveDraft = windowState.floatingBarPresentationReason != .emptySpace
        dismissFloatingBar(in: windowState, preserveDraft: preserveDraft)
    }

    private func clearEmptyStatePresentationIfNeeded(in windowState: BrowserWindowState) {
        guard windowState.isShowingEmptyState
            || windowState.floatingBarPresentationReason == .emptySpace
        else { return }

        windowState.isShowingEmptyState = false
        dismissFloatingBar(in: windowState, preserveDraft: false)
    }

    func sanitizeFloatingBarState(in windowState: BrowserWindowState) {
        if hasValidCurrentSelection(in: windowState) {
            clearEmptyStatePresentationIfNeeded(in: windowState)
        } else if windowState.isShowingEmptyState {
            if windowState.floatingBarPresentationReason == .none {
                windowState.floatingBarPresentationReason = .emptySpace
            }
        } else {
            windowState.floatingBarPresentationReason = .none
        }
    }

    func showFindBar() {
        findManager.showFindBar(for: currentTabForActiveWindow())
    }

    func updateFindManagerCurrentTab() {
        // Update the current tab for find manager
        findManager.updateCurrentTab(currentTabForActiveWindow())
    }

    enum TabSelectionLoadPolicy {
        case immediate
        case deferred
    }

    private struct PendingUserTabActivation {
        let tabId: UUID
        let loadPolicy: TabSelectionLoadPolicy
    }

    enum TabOpenActivationPolicy {
        case foreground(windowState: BrowserWindowState, loadPolicy: TabSelectionLoadPolicy)
        case background
    }

    struct TabOpenContext {
        let windowState: BrowserWindowState?
        let sourceTab: Tab?
        let preferredSpaceId: UUID?
        let activationPolicy: TabOpenActivationPolicy

        static func foreground(
            windowState: BrowserWindowState,
            sourceTab: Tab? = nil,
            preferredSpaceId: UUID? = nil,
            loadPolicy: TabSelectionLoadPolicy = .deferred
        ) -> TabOpenContext {
            TabOpenContext(
                windowState: windowState,
                sourceTab: sourceTab,
                preferredSpaceId: preferredSpaceId,
                activationPolicy: .foreground(windowState: windowState, loadPolicy: loadPolicy)
            )
        }

        static func background(
            windowState: BrowserWindowState? = nil,
            sourceTab: Tab? = nil,
            preferredSpaceId: UUID? = nil
        ) -> TabOpenContext {
            TabOpenContext(
                windowState: windowState,
                sourceTab: sourceTab,
                preferredSpaceId: preferredSpaceId,
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
        let newTab = tabManager.createNewTab(
            url: url,
            in: targetSpace,
            activate: shouldActivateInTabManager
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
    ) -> Tab {
        let context = TabOpenContext.background(
            windowState: windowState(containing: sourceTab),
            sourceTab: sourceTab,
            preferredSpaceId: sourceTab.spaceId
        )
        let targetSpace = resolvedTabOpenSpace(for: context)
        return tabManager.createPopupTab(
            in: targetSpace,
            activate: activate,
            webViewConfigurationOverride: webViewConfigurationOverride
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

        let targetURL: URL
        switch pane {
        case .userScripts:
            sumiSettings?.extensionsSettingsSubPane = .userScripts
            sumiSettings?.currentSettingsTab = .extensions
            targetURL = SumiSurface.settingsSurfaceURL(paneQuery: SettingsTabs.userScripts.paneQueryValue)
        case .extensions:
            sumiSettings?.extensionsSettingsSubPane = .safariExtensions
            sumiSettings?.currentSettingsTab = .extensions
            targetURL = pane.settingsSurfaceURL
        default:
            sumiSettings?.currentSettingsTab = pane
            if pane == .privacy {
                sumiSettings?.privacySettingsRoute = .overview
            }
            targetURL = pane.settingsSurfaceURL
        }

        openSettingsSurface(targetURL: targetURL, in: windowState)
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

        sumiSettings?.currentSettingsTab = .privacy
        sumiSettings?.privacySettingsRoute = .siteSettings(filter)
        let targetURL = sumiSettings?.settingsSurfaceURLForCurrentNavigation()
            ?? SumiSurface.settingsSurfaceURL(
                paneQuery: SettingsTabs.privacy.paneQueryValue,
                extraQueryItems: [URLQueryItem(name: "section", value: "siteSettings")]
            )
        openSettingsSurface(targetURL: targetURL, in: windowState)
    }

    private func openSettingsSurface(targetURL: URL, in windowState: BrowserWindowState) {
        if windowState.isIncognito, let profile = windowState.ephemeralProfile {
            if let existing = windowState.ephemeralTabs.first(where: { $0.representsSumiSettingsSurface }) {
                existing.url = targetURL
                existing.name = "Settings"
                existing.favicon = Image(systemName: SumiSurface.settingsTabFaviconSystemImageName)
                existing.faviconIsTemplateGlobePlaceholder = false
                selectTab(existing, in: windowState)
            } else {
                let newTab = tabManager.createEphemeralTab(
                    url: targetURL,
                    in: windowState,
                    profile: profile
                )
                newTab.name = "Settings"
                newTab.favicon = Image(systemName: SumiSurface.settingsTabFaviconSystemImageName)
                newTab.faviconIsTemplateGlobePlaceholder = false
                selectTab(newTab, in: windowState)
            }
            windowState.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let targetSpace =
            windowState.currentSpaceId.flatMap { id in
                tabManager.spaces.first(where: { $0.id == id })
            }
            ?? windowState.currentProfileId.flatMap { pid in
                tabManager.spaces.first(where: { $0.profileId == pid })
            }
            ?? tabManager.currentSpace

        let spaceIdForLookup = targetSpace?.id ?? tabManager.currentSpace?.id
        if let sid = spaceIdForLookup,
           let existing = (tabManager.tabsBySpace[sid] ?? []).first(where: { $0.representsSumiSettingsSurface })
        {
            existing.url = targetURL
            existing.name = "Settings"
            existing.favicon = Image(systemName: SumiSurface.settingsTabFaviconSystemImageName)
            existing.faviconIsTemplateGlobePlaceholder = false
            selectTab(existing, in: windowState)
            windowState.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let newTab = openNewTab(
            url: targetURL.absoluteString,
            context: .foreground(
                windowState: windowState,
                preferredSpaceId: targetSpace?.id,
                loadPolicy: .deferred
            )
        )
        newTab.name = "Settings"
        newTab.favicon = Image(systemName: SumiSurface.settingsTabFaviconSystemImageName)
        newTab.faviconIsTemplateGlobePlaceholder = false
        windowState.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        let currentTabIndex = tabManager.tabs.firstIndex(where: { $0.id == tab.id }) ?? 0
        let insertIndex = currentTabIndex + 1

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

        tabManager.addTab(newTab)
        if let spaceId = targetSpace?.id {
            tabManager.reorderRegularTabs(newTab, in: spaceId, to: insertIndex)
        }
        selectTab(newTab, in: windowState)
    }

    func closeCurrentTab() {
        if let activeWindow = windowRegistry?.activeWindow,
            activeWindow.isFloatingBarVisible
        {
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
        if windowState.isIncognito {
            closeIncognitoTab(tab, in: windowState)
            return
        }

        if tab.isShortcutLiveInstance {
            closeShortcutLiveTab(tab, in: windowState)
            return
        }

        let wasCurrent = windowState.currentTabId == tab.id
        let fallback = wasCurrent ? fallbackRegularTab(afterClosing: tab, in: windowState) : nil
        tabManager.removeTab(tab.id)
        windowState.removeFromRegularTabHistory(tab.id)

        if wasCurrent {
            if let fallback {
                selectTab(fallback, in: windowState)
            } else {
                showEmptyState(in: windowState)
            }
        } else {
            persistWindowSession(for: windowState)
        }
    }
    isolated deinit {
        permissionRecentActivityTask?.cancel()
        permissionSidebarPinningTask?.cancel()
        pendingWindowSessionPersistTasks.values.forEach { $0.cancel() }
        pendingWindowSessionPersistTasks.removeAll()
        pendingWindowSessionPersistStates.removeAll()
        if let token = tabManagerLoadObserverToken {
            NotificationCenter.default.removeObserver(token)
        }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Window State Management

    /// Register a new window state and attach shell services (`WindowSessionService`, extensions).
    /// Window ↔ `NSWindow` association uses heuristics until window creation is fully owned by the shell layer.
    func setupWindowState(_ windowState: BrowserWindowState) {
        windowSessionService.setupWindowState(windowState, delegate: self)
        extensionsModule.notifyWindowOpenedIfLoaded(windowState)
        reconcileStartupSessionIfPossible()

        if let window = NSApplication.shared.windows.first(where: {
            $0.contentView?.subviews.contains(where: {
                ($0 as? NSHostingView<ContentView>) != nil
            }) ?? false
        }) {
            windowState.window = window
        }
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

            if splitManager.leftTabId(for: windowState.id) == tab.id {
                return true
            }

            if splitManager.rightTabId(for: windowState.id) == tab.id {
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
        pendingUserActivationsByWindow[windowState.id] = PendingUserTabActivation(
            tabId: tab.id,
            loadPolicy: loadPolicy
        )

        guard !userActivationFlushScheduledWindows.contains(windowState.id) else { return }
        userActivationFlushScheduledWindows.insert(windowState.id)

        DispatchQueue.main.async { [weak self] in
            Task { @MainActor [weak self] in
                self?.flushPendingUserTabActivation(for: windowState.id)
            }
        }
    }

    private func flushPendingUserTabActivation(for windowId: UUID) {
        userActivationFlushScheduledWindows.remove(windowId)
        guard let activation = pendingUserActivationsByWindow.removeValue(forKey: windowId),
              let windowState = windowRegistry?.windows[windowId],
              let tab = resolvedTab(for: activation.tabId, in: windowState)
        else {
            return
        }

        applyTabSelection(
            tab,
            in: windowState,
            updateSpaceFromTab: true,
            updateTheme: true,
            rememberSelection: true,
            loadPolicy: activation.loadPolicy
        )
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
        let previousTabId = windowState.currentTabId
        let previousSpaceId = windowState.currentSpaceId
        let targetState = WindowTabSelectionPolicy.targetState(
            tabId: tab.id,
            tabSpaceId: tab.spaceId,
            isShortcutLiveInstance: tab.isShortcutLiveInstance,
            shortcutPinId: tab.shortcutPinId,
            shortcutPinRole: tab.shortcutPinRole,
            currentSpaceId: windowState.currentSpaceId,
            updateSpaceFromTab: updateSpaceFromTab,
            rememberSelection: rememberSelection
        )

        if tab.representsSumiNativeSurface, splitManager.isSplit(for: windowState.id) {
            splitManager.exitSplit(keep: .left, for: windowState.id)
        }

        var stateDidChange = false
        stateDidChange = assignIfChanged(\.currentTabId, targetState.currentTabId, in: windowState) || stateDidChange
        stateDidChange = assignIfChanged(\.isShowingEmptyState, targetState.isShowingEmptyState, in: windowState) || stateDidChange
        stateDidChange = assignIfChanged(\.currentSpaceId, targetState.currentSpaceId, in: windowState) || stateDidChange
        stateDidChange = assignIfChanged(\.currentShortcutPinId, targetState.currentShortcutPinId, in: windowState) || stateDidChange
        stateDidChange = assignIfChanged(\.currentShortcutPinRole, targetState.currentShortcutPinRole, in: windowState) || stateDidChange
        stateDidChange = applyShortcutMemoryUpdate(targetState.shortcutMemoryUpdate, to: windowState) || stateDidChange
        stateDidChange = applyRegularTabMemoryUpdate(targetState.regularTabMemoryUpdate, to: windowState) || stateDidChange

        let selectedTabChanged = previousTabId != tab.id
        let requiresMaterialization = tab.isUnloaded && tab.requiresPrimaryWebView
        guard stateDidChange || selectedTabChanged || requiresMaterialization else {
            return
        }

        SumiNativeNowPlayingController.shared.handleTabActivated(tab.id)
        tab.noteSuspensionAccess()
        dismissFloatingBarAfterSelection(in: windowState)
        splitManager.updateActiveSide(for: tab.id, in: windowState.id)

        syncWindowSpaceContext(in: windowState, animateTheme: updateTheme)

        if updateTheme && !windowState.isInteractiveSpaceTransition {
            if let currentSpace = space(for: windowState.currentSpaceId) {
                let animateWorkspaceTheme = previousSpaceId != currentSpace.id
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

        let previousTab = previousTabId.flatMap { previousId in
            tabManager.tab(for: previousId)
        }
        extensionsModule.notifyTabActivatedIfLoaded(newTab: tab, previous: previousTab)
        tabSuspensionService.reconcileProactiveTimers(reason: "tab-selection-changed")

        // Update global tab state for the active window
        if windowRegistry?.activeWindow?.id == windowState.id {
            // Only update the global state, don't trigger UI operations again
            tabManager.updateActiveTabState(tab)
        }
        if persistSelection {
            persistWindowSession(for: windowState)
        }
    }

    @discardableResult
    private func assignIfChanged<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<BrowserWindowState, Value>,
        _ value: Value,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard windowState[keyPath: keyPath] != value else { return false }
        windowState[keyPath: keyPath] = value
        return true
    }

    @discardableResult
    private func applyShortcutMemoryUpdate(
        _ update: WindowTabSelectionTargetState.ShortcutMemoryUpdate,
        to windowState: BrowserWindowState
    ) -> Bool {
        switch update {
        case .none:
            return false
        case let .set(spaceId, pinId):
            guard windowState.selectedShortcutPinForSpace[spaceId] != pinId else { return false }
            windowState.selectedShortcutPinForSpace[spaceId] = pinId
            return true
        case let .clear(spaceId):
            guard windowState.selectedShortcutPinForSpace[spaceId] != nil else { return false }
            windowState.selectedShortcutPinForSpace[spaceId] = nil
            return true
        }
    }

    @discardableResult
    private func applyRegularTabMemoryUpdate(
        _ update: WindowTabSelectionTargetState.RegularTabMemoryUpdate,
        to windowState: BrowserWindowState
    ) -> Bool {
        switch update {
        case .none:
            return false
        case let .set(spaceId, tabId):
            var didChange = false
            if windowState.activeTabForSpace[spaceId] != tabId {
                windowState.activeTabForSpace[spaceId] = tabId
                didChange = true
            }
            if windowState.recentRegularTabIdsBySpace[spaceId]?.first != tabId {
                windowState.recordRegularTabSelection(tabId, in: spaceId)
                didChange = true
            }
            return didChange
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

        switch loadPolicy {
        case .immediate:
            compositorManager.loadTab(tab)
        case .deferred:
            Task { @MainActor [weak self, weak tab] in
                guard let self, let tab else { return }
                await Task.yield()
                guard self.currentTab(for: windowState)?.id == tab.id else { return }
                self.compositorManager.loadTab(tab)
                self.refreshCompositor(for: windowState)
            }
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
        var record = deferredHistorySwipeWindowMutationsByWindow[windowState.id]
            ?? DeferredHistorySwipeWindowMutations(windowState: WeakBrowserWindowState(windowState))
        record.windowState = WeakBrowserWindowState(windowState)
        record.pendingKinds.insert(kind)
        deferredHistorySwipeWindowMutationsByWindow[windowState.id] = record
    }

    func flushWindowMutationsAfterHistorySwipe(in windowId: UUID) {
        guard let record = deferredHistorySwipeWindowMutationsByWindow.removeValue(forKey: windowId),
              let windowState = record.windowState.value
        else {
            return
        }

        if record.pendingKinds.contains(.prepareVisibleWebViews) {
            _ = prepareVisibleWebViews(for: windowState)
        }
        if record.pendingKinds.contains(.prepareVisibleWebViews)
            || record.pendingKinds.contains(.refreshCompositor)
        {
            windowState.refreshCompositor()
        }
    }

    func cancelWindowMutationsAfterHistorySwipe(in windowId: UUID) {
        deferredHistorySwipeWindowMutationsByWindow.removeValue(forKey: windowId)
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
            clearEmptyStatePresentationIfNeeded(in: windowState)
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
        } else {
            showEmptyState(in: windowState)
        }

        if isActiveWindow {
            adoptProfileIfNeeded(for: windowState, context: .spaceChange)
        }
        persistWindowSession(for: windowState)
    }

    private func selectionTargetForSpaceActivation(
        in space: Space,
        windowState: BrowserWindowState
    ) -> Tab? {
        if windowState.currentSpaceId == space.id,
           hasValidCurrentSelection(in: windowState),
           let currentTab = currentTab(for: windowState) {
            return currentTab
        }

        if let currentTabId = windowState.currentTabId,
           let currentTab = tabManager.tab(for: currentTabId),
           currentTab.isShortcutLiveInstance,
           currentTab.shortcutPinRole == .essential {
            return currentTab
        }

        if let shortcutPinId = windowState.selectedShortcutPinForSpace[space.id],
           let liveShortcut = tabManager.shortcutLiveTab(for: shortcutPinId, in: windowState.id) {
            return liveShortcut
        }

        let regularTabs = tabManager.tabs(in: space)
        if let historyMatch = windowState.recentRegularTabIdsBySpace[space.id]?
            .compactMap({ tabId in regularTabs.first(where: { $0.id == tabId }) })
            .first {
            return historyMatch
        }

        if let rememberedId = windowState.activeTabForSpace[space.id],
           let remembered = regularTabs.first(where: { $0.id == rememberedId }) {
            return remembered
        }

        if let activeId = space.activeTabId,
           let active = regularTabs.first(where: { $0.id == activeId }) {
            return active
        }

        if let backgroundShortcut = tabManager.liveShortcutTabs(in: windowState.id)
            .first(where: { $0.shortcutPinRole != .essential && $0.spaceId == space.id }) {
            return backgroundShortcut
        }

        return regularTabs.first
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
        pendingWindowSessionPersistTasks[windowState.id]?.cancel()
        pendingWindowSessionPersistTasks.removeValue(forKey: windowState.id)
        pendingWindowSessionPersistStates.removeValue(forKey: windowState.id)
        persistWindowSessionNow(for: windowState)
    }

    func schedulePersistWindowSession(
        for windowState: BrowserWindowState,
        delayNanoseconds: UInt64 = 450_000_000
    ) {
        guard !windowState.isIncognito else { return }

        let windowId = windowState.id
        pendingWindowSessionPersistTasks[windowId]?.cancel()
        pendingWindowSessionPersistStates[windowId] = windowState
        pendingWindowSessionPersistTasks[windowId] = Task { @MainActor [weak self, weak windowState] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled,
                  let self,
                  let windowState
            else {
                return
            }

            self.pendingWindowSessionPersistTasks.removeValue(forKey: windowId)
            self.pendingWindowSessionPersistStates.removeValue(forKey: windowId)
            self.persistWindowSessionNow(for: windowState)
        }
    }

    func flushPendingWindowSessionPersistence() {
        guard !pendingWindowSessionPersistStates.isEmpty else { return }

        let pendingStates = pendingWindowSessionPersistStates.values.sorted {
            $0.id.uuidString < $1.id.uuidString
        }
        pendingWindowSessionPersistTasks.values.forEach { $0.cancel() }
        pendingWindowSessionPersistTasks.removeAll()
        pendingWindowSessionPersistStates.removeAll()

        let signpostState = PerformanceTrace.beginInterval("WindowSession.flushPendingPersistence")
        defer {
            PerformanceTrace.endInterval("WindowSession.flushPendingPersistence", signpostState)
        }

        for windowState in pendingStates {
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
        let wasCurrent =
            windowState.currentTabId == tab.id
            || (tab.shortcutPinId != nil && windowState.currentShortcutPinId == tab.shortcutPinId)

        if let pinId = tab.shortcutPinId {
            tabManager.deactivateShortcutLiveTab(pinId: pinId, in: windowState.id)
        } else {
            tabManager.deactivateShortcutLiveTab(in: windowState.id)
        }

        guard wasCurrent else {
            persistWindowSession(for: windowState)
            return
        }

        windowState.currentShortcutPinId = nil
        windowState.currentShortcutPinRole = nil
        windowState.currentTabId = nil

        if let fallback = preferredRegularTabForWindow(windowState) {
            selectTab(fallback, in: windowState)
        } else {
            showEmptyState(in: windowState)
        }
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

    private func fallbackRegularTab(afterClosing tab: Tab, in windowState: BrowserWindowState) -> Tab? {
        let targetSpaceId = tab.spaceId ?? windowState.currentSpaceId
        guard let targetSpaceId,
              let space = tabManager.spaces.first(where: { $0.id == targetSpaceId })
        else {
            return preferredRegularTabForWindow(windowState)
        }

        let regularTabs = tabManager.tabs(in: space).filter { $0.id != tab.id }
        guard !regularTabs.isEmpty else { return nil }

        if let historyMatch = windowState.recentRegularTabIdsBySpace[targetSpaceId]?.first(where: { historyId in
            historyId != tab.id && regularTabs.contains(where: { $0.id == historyId })
        }) {
            if let matchedTab = regularTabs.first(where: { $0.id == historyMatch }) {
                return matchedTab
            }
        }

        let currentRegularTabs = tabManager.tabs(in: space)
        if let closingIndex = currentRegularTabs.firstIndex(where: { $0.id == tab.id }) {
            if regularTabs.indices.contains(closingIndex) {
                return regularTabs[closingIndex]
            }
            if regularTabs.indices.contains(max(0, closingIndex - 1)) {
                return regularTabs[max(0, closingIndex - 1)]
            }
        }

        return regularTabs.last
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

extension BrowserManager: BrowserCommandRouting, WindowCommandRouting, ExternalURLHandling,
    BrowserPersistenceHandling, WebViewLookup
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
