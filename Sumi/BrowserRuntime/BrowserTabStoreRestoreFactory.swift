import Foundation
import SwiftData

@MainActor
enum BrowserTabStoreRestoreFactory {
    static func make(
        modelContext: ModelContext,
        blockedProfileIDs: Set<UUID>,
        runtimeConnection: TabRuntimePortConnection,
        loadLifecycle: TabStartupRestoreLifecycle,
        structuralStore: TabStructuralSnapshotStore,
        tabFactory: TabFactory,
        structuralLookup: TabStructuralLookupCoordinator,
        structuralInstaller: TabStructuralInstallOwner,
        runtimePreparation: TabRuntimePreparationOwner,
        lazyRestore: TabLazyRestoreCoordinator,
        persistence: TabStructuralPersistenceService
    ) -> TabStoreRestoreService {
        TabStoreRestoreService(
            runtimeConnection: runtimeConnection,
            structuralLookup: structuralLookup,
            loadLifecycle: loadLifecycle,
            executor: TabStoreRestoreAttemptExecutor(
                payloadLoader: TabRestoreLoader(
                    container: modelContext.container,
                    blockedProfileIDs: blockedProfileIDs
                ),
                structuralStore: structuralStore,
                structuralLookup: structuralLookup,
                loadLifecycle: loadLifecycle,
                payloadApplier: TabRestorePayloadApplyService(
                    tabFactory: tabFactory,
                    structuralInstaller: structuralInstaller,
                    runtimePreparation: runtimePreparation,
                    lazyRestore: lazyRestore,
                    persistence: persistence
                )
            )
        )
    }
}
