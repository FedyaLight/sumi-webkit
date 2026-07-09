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
import SumiBrowserCore
import SumiChromeContracts
import SumiDomain

@MainActor
class BrowserManager: ObservableObject {
    static let lastWindowSessionKey = "sumi.windowSession.last.v3"
    @Published var zoomStateRevision: Int = 0
    @Published var bookmarkEditorPresentationRequest: SumiBookmarkEditorPresentationRequest?
    @Published var currentProfile: Profile?
    @Published var isTransitioningProfile: Bool = false
    @Published var workspaceThemePickerSession: WorkspaceThemePickerSession?
    @Published var nativeModalPresentation: BrowserNativeModalPresentation?
    @Published var tabStructuralRevision: UInt = 0

    let tabStructureEventBus: TabStructureEventBus
    private(set) var runtimePortRegistry = RuntimePortRegistry()
    var modelContext: ModelContext
    let startupWorkspaceTheme: WorkspaceTheme?
    let moduleRegistry: SumiModuleRegistry
    let adBlockingModule: SumiAdBlockingModule
    let protectionCoordinator: SumiProtectionCoordinator
    let adblockZapperStore: SumiAdblockZapperStore
    let extensionsModule: SumiExtensionsModule
    let userscriptsModule: SumiUserscriptsModule
    let boostsModule: SumiBoostsModule
    let sidebarHostRecoveryCoordinator: SidebarHostRecoveryHandling
    var extensionSurfaceStore: BrowserExtensionSurfaceStore { extensionsModule.surfaceStore }
    var tabManager: TabManager
    var profileManager: ProfileManager
    var downloadManager: DownloadManager
    var authenticationManager: AuthenticationManager
    var historyManager: HistoryManager
    var bookmarkManager: SumiBookmarkManager
    var recentlyClosedManager: RecentlyClosedManager
    var lastSessionWindowsStore: LastSessionWindowsStore {
        didSet { startupSessionRestoreOwner.reload(from: lastSessionWindowsStore) }
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
            privacyBundle.automaticDataCleanupOwner.scheduleAutomaticBrowsingDataCleanup(
                reason: "settings-attached"
            )
        }
    }
    weak var keyboardShortcutManager: KeyboardShortcutManager?
    let sumiProfileRouter = SumiProfileRouter()
    let liveFolderManager = SumiLiveFolderManager()
    let liveFoldersModule: SumiLiveFoldersModule
    lazy var optionalModuleHost = OptionalModuleHost(
        extensionsModule: extensionsModule,
        userscriptsModule: userscriptsModule,
        boostsModule: boostsModule,
        liveFoldersModule: liveFoldersModule
    )
    let permissionSiteSettingsRoutingOwner = BrowserPermissionSiteSettingsRoutingOwner()
    lazy var sidebarCommandService = BrowserSidebarCommandService(browserManager: self)
    lazy var sidebarChromeCommanding: SidebarChromeCommanding =
        BrowserSidebarChromeCommandingAdapter(browserManager: self)
    lazy var shellSelectionService = ShellSelectionService { [weak self] windowId in
        guard let self else { return [] }
        return self.splitManager.visibleTabIds(for: windowId)
    }
    lazy var tabLifecycleService = BrowserTabLifecycleService(browserManager: self)
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
    lazy var lifecycleBundle = BrowserLifecycleBundle(browserManager: self)
    lazy var webViewCloseRouter = BrowserWebViewCloseRouter(browserManager: self)
    lazy var notificationPresenter = BrowserNotificationPresenter(browserManager: self)
    lazy var appCommandRouter = BrowserAppCommandRouter(dependencies: .live(browserManager: self))
    lazy var shortcutActionRouter = BrowserShortcutActionRouter(dependencies: .live(browserManager: self))
    let shellRuntime = BrowserShellRuntime()
    lazy var webViewRoutingService = BrowserWebViewRoutingService(
        tabLookup: { [weak self] tabId in
            self?.tabManager.tabCollectionMembershipOwner.tab(for: tabId)
        },
        coordinatorProvider: { [weak self] in self?.shellRuntime.webViewCoordinator }
    )
    var windowSessionService = WindowSessionService(lastWindowSessionKey: BrowserManager.lastWindowSessionKey)
    let startupSessionRestoreOwner: BrowserStartupSessionRestoreOwner
    var auxiliaryWindowManager = AuxiliaryWindowManager()
    let glanceManager = GlanceManager()
    private(set) var startupProtectionRuntime: BrowserStartupProtectionRuntime!

    /// Designated init: assign always-on managers from a pre-built kernel graph.
    init(kernel graph: BrowserKernelGraph) {
        self.modelContext = graph.modelContext
        self.moduleRegistry = graph.moduleRegistry
        self.liveFoldersModule = graph.liveFoldersModule
        self.sidebarHostRecoveryCoordinator = graph.sidebarHostRecoveryCoordinator
        self.tabStructureEventBus = graph.tabStructureEventBus
        self.adBlockingModule = graph.adBlockingModule
        self.protectionCoordinator = graph.protectionCoordinator
        self.adblockZapperStore = graph.adblockZapperStore
        self.userscriptsModule = graph.userscriptsModule
        self.boostsModule = graph.boostsModule
        self.startupWorkspaceTheme = graph.startupWorkspaceTheme
        self.profileManager = graph.profileManager
        self.currentProfile = graph.currentProfile
        self.extensionsModule = graph.extensionsModule
        self.tabManager = graph.tabManager
        self.downloadManager = graph.downloadManager
        self.authenticationManager = graph.authenticationManager
        self.historyManager = graph.historyManager
        self.bookmarkManager = graph.bookmarkManager
        self.recentlyClosedManager = graph.recentlyClosedManager
        self.lastSessionWindowsStore = graph.lastSessionWindowsStore
        self.startupSessionRestoreOwner = graph.startupSessionRestoreOwner
        self.compositorManager = graph.compositorManager
        self.tabSuspensionService = graph.tabSuspensionService
        self.splitManager = graph.splitManager
        self.workspaceThemeCoordinator = graph.workspaceThemeCoordinator
        self.findManager = graph.findManager
        self.browserConfiguration = graph.browserConfiguration
        self.dataServices = graph.dataServices
        self.browsingDataCleanupService = graph.browsingDataCleanupService
        self.nativeNowPlayingController = graph.nativeNowPlayingController
        self.permissionRuntime = graph.permissionRuntime
        startPermissionEventObservation()
        self.startupProtectionRuntime = BrowserStartupProtectionRuntime(browserManager: self)
        lifecycleBundle.initializationWiringOwner.finishInitializationWiring()
    }

    isolated deinit {
        permissionRuntime.cancelPermissionEventObservation()
        startupProtectionRuntime.cancelProtectionRestoreTask()
        windowSessionService.cancelPendingWindowSessionPersistence()
        lifecycleBundle.initializationWiringOwner.cancel()
        NotificationCenter.default.removeObserver(self)
    }
}

extension BrowserManager {
    func attachRuntimePortRegistry(_ registry: RuntimePortRegistry) {
        runtimePortRegistry = registry
    }
}
