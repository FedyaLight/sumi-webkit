import Foundation

@MainActor
final class RegularTabCollectionOwner {
    struct Removal {
        let tab: Tab
        let spaceId: UUID
        let indexInCurrentSpace: Int?
    }

    private let stateOwner: RegularTabCollectionStateOwner
    private let structuralTransaction: RegularTabStructuralTransaction
    private let shortcutPresentation: TabShortcutPresentationOwner
    private let pins: ShortcutPinCollectionStateOwner
    private let placementTransaction: RegularTabPlacementTransaction

    init(
        stateOwner: RegularTabCollectionStateOwner,
        structuralTransaction: RegularTabStructuralTransaction,
        shortcutPresentation: TabShortcutPresentationOwner,
        pins: ShortcutPinCollectionStateOwner,
        placementTransaction: RegularTabPlacementTransaction
    ) {
        self.stateOwner = stateOwner
        self.structuralTransaction = structuralTransaction
        self.shortcutPresentation = shortcutPresentation
        self.pins = pins
        self.placementTransaction = placementTransaction
    }

    func tabs(in space: Space) -> [Tab] {
        stateOwner.tabs(in: space)
    }

    func tabs(in spaceId: UUID) -> [Tab] {
        stateOwner.tabs(in: spaceId)
    }

    func allTabs(in spaces: [Space]) -> [Tab] {
        stateOwner.allTabs(in: spaces)
    }

    /// Resolves only a durable regular tab. Transient shortcut, extension and
    /// auxiliary tabs intentionally cannot satisfy this lookup.
    func tab(for id: UUID) -> Tab? {
        stateOwner.tab(for: id)
    }

    func contains(_ tab: Tab) -> Bool {
        stateOwner.contains(tab)
    }

    func containsIdentical(_ tab: Tab, in spaceId: UUID) -> Bool {
        stateOwner.containsIdentical(tab, in: spaceId)
    }

    func firstIndex(of tab: Tab, in spaceId: UUID) -> Int? {
        stateOwner.firstIndex(of: tab, in: spaceId)
    }

    func appendIndex(in spaceId: UUID) -> Int {
        stateOwner.appendIndex(in: spaceId)
    }

    func clampedInsertionIndex(_ index: Int, in spaceId: UUID) -> Int {
        stateOwner.clampedInsertionIndex(index, in: spaceId)
    }

    func canInsert(_ tab: Tab, in spaceId: UUID) -> Bool {
        placementTransaction.canInsert(tab, in: spaceId)
    }

    func childInsertionIndex(openedFrom sourceTab: Tab?, in targetSpace: Space?) -> Int? {
        guard let sourceTab, let targetSpace else { return nil }

        if sourceTab.isPinned
            || sourceTab.isSpacePinned
            || sourceTab.shortcutPinRole != nil
            || shortcutPresentation.activeShortcutTabs(role: .essential)
            .contains(where: { $0.id == sourceTab.id })
            || isSpacePinned(sourceTab) {
            return 0
        }

        guard sourceTab.spaceId == targetSpace.id,
              let sourceIndex = firstIndex(of: sourceTab, in: targetSpace.id)
        else {
            return nil
        }

        return sourceIndex + 1
    }

    @discardableResult
    func insert(_ tab: Tab, in spaceId: UUID, at insertionIndex: Int?) -> Bool {
        guard let placement = preparePlacement(
            tab,
            in: spaceId,
            at: insertionIndex
        ) else { return false }
        return placement.commit()
    }

    func preparePlacement(
        _ tab: Tab,
        in spaceId: UUID,
        at insertionIndex: Int?,
        admissionProfileIDs: Set<UUID>? = nil
    ) -> PreparedRegularTabPlacement? {
        placementTransaction.prepare(
            tab,
            in: spaceId,
            at: insertionIndex,
            admissionProfileIDs: admissionProfileIDs
        )
    }

    func place(
        _ tab: Tab,
        in spaceID: UUID,
        at insertionIndex: Int?,
        removingFromSource: @MainActor () -> Bool
    ) -> Bool {
        guard let placement = preparePlacement(
            tab,
            in: spaceID,
            at: insertionIndex
        ) else { return false }
        return structuralTransaction.commitPlacement(
            placement,
            removing: removingFromSource
        )
    }

    func remove(_ tabId: UUID, in spaces: [Space], currentSpaceId: UUID?) -> Removal? {
        for space in spaces {
            if let removal = remove(tabId, from: space.id, currentSpaceId: currentSpaceId) {
                return removal
            }
        }
        return nil
    }

    /// Removes a durable regular-tab batch with one collection replacement per
    /// affected Space. Returned removals are therefore the exact tabs that
    /// existed, rather than the caller's requested candidates.
    func remove(
        _ tabIds: Set<UUID>,
        in spaces: [Space],
        currentSpaceId: UUID?
    ) -> [Removal] {
        guard !tabIds.isEmpty else { return [] }

        var removals: [Removal] = []
        for space in spaces {
            let existing = stateOwner.tabs(in: space.id)
            guard existing.contains(where: { tabIds.contains($0.id) }) else {
                continue
            }

            var remaining: [Tab] = []
            remaining.reserveCapacity(existing.count)
            for (index, tab) in existing.enumerated() {
                if tabIds.contains(tab.id) {
                    removals.append(
                        Removal(
                            tab: tab,
                            spaceId: space.id,
                            indexInCurrentSpace:
                                space.id == currentSpaceId ? index : nil
                        )
                    )
                } else {
                    remaining.append(tab)
                }
            }

            reindex(remaining)
            structuralTransaction.replaceTabs(remaining, in: space.id)
        }
        return removals
    }

    func remove(_ tabId: UUID, from spaceId: UUID, currentSpaceId: UUID?) -> Removal? {
        var regularTabs = stateOwner.tabs(in: spaceId)
        guard regularTabs.isEmpty == false,
              let index = regularTabs.firstIndex(where: { $0.id == tabId })
        else {
            return nil
        }

        let removed = regularTabs.remove(at: index)
        structuralTransaction.replaceTabs(regularTabs, in: spaceId)
        return Removal(
            tab: removed,
            spaceId: spaceId,
            indexInCurrentSpace: spaceId == currentSpaceId ? index : nil
        )
    }

    /// Exact-instance rollback removal. UUID-only removal remains available
    /// for intentional user commands, but transactions must not let a stale
    /// receipt remove a newer physical Tab that reused the same UUID.
    func remove(
        ifIdentical tab: Tab,
        from spaceId: UUID,
        currentSpaceId: UUID?
    ) -> Removal? {
        var regularTabs = stateOwner.tabs(in: spaceId)
        guard let index = regularTabs.firstIndex(where: { $0 === tab }) else {
            return nil
        }

        let removed = regularTabs.remove(at: index)
        structuralTransaction.replaceTabs(regularTabs, in: spaceId)
        return Removal(
            tab: removed,
            spaceId: spaceId,
            indexInCurrentSpace: spaceId == currentSpaceId ? index : nil
        )
    }

    func reorder(_ tab: Tab, in spaceId: UUID, to proposedIndex: Int) -> Bool {
        var regularTabs = stateOwner.tabs(in: spaceId)
        guard regularTabs.isEmpty == false,
              let currentIndex = regularTabs.firstIndex(where: { $0.id == tab.id }) else {
            return false
        }
        let adjustedIndex = SpacePinnedShortcutOrderOwner
            .adjustedSameContainerInsertionIndex(
                currentIndex: currentIndex,
                proposedIndex: proposedIndex
            )
        guard adjustedIndex != currentIndex else { return false }

        regularTabs.remove(at: currentIndex)
        let safeIndex = max(0, min(adjustedIndex, regularTabs.count))
        regularTabs.insert(tab, at: safeIndex)
        reindex(regularTabs)
        structuralTransaction.replaceTabs(regularTabs, in: spaceId)
        return true
    }

    @discardableResult
    func reorderRegularTabs(_ tab: Tab, in spaceId: UUID, to index: Int) -> Bool {
        var regularTabs = stateOwner.tabs(in: spaceId)
        guard let currentIndex = regularTabs.firstIndex(where: { $0.id == tab.id }) else {
            return false
        }
        let adjustedIndex = SpacePinnedShortcutOrderOwner
            .adjustedSameContainerInsertionIndex(
                currentIndex: currentIndex,
                proposedIndex: index
            )
        guard adjustedIndex != currentIndex else { return false }
        regularTabs.remove(at: currentIndex)
        regularTabs.insert(
            tab,
            at: max(0, min(adjustedIndex, regularTabs.count))
        )
        reindex(regularTabs)
        structuralTransaction.commitPersistedTabs(regularTabs, in: spaceId)
        return true
    }

    func moveUp(_ tabId: UUID) -> Bool {
        guard let spaceId = findSpace(for: tabId) else { return false }
        let regularTabs = tabs(in: spaceId)
        guard let currentIndex = regularTabs.firstIndex(where: { $0.id == tabId }),
              currentIndex > 0 else {
            return false
        }

        swapIndexes(in: regularTabs, firstIndex: currentIndex, secondIndex: currentIndex - 1)
        structuralTransaction.replaceTabs(regularTabs, in: spaceId)
        return true
    }

    func moveDown(_ tabId: UUID) -> Bool {
        guard let spaceId = findSpace(for: tabId) else { return false }
        let regularTabs = tabs(in: spaceId)
        guard let currentIndex = regularTabs.firstIndex(where: { $0.id == tabId }),
              currentIndex < regularTabs.count - 1 else {
            return false
        }

        swapIndexes(in: regularTabs, firstIndex: currentIndex, secondIndex: currentIndex + 1)
        structuralTransaction.replaceTabs(regularTabs, in: spaceId)
        return true
    }

    func moveTabUp(_ tabId: UUID) {
        guard let spaceID = findSpace(for: tabId) else { return }
        let regularTabs = tabs(in: spaceID)
        guard let currentIndex = regularTabs.firstIndex(where: { $0.id == tabId }),
              currentIndex > 0 else { return }
        swapIndexes(
            in: regularTabs,
            firstIndex: currentIndex,
            secondIndex: currentIndex - 1
        )
        structuralTransaction.commitPersistedTabs(regularTabs, in: spaceID)
    }

    func moveTabDown(_ tabId: UUID) {
        guard let spaceID = findSpace(for: tabId) else { return }
        let regularTabs = tabs(in: spaceID)
        guard let currentIndex = regularTabs.firstIndex(where: { $0.id == tabId }),
              currentIndex < regularTabs.count - 1 else { return }
        swapIndexes(
            in: regularTabs,
            firstIndex: currentIndex,
            secondIndex: currentIndex + 1
        )
        structuralTransaction.commitPersistedTabs(regularTabs, in: spaceID)
    }

    func findSpace(for tabId: UUID) -> UUID? {
        stateOwner.findSpace(for: tabId)
    }

    func tabsBelow(_ tab: Tab) -> [Tab]? {
        stateOwner.tabsBelow(tab)
    }

    private func isSpacePinned(_ tab: Tab) -> Bool {
        if tab.shortcutPinRole == .spacePinned {
            return true
        }
        guard let shortcutID = tab.shortcutPinId,
              let pin = pins.shortcutPin(by: shortcutID) else {
            return false
        }
        return pin.role == .spacePinned
    }

    private func reindex(_ regularTabs: [Tab]) {
        for (index, tab) in regularTabs.enumerated() {
            tab.index = index
        }
    }

    private func swapIndexes(in regularTabs: [Tab], firstIndex: Int, secondIndex: Int) {
        let first = regularTabs[firstIndex]
        let second = regularTabs[secondIndex]
        let originalIndex = first.index
        first.index = second.index
        second.index = originalIndex
    }
}
