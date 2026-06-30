import Foundation

@MainActor
final class TabCollectionMembershipOwner {
    private unowned let tabManager: TabManager
    private let structuralLookupOwner: TabStructuralLookupOwner

    init(tabManager: TabManager, structuralLookupOwner: TabStructuralLookupOwner) {
        self.tabManager = tabManager
        self.structuralLookupOwner = structuralLookupOwner
    }

    func attach(_ tab: Tab) {
        tabManager.prepareTabForRuntime(tab)
        structuralLookupOwner.attach(tab)
    }

    func detach(_ tab: Tab) {
        structuralLookupOwner.detach(tab)
    }

    func allTabs() -> [Tab] {
        structuralLookupOwner.rebuildIfEmpty(with: structuralLookupSnapshot)

        let normals = tabManager.tabsBySpace.values.flatMap { $0 }
        return tabManager.transientShortcutTabsByWindow.values.flatMap(\.values)
            + Array(tabManager.transientExtensionTabsByID.values)
            + normals
    }

    func allTabsForCurrentProfile() -> [Tab] {
        guard let profileId = tabManager.runtimeContext?.currentProfileId else {
            return allTabs()
        }
        let spaceIds = Set(tabManager.spaces.filter { $0.profileId == profileId }.map(\.id))
        let pinned = tabManager.activeEssentialTabs(for: profileId)
        let spacePinned = tabManager.transientShortcutTabsByWindow.values
            .flatMap(\.values)
            .filter { tab in
                guard tab.shortcutPinRole == .spacePinned, let spaceId = tab.spaceId else {
                    return false
                }
                return spaceIds.contains(spaceId)
            }
        let regular = tabManager.regularTabCollectionOwner
            .allTabs(in: tabManager.spaces.filter { spaceIds.contains($0.id) })
        return pinned + spacePinned + regular
    }

    func contains(_ tab: Tab) -> Bool {
        if tabManager.activeShortcutTabs().contains(where: { $0.id == tab.id }) {
            return true
        }
        if tabManager.allPinnedTabsAllProfiles.contains(where: { $0.id == tab.id }) {
            return true
        }
        if tabManager.regularTabCollectionOwner.contains(tab) {
            return true
        }
        return false
    }

    func isTransientExtensionTab(_ tab: Tab) -> Bool {
        tabManager.transientExtensionTabsByID[tab.id] != nil
    }

    func registerTransientExtensionTab(_ tab: Tab) {
        tabManager.transientExtensionTabsByID[tab.id] = tab
        structuralLookupOwner.insertTransientExtensionTab(tab)
    }

    func removeTransientExtensionTab(id: UUID) -> Tab? {
        guard let tab = tabManager.transientExtensionTabsByID.removeValue(forKey: id) else {
            return nil
        }
        structuralLookupOwner.removeTransientExtensionTab(id)
        return tab
    }

    @discardableResult
    func promoteTransientExtensionTab(_ tab: Tab) -> Bool {
        guard tabManager.transientExtensionTabsByID.removeValue(forKey: tab.id) != nil else {
            return false
        }
        structuralLookupOwner.stopTrackingTransientTab(tab.id)
        return true
    }

    func registerAuxiliaryMiniWindowTab(_ tab: Tab) {
        tabManager.auxiliaryMiniWindowTabsByID[tab.id] = tab
    }

    func auxiliaryMiniWindowTab(for id: UUID) -> Tab? {
        tabManager.auxiliaryMiniWindowTabsByID[id]
    }

    func removeAuxiliaryMiniWindowTab(_ tab: Tab) {
        tabManager.auxiliaryMiniWindowTabsByID.removeValue(forKey: tab.id)
        structuralLookupOwner.remove(tab.id)
    }

    func isAuxiliaryMiniWindowTab(_ tab: Tab) -> Bool {
        tabManager.auxiliaryMiniWindowTabsByID[tab.id] != nil
    }

    private var structuralLookupSnapshot: TabStructuralLookupSnapshot {
        TabStructuralLookupSnapshot(
            tabsBySpace: tabManager.tabsBySpace,
            transientShortcutTabsByWindow: tabManager.transientShortcutTabsByWindow,
            transientExtensionTabsByID: tabManager.transientExtensionTabsByID,
            auxiliaryMiniWindowTabsByID: tabManager.auxiliaryMiniWindowTabsByID
        )
    }
}
