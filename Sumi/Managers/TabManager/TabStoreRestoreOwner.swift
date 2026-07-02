import AppKit
import Foundation
import SwiftData

@MainActor
struct TabRestoreRuntimeState {
    let spaces: [Space]
    let tabsBySpace: [UUID: [Tab]]
    let foldersBySpace: [UUID: [TabFolder]]
    let pinnedByProfile: [UUID: [ShortcutPin]]
    let pendingPinnedWithoutProfile: [ShortcutPin]
    let spacePinnedShortcuts: [UUID: [ShortcutPin]]
    let repairReasons: [String]
}

@MainActor
private struct TabRestoreRuntimeStateBuilder {
    let faviconService: any BrowserFaviconServicing
    let faviconImageService: any BrowserFaviconImageServicing
    let visitedLinkStore: any BrowserVisitedLinkStoreManaging

    func makeState(from payload: TabRestorePayload) -> TabRestoreRuntimeState {
        var repairReasons = payload.repairReasons
        let restoredSpaces = payload.spaces.map { dto in
            let space = Space(
                id: dto.id,
                name: dto.name,
                icon: dto.icon,
                workspaceTheme: dto.workspaceTheme,
                profileId: dto.profileId
            )
            if space.icon != dto.icon {
                repairReasons.append("normalized space icon")
            }
            return space
        }

        var restoredTabsBySpace: [UUID: [Tab]] = [:]
        for space in restoredSpaces {
            restoredTabsBySpace[space.id] = []
        }
        for (spaceId, tabDTOs) in payload.regularTabsBySpace {
            restoredTabsBySpace[spaceId] = tabDTOs.map(makeRestoredTab)
        }

        var restoredFoldersBySpace: [UUID: [TabFolder]] = [:]
        for (spaceId, folderDTOs) in payload.foldersBySpace {
            restoredFoldersBySpace[spaceId] = folderDTOs.map { dto in
                let folder = TabFolder(
                    id: dto.id,
                    name: dto.name,
                    spaceId: dto.spaceId,
                    parentFolderId: dto.parentFolderId,
                    icon: dto.icon,
                    color: NSColor(hex: dto.color) ?? .controlAccentColor,
                    index: dto.index
                )
                folder.isOpen = dto.isOpen
                if folder.icon != dto.icon {
                    repairReasons.append("normalized folder icon")
                }
                return folder
            }
        }

        var restoredPinnedByProfile: [UUID: [ShortcutPin]] = [:]
        for (profileId, shortcutDTOs) in payload.pinnedShortcutsByProfile {
            restoredPinnedByProfile[profileId] = shortcutDTOs.map { dto in
                let pin = makeRestoredShortcut(dto)
                if pin.iconAsset != dto.iconAsset {
                    repairReasons.append("normalized launcher icon")
                }
                return pin
            }
        }

        let restoredPendingPinned = payload.pendingPinnedShortcuts.map { dto in
            let pin = makeRestoredShortcut(dto)
            if pin.iconAsset != dto.iconAsset {
                repairReasons.append("normalized launcher icon")
            }
            return pin
        }

        var restoredSpacePinnedShortcuts: [UUID: [ShortcutPin]] = [:]
        for (spaceId, shortcutDTOs) in payload.spacePinnedShortcutsBySpace {
            restoredSpacePinnedShortcuts[spaceId] = shortcutDTOs.map { dto in
                let pin = makeRestoredShortcut(dto)
                if pin.iconAsset != dto.iconAsset {
                    repairReasons.append("normalized launcher icon")
                }
                return pin
            }
        }

        return TabRestoreRuntimeState(
            spaces: restoredSpaces,
            tabsBySpace: restoredTabsBySpace,
            foldersBySpace: restoredFoldersBySpace,
            pinnedByProfile: restoredPinnedByProfile,
            pendingPinnedWithoutProfile: restoredPendingPinned,
            spacePinnedShortcuts: restoredSpacePinnedShortcuts,
            repairReasons: repairReasons
        )
    }

    private func makeRestoredTab(_ dto: TabRestoreTabDTO) -> Tab {
        let tab = Tab(
            id: dto.id,
            url: dto.url,
            name: dto.name,
            favicon: "globe",
            spaceId: dto.spaceId,
            index: dto.index,
            loadsCachedFaviconOnInit: false,
            faviconService: faviconService,
            faviconImageService: faviconImageService,
            visitedLinkStore: visitedLinkStore
        )
        tab.folderId = dto.folderId
        tab.profileId = dto.profileId
        tab.isPinned = false
        tab.isSpacePinned = false
        tab.canGoBack = dto.canGoBack
        tab.canGoForward = dto.canGoForward
        return tab
    }

    private func makeRestoredShortcut(_ dto: TabRestoreShortcutDTO) -> ShortcutPin {
        ShortcutPin(
            id: dto.id,
            role: dto.role,
            profileId: dto.profileId,
            executionProfileId: dto.executionProfileId,
            spaceId: dto.spaceId,
            index: dto.index,
            folderId: dto.folderId,
            launchURL: dto.launchURL,
            title: dto.title,
            iconAsset: dto.iconAsset
        )
    }
}

/// Restores the persisted tab structure from the SwiftData store at startup and
/// schedules repair persistence when restored data needed normalization.
@MainActor
final class TabStoreRestoreOwner {
    struct Dependencies {
        let modelContainer: ModelContainer
        let persistence: TabSnapshotRepository
        let faviconService: any BrowserFaviconServicing
        let faviconImageService: any BrowserFaviconImageServicing
        let visitedLinkStore: any BrowserVisitedLinkStoreManaging
        let defaultProfileId: @MainActor () -> UUID?
        let markInitialDataLoadStarted: @MainActor () -> Void
        let markInitialDataLoadFinished: @MainActor () -> Void
        let installRestoredCollections: @MainActor (TabRestoreRuntimeState) -> Void
        let installRepairedSplitGroups: @MainActor ([SplitGroup]) -> Void
        let prepareTabForRuntime: @MainActor (Tab) -> Void
        let setCurrentSpace: @MainActor (Space?) -> Void
        let setCurrentTab: @MainActor (Tab?) -> Void
        let rebuildTabLookupForRestore: @MainActor () -> Void
        let resetLazyRestore: @MainActor (Set<UUID>) -> Void
        let prepareStructuralPersistenceForRestoredState: @MainActor () -> Void
        let requestStructuralPublish: @MainActor () -> Void
        let syncWorkspaceTheme: @MainActor (Space) -> Void
        let buildSnapshot: @MainActor () -> TabSnapshotRepository.Snapshot
        let reservePersistenceGeneration: @MainActor () -> Int
    }

    private let dependencies: Dependencies
    private(set) var startupRestoreTask: Task<Void, Never>?

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    deinit {
        MainActor.assumeIsolated {
            startupRestoreTask?.cancel()
            startupRestoreTask = nil
        }
    }

    func loadFromStore() {
        startupRestoreTask?.cancel()
        startupRestoreTask = Task { [weak self] in
            _ = await self?.loadFromStoreAwaitingResult()
        }
    }

    @discardableResult
    func loadFromStoreAwaitingResult() async -> Bool {
        let signpostState = PerformanceTrace.beginInterval("TabManager.loadFromStore")
        defer {
            PerformanceTrace.endInterval("TabManager.loadFromStore", signpostState)
        }

        dependencies.markInitialDataLoadStarted()
        defer {
            dependencies.markInitialDataLoadFinished()
            startupRestoreTask = nil
            NotificationCenter.default.post(name: .tabManagerDidLoadInitialData, object: nil)
        }

        do {
            let defaultProfileId = dependencies.defaultProfileId()
            if defaultProfileId == nil {
                RuntimeDiagnostics.debug(
                    "No profiles available to assign to spaces during load; reconciliation deferred.",
                    category: "TabManager"
                )
            }

            let loader = TabRestoreLoader(container: dependencies.modelContainer)
            let payload = try await loader.load(defaultProfileId: defaultProfileId)
            if Task.isCancelled { return false }

            let applyResult = applyRestorePayload(payload)
            enqueueRestoreRepairIfNeeded(applyResult)
            return true
        } catch {
            RuntimeDiagnostics.debug("SwiftData load error: \(String(describing: error))", category: "TabManager")
            return false
        }
    }

    private struct RestoreApplyResult {
        let snapshot: TabSnapshotRepository.Snapshot?
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

        let restoredState = TabRestoreRuntimeStateBuilder(
            faviconService: dependencies.faviconService,
            faviconImageService: dependencies.faviconImageService,
            visitedLinkStore: dependencies.visitedLinkStore
        )
            .makeState(from: payload)

        dependencies.installRestoredCollections(restoredState)
        dependencies.installRepairedSplitGroups(payload.splitGroups)

        for tab in restoredState.tabsBySpace.values.flatMap(\.self) {
            dependencies.prepareTabForRuntime(tab)
        }

        let restoredCurrentSpace = payload.currentSpaceId.flatMap { currentSpaceId in
            restoredState.spaces.first(where: { $0.id == currentSpaceId })
        } ?? restoredState.spaces.first
        dependencies.setCurrentSpace(restoredCurrentSpace)

        let selectionTabs = restoredCurrentSpace.flatMap { restoredState.tabsBySpace[$0.id] } ?? []
        let restoredCurrentTab: Tab?
        if let selectedTabId = payload.currentTabId,
           let match = selectionTabs.first(where: { $0.id == selectedTabId }) {
            restoredCurrentTab = match
        } else {
            restoredCurrentTab = selectionTabs.first
        }
        dependencies.setCurrentTab(restoredCurrentTab)

        dependencies.rebuildTabLookupForRestore()
        dependencies.resetLazyRestore(
            Set(restoredState.tabsBySpace.values.flatMap { $0.map(\.id) })
        )
        dependencies.prepareStructuralPersistenceForRestoredState()
        dependencies.requestStructuralPublish()

        RuntimeDiagnostics.debug(
            "Current Space: \(restoredCurrentSpace?.name ?? "None"), Tab: \(restoredCurrentTab?.name ?? "None")",
            category: "TabManager"
        )

        if let restoredCurrentSpace {
            dependencies.syncWorkspaceTheme(restoredCurrentSpace)
        }

        let uniqueRepairReasons = Array(Set(restoredState.repairReasons)).sorted()
        guard uniqueRepairReasons.isEmpty == false else {
            return RestoreApplyResult(snapshot: nil, reasons: [])
        }

        let snapshot = uniqueRepairReasons == payload.repairReasons
            ? payload.snapshot
            : dependencies.buildSnapshot()
        return RestoreApplyResult(snapshot: snapshot, reasons: uniqueRepairReasons)
    }

    private func enqueueRestoreRepairIfNeeded(_ result: RestoreApplyResult) {
        guard let snapshot = result.snapshot else {
            return
        }

        let generation = dependencies.reservePersistenceGeneration()
        let persistence = dependencies.persistence
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
            _ = await persistence.persistFullReconcile(snapshot: snapshot, generation: generation)
        }
    }
}

extension TabStoreRestoreOwner.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            modelContainer: tabManager.context.container,
            persistence: tabManager.persistence,
            faviconService: tabManager.faviconService,
            faviconImageService: tabManager.faviconImageService,
            visitedLinkStore: tabManager.visitedLinkStore,
            defaultProfileId: { [weak tabManager] in
                tabManager?.runtimeContext?.defaultProfileId
            },
            markInitialDataLoadStarted: { [weak tabManager] in
                tabManager?.markInitialDataLoadStarted()
            },
            markInitialDataLoadFinished: { [weak tabManager] in
                tabManager?.markInitialDataLoadFinished()
            },
            installRestoredCollections: { [weak tabManager] restoredState in
                tabManager?.installRestoredCollections(restoredState)
            },
            installRepairedSplitGroups: { [weak tabManager] splitGroups in
                guard let tabManager else { return }
                tabManager.splitGroups = tabManager.sanitizedRepairedSplitGroups(splitGroups)
            },
            prepareTabForRuntime: { [weak tabManager] tab in
                tabManager?.prepareTabForRuntime(tab)
            },
            setCurrentSpace: { [weak tabManager] space in
                tabManager?.currentSpace = space
            },
            setCurrentTab: { [weak tabManager] tab in
                tabManager?.currentTab = tab
            },
            rebuildTabLookupForRestore: { [weak tabManager] in
                tabManager?.rebuildTabLookupForRestore()
            },
            resetLazyRestore: { [weak tabManager] restoredTabIDs in
                tabManager?.lazyRestoreCoordinator.reset(restoredTabIDs: restoredTabIDs)
            },
            prepareStructuralPersistenceForRestoredState: { [weak tabManager] in
                tabManager?.structuralPersistence.prepareForRestoredState()
            },
            requestStructuralPublish: { [weak tabManager] in
                tabManager?.requestStructuralPublish()
            },
            syncWorkspaceTheme: { [weak tabManager] space in
                tabManager?.runtimeContext?.syncWorkspaceThemeAcrossWindows(for: space, animate: false)
            },
            buildSnapshot: { [weak tabManager] in
                tabManager?.structuralPersistence.buildSnapshot()
                    ?? TabStructuralSnapshotMaterializer().makeSnapshot(
                        spaces: [],
                        tabs: [],
                        folders: [],
                        splitGroups: [],
                        currentTabId: nil,
                        currentSpaceId: nil
                    )
            },
            reservePersistenceGeneration: { [weak tabManager] in
                tabManager?.structuralPersistence.reservePersistenceGeneration() ?? 0
            }
        )
    }
}
