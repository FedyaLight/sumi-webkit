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
    private weak var tabManager: TabManager?
    private let faviconPresentationRefreshDebounceNanoseconds: UInt64

    init(faviconPresentationRefreshDebounceNanoseconds: UInt64) {
        self.faviconPresentationRefreshDebounceNanoseconds = faviconPresentationRefreshDebounceNanoseconds
    }

    func bind(_ tabManager: TabManager) {
        self.tabManager = tabManager
    }

    private var tm: TabManager {
        guard let tabManager else {
            preconditionFailure("TabLifecycleOwnerBag used before bind(tabManager:)")
        }
        return tabManager
    }

    lazy var profileRuntimeStateOwner = TabProfileRuntimeStateOwner(tabManager: tm)
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
    lazy var tabRemovalOwner = TabRemovalOwner(dependencies: .live(tabManager: tm))
    lazy var activeSelectionOwner = TabActiveSelectionOwner(
        dependencies: .live(tabManager: tm)
    )
    lazy var spaceLifecycleOwner = TabSpaceLifecycleOwner(dependencies: .live(tabManager: tm))
    lazy var profileAssignmentOwner = TabProfileAssignmentOwner(dependencies: .live(tabManager: tm))
    lazy var transientWebKitTabLifecycleOwner = TabTransientWebKitTabLifecycleOwner(
        dependencies: .live(tabManager: tm)
    )
    lazy var ephemeralLifecycleOwner = TabEphemeralLifecycleOwner(
        prepareTabForRuntime: { [weak self] tab in
            self?.tm.runtimePreparationOwner.prepare(tab)
        },
        faviconService: { [weak self] in
            guard let self else { preconditionFailure("TabManager dependency used after deallocation") }
            return self.tm.faviconService
        },
        faviconImageService: { [weak self] in
            guard let self else { preconditionFailure("TabManager dependency used after deallocation") }
            return self.tm.faviconImageService
        },
        visitedLinkStore: { [weak self] in
            guard let self else { preconditionFailure("TabManager dependency used after deallocation") }
            return self.tm.visitedLinkStore
        }
    )
    lazy var faviconPresentationRefreshOwner = TabFaviconPresentationRefreshOwner(
        notificationCenter: .default,
        debounceNanoseconds: faviconPresentationRefreshDebounceNanoseconds,
        tabsNeedingRefresh: { [weak self] in
            guard let self else { return [] }
            return self.tm.regularTabCollectionStateOwner.allTabs()
                + self.tm.transientTabRegistryOwner.transientShortcutTabs
        },
        requestStructuralPublish: { [weak self] in
            self?.tm.requestStructuralPublish()
        }
    )
}
