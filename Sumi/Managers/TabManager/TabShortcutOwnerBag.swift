//
//  TabShortcutOwnerBag.swift
//  Sumi
//
//  Capability bag: shortcut pin / live-tab / drag presentation owners.
//

import Foundation

/// Groups shortcut-adjacent TabManager owners so they are not peer `lazy var`
/// Owners on the TabManager façade.
@MainActor
final class TabShortcutOwnerBag {
    private unowned let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    private var tm: TabManager { tabManager }

    lazy var shortcutPinCommandOwner = ShortcutPinCommandOwner(dependencies: .live(tabManager: tm))
    lazy var essentialsShortcutPlacementOwner = EssentialsShortcutPlacementOwner(
        spaces: { [weak self] in self?.tm.spaceStateOwner.spaces ?? [] },
        runtimePorts: { [weak self] in self?.tm.runtimePorts },
        essentialPins: { [weak self] profileId in
            self?.tm.shortcutPinCollectionStateOwner.essentialPins(for: profileId) ?? []
        }
    )
    lazy var shortcutPinStoreOwner = ShortcutPinStoreOwner(
        dependencies: .live(tabManager: tm)
    )
    lazy var shortcutPinRuntimeResolutionOwner = ShortcutPinRuntimeResolutionOwner(
        spaces: { [weak self] in self?.tm.spaceStateOwner.spaces ?? [] },
        runtimePorts: { [weak self] in self?.tm.runtimePorts },
        faviconService: { [weak self] in
            guard let self else { preconditionFailure("TabManager dependency used after deallocation") }
            return self.tm.faviconService
        }
    )
    lazy var shortcutPinConversionOwner = ShortcutPinConversionOwner(tabManager: tm)
    lazy var shortcutDragOperationOwner = ShortcutDragOperationOwner(tabManager: tm)
    lazy var shortcutPresentationOwner = TabShortcutPresentationOwner(tabManager: tm)
    lazy var shortcutContainerRemovalOwner = ShortcutContainerRemovalOwner(
        pinnedByProfile: { [weak self] in
            self?.tm.shortcutPinCollectionStateOwner.pinnedByProfileSnapshot() ?? [:]
        },
        setPinnedTabs: { [weak self] pins, profileId in
            self?.tm.structuralCollectionMutationOwner.setPinnedTabs(pins, for: profileId)
        },
        removeRegularTab: { [weak self] tabId, spaceId, currentSpaceId in
            _ = self?.tm.regularTabCollectionOwner.remove(
                tabId,
                from: spaceId,
                currentSpaceId: currentSpaceId
            )
        },
        currentSpaceId: { [weak self] in
            self?.tm.spaceStateOwner.currentSpace?.id
        }
    )
    lazy var shortcutLiveTabOwner = ShortcutLiveTabOwner(
        dependencies: .live(tabManager: tm)
    )
}
