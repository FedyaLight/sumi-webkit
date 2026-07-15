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
        runtimePorts: { [weak self] in self?.tm.runtimePorts },
        settings: { [weak self] in self?.tm.sumiSettings }
    )
    lazy var runtimePortsAttachmentOwner = TabRuntimePortsAttachmentOwner(
        dependencies: .live(tabManager: tm)
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
    lazy var profileAssignments = ProfileAssignmentServices(
        tabManager: tm,
        selectionContext: selectionContextProjection
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
