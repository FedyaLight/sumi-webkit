import Foundation

@MainActor
final class RegularTabCollectionOwner {
    struct Removal {
        let tab: Tab
        let spaceId: UUID
        let indexInCurrentSpace: Int?
    }

    private unowned let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    func tabs(in space: Space) -> [Tab] {
        tabs(in: space.id)
    }

    func tabs(in spaceId: UUID) -> [Tab] {
        Array(tabManager.tabsBySpace[spaceId] ?? [])
    }

    func allTabs(in spaces: [Space]) -> [Tab] {
        spaces.flatMap { tabManager.tabsBySpace[$0.id] ?? [] }
    }

    func contains(_ tab: Tab) -> Bool {
        guard let spaceId = tab.spaceId else { return false }
        return (tabManager.tabsBySpace[spaceId] ?? []).contains { $0.id == tab.id }
    }

    func firstIndex(of tab: Tab, in spaceId: UUID) -> Int? {
        tabManager.tabsBySpace[spaceId]?.firstIndex { $0.id == tab.id }
    }

    func appendIndex(in spaceId: UUID) -> Int {
        (tabManager.tabsBySpace[spaceId]?.map(\.index).max() ?? -1) + 1
    }

    func clampedInsertionIndex(_ index: Int, in spaceId: UUID) -> Int {
        let count = tabManager.tabsBySpace[spaceId]?.count ?? 0
        return max(0, min(index, count))
    }

    func childInsertionIndex(openedFrom sourceTab: Tab?, in targetSpace: Space?) -> Int? {
        guard let sourceTab, let targetSpace else { return nil }

        if sourceTab.isPinned
            || sourceTab.isSpacePinned
            || sourceTab.shortcutPinRole != nil
            || tabManager.isGlobalPinned(sourceTab)
            || tabManager.isSpacePinned(sourceTab)
        {
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
        var regularTabs = tabManager.tabsBySpace[spaceId] ?? []
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
        guard var regularTabs = tabManager.tabsBySpace[spaceId],
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
        guard var regularTabs = tabManager.tabsBySpace[spaceId],
              let currentIndex = regularTabs.firstIndex(where: { $0.id == tab.id }) else {
            return false
        }
        let adjustedIndex = tabManager.adjustedSameContainerInsertionIndex(
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
        for (spaceId, tabs) in tabManager.tabsBySpace where tabs.contains(where: { $0.id == tabId }) {
            return spaceId
        }
        return nil
    }

    func tabsBelow(_ tab: Tab) -> [Tab]? {
        guard let spaceId = tab.spaceId,
              let tabs = tabManager.tabsBySpace[spaceId],
              tabs.contains(where: { $0.id == tab.id }) else {
            return nil
        }
        return tabs.filter { $0.index > tab.index }
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
