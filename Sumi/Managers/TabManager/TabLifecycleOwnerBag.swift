//
//  TabLifecycleOwnerBag.swift
//  Sumi
//
//  Capability bag: tab/space/profile lifecycle and runtime preparation owners.
//

import Foundation

/// Groups lifecycle-adjacent TabManager owners so they are not peer `lazy var`
/// Owners on the TabManager façade.
@MainActor
final class TabLifecycleOwnerBag {
    private unowned let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    private var tm: TabManager { tabManager }

    lazy var runtimePreparationOwner = TabRuntimePreparationOwner(
        runtimeConnection: tm.runtimePortConnection
    )
    lazy var pendingShortcutPinAdopter = PendingShortcutPinAdopter(
        pins: tm.shortcutPinCollectionStateOwner,
        structuralMutations: tm.structuralCollectionMutationOwner,
        persistence: tm.structuralPersistence
    )
    lazy var runtimeAttachmentBootstrap = TabRuntimeAttachmentBootstrap(
        connection: tm.runtimePortConnection,
        membership: tm.tabCollectionMembershipOwner,
        runtimePreparation: runtimePreparationOwner,
        selection: tm.selectionStateOwner
    )
    lazy var runtimeAttachmentRestoreStarter: TabRuntimeAttachmentRestoreStarter? = {
        guard tm.startupRestorePolicy.isEnabled else {
            return nil
        }
        return TabRuntimeAttachmentRestoreStarter(
            connection: tm.runtimePortConnection,
            policy: tm.startupRestorePolicy,
            lifecycle: tm.startupRestoreLifecycle,
            restore: tm.storeRestore
        )
    }()
    lazy var runtimeAttachmentDeferredWorkOwner = TabRuntimeAttachmentDeferredWorkOwner(
        connection: tm.runtimePortConnection,
        spaceProfiles: spaceProfileReconciliation,
        spaceAvailability: profileAssignments.spaceAvailability,
        pendingPins: pendingShortcutPinAdopter
    )
    lazy var runtimeAttachmentSettlement = TabRuntimeAttachmentSettlement(
        connection: tm.runtimePortConnection,
        spaces: tm.spaceStateOwner,
        deferredWork: runtimeAttachmentDeferredWorkOwner,
        restoreStarter: runtimeAttachmentRestoreStarter
    )
    lazy var runtimePortsAttachmentOwner = TabRuntimePortsAttachmentOwner(
        connection: tm.runtimePortConnection,
        bootstrap: runtimeAttachmentBootstrap,
        settlement: runtimeAttachmentSettlement
    )
    lazy var regularTabLifecycleOwner = TabRegularLifecycleOwner(
        dependencies: .live(tabManager: tm)
    )
    lazy var tabClosureService = TabClosureService.live(tabManager: tm)
    lazy var activeSpaceSelectionUpdater = TabActiveSpaceSelectionUpdater(
        spaces: tm.spaceStateOwner,
        persistence: tm.structuralPersistence
    )
    lazy var selectionContextProjection = TabSelectionContextProjection(
        runtimeConnection: tm.runtimePortConnection,
        spaces: tm.spaceStateOwner,
        regularTabs: tm.regularTabCollectionOwner,
        shortcutPresentation: tm.shortcutPresentationOwner
    )
    lazy var activeSelectionOwner = TabActiveSelectionOwner(
        membership: tm.tabCollectionMembershipOwner,
        selection: tm.selectionStateOwner,
        runtimeConnection: tm.runtimePortConnection,
        persistence: tm.structuralPersistence,
        spaceSelection: activeSpaceSelectionUpdater
    )
    lazy var profileAssignments = ProfileAssignmentServices.live(
        tabManager: tm,
        selectionContext: selectionContextProjection
    )
    lazy var spaceProfileReconciliation = SpaceProfileReconciliationService(
        spaces: tm.spaceStateOwner,
        runtimeConnection: tm.runtimePortConnection,
        spaceTransitions: profileAssignments.spaces,
        transitionLifecycle: profileAssignments.spaceLifecycle
    )
    lazy var transientWebKitTabLifecycleOwner = TabTransientWebKitTabLifecycleOwner(
        dependencies: .live(tabManager: tm)
    )
    lazy var ephemeralLifecycleOwner = TabEphemeralLifecycleOwner(
        prepareTabForRuntime: { [weak self] tab in
            self?.tm.runtimePreparationOwner.prepare(tab)
        },
        tabFactory: tm.tabFactory
    )
    lazy var faviconPresentationRefreshOwner = TabFaviconPresentationRefreshOwner(
        notificationCenter: .default,
        debounceNanoseconds: TabFaviconPresentationRefreshOwner.defaultDebounceNanoseconds,
        tabsNeedingRefresh: { [weak self] in
            guard let self else { return [] }
            return self.tm.regularTabCollectionStateOwner.allTabs()
                + self.tm.transientTabRegistryOwner.transientShortcutTabs
        }
    )
}
