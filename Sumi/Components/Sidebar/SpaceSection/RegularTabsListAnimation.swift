//
//  RegularTabsListAnimation.swift
//  Sumi
//

import SwiftUI

enum RegularTabRenderedItem: Hashable {
    case tab(UUID)
    case gap(UUID)
}

enum RegularTabRemovalMode: Equatable {
    case fadeOnly
    case heightCollapse
}

struct RegularTabRowMotion: Equatable {
    let layoutHeight: CGFloat
    let hidesContent: Bool
    let isInteractionDisabled: Bool
}

struct RegularTabRemovalPlan {
    let generation: Int
    let mode: RegularTabRemovalMode
    let finalItems: [RegularTabRenderedItem]
}

struct RegularTabsListAnimationState {
    var renderedItems: [RegularTabRenderedItem] = []
    var gapHeights: [UUID: CGFloat] = [:]
    var appearingTabIds: Set<UUID> = []
    var disappearingTabIds: Set<UUID> = []
    var removalModes: [UUID: RegularTabRemovalMode] = [:]
    var tabRenderCache: [UUID: Tab] = [:]
    var layoutAnimationGeneration = 0

    var hasRemovalInFlight: Bool {
        !removalModes.isEmpty
    }

    mutating func reset(to tabIds: [UUID]) {
        renderedItems = tabIds.map(RegularTabRenderedItem.tab)
        gapHeights.removeAll()
        appearingTabIds.removeAll()
        disappearingTabIds.removeAll()
        removalModes.removeAll()
        layoutAnimationGeneration += 1
    }

    mutating func cacheTabs(_ tabs: [Tab]) {
        for tab in tabs {
            tabRenderCache[tab.id] = tab
        }
    }

    mutating func preserveSnapshots(
        from oldIds: [UUID],
        to newIds: [UUID],
        liveTab: (UUID) -> Tab?
    ) {
        for removedId in oldIds where !newIds.contains(removedId) {
            guard tabRenderCache[removedId] == nil else { continue }
            if let tab = liveTab(removedId) {
                tabRenderCache[removedId] = tab
            }
        }
    }

    func resolvedTab(for tabId: UUID, liveTab: (UUID) -> Tab?) -> Tab? {
        liveTab(tabId) ?? tabRenderCache[tabId]
    }

    func containsRenderedTab(_ tabId: UUID) -> Bool {
        renderedItems.contains { item in
            if case .tab(let id) = item { return id == tabId }
            return false
        }
    }

    func isRemovalInFlight(for tabId: UUID) -> Bool {
        removalModes[tabId] != nil
    }

    func rowMotion(for tabId: UUID) -> RegularTabRowMotion {
        let isAppearing = appearingTabIds.contains(tabId)
        let removalMode = removalModes[tabId]
        let isDisappearing = disappearingTabIds.contains(tabId)
        let isHeightCollapsing = removalMode == .heightCollapse
        let layoutHeight = isHeightCollapsing
            ? (gapHeights[tabId] ?? SidebarRowLayout.rowHeight)
            : SidebarRowLayout.rowHeight

        return RegularTabRowMotion(
            layoutHeight: layoutHeight,
            hidesContent: isAppearing || isDisappearing,
            isInteractionDisabled: isAppearing || removalMode != nil
        )
    }

    mutating func beginInsertion(_ insertedIds: Set<UUID>, liveTab: (UUID) -> Tab?) {
        appearingTabIds.formUnion(insertedIds)
        for tabId in insertedIds {
            if let tab = liveTab(tabId) {
                tabRenderCache[tabId] = tab
            }
        }
    }

    mutating func revealInserted(_ insertedIds: Set<UUID>) {
        appearingTabIds.subtract(insertedIds)
    }

    mutating func prepareRemoval(tabId: UUID, tab: Tab) -> RegularTabRemovalPlan? {
        guard containsRenderedTab(tabId), !isRemovalInFlight(for: tabId) else { return nil }

        tabRenderCache[tabId] = tab
        let mode: RegularTabRemovalMode = isLastRowRemoval(tabId: tabId) ? .fadeOnly : .heightCollapse
        layoutAnimationGeneration += 1
        appearingTabIds.remove(tabId)
        removalModes[tabId] = mode
        if mode == .heightCollapse {
            gapHeights[tabId] = SidebarRowLayout.rowHeight
        }

        return RegularTabRemovalPlan(
            generation: layoutAnimationGeneration,
            mode: mode,
            finalItems: finalItems(removing: tabId)
        )
    }

    mutating func commitRemovalAppearance(tabId: UUID, mode: RegularTabRemovalMode) {
        disappearingTabIds.insert(tabId)
        if mode == .heightCollapse {
            gapHeights[tabId] = 0
        }
    }

    @discardableResult
    mutating func finishRemoval(
        tabId: UUID,
        generation: Int,
        finalItems: [RegularTabRenderedItem]
    ) -> Bool {
        guard layoutAnimationGeneration == generation else { return false }
        renderedItems = finalItems
        gapHeights.removeValue(forKey: tabId)
        removalModes.removeValue(forKey: tabId)
        disappearingTabIds.remove(tabId)
        return true
    }

    private func isLastRowRemoval(tabId: UUID) -> Bool {
        let renderedTabIds = renderedItems.compactMap { item -> UUID? in
            guard case .tab(let id) = item else { return nil }
            return id
        }
        return renderedTabIds.count == 1 && renderedTabIds[0] == tabId
    }

    private func finalItems(removing tabId: UUID) -> [RegularTabRenderedItem] {
        renderedItems.compactMap { item in
            guard case .tab(let id) = item else { return item }
            return id == tabId ? nil : item
        }
    }
}
