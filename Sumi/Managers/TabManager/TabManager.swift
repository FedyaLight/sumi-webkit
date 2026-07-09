import AppKit
import Combine
import Observation
import SwiftData
import WebKit

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

    private(set) var runtimeContext: TabManagerRuntimeContext?
    weak var sumiSettings: SumiSettingsService?
    let context: ModelContext
    let persistence: TabSnapshotRepository
    let runtimeStateCoalescer: RuntimeStateCoalescer
    let faviconService: any BrowserFaviconServicing
    let faviconImageService: any BrowserFaviconImageServicing
    let visitedLinkStore: any BrowserVisitedLinkStoreManaging

    lazy var runtimeStore = DefaultTabRuntimeStore(tabManager: self)
    lazy var folderMutationOwner = TabFolderMutationOwner(dependencies: .live(tabManager: self))
    private let spaceCollectionStateOwner = TabSpaceCollectionStateOwner()
    var spaceStateOwner: TabSpaceCollectionStateOwner { spaceCollectionStateOwner }
    let regularTabCollectionStateOwner = RegularTabCollectionStateOwner()
    let selectionStateOwner = TabSelectionStateOwner()
    lazy var profileRuntimeStateOwner = TabProfileRuntimeStateOwner(tabManager: self)
    lazy var runtimePreparationOwner = TabRuntimePreparationOwner(
        runtimeContext: { [weak self] in self?.runtimeContext },
        settings: { [weak self] in self?.sumiSettings }
    )
    lazy var runtimeContextAttachmentOwner = TabRuntimeContextAttachmentOwner(
        dependencies: .live(tabManager: self)
    )
    lazy var regularTabCollectionOwner = RegularTabCollectionOwner(
        tabManager: self,
        stateOwner: regularTabCollectionStateOwner
    )
    lazy var regularTabLifecycleOwner = TabRegularLifecycleOwner(
        dependencies: .live(tabManager: self)
    )
    lazy var tabRemovalOwner = TabRemovalOwner(dependencies: .live(tabManager: self))
    lazy var activeSelectionOwner = TabActiveSelectionOwner(
        dependencies: .live(tabManager: self)
    )
    lazy var regularTabDragService = SidebarRegularTabDragService(dependencies: .live(tabManager: self))
    lazy var lazyRestoreCoordinator = TabLazyRestoreCoordinator(
        spaces: { [weak self] in self?.spaceStateOwner.spaces ?? [] },
        tabsBySpaceSnapshot: { [weak self] in
            self?.regularTabCollectionStateOwner.tabsBySpaceSnapshot() ?? [:]
        },
        resolveTab: { [weak self] id in
            self?.tabCollectionMembershipOwner.tab(for: id)
        }
    )
    lazy var spacePinnedStructureOwner = SpacePinnedStructureOwner(dependencies: .live(tabManager: self))
    lazy var spaceLifecycleOwner = TabSpaceLifecycleOwner(dependencies: .live(tabManager: self))
    lazy var profileAssignmentOwner = TabProfileAssignmentOwner(dependencies: .live(tabManager: self))
    lazy var lastSessionRestoreOwner = TabLastSessionRestoreOwner(dependencies: .live(tabManager: self))
    lazy var shortcutPinCommandOwner = ShortcutPinCommandOwner(dependencies: .live(tabManager: self))
    lazy var sidebarDragRoutingOwner = SidebarDragOperationRoutingOwner(dependencies: .live(tabManager: self))
    lazy var essentialsShortcutPlacementOwner = EssentialsShortcutPlacementOwner(
        spaces: { [weak self] in self?.spaceStateOwner.spaces ?? [] },
        runtimeContext: { [weak self] in self?.runtimeContext },
        essentialPins: { [weak self] profileId in
            self?.shortcutPinCollectionStateOwner.essentialPins(for: profileId) ?? []
        }
    )
    lazy var shortcutPinStoreOwner = ShortcutPinStoreOwner(
        dependencies: .live(tabManager: self)
    )
    lazy var shortcutPinRuntimeResolutionOwner = ShortcutPinRuntimeResolutionOwner(
        spaces: { [weak self] in self?.spaceStateOwner.spaces ?? [] },
        runtimeContext: { [weak self] in self?.runtimeContext },
        faviconService: { [weak self] in
            guard let self else { preconditionFailure("TabManager dependency used after deallocation") }
            return self.faviconService
        }
    )
    lazy var shortcutPinConversionOwner = ShortcutPinConversionOwner(tabManager: self)
    lazy var shortcutDragOperationOwner = ShortcutDragOperationOwner(tabManager: self)
    lazy var shortcutPresentationOwner = TabShortcutPresentationOwner(tabManager: self)
    lazy var shortcutContainerRemovalOwner = ShortcutContainerRemovalOwner(
        pinnedByProfile: { [weak self] in
            self?.shortcutPinCollectionStateOwner.pinnedByProfileSnapshot() ?? [:]
        },
        setPinnedTabs: { [weak self] pins, profileId in
            self?.structuralCollectionMutationOwner.setPinnedTabs(pins, for: profileId)
        },
        removeRegularTab: { [weak self] tabId, spaceId, currentSpaceId in
            _ = self?.regularTabCollectionOwner.remove(
                tabId,
                from: spaceId,
                currentSpaceId: currentSpaceId
            )
        },
        currentSpaceId: { [weak self] in
            self?.spaceStateOwner.currentSpace?.id
        }
    )
    lazy var shortcutLiveTabOwner = ShortcutLiveTabOwner(
        dependencies: .live(tabManager: self)
    )
    lazy var spaceLauncherProjectionOwner = SpaceLauncherProjectionOwner(tabManager: self)

    let splitGroupCollectionStateOwner = SplitGroupCollectionStateOwner()
    lazy var splitGroupRepairOwner = TabManagerSplitGroupRepairOwner(
        shortcutPin: { [weak self] id in
            self?.shortcutPinCollectionStateOwner.shortcutPin(by: id)
        },
        tab: { [weak self] id in
            self?.tabCollectionMembershipOwner.tab(for: id)
        },
        folderSpaceId: { [weak self] folderId in
            self?.folderCollectionStateOwner.spaceId(for: folderId)
        },
        spaceExists: { [weak self] spaceId in
            self?.spaceStateOwner.contains(spaceId: spaceId) ?? false
        }
    )
    lazy var splitGroupStructureOwner = TabSplitGroupStructureOwner(
        dependencies: .live(tabManager: self)
    )

    let folderCollectionStateOwner = TabFolderCollectionStateOwner()

    let shortcutPinCollectionStateOwner = ShortcutPinCollectionStateOwner()

    let transientTabRegistryOwner = TabTransientTabRegistryOwner()
    lazy var structuralCollectionMutationOwner = TabStructuralCollectionMutationOwner(
        dependencies: .live(tabManager: self)
    )
    lazy var structuralInstallOwner = TabStructuralInstallOwner(
        dependencies: .live(tabManager: self)
    )
    lazy var tabCollectionMembershipOwner = TabCollectionMembershipOwner(
        tabManager: self,
        structuralLookupOwner: structuralLookupCoordinator.lookupOwner,
        transientTabRegistryOwner: transientTabRegistryOwner
    )
    lazy var transientWebKitTabLifecycleOwner = TabTransientWebKitTabLifecycleOwner(
        dependencies: .live(tabManager: self)
    )
    lazy var ephemeralLifecycleOwner = TabEphemeralLifecycleOwner(
        prepareTabForRuntime: { [weak self] tab in
            self?.runtimePreparationOwner.prepare(tab)
        },
        faviconService: { [weak self] in
            guard let self else { preconditionFailure("TabManager dependency used after deallocation") }
            return self.faviconService
        },
        faviconImageService: { [weak self] in
            guard let self else { preconditionFailure("TabManager dependency used after deallocation") }
            return self.faviconImageService
        },
        visitedLinkStore: { [weak self] in
            guard let self else { preconditionFailure("TabManager dependency used after deallocation") }
            return self.visitedLinkStore
        }
    )
    /// Emitted when tab structure changes without a corresponding `@Published` update (e.g. transient shortcut live tabs). Not used for persistence completion—`scheduleStructuralPersistence()` does not send this.
    let structuralChanges = PassthroughSubject<Void, Never>()
    lazy var structuralLookupCoordinator = TabStructuralLookupCoordinator(
        structuralChanges: structuralChanges,
        tabsBySpace: { [weak self] in
            self?.regularTabCollectionStateOwner.tabsBySpaceSnapshot() ?? [:]
        },
        transientShortcutTabsByWindow: { [weak self] in
            self?.transientTabRegistryOwner.transientShortcutTabsByWindow ?? [:]
        },
        transientExtensionTabsByID: { [weak self] in
            self?.transientTabRegistryOwner.transientExtensionTabsByID ?? [:]
        },
        auxiliaryMiniWindowTabsByID: { [weak self] in
            self?.transientTabRegistryOwner.auxiliaryMiniWindowTabsByID ?? [:]
        }
    )
    var structuralLookupBatchFlushCount: Int { structuralLookupCoordinator.batchFlushCount }
    var structuralLookupImmediateFlushCount: Int { structuralLookupCoordinator.immediateFlushCount }
    private lazy var faviconPresentationRefreshOwner = TabFaviconPresentationRefreshOwner(
        notificationCenter: .default,
        debounceNanoseconds: Self.faviconPresentationRefreshDebounceNanoseconds,
        tabsNeedingRefresh: { [weak self] in
            guard let self else { return [] }
            return self.regularTabCollectionStateOwner.allTabs()
                + self.transientTabRegistryOwner.transientShortcutTabs
        },
        requestStructuralPublish: { [weak self] in
            self?.requestStructuralPublish()
        }
    )
    // Space activation to resume after a deferred profile switch
    var pendingSpaceActivation: UUID?

    private(set) var hasLoadedInitialData = false

    func markInitialDataLoadStarted() {
        hasLoadedInitialData = false
    }

    func markInitialDataLoadFinished() {
        hasLoadedInitialData = true
    }

    init(
        runtimeContext: TabManagerRuntimeContext? = nil,
        context: ModelContext,
        loadPersistedState: Bool = true,
        faviconService: any BrowserFaviconServicing = TabDependencyIsolationDefaults.faviconService,
        faviconImageService: any BrowserFaviconImageServicing = TabDependencyIsolationDefaults.faviconImageService,
        visitedLinkStore: any BrowserVisitedLinkStoreManaging = TabDependencyIsolationDefaults.visitedLinkStore
    ) {
        self.runtimeContext = runtimeContext
        self.context = context
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
        faviconPresentationRefreshOwner.startObserving()
        if loadPersistedState {
            Task { @MainActor in
                storeRestore.loadFromStore()
            }
        }
    }

    deinit {
        // MEMORY LEAK FIX: Clean up all tab references and break potential cycles.
        // Scheduled persistence and startup restore tasks are cancelled by the
        // owning TabStructuralPersistenceOwner/TabStoreRestoreOwner deinits.
        MainActor.assumeIsolated {
            faviconPresentationRefreshOwner.stop()
            regularTabCollectionStateOwner.removeAll()
            splitGroupCollectionStateOwner.removeAll()
            folderCollectionStateOwner.removeAll()
            shortcutPinCollectionStateOwner.removeAll()
            transientTabRegistryOwner.removeAll()
            structuralLookupCoordinator.removeAll()
            spaceCollectionStateOwner.removeAll()
            selectionStateOwner.replaceCurrentTab(nil)
            runtimeContext = nil
        }

        RuntimeDiagnostics.debug("Cleaned up all tab resources.", category: "TabManager")
    }

    func notifyTransientShortcutStateChanged() {
        structuralLookupCoordinator.notifyTransientShortcutStateChanged()
    }

    func rebuildTabLookup() {
        structuralLookupCoordinator.rebuild()
    }

    @discardableResult
    func withStructuralUpdateTransaction<T>(_ operation: () throws -> T) rethrows -> T {
        try structuralLookupCoordinator.withTransaction(operation)
    }

    func requestStructuralPublish() {
        structuralLookupCoordinator.requestPublish()
    }

    func queueTabLookupEntries(removing previousTabs: [Tab], with currentTabs: [Tab]) {
        structuralLookupCoordinator.queueEntries(removing: previousTabs, with: currentTabs)
    }

    static let defaultRuntimeStatePersistDebounceNanoseconds: UInt64 = 250_000_000

    // MARK: - Structural Persistence and Store Restore Composition

    lazy var structuralPersistence = TabStructuralPersistenceOwner(
        persistence: persistence,
        runtimeStateCoalescer: runtimeStateCoalescer,
        dependencies: .live(tabManager: self)
    )
    lazy var storeRestore = TabStoreRestoreOwner(dependencies: .live(tabManager: self))

    var structuralDirtySet: TabStructuralDirtySet {
        structuralPersistence.dirtySet
    }

    var scheduledStructuralPersistTask: Task<Void, Never>? {
        structuralPersistence.scheduledPersistTask
    }

    public nonisolated func scheduleStructuralPersistence() {
        Task { @MainActor [weak self] in
            self?.structuralPersistence.scheduleStructuralPersistenceFromMain()
        }
    }

    /// Explicit full reconcile path for restore, repair, fallback, and termination only.
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
    /// Single controlled write path for the `private(set)` `runtimeContext`, used by
    /// `runtimeContextAttachmentOwner`'s wiring. Keeping this a named method (rather than
    /// widening the property setter to `internal`) preserves the invariant that only the
    /// attachment flow reassigns the runtime context.
    func installRuntimeContext(_ context: TabManagerRuntimeContext) {
        runtimeContext = context
    }

    func requireRuntimeContext() -> TabManagerRuntimeContext {
        guard let runtimeContext else {
            preconditionFailure(
                "TabManager.runtimeContext is nil. BrowserManagerRuntimeWiring.attach(to:) must run before destructive tab operations."
            )
        }
        return runtimeContext
    }

}
