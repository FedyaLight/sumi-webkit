import AppKit
import Combine
import Observation
import SwiftData
import SumiWebRuntime

@MainActor
class TabManager: ObservableObject {
    private static let faviconPresentationRefreshDebounceNanoseconds: UInt64 = 250_000_000

    enum TabManagerError: LocalizedError {
        case spaceNotFound(UUID)

        var errorDescription: String? {
            switch self {
            case .spaceNotFound(let id):
                return "Space with id \(id.uuidString) was not found."
            }
        }
    }

    private(set) var runtimePorts: RuntimePortRegistry?
    weak var sumiSettings: SumiSettingsService?
    let context: ModelContext
    let structuralSnapshotStore: TabStructuralSnapshotStore
    let selectionStore: TabSelectionStore
    let runtimeStateStore: TabRuntimeStateStore
    let runtimeStateCoalescer: RuntimeStateCoalescer
    let faviconService: any BrowserFaviconServicing
    let faviconCapabilities: BrowserFaviconCapabilities
    let visitedLinkStore: any BrowserVisitedLinkStoreManaging
    let tabFactory: TabFactory

    let stateStore = TabStateStore()
    var spaceStateOwner: TabSpaceCollectionStateOwner { stateStore.spaces }
    var regularTabCollectionStateOwner: RegularTabCollectionStateOwner { stateStore.regularTabs }
    var selectionStateOwner: TabSelectionStateOwner { stateStore.selection }
    var splitGroupCollectionStateOwner: SplitGroupCollectionStateOwner { stateStore.splitGroups }
    var folderCollectionStateOwner: TabFolderCollectionStateOwner { stateStore.folders }
    var shortcutPinCollectionStateOwner: ShortcutPinCollectionStateOwner { stateStore.shortcutPins }
    var transientTabRegistryOwner: TabTransientTabRegistryOwner { stateStore.transientTabs }
    let tabStructureEventBus: TabStructureEventBus
    let startupRestoreLifecycle: TabStartupRestoreLifecycle

    lazy var structureOwners = TabStructureOwnerBag(tabManager: self)
    lazy var shortcutOwners = TabShortcutOwnerBag(tabManager: self)
    lazy var lifecycleOwners = TabLifecycleOwnerBag(
        tabManager: self,
        faviconPresentationRefreshDebounceNanoseconds: Self.faviconPresentationRefreshDebounceNanoseconds
    )
    lazy var runtimeStore = DefaultTabRuntimeStore(
        state: stateStore,
        membership: tabCollectionMembershipOwner,
        regularTabs: regularTabCollectionOwner,
        presentation: shortcutPresentationOwner
    )
    lazy var structuralPersistence = TabStructuralPersistenceService(
        structuralStore: structuralSnapshotStore,
        selectionStore: selectionStore,
        runtimeStateCoalescer: runtimeStateCoalescer,
        state: stateStore,
        profileRuntimeState: profileRuntimeStateOwner
    )
    lazy var storeRestore = TabStoreRestoreService(
        modelContainer: context.container,
        structuralStore: structuralSnapshotStore,
        tabFactory: tabFactory,
        runtimePorts: { [weak self] in self?.runtimePorts },
        structuralLookup: structuralLookupCoordinator,
        loadLifecycle: startupRestoreLifecycle,
        structuralInstaller: structuralInstallOwner,
        splitGroupStructure: splitGroupStructureOwner,
        runtimePreparation: runtimePreparationOwner,
        lazyRestore: lazyRestoreCoordinator,
        persistence: structuralPersistence
    )
    lazy var startupStateReset = TabStartupStateReset(
        runtimePortsProvider: { [weak self] in self?.runtimePorts },
        state: stateStore,
        lazyRestore: lazyRestoreCoordinator,
        persistence: structuralPersistence,
        membership: tabCollectionMembershipOwner,
        structuralMutations: structuralCollectionMutationOwner,
        structuralLookup: structuralLookupCoordinator
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

    var structuralLookupBatchFlushCount: Int { structuralLookupCoordinator.batchFlushCount }
    var structuralLookupImmediateFlushCount: Int { structuralLookupCoordinator.immediateFlushCount }
    var structuralMutationRevision: UInt64 { structuralLookupCoordinator.mutationRevision }
    var pendingSpaceActivation: UUID?

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
        self.runtimePorts = runtimePorts
        self.context = context
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
        self.runtimeStateCoalescer = RuntimeStateCoalescer(
            debounceNanoseconds: Self.defaultRuntimeStatePersistDebounceNanoseconds,
            persistBatch: { runtimeStates in
                await runtimeStateStore.persist(runtimeStates)
            }
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
            structuralLookupCoordinator.removeAll()
            runtimePorts = nil
        }
        RuntimeDiagnostics.debug("Cleaned up all tab resources.", category: "TabManager")
    }

    func notifyTransientShortcutStateChanged() {
        structuralLookupCoordinator.notifyTransientShortcutStateChanged()
    }

    func rebuildTabLookup() { structuralLookupCoordinator.rebuild() }

    @discardableResult
    func withStructuralUpdateTransaction<T>(_ operation: () throws -> T) rethrows -> T {
        try structuralLookupCoordinator.withTransaction(operation)
    }

    func requestStructuralPublish() { structuralLookupCoordinator.requestPublish() }

    func queueTabLookupEntries(removing previousTabs: [Tab], with currentTabs: [Tab]) {
        structuralLookupCoordinator.queueEntries(removing: previousTabs, with: currentTabs)
    }

    static let defaultRuntimeStatePersistDebounceNanoseconds: UInt64 = 250_000_000

    var structuralDirtySet: TabStructuralDirtySet { structuralPersistence.dirtySet }
    var scheduledStructuralPersistTask: Task<Void, Never>? { structuralPersistence.scheduledPersistTask }

    public nonisolated func scheduleStructuralPersistence() {
        Task { @MainActor [weak self] in
            self?.structuralPersistence.scheduleStructuralPersistenceFromMain()
        }
    }

    public nonisolated func persistFullReconcileAwaitingResult(
        reason: String = "explicit full reconcile"
    ) async -> Bool {
        let owner = await MainActor.run { [weak self] in self?.structuralPersistence }
        guard let owner else { return false }
        return await owner.persistFullReconcileAwaitingResult(reason: reason)
    }

    @discardableResult
    public nonisolated func flushRuntimeStatePersistenceAwaitingResult() async -> Int {
        await runtimeStateCoalescer.flushImmediately()
    }
}

extension TabManager {
    func installRuntimePorts(_ ports: RuntimePortRegistry) {
        runtimePorts = ports
    }

    func requireRuntimePorts() -> RuntimePortRegistry {
        guard let runtimePorts else {
            preconditionFailure(
                "TabManager.runtimePorts is nil. BrowserManagerRuntimeWiring.attach(to:) must run before destructive tab operations."
            )
        }
        return runtimePorts
    }
}
