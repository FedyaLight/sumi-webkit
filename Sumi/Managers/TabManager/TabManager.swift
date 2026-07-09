import AppKit
import Combine
import Observation
import SwiftData
import WebKit
import SumiBrowserCore

@MainActor
class TabManager: ObservableObject, TabStructureStore {
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
    let persistence: TabSnapshotRepository
    let runtimeStateCoalescer: RuntimeStateCoalescer
    let faviconService: any BrowserFaviconServicing
    let faviconImageService: any BrowserFaviconImageServicing
    let visitedLinkStore: any BrowserVisitedLinkStoreManaging

    private let spaceCollectionStateOwner = TabSpaceCollectionStateOwner()
    var spaceStateOwner: TabSpaceCollectionStateOwner { spaceCollectionStateOwner }
    let regularTabCollectionStateOwner = RegularTabCollectionStateOwner()
    let selectionStateOwner = TabSelectionStateOwner()
    let splitGroupCollectionStateOwner = SplitGroupCollectionStateOwner()
    let folderCollectionStateOwner = TabFolderCollectionStateOwner()
    let shortcutPinCollectionStateOwner = ShortcutPinCollectionStateOwner()
    let transientTabRegistryOwner = TabTransientTabRegistryOwner()
    let structuralChanges = PassthroughSubject<Void, Never>()
    let tabStructureEventBus: TabStructureEventBus

    let structureOwners: TabStructureOwnerBag
    let shortcutOwners: TabShortcutOwnerBag
    let lifecycleOwners: TabLifecycleOwnerBag
    let persistenceOwners: TabPersistenceOwnerBag

    var structuralLookupBatchFlushCount: Int { structuralLookupCoordinator.batchFlushCount }
    var structuralLookupImmediateFlushCount: Int { structuralLookupCoordinator.immediateFlushCount }
    var pendingSpaceActivation: UUID?
    private(set) var hasLoadedInitialData = false

    func markInitialDataLoadStarted() { hasLoadedInitialData = false }
    func markInitialDataLoadFinished() {
        hasLoadedInitialData = true
        tabStructureEventBus.publishInitialDataLoaded()
    }

    init(
        runtimePorts: RuntimePortRegistry? = nil,
        context: ModelContext,
        loadPersistedState: Bool = true,
        tabStructureEventBus: TabStructureEventBus? = nil,
        faviconService: any BrowserFaviconServicing = TabDependencyIsolationDefaults.faviconService,
        faviconImageService: any BrowserFaviconImageServicing = TabDependencyIsolationDefaults.faviconImageService,
        visitedLinkStore: any BrowserVisitedLinkStoreManaging = TabDependencyIsolationDefaults.visitedLinkStore
    ) {
        self.runtimePorts = runtimePorts
        self.context = context
        self.tabStructureEventBus = tabStructureEventBus ?? BrowserCompositionRoot.makeTabStructureEventBus()
        self.faviconService = faviconService
        self.faviconImageService = faviconImageService
        self.visitedLinkStore = visitedLinkStore
        let persistence = TabSnapshotRepository(container: context.container)
        self.persistence = persistence
        self.runtimeStateCoalescer = RuntimeStateCoalescer(
            debounceNanoseconds: Self.defaultRuntimeStatePersistDebounceNanoseconds,
            persistBatch: { runtimeStates in
                await persistence.persistRuntimeStates(runtimeStates)
            }
        )
        let structureOwners = TabStructureOwnerBag()
        let shortcutOwners = TabShortcutOwnerBag()
        let lifecycleOwners = TabLifecycleOwnerBag(
            faviconPresentationRefreshDebounceNanoseconds: Self.faviconPresentationRefreshDebounceNanoseconds
        )
        let persistenceOwners = TabPersistenceOwnerBag()
        self.structureOwners = structureOwners
        self.shortcutOwners = shortcutOwners
        self.lifecycleOwners = lifecycleOwners
        self.persistenceOwners = persistenceOwners
        structureOwners.bind(self)
        shortcutOwners.bind(self)
        lifecycleOwners.bind(self)
        persistenceOwners.bind(self)
        lifecycleOwners.faviconPresentationRefreshOwner.startObserving()
        if loadPersistedState {
            // Capture `self` weakly so a short-lived TabManager (tests) does not
            // touch persistence bags after deallocation.
            Task { @MainActor [weak self] in
                self?.persistenceOwners.storeRestore.loadFromStore()
            }
        }
    }

    deinit {
        MainActor.assumeIsolated {
            lifecycleOwners.faviconPresentationRefreshOwner.stop()
            regularTabCollectionStateOwner.removeAll()
            splitGroupCollectionStateOwner.removeAll()
            folderCollectionStateOwner.removeAll()
            shortcutPinCollectionStateOwner.removeAll()
            transientTabRegistryOwner.removeAll()
            structuralLookupCoordinator.removeAll()
            spaceCollectionStateOwner.removeAll()
            selectionStateOwner.replaceCurrentTab(nil)
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
