import AppKit
import Combine
import Observation
import SumiWebRuntime
import SwiftData

@MainActor
class TabManager: ObservableObject {
    let runtimePortConnection: TabRuntimePortConnection
    var runtimePorts: RuntimePortRegistry? { runtimePortConnection.current }
    weak var sumiSettings: SumiSettingsService?
    let context: ModelContext
    let structuralSnapshotStore: TabStructuralSnapshotStore
    let selectionStore: TabSelectionStore
    let runtimeStateStore: TabRuntimeStateStore
    let runtimeStateCoalescer: RuntimeStateCoalescer
    let structuralPersistence: TabStructuralPersistenceService
    let profileRuntimeState: SpaceProfileRuntimeStateService
    let faviconService: any BrowserFaviconServicing
    let faviconCapabilities: BrowserFaviconCapabilities
    let visitedLinkStore: any BrowserVisitedLinkStoreManaging
    let tabFactory: TabFactory

    let stateStore: TabStateStore
    var spaceStateOwner: TabSpaceCollectionStateOwner { stateStore.spaces }
    var regularTabCollectionStateOwner: RegularTabCollectionStateOwner { stateStore.regularTabs }
    var selectionStateOwner: TabSelectionStateOwner { stateStore.selection }
    var splitGroupStore: SplitGroupStore { stateStore.splitGroups }
    var folderCollectionStateOwner: TabFolderCollectionStateOwner { stateStore.folders }
    var shortcutPinCollectionStateOwner: ShortcutPinCollectionStateOwner { stateStore.shortcutPins }
    var transientTabRegistryOwner: TabTransientTabRegistryOwner { stateStore.transientTabs }
    let tabStructureEventBus: TabStructureEventBus
    let startupRestoreLifecycle: TabStartupRestoreLifecycle

    lazy var structureOwners = TabStructureOwnerBag(tabManager: self)
    lazy var shortcutOwners = TabShortcutOwnerBag(tabManager: self)
    lazy var lifecycleOwners = TabLifecycleOwnerBag(tabManager: self)
    lazy var spaceServices = TabSpaceServices.live(tabManager: self)
    lazy var liveShortcutTabs = LiveShortcutTabRegistry(tabManager: self)
    lazy var liveShortcutTabBatchRetirement = LiveShortcutTabBatchRetirement(tabManager: self)
    lazy var liveShortcutPresentationRefreshes = LiveShortcutPresentationRefreshService(
        registry: liveShortcutTabs,
        resolution: shortcutPinRuntimeResolutionOwner
    )
    lazy var shortcutTabWindowQuery = ShortcutTabWindowQuery(runtimeConnection: runtimePortConnection)
    lazy var shortcutTabBindings = ShortcutTabBindingSynchronizer(tabManager: self)
    lazy var shortcutTabMaterializer = ShortcutTabMaterializer(tabManager: self)
    lazy var shortcutPresentationActivation = ShortcutPresentationActivationService(
        tabManager: self
    )
    lazy var splitGroupMutations = SplitGroupMutationService(tabManager: self)
    lazy var splitGroupSidebarOrdering = SplitGroupSidebarOrderingService(
        tabManager: self
    )
    lazy var splitGroupMembership = SplitGroupMembershipQuery(tabManager: self)
    lazy var regularTabShortcutConversion = RegularTabShortcutConversionService(
        tabManager: self
    )
    lazy var shortcutPinToRegularTab = ShortcutPinToRegularTabService(
        tabManager: self
    )
    lazy var shortcutLiveTabRetirement = ShortcutLiveTabRetirementService(tabManager: self)
    lazy var shortcutTabPromotion = ShortcutTabPromotionService(tabManager: self)
    lazy var runtimeTeardown = TabRuntimeTeardownService(
        persistence: structuralPersistence,
        membership: tabCollectionMembershipOwner,
        webViewSessions: tabFactory.webViewSessions
    )
    lazy var runtimeStore = DefaultTabRuntimeStore(
        state: stateStore,
        membership: tabCollectionMembershipOwner,
        regularTabs: regularTabCollectionOwner,
        presentation: shortcutPresentationOwner
    )
    lazy var storeRestore = TabStoreRestoreService(
        modelContainer: context.container,
        structuralStore: structuralSnapshotStore,
        tabFactory: tabFactory,
        runtimePorts: { [weak self] in self?.runtimePorts },
        structuralLookup: structuralLookupCoordinator,
        loadLifecycle: startupRestoreLifecycle,
        structuralInstaller: structuralInstallOwner,
        runtimePreparation: runtimePreparationOwner,
        lazyRestore: lazyRestoreCoordinator,
        persistence: structuralPersistence
    )
    lazy var startupStateReset = TabStartupStateReset(
        state: stateStore,
        lazyRestore: lazyRestoreCoordinator,
        persistence: structuralPersistence,
        structuralMutations: structuralCollectionMutationOwner,
        structuralLookup: structuralLookupCoordinator,
        splitGroupStore: splitGroupStore,
        splitGroupMutations: splitGroupMutations,
        liveShortcutTabs: liveShortcutTabs,
        liveShortcutRetirement: liveShortcutTabBatchRetirement,
        runtimePorts: { [weak self] in self?.runtimePorts },
        runtimeTeardown: runtimeTeardown
    )
    lazy var lastSessionMergeMaterializer = TabLastSessionMergeMaterializer(
        state: stateStore,
        structuralMutations: structuralCollectionMutationOwner,
        membership: tabCollectionMembershipOwner,
        normalizeSpacePinnedShortcuts: {
            [spacePinnedStructureOwner] in
            spacePinnedStructureOwner.normalizedSpacePinnedShortcuts($0)
        },
        tabFactory: tabFactory,
        lazyRestore: lazyRestoreCoordinator,
        structuralLookup: structuralLookupCoordinator,
        persistence: structuralPersistence,
        announceStateChange: { [objectWillChange] in objectWillChange.send() }
    )
    init(
        runtimePorts: RuntimePortRegistry? = nil,
        context: ModelContext,
        webViewSessions: WebViewSessionRepository,
        loadPersistedState: Bool = true,
        automaticallyStartPersistedStateLoad: Bool = true,
        tabStructureEventBus: TabStructureEventBus? = nil,
        faviconService: any BrowserFaviconServicing = TabDependencyIsolationDefaults.faviconService,
        faviconCapabilities: BrowserFaviconCapabilities = TabDependencyIsolationDefaults.faviconCapabilities,
        visitedLinkStore: any BrowserVisitedLinkStoreManaging = TabDependencyIsolationDefaults.visitedLinkStore
    ) {
        self.runtimePortConnection = TabRuntimePortConnection(runtimePorts)
        self.context = context
        let stateStore = TabStateStore()
        self.stateStore = stateStore
        let eventBus = tabStructureEventBus ?? TabStructureEventBus()
        self.tabStructureEventBus = eventBus
        self.startupRestoreLifecycle = TabStartupRestoreLifecycle(
            shouldLoadPersistedState: loadPersistedState,
            automaticallyStartAfterRuntimeAttachment: automaticallyStartPersistedStateLoad,
            eventBus: eventBus
        )
        self.faviconService = faviconService
        self.faviconCapabilities = faviconCapabilities
        self.visitedLinkStore = visitedLinkStore
        self.tabFactory = TabFactory(
            webViewSessions: webViewSessions,
            faviconService: faviconService,
            faviconCapabilities: faviconCapabilities,
            visitedLinkStore: visitedLinkStore
        )
        let writes = TabStoreWriteExecutor(container: context.container)
        let structuralSnapshotStore = TabStructuralSnapshotStore(writes: writes)
        let selectionStore = TabSelectionStore(writes: writes)
        let runtimeStateStore = TabRuntimeStateStore(writes: writes)
        self.structuralSnapshotStore = structuralSnapshotStore
        self.selectionStore = selectionStore
        self.runtimeStateStore = runtimeStateStore
        let runtimeStateCoalescer = RuntimeStateCoalescer(
            persistBatch: { runtimeStates in
                await runtimeStateStore.persist(runtimeStates)
            }
        )
        self.runtimeStateCoalescer = runtimeStateCoalescer
        let profileRuntimeState = SpaceProfileRuntimeStateService(
            spaces: stateStore.spaces,
            regularTabs: stateStore.regularTabs,
            liveShortcutTabs: { [weak stateStore] in
                stateStore?.transientTabs.transientShortcutTabs ?? []
            }
        )
        self.profileRuntimeState = profileRuntimeState
        self.structuralPersistence = TabStructuralPersistenceService(
            structuralStore: structuralSnapshotStore,
            selectionStore: selectionStore,
            runtimeStateCoalescer: runtimeStateCoalescer,
            state: stateStore
        )
        lifecycleOwners.faviconPresentationRefreshOwner.startObserving()
        if let runtimePorts {
            lifecycleOwners.runtimePortsAttachmentOwner.attach(runtimePorts)
        }
    }

    deinit {
        MainActor.assumeIsolated {
            lifecycleOwners.faviconPresentationRefreshOwner.stop()
            stateStore.removeAll()
            // Do not materialize the lazy structural owner bag while `self`
            // is already deallocating. If the lookup was used, its bag releases
            // the index immediately after this deinit; stateStore removal above
            // already drops the canonical tab graph.
            runtimePortConnection.detach()
        }
        RuntimeDiagnostics.debug("Cleaned up all tab resources.", category: "TabManager")
    }
}

extension TabManager {
    func installRuntimePorts(_ ports: RuntimePortRegistry) {
        runtimePortConnection.attach(ports)
    }

    /// Stops work that may resume through BrowserManager-backed ports after
    /// the browser root has begun deallocation. Lazy persistence services are
    /// touched only if startup restore already reached them.
    func detachBrowserRuntime() {
        let canceledBeforeStoreRestore = startupRestoreLifecycle.cancelPendingStart()
        if startupRestoreLifecycle.didStartPersistedStateLoad,
           canceledBeforeStoreRestore == false {
            storeRestore.cancelPendingRestore()
            structuralPersistence.cancelPendingPersistence()
        }
        runtimePortConnection.detach()
    }

    func requireRuntimePorts() -> RuntimePortRegistry {
        runtimePortConnection.requireLease()
    }
}
