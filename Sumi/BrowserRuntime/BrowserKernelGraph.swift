import Foundation
import SwiftData
import SumiBrowserCore

/// Always-on managers assembled by `BrowserCompositionRoot.makeKernel` so
/// `BrowserManager` init can assign from a single graph instead of inline construction.
@MainActor
struct BrowserKernelGraph {
    let modelContext: ModelContext
    let moduleRegistry: SumiModuleRegistry
    let liveFoldersModule: SumiLiveFoldersModule
    let sidebarHostRecoveryCoordinator: SidebarHostRecoveryHandling
    let tabStructureEventBus: TabStructureEventBus
    let adBlockingModule: SumiAdBlockingModule
    let protectionCoordinator: SumiProtectionCoordinator
    let adblockZapperStore: SumiAdblockZapperStore
    let userscriptsModule: SumiUserscriptsModule
    let boostsModule: SumiBoostsModule
    let startupWorkspaceTheme: WorkspaceTheme?
    let profileManager: ProfileManager
    let currentProfile: Profile?
    let extensionsModule: SumiExtensionsModule
    let tabManager: TabManager
    let downloadManager: DownloadManager
    let authenticationManager: AuthenticationManager
    let historyManager: HistoryManager
    let bookmarkManager: SumiBookmarkManager
    let recentlyClosedManager: RecentlyClosedManager
    let lastSessionWindowsStore: LastSessionWindowsStore
    let startupSessionRestoreOwner: BrowserStartupSessionRestoreOwner
    let compositorManager: TabCompositorManager
    let tabSuspensionService: TabSuspensionService
    let splitManager: SplitViewManager
    let workspaceThemeCoordinator: WorkspaceThemeCoordinator
    let findManager: FindManager
    let browserConfiguration: BrowserConfiguration
    let dataServices: BrowserManagerDataServices
    let browsingDataCleanupService: SumiBrowsingDataCleanupService
    let nativeNowPlayingController: any SumiNativeNowPlayingRuntimeControlling
    let permissionRuntime: BrowserManagerPermissionRuntime
}
