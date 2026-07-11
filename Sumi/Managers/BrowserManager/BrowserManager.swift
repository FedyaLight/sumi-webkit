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
import SumiDomain
import SumiWebRuntime

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

    let webViewSessions: WebViewSessionRepository
    var modelContext: ModelContext
    let startupWorkspaceTheme: WorkspaceTheme?
    let moduleRegistry: SumiModuleRegistry
    let adBlockingModule: SumiAdBlockingModule
    let protectionCoordinator: SumiProtectionCoordinator
    let adblockZapperStore: SumiAdblockZapperStore
    let optionalModules: OptionalModuleHost
    let sidebarHostRecoveryCoordinator: SidebarHostRecoveryHandling
    let tabManager: TabManager
    let profileManager: ProfileManager
    let downloadManager: DownloadManager
    let authenticationManager: AuthenticationManager
    var historyManager: HistoryManager
    var bookmarkManager: SumiBookmarkManager
    var recentlyClosedManager: RecentlyClosedManager
    var lastSessionWindowsStore: LastSessionWindowsStore {
        didSet { startupSessionRestoreOwner.reload(from: lastSessionWindowsStore) }
    }
    let compositorManager: TabCompositorManager
    let tabSuspensionController: TabSuspensionController
    let backgroundMediaOptimizationService = SumiBackgroundMediaOptimizationService()
    let nativeNowPlayingController: any SumiNativeNowPlayingRuntimeControlling
    let workspaceThemeCoordinator: WorkspaceThemeCoordinator
    let findManager: FindManager
    let browserConfiguration: BrowserConfiguration
    let dataServices: BrowserManagerDataServices
    let browsingDataCleanupService: SumiBrowsingDataCleanupService
    let permissionRuntime: BrowserManagerPermissionRuntime
    let zoomManager = ZoomManager()
    weak var sumiSettings: SumiSettingsService? {
        didSet { settingsAttachment.attach(sumiSettings) }
    }
    weak var keyboardShortcutManager: KeyboardShortcutManager?
    let liveFolderManager = SumiLiveFolderManager()
    private(set) lazy var splitComposition = BrowserSplitServices.live(
        browserManager: self
    )
    lazy var sidebarCommandService = BrowserSidebarCommandService(browserManager: self)
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
    lazy var extensionBridgeComposition = BrowserExtensionBridgeComposition(
        browserManager: self
    )
    /// Process-lifetime runtime lifecycle: started once in init, shut down once in deinit.
    private lazy var runtimeLifecycle = BrowserRuntimeLifecycle.live(browserManager: self)
    /// Reached only from `sumiSettings.didSet`; private so feature code cannot use it as a service locator.
    private lazy var settingsAttachment = BrowserSettingsAttachmentCoordinator.live(browserManager: self)
    lazy var webViewCloseRouter = BrowserWebViewCloseRouter(browserManager: self)
    lazy var notificationPresenter = BrowserNotificationPresenter(browserManager: self)
    lazy var shortcutActionRouter = BrowserShortcutActionRouter(dependencies: .live(browserManager: self))
    lazy var windowCommands = BrowserWindowCommands(browserRuntime: self)
    lazy var windowStateReconciler = BrowserWindowStateReconciler(
        browserManager: self
    )
    lazy var windowSpaceTransitions = BrowserWindowSpaceTransitionService(
        browserManager: self
    )
    lazy var shellRuntime = BrowserShellRuntime(
        tabManager: tabManager,
        splitQuery: splitComposition.query,
        glanceManager: glanceManager,
        webViewSessions: webViewSessions
    )
    lazy var webViewOwnershipQuery = WebViewOwnershipQuery(
        webViewSessions: webViewSessions
    )
    lazy var webViewRoutingService = BrowserWebViewRoutingService(
        tabLookup: { [weak self] tabId in
            self?.tabManager.tabCollectionMembershipOwner.tab(for: tabId)
        },
        webViewSessions: webViewSessions,
        ownershipQuery: webViewOwnershipQuery,
        commandsProvider: { [weak self] in
            self?.shellRuntime.webViewCoordinator.map(
                BrowserWebViewRoutingService.Commands.live
            )
        }
    )
    let windowSessionPersistence: WindowSessionPersistenceRuntime
    let startupSessionRestoreOwner: BrowserStartupSessionRestoreOwner
    let auxiliaryWindowTeardownRegistry: AuxiliaryWindowTeardownRegistry
    lazy var auxiliaryWindows: BrowserAuxiliaryWindowComposition = {
        let composition = BrowserAuxiliaryWindowComposition(
            windowRegistry: { [weak shellRuntime] in shellRuntime?.windowRegistry },
            currentProfile: { [weak tabManager] in tabManager?.runtimePorts?.currentProfileId },
            spaces: tabManager.spaceStateOwner,
            tabContext: shellRuntime.windowTabs,
            transientTabs: tabManager.transientWebKitTabLifecycleOwner,
            webViewOwnership: { [weak shellRuntime] in
                shellRuntime?.webViewCoordinator?.ownershipService
            },
            extensions: optionalModules.extensions,
            popupPermissions: permissionRuntime.popupPermissionBridge,
            filePickerPermissions: permissionRuntime.filePickerPermissionBridge,
            mutationAdmission: { [weak shellRuntime] in
                shellRuntime?.webViewCoordinator?.websiteDataCleanupService
            }
        )
        auxiliaryWindowTeardownRegistry.register(composition.teardown)
        return composition
    }()
    let glanceManager: GlanceManager
    lazy var shutdownCleanupService = BrowserShutdownCleanupService(
        extensions: optionalModules.extensions,
        auxiliaryWindows: auxiliaryWindowTeardownRegistry,
        glance: glanceManager,
        tabs: tabManager,
        shell: shellRuntime
    )
    private(set) var startupProtectionRuntime: BrowserStartupProtectionRuntime!

    /// Designated init: assign always-on managers from a pre-built kernel graph.
    init(kernel graph: BrowserKernelGraph) {
        precondition(
            graph.tabManager.tabFactory.webViewSessions === graph.webViewSessions,
            "Browser kernel must give TabManager and WebViewCoordinator one canonical WebView session repository"
        )
        let auxiliaryWindowTeardownRegistry = AuxiliaryWindowTeardownRegistry()
        let glanceManager = GlanceManager()
        self.webViewSessions = graph.webViewSessions
        self.modelContext = graph.modelContext
        self.moduleRegistry = graph.moduleRegistry
        self.sidebarHostRecoveryCoordinator = graph.sidebarHostRecoveryCoordinator
        self.adBlockingModule = graph.adBlockingModule
        self.protectionCoordinator = graph.protectionCoordinator
        self.adblockZapperStore = graph.adblockZapperStore
        self.startupWorkspaceTheme = graph.startupWorkspaceTheme
        self.windowSessionPersistence = graph.windowSessionPersistence
        self.profileManager = graph.profileManager
        self.currentProfile = graph.currentProfile
        self.optionalModules = graph.optionalModules
        self.tabManager = graph.tabManager
        self.downloadManager = graph.downloadManager
        self.authenticationManager = graph.authenticationManager
        self.historyManager = graph.historyManager
        self.bookmarkManager = graph.bookmarkManager
        self.recentlyClosedManager = graph.recentlyClosedManager
        self.lastSessionWindowsStore = graph.lastSessionWindowsStore
        self.startupSessionRestoreOwner = graph.startupSessionRestoreOwner
        self.compositorManager = graph.compositorManager
        self.tabSuspensionController = graph.tabSuspensionController
        self.workspaceThemeCoordinator = graph.workspaceThemeCoordinator
        self.findManager = graph.findManager
        self.browserConfiguration = graph.browserConfiguration
        self.dataServices = graph.dataServices
        self.browsingDataCleanupService = graph.browsingDataCleanupService
        self.nativeNowPlayingController = graph.nativeNowPlayingController
        self.permissionRuntime = graph.permissionRuntime
        self.auxiliaryWindowTeardownRegistry = auxiliaryWindowTeardownRegistry
        self.glanceManager = glanceManager
        _ = shellRuntime
        _ = shutdownCleanupService
        self.startupProtectionRuntime = BrowserStartupProtectionRuntime(browserManager: self)
        runtimeLifecycle.start()
    }

    isolated deinit {
        windowSessionPersistence.flushForBrowserRuntimeTeardown()
        tabManager.detachBrowserRuntime()
        runtimeLifecycle.shutdown()
        shutdownCleanupService.cleanupAfterBrowserRuntimeDeallocation()
        NotificationCenter.default.removeObserver(self)
    }
}
