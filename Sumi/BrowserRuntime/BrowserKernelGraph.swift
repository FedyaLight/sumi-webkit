import Combine
import Foundation
import SumiDomain
import SumiWebRuntime

/// Always-on managers assembled by `BrowserCompositionRoot.makeKernel` so
/// `BrowserManager` init can assign from a single graph instead of inline construction.
@MainActor
struct BrowserKernelGraph {
    let objectWillChange: ObservableObjectPublisher
    let webViewSessions: WebViewSessionRepository
    let windowRegistry: WindowRegistry
    let database: SumiDatabase
    let moduleRegistry: SumiModuleRegistry
    let sidebarHostRecoveryCoordinator: SidebarHostRecoveryHandling
    let adBlockingModule: SumiAdBlockingModule
    let protectionCoordinator: SumiProtectionCoordinator
    let adblockZapperStore: SumiAdblockZapperStore
    let windowSessionPersistence: WindowSessionPersistenceRuntime
    let profileRetirementStartupPreflight: ProfileRetirementStartupPreflightStatus
    let profileManager: ProfileManager
    let currentProfile: Profile?
    let optionalModules: OptionalModuleHost
    let runtimePortConnection: TabRuntimePortConnection
    let tabStateStore: TabStateStore
    let spaceStateOwner: TabSpaceCollectionStateOwner
    let splitGroupStore: SplitGroupStore
    let folderCollectionStateOwner: TabFolderCollectionStateOwner
    let shortcutPinCollectionStateOwner: ShortcutPinCollectionStateOwner
    let tabStructureEventBus: TabStructureEventBus
    let startupRestoreLifecycle: TabStartupRestoreLifecycle
    let structuralPersistence: TabStructuralPersistenceService
    let profileRuntimeState: SpaceProfileRuntimeStateService
    let tabFactory: TabFactory
    let folderOpenState: TabFolderOpenStateService
    let regularTabCollectionOwner: RegularTabCollectionOwner
    let regularTabLifecycleOwner: TabRegularLifecycleOwner
    let tabClosureService: TabClosureService
    let activeSelectionOwner: TabActiveSelectionOwner
    let spacePinnedStructureOwner: SpacePinnedStructureOwner
    let tabProfileTransitions: TabProfileTransitionService
    let spaceProfileTransitions: SpaceProfileTransitionService
    let profileSelection: ProfileSelectionCoordinator
    let profileDeletion: ProfileDeletionMigration
    let shortcutExecutionProfileAssignments:
        ShortcutExecutionProfileAssignmentService
    let sidebarDragRouter: SidebarDragOperationRouter
    let favoriteShortcutPlacementOwner: FavoriteShortcutPlacementOwner
    let shortcutPinStoreOwner: ShortcutPinStoreOwner
    let shortcutPinRuntimeResolutionOwner:
        ShortcutPinRuntimeResolutionOwner
    let shortcutWindowMutationOwner: BrowserWindowShortcutMutationOwner
    let shortcutPresentationOwner: TabShortcutPresentationOwner
    let structuralCollectionMutationOwner:
        TabStructuralCollectionMutationOwner
    let structuralInstallOwner: TabStructuralInstallOwner
    let tabCollectionMembershipOwner: TabCollectionMembershipOwner
    let extensionTabCommands: BrowserExtensionTabCommands
    let auxiliaryMiniWindowTabs: AuxiliaryMiniWindowTabLifecycleTransaction
    let ephemeralLifecycleOwner: TabEphemeralLifecycleOwner
    let structuralLookupCoordinator: TabStructuralLookupCoordinator
    let sidebarSpaceLifecycle: SidebarSpaceLifecycle
    let spaceActivation: SpaceActivationService
    let liveShortcutTabs: LiveShortcutTabRegistry
    let liveShortcutPresentationRefreshes:
        LiveShortcutPresentationRefreshService
    let shortcutTabMaterializer: ShortcutTabMaterializer
    let shortcutPresentationActivation:
        ShortcutPresentationActivationService
    let splitGroupMutations: SplitGroupMutationService
    let splitGroupSidebarOrdering: SplitGroupSidebarOrderingService
    let splitGroupContainerConversion: SplitGroupContainerConversion
    let splitGroupShortcutMemberRelocation: SplitGroupShortcutMemberRelocation
    let splitGroupMembership: SplitGroupMembershipQuery
    let regularTabShortcutConversion:
        RegularTabShortcutConversionService
    let shortcutPinToRegularTab: ShortcutPinToRegularTabService
    let shortcutLiveTabRetirement: ShortcutLiveTabRetirementService
    let emptySplitConvertedPlaceholderRetirement:
        EmptySplitConvertedPlaceholderRetirementService
    let sidebarPinCommands: SidebarPinCommands
    let sidebarFolderCommands: SidebarFolderCommands
    let sidebarRegularTabLifecycleCommands: SidebarRegularTabLifecycleCommands
    let sidebarRegularTabShortcutCommands: SidebarRegularTabShortcutCommands
    let sidebarRegularTabPlacementCommands: SidebarRegularTabPlacementCommands
    let runtimeStore: DefaultTabRuntimeStore
    let startupStateReset: TabStartupStateReset
    let lastSessionMergeMaterializer: TabLastSessionMergeMaterializer
    let tabRuntimeLifecycle: TabRuntimeLifecycle
    let tabResidenceAuthority: BrowserTabResidenceAuthority
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
