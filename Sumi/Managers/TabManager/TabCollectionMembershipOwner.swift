import Foundation

@MainActor
final class TabCollectionMembershipOwner {
    struct Dependencies {
        let prepareTabForRuntime: @MainActor (Tab) -> Void
        let regularTabsBySpace: @MainActor () -> [UUID: [Tab]]
        let allRegularTabs: @MainActor () -> [Tab]
        let containsRegularTab: @MainActor (Tab) -> Bool
        let spaces: @MainActor () -> [Space]
        let currentProfileId: @MainActor () -> UUID?
        let activeShortcutTabs: @MainActor () -> [Tab]
        let activeEssentialTabs: @MainActor (UUID?) -> [Tab]
    }

    private let structuralLookupOwner: TabStructuralLookupOwner
    private let transientTabRegistryOwner: TabTransientTabRegistryOwner
    private let dependencies: Dependencies

    init(
        structuralLookupOwner: TabStructuralLookupOwner,
        transientTabRegistryOwner: TabTransientTabRegistryOwner,
        dependencies: Dependencies
    ) {
        self.structuralLookupOwner = structuralLookupOwner
        self.transientTabRegistryOwner = transientTabRegistryOwner
        self.dependencies = dependencies
    }

    func attach(_ tab: Tab) {
        dependencies.prepareTabForRuntime(tab)
        structuralLookupOwner.attach(tab)
    }

    func detach(_ tab: Tab) {
        structuralLookupOwner.detach(tab)
    }

    func allTabs() -> [Tab] {
        structuralLookupOwner.rebuildIfEmpty(with: structuralLookupSnapshot)

        let normals = dependencies.allRegularTabs()
        return transientTabRegistryOwner.allTransientTabs
            + normals
    }

    func allTabsForCurrentProfile() -> [Tab] {
        guard let profileId = dependencies.currentProfileId() else {
            return allTabs()
        }
        let matchingSpaces = dependencies.spaces().filter { $0.profileId == profileId }
        let spaceIds = Set(matchingSpaces.map(\.id))
        let pinned = dependencies.activeEssentialTabs(profileId)
        let spacePinned = transientTabRegistryOwner.transientShortcutTabs
            .filter { tab in
                guard tab.shortcutPinRole == .spacePinned, let spaceId = tab.spaceId else {
                    return false
                }
                return spaceIds.contains(spaceId)
            }
        let regular = matchingSpaces.flatMap { dependencies.regularTabsBySpace()[$0.id] ?? [] }
        return pinned + spacePinned + regular
    }

    func contains(_ tab: Tab) -> Bool {
        if dependencies.activeShortcutTabs().contains(where: { $0.id == tab.id }) {
            return true
        }
        if dependencies.containsRegularTab(tab) {
            return true
        }
        return false
    }

    func tab(for id: UUID) -> Tab? {
        structuralLookupOwner.tab(for: id, snapshot: structuralLookupSnapshot)
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
            tabsBySpace: dependencies.regularTabsBySpace(),
            transientShortcutTabsByWindow: transientTabRegistryOwner.transientShortcutTabsByWindow,
            transientExtensionTabsByID: transientTabRegistryOwner.transientExtensionTabsByID,
            auxiliaryMiniWindowTabsByID: transientTabRegistryOwner.auxiliaryMiniWindowTabsByID
        )
    }
}

extension TabCollectionMembershipOwner.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            prepareTabForRuntime: { [weak tabManager] tab in
                tabManager?.runtimePreparationOwner.prepare(tab)
            },
            regularTabsBySpace: { [weak tabManager] in
                tabManager?.regularTabCollectionStateOwner.tabsBySpaceSnapshot() ?? [:]
            },
            allRegularTabs: { [weak tabManager] in
                tabManager?.regularTabCollectionStateOwner.allTabsSnapshot() ?? []
            },
            containsRegularTab: { [weak tabManager] tab in
                tabManager?.regularTabCollectionOwner.contains(tab) ?? false
            },
            spaces: { [weak tabManager] in
                tabManager?.spaceStateOwner.spaces ?? []
            },
            currentProfileId: { [weak tabManager] in
                tabManager?.runtimeContext?.currentProfileId
            },
            activeShortcutTabs: { [weak tabManager] in
                tabManager?.shortcutPresentationOwner.activeShortcutTabs() ?? []
            },
            activeEssentialTabs: { [weak tabManager] profileId in
                tabManager?.shortcutPresentationOwner.activeEssentialTabs(for: profileId) ?? []
            }
        )
    }
}
