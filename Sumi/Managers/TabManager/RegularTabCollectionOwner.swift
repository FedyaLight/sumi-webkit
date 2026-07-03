import Foundation

@MainActor
final class RegularTabCollectionOwner {
    struct Removal {
        let tab: Tab
        let spaceId: UUID
        let indexInCurrentSpace: Int?
    }

    private unowned let tabManager: TabManager
    private let stateOwner: RegularTabCollectionStateOwner

    init(tabManager: TabManager, stateOwner: RegularTabCollectionStateOwner) {
        self.tabManager = tabManager
        self.stateOwner = stateOwner
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
            || tabManager.isGlobalPinned(sourceTab)
            || tabManager.isSpacePinned(sourceTab) {
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
        var regularTabs = stateOwner.tabs(in: spaceId)
        let safeIndex = max(0, min(insertionIndex ?? regularTabs.count, regularTabs.count))
        tab.spaceId = spaceId
        tab.isPinned = false
        tab.isSpacePinned = false
        tab.folderId = nil
        regularTabs.insert(tab, at: safeIndex)
        reindex(regularTabs)
        tabManager.setTabs(regularTabs, for: spaceId)
    }

    func remove(_ tabId: UUID, in spaces: [Space], currentSpaceId: UUID?) -> Removal? {
        for space in spaces {
            if let removal = remove(tabId, from: space.id, currentSpaceId: currentSpaceId) {
                return removal
            }
        }
        return nil
    }

    func remove(_ tabId: UUID, from spaceId: UUID, currentSpaceId: UUID?) -> Removal? {
        var regularTabs = stateOwner.tabs(in: spaceId)
        guard regularTabs.isEmpty == false,
              let index = regularTabs.firstIndex(where: { $0.id == tabId })
        else {
            return nil
        }

        let removed = regularTabs.remove(at: index)
        tabManager.setTabs(regularTabs, for: spaceId)
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
        let adjustedIndex = tabManager.spacePinnedStructureOwner.adjustedSameContainerInsertionIndex(
            currentIndex: currentIndex,
            proposedIndex: proposedIndex
        )
        guard adjustedIndex != currentIndex else { return false }

        regularTabs.remove(at: currentIndex)
        let safeIndex = max(0, min(adjustedIndex, regularTabs.count))
        regularTabs.insert(tab, at: safeIndex)
        reindex(regularTabs)
        tabManager.setTabs(regularTabs, for: spaceId)
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
        tabManager.setTabs(regularTabs, for: spaceId)
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
        tabManager.setTabs(regularTabs, for: spaceId)
        return true
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
