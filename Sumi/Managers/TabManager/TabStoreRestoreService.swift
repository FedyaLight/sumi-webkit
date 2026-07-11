import Foundation
import SumiDomain
import SwiftData

/// Restores the persisted tab structure from the SwiftData store at startup and
/// schedules repair persistence when restored data needed normalization.
@MainActor
final class TabStoreRestoreService {
    private let payloadLoader: any TabRestorePayloadLoading
    private let structuralStore: TabStructuralSnapshotStore
    private let tabFactory: TabFactory
    private let defaultProfileId: () -> UUID?
    private let structuralRevision: () -> UInt64
    private let loadLifecycle: TabStartupRestoreLifecycle
    private let structuralInstaller: TabStructuralInstallOwner
    private let runtimePreparation: TabRuntimePreparationOwner
    private let lazyRestore: TabLazyRestoreCoordinator
    private let persistence: TabStructuralPersistenceService
    private let syncWorkspaceTheme: (Space) -> Void
    private(set) var startupRestoreTask: Task<Void, Never>?

    init(
        payloadLoader: any TabRestorePayloadLoading,
        structuralStore: TabStructuralSnapshotStore,
        tabFactory: TabFactory,
        defaultProfileId: @escaping () -> UUID?,
        structuralRevision: @escaping () -> UInt64,
        loadLifecycle: TabStartupRestoreLifecycle,
        structuralInstaller: TabStructuralInstallOwner,
        runtimePreparation: TabRuntimePreparationOwner,
        lazyRestore: TabLazyRestoreCoordinator,
        persistence: TabStructuralPersistenceService,
        syncWorkspaceTheme: @escaping (Space) -> Void
    ) {
        self.payloadLoader = payloadLoader
        self.structuralStore = structuralStore
        self.tabFactory = tabFactory
        self.defaultProfileId = defaultProfileId
        self.structuralRevision = structuralRevision
        self.loadLifecycle = loadLifecycle
        self.structuralInstaller = structuralInstaller
        self.runtimePreparation = runtimePreparation
        self.lazyRestore = lazyRestore
        self.persistence = persistence
        self.syncWorkspaceTheme = syncWorkspaceTheme
    }

    convenience init(
        modelContainer: ModelContainer,
        structuralStore: TabStructuralSnapshotStore,
        tabFactory: TabFactory,
        runtimePorts: @escaping () -> RuntimePortRegistry?,
        structuralLookup: TabStructuralLookupCoordinator,
        loadLifecycle: TabStartupRestoreLifecycle,
        structuralInstaller: TabStructuralInstallOwner,
        runtimePreparation: TabRuntimePreparationOwner,
        lazyRestore: TabLazyRestoreCoordinator,
        persistence: TabStructuralPersistenceService
    ) {
        self.init(
            payloadLoader: TabRestoreLoader(container: modelContainer),
            structuralStore: structuralStore,
            tabFactory: tabFactory,
            defaultProfileId: { runtimePorts()?.defaultProfileId },
            structuralRevision: { structuralLookup.mutationRevision },
            loadLifecycle: loadLifecycle,
            structuralInstaller: structuralInstaller,
            runtimePreparation: runtimePreparation,
            lazyRestore: lazyRestore,
            persistence: persistence,
            syncWorkspaceTheme: {
                runtimePorts()?.syncWorkspaceThemeAcrossWindows(for: $0, animate: false)
            }
        )
    }

    deinit {
        MainActor.assumeIsolated {
            startupRestoreTask?.cancel()
            startupRestoreTask = nil
        }
    }

    func cancelPendingRestore() {
        startupRestoreTask?.cancel()
        startupRestoreTask = nil
    }

    func loadFromStore(expectedStructuralRevision: UInt64? = nil) {
        let expectedStructuralRevision = expectedStructuralRevision
            ?? structuralRevision()
        startupRestoreTask?.cancel()
        startupRestoreTask = Task { [weak self] in
            _ = await self?.loadFromStoreAwaitingResult(
                expectedStructuralRevision: expectedStructuralRevision
            )
        }
    }

    @discardableResult
    func loadFromStoreAwaitingResult(
        expectedStructuralRevision: UInt64? = nil
    ) async -> Bool {
        let signpostState = PerformanceTrace.beginInterval("TabManager.loadFromStore")
        defer {
            PerformanceTrace.endInterval("TabManager.loadFromStore", signpostState)
        }

        loadLifecycle.markLoadStarted()
        defer {
            loadLifecycle.markLoadFinished()
            startupRestoreTask = nil
        }
        let restoreStartRevision = expectedStructuralRevision
            ?? structuralRevision()

        do {
            let revisionBeforeLoad = structuralRevision()
            guard revisionBeforeLoad == restoreStartRevision else {
                RuntimeDiagnostics.debug(
                    "Skipped stale startup restore before loading because the live tab structure changed after the restore request (expected revision: \(restoreStartRevision), current revision: \(revisionBeforeLoad)).",
                    category: "TabManager"
                )
                return false
            }

            let defaultProfileId = defaultProfileId()
            if defaultProfileId == nil {
                RuntimeDiagnostics.debug(
                    "No profiles available to assign to spaces during load; reconciliation deferred.",
                    category: "TabManager"
                )
            }

            let payload = try await payloadLoader.load(defaultProfileId: defaultProfileId)
            if Task.isCancelled { return false }

            let currentRevision = structuralRevision()
            guard currentRevision == restoreStartRevision else {
                RuntimeDiagnostics.debug(
                    "Skipped stale startup restore because the live tab structure changed while loading (start revision: \(restoreStartRevision), current revision: \(currentRevision)).",
                    category: "TabManager"
                )
                return false
            }

            let applyResult = applyRestorePayload(payload)
            enqueueRestoreRepairIfNeeded(applyResult)
            return true
        } catch {
            RuntimeDiagnostics.debug("SwiftData load error: \(String(describing: error))", category: "TabManager")
            return false
        }
    }

    private struct RestoreApplyResult {
        let snapshot: TabPersistenceSnapshot?
        let reasons: [String]
    }

    private func applyRestorePayload(_ payload: TabRestorePayload) -> RestoreApplyResult {
        let signpostState = PerformanceTrace.beginInterval("TabManager.restoreApplyMainActor")
        defer {
            PerformanceTrace.endInterval("TabManager.restoreApplyMainActor", signpostState)
        }

        RuntimeDiagnostics.debug(
            "Loading tabs from store: total=\(payload.totalTabCount), pinned=\(payload.pinnedCount), spacePinned=\(payload.spacePinnedCount), regular=\(payload.regularCount)",
            category: "TabManager"
        )

        let restoredState = TabRestoreRuntimeStateBuilder(tabFactory: tabFactory)
            .makeState(from: payload)

        let restoredCurrentSpace = payload.currentSpaceId.flatMap { currentSpaceId in
            restoredState.spaces.first(where: { $0.id == currentSpaceId })
        } ?? restoredState.spaces.first

        let selectionTabs = restoredCurrentSpace.flatMap { restoredState.tabsBySpace[$0.id] } ?? []
        let restoredCurrentTab: Tab?
        if let selectedTabId = payload.currentTabId,
           let match = selectionTabs.first(where: { $0.id == selectedTabId }) {
            restoredCurrentTab = match
        } else {
            restoredCurrentTab = selectionTabs.first
        }

        structuralInstaller.installRestoredCollections(
            restoredState,
            splitGroups: SumiDomain.SplitGroup.sanitized(payload.splitGroups),
            currentSpace: restoredCurrentSpace,
            currentTab: restoredCurrentTab
        )

        for tab in restoredState.tabsBySpace.values.flatMap(\.self) {
            runtimePreparation.prepare(tab)
        }

        lazyRestore.reset(
            restoredTabIDs: Set(restoredState.tabsBySpace.values.flatMap { $0.map(\.id) })
        )
        persistence.prepareForRestoredState()

        RuntimeDiagnostics.debug(
            "Current Space: \(restoredCurrentSpace?.name ?? "None"), Tab: \(restoredCurrentTab?.name ?? "None")",
            category: "TabManager"
        )

        if let restoredCurrentSpace {
            syncWorkspaceTheme(restoredCurrentSpace)
        }

        let uniqueRepairReasons = Array(Set(restoredState.repairReasons)).sorted()
        guard uniqueRepairReasons.isEmpty == false else {
            return RestoreApplyResult(snapshot: nil, reasons: [])
        }

        let snapshot = uniqueRepairReasons == payload.repairReasons
            ? payload.snapshot
            : persistence.buildSnapshot()
        return RestoreApplyResult(snapshot: snapshot, reasons: uniqueRepairReasons)
    }

    private func enqueueRestoreRepairIfNeeded(_ result: RestoreApplyResult) {
        guard let snapshot = result.snapshot else {
            return
        }

        let generation = persistence.reservePersistenceGeneration()
        let reasonSummary = result.reasons.joined(separator: ", ")
        Task {
            let signpostState = PerformanceTrace.beginInterval("TabManager.restoreRepairFullReconcile")
            defer {
                PerformanceTrace.endInterval("TabManager.restoreRepairFullReconcile", signpostState)
            }
            RuntimeDiagnostics.debug(
                "Persisting restore repair via full reconcile: \(reasonSummary)",
                category: "TabManager"
            )
            _ = await structuralStore.persistFullReconcile(
                snapshot: snapshot,
                generation: generation
            )
        }
    }
}
