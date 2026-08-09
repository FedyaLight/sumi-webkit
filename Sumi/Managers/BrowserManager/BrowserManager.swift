//
//  BrowserManager.swift
//  Sumi
//
//

import AppKit
import Combine
import SumiDomain
import SumiWebRuntime
import SwiftUI
import WebKit

@MainActor
class BrowserManager: ObservableObject {
    nonisolated(unsafe) let objectWillChange: ObservableObjectPublisher
    static let lastWindowSessionKey = "sumi.windowSession.last.v3"
    let zoomRevisionState = BrowserZoomRevisionState()
    let bookmarkEditorPresentationState =
        BrowserBookmarkEditorPresentationState()
    let currentProfileAuthority: BrowserCurrentProfileAuthority
    let workspaceThemePickerSessionState =
        BrowserWorkspaceThemePickerSessionState()
    let nativeModalPresentationState = BrowserNativeModalPresentationState()
    var startupServicesStorage: BrowserStartupServices?

    let webViewSessions: WebViewSessionRepository
    let windowRegistry: WindowRegistry
    let database: SumiDatabase
    let profileRetirementStartupPreflight: ProfileRetirementStartupPreflightStatus
    let moduleRegistry: SumiModuleRegistry
    let adBlockingModule: SumiAdBlockingModule
    let protectionCoordinator: SumiProtectionCoordinator
    let adblockZapperStore: SumiAdblockZapperStore
    let optionalModules: OptionalModuleHost
    let sidebarHostRecoveryCoordinator: SidebarHostRecoveryHandling
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
    let lazyRestoreCoordinator: TabLazyRestoreCoordinator
    let spacePinnedStructureOwner: SpacePinnedStructureOwner
    let tabProfileTransitions: TabProfileTransitionService
    let spaceProfileTransitions: SpaceProfileTransitionService
    let profileSelection: ProfileSelectionCoordinator
    let profileDeletion: ProfileDeletionMigration
    let shortcutExecutionProfileAssignments:
        ShortcutExecutionProfileAssignmentService
    let sidebarDragRouter: SidebarDragOperationRouter
    let essentialsShortcutPlacementOwner: EssentialsShortcutPlacementOwner
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
    let profileManager: ProfileManager
    let downloadManager: DownloadManager
    let downloadTransportFactory: any DownloadWebKitTransportAdapting
    let authenticationManager: AuthenticationManager
    var historyManager: HistoryManager
    var bookmarkManager: SumiBookmarkManager
    let recentlyClosedManager: RecentlyClosedManager
    var lastSessionWindowsStore: LastSessionWindowsStore {
        didSet { startupSessionRestoreOwner.reload(from: lastSessionWindowsStore) }
    }
    let compositorManager: TabCompositorManager
    let tabSuspensionController: TabSuspensionController
    lazy var pageResidency = BrowserPageResidencyController(
        tabSuspension: tabSuspensionController
    )
    lazy var tabBrowserRuntimeReference = TabBrowserRuntimeReference(
        TabBrowserRuntimeFactory.make(for: self)
    )
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
    let liveFolderManager: SumiLiveFolderManager
    let settingsState = BrowserSettingsState()
    let startupMaterializationGate: BrowserStartupMaterializationGate
    let webViewWindowCommands = BrowserWebViewWindowCommandChannel()
    let webViewCloseRequests = BrowserWebViewCloseRequestBroker()
    lazy var windowSelectionProjection = ShellSelectionService(
        splitQuery: splitQuery
    )
    lazy var windowTabContext = BrowserWindowTabContext(
        selectionService: windowSelectionProjection,
        tabStore: runtimeStore,
        windows: windowRegistry,
        splitQuery: splitQuery,
        webViewSessions: webViewSessions
    )
    /// Canonical process-lifetime WebView service graph. It shares the same
    /// session repository as every Tab created by this browser kernel.
    private(set) lazy var webViewRuntime = composeWebViewRuntime()
    lazy var splitUpdateChannel = SplitWindowUpdateStream.makeChannel()
    lazy var splitPreviews = composeSplitPreviews()
    lazy var splitQuery = composeSplitQuery()
    lazy var splitMembers = composeSplitMembers()
    lazy var splitMaterialization = composeSplitMaterialization()
    lazy var splitPresentations = composeSplitPresentations()
    lazy var splitLauncherRelease = composeSplitLauncherRelease()
    lazy var splitReleaseOrdering = composeSplitReleaseOrdering()
    lazy var splitDissolution = composeSplitDissolution()
    lazy var splitWeightMutations = composeSplitWeightMutations()
    lazy var splitDropTargets = composeSplitDropTargets()
    lazy var splitPlaceholderRetirement = composeSplitPlaceholderRetirement()
    lazy var emptySplitSession = EmptySplitSession(
        structuralTransactions: structuralLookupCoordinator,
        terminalMutations: structuralCollectionMutationOwner,
        placeholderRetirement: splitPlaceholderRetirement
    )
    lazy var splitPlaceholderReplacements = composeSplitPlaceholderReplacements()
    lazy var splitDrops = composeSplitDrops()
    lazy var splitInsertion = composeSplitInsertion()
    lazy var splitShortcutFocus = composeSplitShortcutFocus()
    lazy var splitShortcutHostedUnload = composeSplitShortcutHostedUnload()
    lazy var splitLayout = composeSplitLayout()
    lazy var splitEmptyPlaceholders = composeSplitEmptyPlaceholders()
    lazy var splitEmptyCreation = composeSplitEmptyCreation()
    lazy var splitTabClosures = SplitTabClosureService(
        dropTargets: splitDropTargets,
        layout: splitLayout
    )
    lazy var splitWindowContext = WindowSplitContext(
        updates: splitUpdateChannel.stream,
        query: splitQuery,
        previews: splitPreviews,
        layout: splitLayout,
        drops: splitDrops,
        dropTargets: splitDropTargets
    )
    lazy var windowSpaceContextReconciler =
        BrowserWindowSpaceContextReconciler(
            membership: tabCollectionMembershipOwner,
            spaces: spaceStateOwner
        )
    lazy var focusedSpaceRuntimeSynchronizer =
        FocusedSpaceRuntimeStateSynchronizer(
            windows: windowRegistry,
            windowContext: windowSpaceContextReconciler,
            runtimeState: profileRuntimeState
        )
    lazy var windowSpaceContextSynchronizer =
        BrowserWindowSpaceContextSynchronizer(
            spaceContext: windowSpaceContextReconciler,
            focusedRuntime: focusedSpaceRuntimeSynchronizer
        )
    lazy var browserTabSelection: BrowserTabSelectionOwner = {
        let shell = shellRuntime
        let state = BrowserTabSelectionStateApplication(
            windows: windowRegistry,
            windowSelection: shell.windowSelection,
            tabStore: runtimeStore,
            spaces: spaceStateOwner,
            splitMembership: splitGroupMembership
        )
        let materialization = BrowserTabSelectionMaterializationOwner(
            state: state,
            startupProtection: startupProtectionRuntime,
            compositor: compositorManager,
            trackedAdmission: webViewRuntime.trackedWebViewAdmission,
            windowVisuals: shell.windowVisuals,
            visibleTabs: {
                [splitQuery,
                 membership = tabCollectionMembershipOwner]
                selected,
                windowState in
                let visibleIDs = splitQuery.visibleTabIDs(in: windowState.id)
                guard visibleIDs.isEmpty == false else { return [selected] }
                var tabs = visibleIDs.compactMap { tabID in
                    if windowState.isIncognito {
                        return windowState.ephemeralTabs.first { $0.id == tabID }
                    }
                    return membership.tab(for: tabID)
                }
                if tabs.contains(where: { $0 === selected }) == false {
                    tabs.append(selected)
                }
                return tabs
            },
            tabForID: { [membership = tabCollectionMembershipOwner]
                tabID,
                windowState in
                if windowState.isIncognito {
                    return windowState.ephemeralTabs.first { $0.id == tabID }
                }
                return membership.tab(for: tabID)
            }
        )
        let chromeEffects = BrowserTabSelectionChromeEffects(
            state: state,
            windowSpaceContext: windowSpaceContextSynchronizer,
            workspaceThemes: workspaceThemeTransitionOwner,
            commandPalette: commandPalettePresentation
        )
        let mediaEffects = BrowserTabSelectionMediaEffects(
            nowPlaying: nativeNowPlayingController,
            findManager: findManager,
            activePage: shell.activePageResolver,
            windowVisuals: shell.windowVisuals
        )
        return BrowserTabSelectionOwner(
            activation: BrowserTabSelectionActivation(
                shortcutActivation: shortcutPresentationActivation
            ),
            performance: pageActivationPerformance,
            state: state,
            materialization: materialization,
            presentation: BrowserTabSelectionPresentationEffects(
                chrome: chromeEffects,
                media: mediaEffects
            ),
            publication: BrowserTabSelectionPublicationTransaction(
                state: state,
                extensionLifecycle: LiveTabExtensionLifecyclePort(
                    extensions: optionalModules.extensions.runtimeSurface
                ),
                pageResidency: pageResidency,
                activeSelection: activeSelectionOwner,
                persistence: windowSessionPersistenceCoordinator
            )
        )
    }()
    lazy var tabCloseFallbackPlanner = composeTabCloseFallbackPlanner()
    lazy var shortcutLiveTabClose = composeShortcutLiveTabClose()
    lazy var tabCloseOrchestration = composeTabCloseOrchestration()
    lazy var tabOpening = composeTabOpening()
    lazy var privacyBundle = BrowserPrivacyBundle(
        permissionRuntime: permissionRuntime,
        dataServices: dataServices,
        settings: settingsState,
        history: historyManager,
        profiles: profileManager,
        currentProfile: currentProfileAuthority,
        windows: windowRegistry,
        windowTabs: shellRuntime.windowTabs
    )
    lazy var nativeModalTransaction = BrowserNativeModalTransaction(
        state: nativeModalPresentationState,
        windows: windowRegistry,
        recovery: sidebarHostRecoveryCoordinator
    )
    lazy var workspaceThemeTransitionOwner =
        BrowserWorkspaceThemeTransitionOwner(
            shellRuntime: shellRuntime,
            coordinator: workspaceThemeCoordinator
        )
    lazy var workspaceThemePickerPresentation =
        BrowserWorkspaceThemePickerPresentation(
            state: workspaceThemePickerSessionState,
            windows: windowRegistry,
            settings: settingsState,
            recovery: sidebarHostRecoveryCoordinator
        )
    lazy var workspaceThemeEditorOwner = composeWorkspaceThemeEditor()
    lazy var commandPalettePresentation = composeCommandPalettePresentation()
    lazy var commandPaletteCommit = composeCommandPaletteCommit(
        presentation: commandPalettePresentation
    )
    lazy var commandPaletteBrowserContext =
        composeCommandPaletteBrowserContext(
            presentation: commandPalettePresentation,
            commit: commandPaletteCommit
        )
    lazy var chromeBundle = composeChromeBundle()
    lazy var urlBarBundle = composeURLBarBundle()
    lazy var windowExtensionPublication = WindowExtensionPublicationTransaction.live(
        browserManager: self, webViewOwnership: webViewRuntime.ownershipQuery
    )
    lazy var windowSessionSnapshotFactory = WindowSessionSnapshotFactory(
        glanceManager: glanceManager,
        windowGeometry: { [weak self] windowState in
            if let pendingGeometry = windowState.restorationState
                .pendingWindowGeometry {
                return pendingGeometry
            }
            guard let window = self?.windowRegistry.appKitWindow(
                for: windowState
            ) else {
                return nil
            }
            return BrowserWindowGeometryPolicy.snapshot(of: window)
        },
        liveShortcuts: { [weak self] windowState in
            self?.liveShortcutTabs.entries(in: windowState.id).map {
                ShortcutLiveSessionSnapshot(
                    shortcutPinId: $0.pinId,
                    presentationSpaceId: $0.presentationPage.page.spaceID,
                    currentURL: $0.tab.url,
                    title: $0.tab.name
                )
            } ?? []
        }
    )
    lazy var windowSessionHistory = composeWindowSessionHistory()
    lazy var windowSessionPersistenceCoordinator =
        composeWindowSessionPersistence()
    lazy var shortcutLiveSessionPersistence =
        ShortcutLiveSessionPersistence(
            liveTabs: liveShortcutTabs,
            windows: { [weak self] in self?.windowRegistry },
            persistence: windowSessionPersistenceCoordinator
        )
    lazy var windowActivation = composeWindowActivation()
    lazy var windowSessionBundle = BrowserWindowSessionBundle(
        browserManager: self,
        startupSessionRestoreOwner: startupSessionRestoreOwner,
        splitFocus: splitShortcutFocus,
        history: windowSessionHistory,
        persistence: windowSessionPersistenceCoordinator
    )
    lazy var historyBundle = BrowserHistoryBundle(browserManager: self)
    lazy var bookmarkBundle = BrowserBookmarkBundle(browserManager: self)
    lazy var profileLifecycleBundle = composeProfileLifecycleBundle()
    lazy var startupSessionReconciliation =
        BrowserStartupSessionReconciliationService(
            startupRestore: startupSessionRestoreOwner,
            tabRestore: startupRestoreLifecycle,
            settings: settingsState,
            startupPolicy: profileLifecycleBundle.startupPolicy
        )
    lazy var profileAdoption = BrowserProfileAdoptionService(
        currentProfile: currentProfileAuthority,
        profiles: profileManager,
        transitions: profileLifecycleBundle.profileSwitchTransition
    )
    lazy var extensionBridgeComposition = BrowserExtensionBridgeComposition(
        browserManager: self,
        tabCommands: extensionTabCommands
    )
    /// Reached only from `sumiSettings.didSet`; private so feature code cannot use it as a service locator.
    private(set) lazy var settingsAttachment = BrowserSettingsAttachmentCoordinator.live(browserManager: self)
    lazy var webViewCloseRouter = composeWebViewCloseRouter()
    lazy var notificationPresenter = BrowserNotificationPresenter(browserManager: self)
    lazy var shortcutTargetResolver = makeShortcutTargetResolver()
    lazy var shortcutActionRouter = makeShortcutActionRouter()
    lazy var windowCommands = BrowserWindowCommands.live(browserRuntime: self)
    lazy var windowStateReconciler = composeWindowStateReconciler()
    lazy var windowSpaceTransitions = composeWindowSpaceTransitions(
        splitFocus: splitShortcutFocus
    )
    lazy var shellRuntime = BrowserShellRuntime(
        windowSelection: windowSelectionProjection,
        windowTabs: windowTabContext,
        glanceManager: glanceManager,
        windowRegistry: windowRegistry,
        webViewSessions: webViewSessions,
        webViewProtection: webViewRuntime.protectionRuntime,
        webViewCompositor: webViewRuntime.compositorRuntime,
        visibleWebViewPreparation: webViewRuntime.visiblePreparationService,
        webViewLifecycle: webViewRuntime.lifecycleService
    )
    lazy var webViewRoutingService: BrowserWebViewRoutingService = {
        let webViewRuntime = self.webViewRuntime
        let membership = tabCollectionMembershipOwner
        return BrowserWebViewRoutingService(
            tabLookup: { [membership] tabId in
                membership.tab(for: tabId)
            },
            webViewSessions: webViewSessions,
            ownershipQuery: webViewRuntime.ownershipQuery,
            commands: BrowserWebViewRoutingService.Commands.live(
                navigationBroadcast: webViewRuntime.navigationBroadcastOwner,
                processRecovery: webViewRuntime.processRecoveryService,
                trackedAdmission: webViewRuntime.trackedWebViewAdmission,
                rebuild: webViewRuntime.rebuildService,
                refreshCompositor: { [webViewWindowCommands] windowID in
                    webViewWindowCommands.refreshCompositor(in: windowID)
                }
            )
        )
    }()
    let windowSessionPersistence: WindowSessionPersistenceRuntime
    let startupSessionRestoreOwner: BrowserStartupSessionRestoreOwner
    let auxiliaryWindowTeardownRegistry: AuxiliaryWindowTeardownRegistry
    lazy var auxiliaryWindows = composeAuxiliaryWindows()
    let glanceManager: GlanceManager
    lazy var shutdownCleanupService = BrowserShutdownCleanupService(
        extensions: optionalModules.extensions,
        auxiliaryWindows: auxiliaryWindowTeardownRegistry,
        glance: glanceManager,
        shortcutPresentation: shortcutPresentationOwner,
        membership: tabCollectionMembershipOwner,
        webViewLifecycle: webViewRuntime.lifecycleService,
        windowRegistry: { [weak shellRuntime] in shellRuntime?.windowRegistry }
    )
    private(set) lazy var startupProtectionRuntime =
        BrowserStartupProtectionRuntime(
            materializationGate: startupMaterializationGate,
            deferredTabs: BrowserStartupDeferredTabMaterialization(
                membership: tabCollectionMembershipOwner
            ),
            visibleWindows: BrowserStartupVisibleWindowSettlement(
                windows: windowRegistry,
                visuals: shellRuntime.windowVisuals,
                retryMaterialization: { [weak self] windowState in
                    self?.browserTabSelection
                        .retryCurrentPageMaterializationRequests(in: windowState)
                }
            )
        )

    /// Designated init: assign always-on managers from a pre-built kernel graph.
    init(kernel graph: BrowserKernelGraph) {
        precondition(
            graph.tabFactory.webViewSessions === graph.webViewSessions,
            "Browser kernel must give TabManager and WebView runtime one canonical WebView session repository"
        )
        let auxiliaryWindowTeardownRegistry = AuxiliaryWindowTeardownRegistry()
        let glanceManager = GlanceManager()
        self.objectWillChange = graph.objectWillChange
        self.webViewSessions = graph.webViewSessions
        self.windowRegistry = graph.windowRegistry
        self.database = graph.database
        self.liveFolderManager = SumiLiveFolderManager(
            store: SumiLiveFolderStore(database: graph.database)
        )
        self.moduleRegistry = graph.moduleRegistry
        self.sidebarHostRecoveryCoordinator = graph.sidebarHostRecoveryCoordinator
        self.adBlockingModule = graph.adBlockingModule
        self.protectionCoordinator = graph.protectionCoordinator
        self.startupMaterializationGate =
            BrowserStartupMaterializationGate(
                restoration: BrowserStartupProtectionLevelRestoration(
                    protectionCoordinator: graph.protectionCoordinator
                )
            )
        self.adblockZapperStore = graph.adblockZapperStore
        self.profileRetirementStartupPreflight = graph.profileRetirementStartupPreflight
        self.windowSessionPersistence = graph.windowSessionPersistence
        self.profileManager = graph.profileManager
        self.currentProfileAuthority = BrowserCurrentProfileAuthority(
            graph.currentProfile
        )
        self.optionalModules = graph.optionalModules
        self.runtimePortConnection = graph.runtimePortConnection
        self.tabStateStore = graph.tabStateStore
        self.spaceStateOwner = graph.spaceStateOwner
        self.splitGroupStore = graph.splitGroupStore
        self.folderCollectionStateOwner = graph.folderCollectionStateOwner
        self.shortcutPinCollectionStateOwner =
            graph.shortcutPinCollectionStateOwner
        self.tabStructureEventBus = graph.tabStructureEventBus
        self.startupRestoreLifecycle = graph.startupRestoreLifecycle
        self.structuralPersistence = graph.structuralPersistence
        self.profileRuntimeState = graph.profileRuntimeState
        self.tabFactory = graph.tabFactory
        self.folderOpenState = graph.folderOpenState
        self.regularTabCollectionOwner = graph.regularTabCollectionOwner
        self.regularTabLifecycleOwner = graph.regularTabLifecycleOwner
        self.tabClosureService = graph.tabClosureService
        self.activeSelectionOwner = graph.activeSelectionOwner
        self.lazyRestoreCoordinator = graph.lazyRestoreCoordinator
        self.spacePinnedStructureOwner = graph.spacePinnedStructureOwner
        self.tabProfileTransitions = graph.tabProfileTransitions
        self.spaceProfileTransitions = graph.spaceProfileTransitions
        self.profileSelection = graph.profileSelection
        self.profileDeletion = graph.profileDeletion
        self.shortcutExecutionProfileAssignments =
            graph.shortcutExecutionProfileAssignments
        self.sidebarDragRouter = graph.sidebarDragRouter
        self.essentialsShortcutPlacementOwner =
            graph.essentialsShortcutPlacementOwner
        self.shortcutPinStoreOwner = graph.shortcutPinStoreOwner
        self.shortcutPinRuntimeResolutionOwner =
            graph.shortcutPinRuntimeResolutionOwner
        self.shortcutWindowMutationOwner = graph.shortcutWindowMutationOwner
        self.shortcutPresentationOwner = graph.shortcutPresentationOwner
        self.structuralCollectionMutationOwner =
            graph.structuralCollectionMutationOwner
        self.structuralInstallOwner = graph.structuralInstallOwner
        self.tabCollectionMembershipOwner =
            graph.tabCollectionMembershipOwner
        self.extensionTabCommands = graph.extensionTabCommands
        self.auxiliaryMiniWindowTabs = graph.auxiliaryMiniWindowTabs
        self.ephemeralLifecycleOwner = graph.ephemeralLifecycleOwner
        self.structuralLookupCoordinator = graph.structuralLookupCoordinator
        self.sidebarSpaceLifecycle = graph.sidebarSpaceLifecycle
        self.spaceActivation = graph.spaceActivation
        self.liveShortcutTabs = graph.liveShortcutTabs
        self.liveShortcutPresentationRefreshes =
            graph.liveShortcutPresentationRefreshes
        self.shortcutTabMaterializer = graph.shortcutTabMaterializer
        self.shortcutPresentationActivation =
            graph.shortcutPresentationActivation
        self.splitGroupMutations = graph.splitGroupMutations
        self.splitGroupSidebarOrdering = graph.splitGroupSidebarOrdering
        self.splitGroupContainerConversion = graph.splitGroupContainerConversion
        self.splitGroupShortcutMemberRelocation =
            graph.splitGroupShortcutMemberRelocation
        self.splitGroupMembership = graph.splitGroupMembership
        self.regularTabShortcutConversion =
            graph.regularTabShortcutConversion
        self.shortcutPinToRegularTab = graph.shortcutPinToRegularTab
        self.shortcutLiveTabRetirement = graph.shortcutLiveTabRetirement
        self.sidebarPinCommands = graph.sidebarPinCommands
        self.sidebarFolderCommands = graph.sidebarFolderCommands
        self.sidebarRegularTabLifecycleCommands =
            graph.sidebarRegularTabLifecycleCommands
        self.sidebarRegularTabShortcutCommands =
            graph.sidebarRegularTabShortcutCommands
        self.sidebarRegularTabPlacementCommands =
            graph.sidebarRegularTabPlacementCommands
        self.runtimeStore = graph.runtimeStore
        self.startupStateReset = graph.startupStateReset
        self.lastSessionMergeMaterializer =
            graph.lastSessionMergeMaterializer
        self.tabRuntimeLifecycle = graph.tabRuntimeLifecycle
        self.tabResidenceAuthority = graph.tabResidenceAuthority
        self.downloadManager = graph.downloadManager
        self.downloadTransportFactory = graph.downloadTransportFactory
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
        _ = webViewRuntime
        _ = shellRuntime
        _ = shutdownCleanupService
    }

    isolated deinit {
        windowSessionPersistence.flushForBrowserRuntimeTeardown()
        startupServicesStorage?.shutdown()
        shutdownCleanupService.cleanupAfterBrowserRuntimeDeallocation()
        NotificationCenter.default.removeObserver(self)
    }
}
