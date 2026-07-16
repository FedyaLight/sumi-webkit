import Foundation
import SumiDomain

/// Commits a loaded restore payload, then applies attachment-bound runtime effects.
@MainActor
final class TabRestorePayloadApplyService {
    struct Repair {
        let snapshot: TabPersistenceSnapshot
        let generation: Int
        let reasons: [String]
    }

    struct InstalledPayload {
        let repair: Repair?
    }

    enum Disposition {
        case notInstalled
        case installed(InstalledPayload)
    }

    private let tabFactory: TabFactory
    private let structuralInstaller: TabStructuralInstallOwner
    private let runtimePreparation: TabRuntimePreparationOwner
    private let lazyRestore: TabLazyRestoreCoordinator
    private let persistence: TabStructuralPersistenceService

    init(
        tabFactory: TabFactory,
        structuralInstaller: TabStructuralInstallOwner,
        runtimePreparation: TabRuntimePreparationOwner,
        lazyRestore: TabLazyRestoreCoordinator,
        persistence: TabStructuralPersistenceService
    ) {
        self.tabFactory = tabFactory
        self.structuralInstaller = structuralInstaller
        self.runtimePreparation = runtimePreparation
        self.lazyRestore = lazyRestore
        self.persistence = persistence
    }

    func apply(
        _ payload: TabRestorePayload,
        runtimeAttachment: TabRuntimeAttachmentWitness,
        admitted: @escaping @MainActor () -> Bool,
        onInstalled: @escaping @MainActor (InstalledPayload) -> Void
    ) -> Disposition {
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
        let currentSpace = payload.currentSpaceId.flatMap { currentSpaceID in
            restoredState.spaces.first(where: { $0.id == currentSpaceID })
        } ?? restoredState.spaces.first
        let selectionTabs = currentSpace.flatMap {
            restoredState.tabsBySpace[$0.id]
        } ?? []
        let currentTab = payload.currentTabId.flatMap { currentTabID in
            selectionTabs.first(where: { $0.id == currentTabID })
        } ?? selectionTabs.first
        let tabs = restoredState.tabsBySpace.values.flatMap(\.self)
        var installedPayload: InstalledPayload?

        guard structuralInstaller.installRestoredCollections(
            restoredState,
            splitGroups: SumiDomain.SplitGroup.sanitized(payload.splitGroups),
            currentSpace: currentSpace,
            currentTab: currentTab,
            admitted: admitted,
            onInstalled: {
                self.lazyRestore.reset(restoredTabIDs: Set(tabs.map(\.id)))
                self.persistence.settleAfterRestoredStateInstallation()
                let payload = InstalledPayload(
                    repair: self.makeRepair(
                        restoredState: restoredState,
                        payload: payload
                    )
                )
                installedPayload = payload
                onInstalled(payload)
            }
        ), let installedPayload else {
            return .notInstalled
        }

        settleRuntime(
            tabs: tabs,
            currentSpace: currentSpace,
            runtimeAttachment: runtimeAttachment
        )
        return .installed(installedPayload)
    }

    private func settleRuntime(
        tabs: [Tab],
        currentSpace: Space?,
        runtimeAttachment: TabRuntimeAttachmentWitness
    ) {
        guard runtimeAttachment.isCurrent() else { return }
        for tab in tabs {
            guard runtimePreparation.prepare(
                tab,
                using: runtimeAttachment.lease
            ) == .completed else {
                return
            }
        }
        guard runtimeAttachment.isCurrent() else { return }

        RuntimeDiagnostics.debug(
            "Current Space: \(currentSpace?.name ?? "None")",
            category: "TabManager"
        )
        _ = syncTheme(
            for: currentSpace,
            runtimeAttachment: runtimeAttachment
        )
    }

    private func makeRepair(
        restoredState: TabRestoreRuntimeState,
        payload: TabRestorePayload
    ) -> Repair? {
        let reasons = Array(Set(restoredState.repairReasons)).sorted()
        guard reasons.isEmpty == false else { return nil }
        let snapshot = reasons == payload.repairReasons
            ? payload.snapshot
            : persistence.buildSnapshot()
        return Repair(
            snapshot: snapshot,
            generation: persistence.reservePersistenceGeneration(),
            reasons: reasons
        )
    }

    private func syncTheme(
        for space: Space?,
        runtimeAttachment: TabRuntimeAttachmentWitness
    ) -> Bool {
        guard let space else { return runtimeAttachment.isCurrent() }
        guard let runtime = runtimeAttachment.currentRegistry() else {
            return false
        }
        runtime.syncWorkspaceThemeAcrossWindows(for: space, animate: false)
        return runtimeAttachment.isCurrent()
    }
}
