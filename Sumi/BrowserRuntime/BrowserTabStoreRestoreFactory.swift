import Foundation

@MainActor
enum BrowserTabStoreRestoreFactory {
    static func make(
        database: SumiDatabase,
        blockedProfileIDs: Set<UUID>,
        runtimeConnection: TabRuntimePortConnection,
        loadLifecycle: TabStartupRestoreLifecycle,
        structuralStore: TabStructuralSnapshotStore,
        tabFactory: TabFactory,
        structuralLookup: TabStructuralLookupCoordinator,
        structuralInstaller: TabStructuralInstallOwner,
        runtimePreparation: TabRuntimePreparationOwner,
        persistence: TabStructuralPersistenceService
    ) -> TabStoreRestoreService {
        TabStoreRestoreService(
            runtimeConnection: runtimeConnection,
            structuralLookup: structuralLookup,
            loadLifecycle: loadLifecycle,
            executor: TabStoreRestoreAttemptExecutor(
                payloadLoader: TabRestoreLoader(
                    database: database,
                    blockedProfileIDs: blockedProfileIDs
                ),
                structuralStore: structuralStore,
                structuralLookup: structuralLookup,
                loadLifecycle: loadLifecycle,
                payloadApplier: TabRestorePayloadApplyService(
                    tabFactory: tabFactory,
                    structuralInstaller: structuralInstaller,
                    runtimePreparation: runtimePreparation,
                    persistence: persistence
                )
            )
        )
    }
}
