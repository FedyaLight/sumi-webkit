import Foundation

@MainActor
final class RegularTabCollectionOwner {
    struct Removal {
        let tab: Tab
        let spaceId: UUID
        let indexInCurrentSpace: Int?
    }

    private let stateOwner: RegularTabCollectionStateOwner
    private let setTabs: @MainActor ([Tab], UUID) -> Void
    private let adjustedSameContainerInsertionIndex: @MainActor (_ currentIndex: Int, _ proposedIndex: Int) -> Int
    private let isGlobalPinned: @MainActor (Tab) -> Bool
    private let isSpacePinned: @MainActor (Tab) -> Bool
    private let withStructuralUpdateTransaction: @MainActor (@MainActor () -> Bool) -> Bool
    private let scheduleStructuralPersistence: @MainActor () -> Void
    private let prepareForSpaceTransition: @MainActor (
        Tab,
        UUID
    ) -> TabSpaceProfileTransitionPreparation?
    private let finishSpaceTransition: @MainActor (
        TabSpaceProfileTransitionPreparation,
        Tab
    ) -> Void

    init(
        stateOwner: RegularTabCollectionStateOwner,
        setTabs: @escaping @MainActor ([Tab], UUID) -> Void,
        adjustedSameContainerInsertionIndex: @escaping @MainActor (_ currentIndex: Int, _ proposedIndex: Int) -> Int,
        isGlobalPinned: @escaping @MainActor (Tab) -> Bool,
        isSpacePinned: @escaping @MainActor (Tab) -> Bool,
        withStructuralUpdateTransaction: @escaping @MainActor (@MainActor () -> Bool) -> Bool,
        scheduleStructuralPersistence: @escaping @MainActor () -> Void,
        prepareForSpaceTransition: @escaping @MainActor (
            Tab,
            UUID
        ) -> TabSpaceProfileTransitionPreparation?,
        finishSpaceTransition: @escaping @MainActor (
            TabSpaceProfileTransitionPreparation,
            Tab
        ) -> Void
    ) {
        self.stateOwner = stateOwner
        self.setTabs = setTabs
        self.adjustedSameContainerInsertionIndex = adjustedSameContainerInsertionIndex
        self.isGlobalPinned = isGlobalPinned
        self.isSpacePinned = isSpacePinned
        self.withStructuralUpdateTransaction = withStructuralUpdateTransaction
        self.scheduleStructuralPersistence = scheduleStructuralPersistence
        self.prepareForSpaceTransition = prepareForSpaceTransition
        self.finishSpaceTransition = finishSpaceTransition
    }

    convenience init(tabManager: TabManager, stateOwner: RegularTabCollectionStateOwner) {
        self.init(
            stateOwner: stateOwner,
            setTabs: { [weak tabManager] tabs, spaceId in
                tabManager?.structuralCollectionMutationOwner.setTabs(tabs, for: spaceId)
            },
            adjustedSameContainerInsertionIndex: { [weak tabManager] currentIndex, proposedIndex in
                tabManager?.spacePinnedStructureOwner.adjustedSameContainerInsertionIndex(
                    currentIndex: currentIndex,
                    proposedIndex: proposedIndex
                ) ?? proposedIndex
            },
            isGlobalPinned: { [weak tabManager] tab in
                tabManager?.shortcutPresentationOwner.activeShortcutTabs(role: .essential).contains { $0.id == tab.id } ?? false
            },
            isSpacePinned: { [weak tabManager] tab in
                if tab.shortcutPinRole == .spacePinned {
                    return true
                }
                guard let shortcutId = tab.shortcutPinId,
                      let pin = tabManager?.shortcutPinCollectionStateOwner.shortcutPin(by: shortcutId) else { return false }
                return pin.role == .spacePinned
            },
            withStructuralUpdateTransaction: { [weak tabManager] operation in
                guard let tabManager else { return operation() }
                return tabManager.structuralLookupCoordinator.withTransaction(operation)
            },
            scheduleStructuralPersistence: { [weak tabManager] in
                tabManager?.structuralPersistence.scheduleStructuralPersistence()
            },
            prepareForSpaceTransition: { [weak tabManager] tab, targetSpaceID in
                tabManager?.profileAssignments.tabs.prepareForSpaceTransition(
                    tab: tab,
                    targetSpaceID: targetSpaceID
                )
            },
            finishSpaceTransition: { [weak tabManager] preparation, tab in
                _ = tabManager?.profileAssignments.tabs.finishSpaceTransition(
                    preparation,
                    for: tab
                )
            }
        )
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

    func firstIndex(of tab: Tab, in spaceId: UUID) -> Int? {
        stateOwner.firstIndex(of: tab, in: spaceId)
    }

    func appendIndex(in spaceId: UUID) -> Int {
        stateOwner.appendIndex(in: spaceId)
    }

    func clampedInsertionIndex(_ index: Int, in spaceId: UUID) -> Int {
        stateOwner.clampedInsertionIndex(index, in: spaceId)
    }

    func childInsertionIndex(openedFrom sourceTab: Tab?, in targetSpace: Space?) -> Int? {
        guard let sourceTab, let targetSpace else { return nil }

        if sourceTab.isPinned
            || sourceTab.isSpacePinned
            || sourceTab.shortcutPinRole != nil
            || isGlobalPinned(sourceTab)
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

    func insert(_ tab: Tab, in spaceId: UUID, at insertionIndex: Int?) {
        let profileTransition = prepareForSpaceTransition(tab, spaceId)
        var regularTabs = stateOwner.tabs(in: spaceId)
        let safeIndex = max(0, min(insertionIndex ?? regularTabs.count, regularTabs.count))
        tab.spaceId = spaceId
        tab.isPinned = false
        tab.isSpacePinned = false
        tab.folderId = nil
        regularTabs.insert(tab, at: safeIndex)
        reindex(regularTabs)
        setTabs(regularTabs, spaceId)
        if let profileTransition {
            finishSpaceTransition(profileTransition, tab)
        }
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
            setTabs(remaining, space.id)
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
        setTabs(regularTabs, spaceId)
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
        let adjustedIndex = adjustedSameContainerInsertionIndex(currentIndex, proposedIndex)
        guard adjustedIndex != currentIndex else { return false }

        regularTabs.remove(at: currentIndex)
        let safeIndex = max(0, min(adjustedIndex, regularTabs.count))
        regularTabs.insert(tab, at: safeIndex)
        reindex(regularTabs)
        setTabs(regularTabs, spaceId)
        return true
    }

    @discardableResult
    func reorderRegularTabs(_ tab: Tab, in spaceId: UUID, to index: Int) -> Bool {
        withStructuralUpdateTransaction {
            guard reorder(tab, in: spaceId, to: index) else {
                return false
            }
            scheduleStructuralPersistence()
            return true
        }
    }

    func moveUp(_ tabId: UUID) -> Bool {
        guard let spaceId = findSpace(for: tabId) else { return false }
        let regularTabs = tabs(in: spaceId)
        guard let currentIndex = regularTabs.firstIndex(where: { $0.id == tabId }),
              currentIndex > 0 else {
            return false
        }

        swapIndexes(in: regularTabs, firstIndex: currentIndex, secondIndex: currentIndex - 1)
        setTabs(regularTabs, spaceId)
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
        setTabs(regularTabs, spaceId)
        return true
    }

    func moveTabUp(_ tabId: UUID) {
        _ = withStructuralUpdateTransaction {
            guard moveUp(tabId) else { return false }
            scheduleStructuralPersistence()
            return true
        }
    }

    func moveTabDown(_ tabId: UUID) {
        _ = withStructuralUpdateTransaction {
            guard moveDown(tabId) else { return false }
            scheduleStructuralPersistence()
            return true
        }
    }

    func findSpace(for tabId: UUID) -> UUID? {
        stateOwner.findSpace(for: tabId)
    }

    func tabsBelow(_ tab: Tab) -> [Tab]? {
        stateOwner.tabsBelow(tab)
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
