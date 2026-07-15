import Foundation

@MainActor
final class TabCollectionMembershipOwner {
    private let structuralLookupOwner: TabStructuralLookupOwner
    private let transientTabRegistryOwner: TabTransientTabRegistryOwner
    private let prepareTabForRuntime: @MainActor (Tab) -> Void
    private let regularTabsBySpace: @MainActor () -> [UUID: [Tab]]
    private let allRegularTabs: @MainActor () -> [Tab]
    private let containsRegularTab: @MainActor (Tab) -> Bool
    private let spaces: @MainActor () -> [Space]
    private let currentProfileId: @MainActor () -> UUID?
    private let activeShortcutTabs: @MainActor () -> [Tab]
    private let activeEssentialTabs: @MainActor (UUID?) -> [Tab]

    init(
        structuralLookupOwner: TabStructuralLookupOwner,
        transientTabRegistryOwner: TabTransientTabRegistryOwner,
        prepareTabForRuntime: @escaping @MainActor (Tab) -> Void,
        regularTabsBySpace: @escaping @MainActor () -> [UUID: [Tab]],
        allRegularTabs: @escaping @MainActor () -> [Tab],
        containsRegularTab: @escaping @MainActor (Tab) -> Bool,
        spaces: @escaping @MainActor () -> [Space],
        currentProfileId: @escaping @MainActor () -> UUID?,
        activeShortcutTabs: @escaping @MainActor () -> [Tab],
        activeEssentialTabs: @escaping @MainActor (UUID?) -> [Tab]
    ) {
        self.structuralLookupOwner = structuralLookupOwner
        self.transientTabRegistryOwner = transientTabRegistryOwner
        self.prepareTabForRuntime = prepareTabForRuntime
        self.regularTabsBySpace = regularTabsBySpace
        self.allRegularTabs = allRegularTabs
        self.containsRegularTab = containsRegularTab
        self.spaces = spaces
        self.currentProfileId = currentProfileId
        self.activeShortcutTabs = activeShortcutTabs
        self.activeEssentialTabs = activeEssentialTabs
    }

    convenience init(
        tabManager: TabManager,
        structuralLookupOwner: TabStructuralLookupOwner,
        transientTabRegistryOwner: TabTransientTabRegistryOwner
    ) {
        self.init(
            structuralLookupOwner: structuralLookupOwner,
            transientTabRegistryOwner: transientTabRegistryOwner,
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
                tabManager?.runtimePorts?.currentProfileId
            },
            activeShortcutTabs: { [weak tabManager] in
                tabManager?.shortcutPresentationOwner.activeShortcutTabs() ?? []
            },
            activeEssentialTabs: { [weak tabManager] profileId in
                tabManager?.shortcutPresentationOwner.activeEssentialTabs(for: profileId) ?? []
            }
        )
    }

    func attach(_ tab: Tab) {
        prepareTabForRuntime(tab)
        structuralLookupOwner.attach(tab)
    }

    func prepareForRuntime(_ tabs: [Tab]) {
        tabs.forEach(prepareTabForRuntime)
    }

    func attachPreparedIfAbsent(
        _ tabs: [Tab],
        retainingExact source: Tab
    ) -> Bool {
        structuralLookupOwner.attachIfAbsent(
            tabs,
            retainingExact: source
        )
    }

    func lookupContainsExact(_ tab: Tab) -> Bool {
        structuralLookupOwner.containsExact(tab)
    }

    func lookupContainsNone(of tabIDs: Set<UUID>) -> Bool {
        structuralLookupOwner.containsNone(of: tabIDs)
    }

    func hasExactIdentityResidences(
        _ expected: [Tab],
        scopedTo tabIDs: Set<UUID>
    ) -> Bool {
        let actual = allIdentityWitnesses().filter {
            tabIDs.contains($0.id)
        }
        guard actual.count == expected.count else { return false }
        return expected.allSatisfy { expectedTab in
            actual.filter { $0.id == expectedTab.id }.count == 1
                && actual.contains { $0 === expectedTab }
        }
    }

    func detach(_ tab: Tab) {
        structuralLookupOwner.detach(tab)
    }

    func canDetachExact(_ tabs: [Tab]) -> Bool {
        tabs.allSatisfy(structuralLookupOwner.containsExact)
    }

    func detachExact(_ tabs: [Tab]) -> Bool {
        guard canDetachExact(tabs) else { return false }
        return tabs.allSatisfy(structuralLookupOwner.detachExact)
    }

    func allTabs() -> [Tab] {
        structuralLookupOwner.rebuildIfEmpty(with: structuralLookupSnapshot)

        let normals = allRegularTabs()
        return transientTabRegistryOwner.allTransientTabs
            + normals
    }

    /// Returns every physical Tab residence that participates in the shared
    /// UUID namespace. Auxiliary mini-window Tabs are intentionally excluded
    /// from normal browser membership, but must be included when a transaction
    /// proves that one UUID still names one exact object.
    func allIdentityWitnesses() -> [Tab] {
        transientTabRegistryOwner.allTransientTabs
            + allRegularTabs()
            + Array(
                transientTabRegistryOwner.auxiliaryMiniWindowTabsByID.values
            )
    }

    func allTabsForCurrentProfile() -> [Tab] {
        guard let profileId = currentProfileId() else {
            return allTabs()
        }
        let matchingSpaces = spaces().filter { $0.profileId == profileId }
        let spaceIds = Set(matchingSpaces.map(\.id))
        let pinned = activeEssentialTabs(profileId)
        let spacePinned = transientTabRegistryOwner.transientShortcutTabs
            .filter { tab in
                guard tab.shortcutPinRole == .spacePinned, let spaceId = tab.spaceId else {
                    return false
                }
                return spaceIds.contains(spaceId)
            }
        let regular = matchingSpaces.flatMap { regularTabsBySpace()[$0.id] ?? [] }
        return pinned + spacePinned + regular
    }

    func contains(_ tab: Tab) -> Bool {
        if activeShortcutTabs().contains(where: { $0.id == tab.id }) {
            return true
        }
        if containsRegularTab(tab) {
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
            tabsBySpace: regularTabsBySpace(),
            transientShortcutTabsByWindow: transientTabRegistryOwner.transientShortcutTabsByWindow,
            transientExtensionTabsByID: transientTabRegistryOwner.transientExtensionTabsByID,
            auxiliaryMiniWindowTabsByID: transientTabRegistryOwner.auxiliaryMiniWindowTabsByID
        )
    }
}
