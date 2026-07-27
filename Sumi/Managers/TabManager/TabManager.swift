import AppKit
import Combine
import Observation
import SumiWebRuntime

@MainActor
class TabManager: ObservableObject {
    nonisolated(unsafe) let objectWillChange: ObservableObjectPublisher
    let runtimePortConnection: TabRuntimePortConnection
    let database: SumiDatabase
    let profileReferenceAdmission: ProfileReferenceAdmissionLedger
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
    let tabStructureEventBus: TabStructureEventBus
    let startupRestorePolicy: TabStartupRestorePolicy
    let startupRestoreLifecycle: TabStartupRestoreLifecycle

    init(
        database: SumiDatabase,
        webViewSessions: WebViewSessionRepository,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger,
        initialRuntimePorts: RuntimePortRegistry? = nil,
        loadPersistedState: Bool = true,
        automaticallyStartPersistedStateLoad: Bool = true,
        tabStructureEventBus: TabStructureEventBus? = nil,
        objectWillChange: ObservableObjectPublisher = .init(),
        faviconService: any BrowserFaviconServicing = TabDependencyIsolationDefaults.faviconService,
        faviconCapabilities: BrowserFaviconCapabilities = TabDependencyIsolationDefaults.faviconCapabilities,
        visitedLinkStore: any BrowserVisitedLinkStoreManaging = TabDependencyIsolationDefaults.visitedLinkStore
    ) {
        self.objectWillChange = objectWillChange
        self.runtimePortConnection = TabRuntimePortConnection(initialRuntimePorts)
        self.database = database
        self.profileReferenceAdmission = profileReferenceAdmission
        let stateStore = TabStateStore()
        self.stateStore = stateStore
        let eventBus = tabStructureEventBus ?? TabStructureEventBus()
        self.tabStructureEventBus = eventBus
        self.startupRestorePolicy = TabStartupRestorePolicy(
            isEnabled: loadPersistedState,
            automaticallyStarts: automaticallyStartPersistedStateLoad,
            requestedStructuralRevision: 0
        )
        self.startupRestoreLifecycle = TabStartupRestoreLifecycle(eventBus: eventBus)
        self.faviconService = faviconService
        self.faviconCapabilities = faviconCapabilities
        self.visitedLinkStore = visitedLinkStore
        self.tabFactory = TabFactory(
            webViewSessions: webViewSessions,
            faviconService: faviconService,
            faviconCapabilities: faviconCapabilities,
            visitedLinkStore: visitedLinkStore
        )
        let writes = TabStoreWriteExecutor(database: database)
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
            liveShortcutTabs: stateStore.transientTabs
        )
        self.profileRuntimeState = profileRuntimeState
        self.structuralPersistence = TabStructuralPersistenceService(
            structuralStore: structuralSnapshotStore,
            selectionStore: selectionStore,
            runtimeStateCoalescer: runtimeStateCoalescer,
            state: stateStore
        )
    }
}
