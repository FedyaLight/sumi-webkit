import Foundation

@MainActor
final class TabCollectionMembershipOwner {
    private unowned let tabManager: TabManager
    private let structuralLookupOwner: TabStructuralLookupOwner
    private let transientTabRegistryOwner: TabTransientTabRegistryOwner

    init(
        tabManager: TabManager,
        structuralLookupOwner: TabStructuralLookupOwner,
        transientTabRegistryOwner: TabTransientTabRegistryOwner
    ) {
        self.tabManager = tabManager
        self.structuralLookupOwner = structuralLookupOwner
        self.transientTabRegistryOwner = transientTabRegistryOwner
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

        let normals = tabManager.regularTabCollectionStateOwner.allTabs()
        return transientTabRegistryOwner.allTransientTabs
            + normals
    }

    func allTabsForCurrentProfile() -> [Tab] {
        guard let profileId = tabManager.runtimeContext?.currentProfileId else {
            return allTabs()
        }
        let spaceIds = Set(tabManager.spaces.filter { $0.profileId == profileId }.map(\.id))
        let pinned = tabManager.shortcutPresentationOwner.activeEssentialTabs(for: profileId)
        let spacePinned = transientTabRegistryOwner.transientShortcutTabs
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
        if tabManager.shortcutPresentationOwner.activeShortcutTabs().contains(where: { $0.id == tab.id }) {
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
        transientTabRegistryOwner.isTransientExtensionTab(tab)
    }

    func registerTransientExtensionTab(_ tab: Tab) {
        transientTabRegistryOwner.registerTransientExtensionTab(tab)
        structuralLookupOwner.insertTransientExtensionTab(tab)
    }

    func removeTransientExtensionTab(id: UUID) -> Tab? {
        guard let tab = transientTabRegistryOwner.removeTransientExtensionTab(id: id) else {
            return nil
        }
        structuralLookupOwner.removeTransientExtensionTab(id)
        return tab
    }

    @discardableResult
    func promoteTransientExtensionTab(_ tab: Tab) -> Bool {
        guard transientTabRegistryOwner.promoteTransientExtensionTab(tab) else {
            return false
        }
        structuralLookupOwner.stopTrackingTransientTab(tab.id)
        return true
    }

    func registerAuxiliaryMiniWindowTab(_ tab: Tab) {
        transientTabRegistryOwner.registerAuxiliaryMiniWindowTab(tab)
    }

    func auxiliaryMiniWindowTab(for id: UUID) -> Tab? {
        transientTabRegistryOwner.auxiliaryMiniWindowTab(for: id)
    }

    func removeAuxiliaryMiniWindowTab(_ tab: Tab) {
        transientTabRegistryOwner.removeAuxiliaryMiniWindowTab(tab)
        structuralLookupOwner.remove(tab.id)
    }

    func isAuxiliaryMiniWindowTab(_ tab: Tab) -> Bool {
        transientTabRegistryOwner.isAuxiliaryMiniWindowTab(tab)
    }

    private var structuralLookupSnapshot: TabStructuralLookupSnapshot {
        TabStructuralLookupSnapshot(
            tabsBySpace: tabManager.regularTabCollectionStateOwner.tabsBySpace,
            transientShortcutTabsByWindow: transientTabRegistryOwner.transientShortcutTabsByWindow,
            transientExtensionTabsByID: transientTabRegistryOwner.transientExtensionTabsByID,
            auxiliaryMiniWindowTabsByID: transientTabRegistryOwner.auxiliaryMiniWindowTabsByID
        )
    }
}
