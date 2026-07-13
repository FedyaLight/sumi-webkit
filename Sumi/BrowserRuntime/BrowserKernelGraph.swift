import Foundation
import SwiftData
import SumiWebRuntime

/// Always-on managers assembled by `BrowserCompositionRoot.makeKernel` so
/// `BrowserManager` init can assign from a single graph instead of inline construction.
@MainActor
struct BrowserKernelGraph {
    let webViewSessions: WebViewSessionRepository
    let modelContext: ModelContext
    let moduleRegistry: SumiModuleRegistry
    let sidebarHostRecoveryCoordinator: SidebarHostRecoveryHandling
    let adBlockingModule: SumiAdBlockingModule
    let protectionCoordinator: SumiProtectionCoordinator
    let adblockZapperStore: SumiAdblockZapperStore
    let startupWorkspaceTheme: WorkspaceTheme?
    let windowSessionPersistence: WindowSessionPersistenceRuntime
    let profileManager: ProfileManager
    let currentProfile: Profile?
    let optionalModules: OptionalModuleHost
    let tabManager: TabManager
    let downloadManager: DownloadManager
    let downloadTransportFactory: any DownloadWebKitTransportAdapting
    let authenticationManager: AuthenticationManager
    let historyManager: HistoryManager
    let bookmarkManager: SumiBookmarkManager
    let recentlyClosedManager: RecentlyClosedManager
    let lastSessionWindowsStore: LastSessionWindowsStore
    let startupSessionRestoreOwner: BrowserStartupSessionRestoreOwner
    let compositorManager: TabCompositorManager
    let tabSuspensionController: TabSuspensionController
    let workspaceThemeCoordinator: WorkspaceThemeCoordinator
    let findManager: FindManager
    let browserConfiguration: BrowserConfiguration
    let dataServices: BrowserManagerDataServices
    let browsingDataCleanupService: SumiBrowsingDataCleanupService
    let nativeNowPlayingController: any SumiNativeNowPlayingRuntimeControlling
    let permissionRuntime: BrowserManagerPermissionRuntime
}
