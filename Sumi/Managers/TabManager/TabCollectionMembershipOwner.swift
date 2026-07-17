import Foundation

@MainActor
final class TabCollectionMembershipOwner {
    private let structuralLookupOwner: TabStructuralLookupOwner
    private let state: TabStateStore
    private let runtimePreparation: TabRuntimePreparationOwner
    private let runtimeConnection: TabRuntimePortConnection

    init(
        structuralLookupOwner: TabStructuralLookupOwner,
        state: TabStateStore,
        runtimePreparation: TabRuntimePreparationOwner,
        runtimeConnection: TabRuntimePortConnection
    ) {
        self.structuralLookupOwner = structuralLookupOwner
        self.state = state
        self.runtimePreparation = runtimePreparation
        self.runtimeConnection = runtimeConnection
    }

    func attach(_ tab: Tab) {
        runtimePreparation.prepare(tab)
        structuralLookupOwner.attach(tab)
    }

    func prepareForRuntime(_ tabs: [Tab]) {
        tabs.forEach { runtimePreparation.prepare($0) }
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

        let normals = state.regularTabs.allTabsSnapshot()
        return state.transientTabs.allTransientTabs
            + normals
    }

    /// Returns every physical Tab residence that participates in the shared
    /// UUID namespace. Auxiliary mini-window Tabs are intentionally excluded
    /// from normal browser membership, but must be included when a transaction
    /// proves that one UUID still names one exact object.
    func allIdentityWitnesses() -> [Tab] {
        state.transientTabs.allTransientTabs
            + state.regularTabs.allTabsSnapshot()
            + Array(
                state.transientTabs.auxiliaryMiniWindowTabsByID.values
            )
    }

    func allTabsForCurrentProfile() -> [Tab] {
        guard let profileId = runtimeConnection.current?.currentProfileId else {
            return allTabs()
        }
        let matchingSpaces = state.spaces.spaces.filter {
            $0.profileId == profileId
        }
        let spaceIds = Set(matchingSpaces.map(\.id))
        let pinned = state.transientTabs.transientShortcutTabs.filter { tab in
            guard tab.shortcutPinRole == .essential,
                  let pinID = tab.shortcutPinId,
                  let pin = state.shortcutPins.shortcutPin(by: pinID) else {
                return false
            }
            return pin.profileId == profileId
        }
        let spacePinned = state.transientTabs.transientShortcutTabs
            .filter { tab in
                guard tab.shortcutPinRole == .spacePinned, let spaceId = tab.spaceId else {
                    return false
                }
                return spaceIds.contains(spaceId)
            }
        let tabsBySpace = state.regularTabs.tabsBySpaceSnapshot()
        let regular = matchingSpaces.flatMap { tabsBySpace[$0.id] ?? [] }
        return pinned + spacePinned + regular
    }

    func contains(_ tab: Tab) -> Bool {
        if state.transientTabs.transientShortcutTabs.contains(where: {
            $0.id == tab.id
        }) {
            return true
        }
        if state.regularTabs.contains(tab) {
            return true
        }
        return false
    }

    func tab(for id: UUID) -> Tab? {
        structuralLookupOwner.tab(for: id, snapshot: structuralLookupSnapshot)
    }

    func isTransientExtensionTab(_ tab: Tab) -> Bool {
        state.transientTabs.isTransientExtensionTab(tab)
    }

    func registerTransientExtensionTab(_ tab: Tab) {
        state.transientTabs.registerTransientExtensionTab(tab)
        structuralLookupOwner.insertTransientExtensionTab(tab)
    }

    func removeTransientExtensionTab(id: UUID) -> Tab? {
        guard let tab = state.transientTabs.removeTransientExtensionTab(id: id) else {
            return nil
        }
        structuralLookupOwner.removeTransientExtensionTab(id)
        return tab
    }

    @discardableResult
    func promoteTransientExtensionTab(_ tab: Tab) -> Bool {
        guard state.transientTabs.promoteTransientExtensionTab(tab) else {
            return false
        }
        structuralLookupOwner.stopTrackingTransientTab(tab.id)
        return true
    }

    func registerAuxiliaryMiniWindowTab(_ tab: Tab) {
        state.transientTabs.registerAuxiliaryMiniWindowTab(tab)
    }

    func auxiliaryMiniWindowTab(for id: UUID) -> Tab? {
        state.transientTabs.auxiliaryMiniWindowTab(for: id)
    }

    func removeAuxiliaryMiniWindowTab(_ tab: Tab) {
        state.transientTabs.removeAuxiliaryMiniWindowTab(tab)
        structuralLookupOwner.remove(tab.id)
    }

    func isAuxiliaryMiniWindowTab(_ tab: Tab) -> Bool {
        state.transientTabs.isAuxiliaryMiniWindowTab(tab)
    }

    private var structuralLookupSnapshot: TabStructuralLookupSnapshot {
        TabStructuralLookupSnapshot(
            tabsBySpace: state.regularTabs.tabsBySpaceSnapshot(),
            transientShortcutTabsByWindow: state.transientTabs.transientShortcutTabsByWindow,
            transientExtensionTabsByID: state.transientTabs.transientExtensionTabsByID,
            auxiliaryMiniWindowTabsByID: state.transientTabs.auxiliaryMiniWindowTabsByID
        )
    }
}
