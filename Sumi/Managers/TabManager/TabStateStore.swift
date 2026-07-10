//
//  TabStateStore.swift
//  Sumi
//
//  Owns the mutable in-memory tab-domain collections. Browser side effects
//  and persistence orchestration deliberately live outside this store.
//

import Foundation

@MainActor
final class TabStateStore {
    let spaces = TabSpaceCollectionStateOwner()
    let regularTabs = RegularTabCollectionStateOwner()
    let selection = TabSelectionStateOwner()
    let splitGroups = SplitGroupCollectionStateOwner()
    let folders = TabFolderCollectionStateOwner()
    let shortcutPins = ShortcutPinCollectionStateOwner()
    let transientTabs = TabTransientTabRegistryOwner()

    func removeAll() {
        regularTabs.removeAll()
        splitGroups.removeAll()
        folders.removeAll()
        shortcutPins.removeAll()
        transientTabs.removeAll()
        spaces.removeAll()
        selection.replaceCurrentTab(nil)
    }
}
