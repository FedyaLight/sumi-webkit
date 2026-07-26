//
//  RegularTabsListAnimation.swift
//  Sumi
//

import SwiftUI

enum RegularTabRemovalMode: Equatable {
    case fadeOnly
    case heightCollapse
}

enum RegularSidebarVisualChange: Equatable {
    case none
    case insertion(Set<UUID>)
    case removal(UUID)
    case immediateReplacement
    case reorder

    static func resolve(
        from oldRun: SidebarVisualSceneProjection.RegularRun,
        to newRun: SidebarVisualSceneProjection.RegularRun
    ) -> Self {
        let oldIdentities = oldRun.rows.map(\.identity)
        let newIdentities = newRun.rows.map(\.identity)
        let oldIdentitySet = Set(oldIdentities)
        let newIdentitySet = Set(newIdentities)
        let insertedRows = newRun.rows.filter {
            !oldIdentitySet.contains($0.identity)
        }
        let removedRows = oldRun.rows.filter {
            !newIdentitySet.contains($0.identity)
        }

        guard insertedRows.isEmpty || removedRows.isEmpty else {
            return .immediateReplacement
        }

        if !insertedRows.isEmpty {
            let insertedTabIDs = insertedRows.compactMap { row -> UUID? in
                guard case .tab(let tabID) = row.identity else { return nil }
                return tabID
            }
            return insertedTabIDs.count == insertedRows.count
                ? .insertion(Set(insertedTabIDs))
                : .immediateReplacement
        }

        if removedRows.count == 1,
           case .tab(let tabID) = removedRows[0].identity {
            return .removal(tabID)
        }
        if !removedRows.isEmpty {
            return .immediateReplacement
        }

        if oldRun != newRun {
            return .reorder
        }
        return .none
    }
}

struct RegularTabRowMotion: Equatable {
    let layoutHeight: CGFloat
    let hidesContent: Bool
    let isInteractionDisabled: Bool
}

struct RegularTabRemovalPlan {
    let generation: Int
    let mode: RegularTabRemovalMode
    let finalRows: [SidebarVisualSceneProjection.RegularRow]
}

struct RegularTabsListAnimationState {
    var renderedRows: [SidebarVisualSceneProjection.RegularRow] = []
    var gapHeights: [UUID: CGFloat] = [:]
    var appearingTabIds: Set<UUID> = []
    var disappearingTabIds: Set<UUID> = []
    var removalModes: [UUID: RegularTabRemovalMode] = [:]
    var tabRenderCache: [UUID: Tab] = [:]
    var layoutAnimationGeneration = 0

    var hasRemovalInFlight: Bool {
        !removalModes.isEmpty
    }

    var renderedRun: SidebarVisualSceneProjection.RegularRun {
        SidebarVisualSceneProjection.RegularRun(rows: renderedRows)
    }

    mutating func reset(
        to run: SidebarVisualSceneProjection.RegularRun
    ) {
        renderedRows = run.rows
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
        renderedRows.contains { row in
            row.identity == .tab(tabId)
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
            finalRows: finalRows(removing: tabId)
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
        finalRows: [SidebarVisualSceneProjection.RegularRow]
    ) -> Bool {
        guard layoutAnimationGeneration == generation else { return false }
        renderedRows = finalRows
        gapHeights.removeValue(forKey: tabId)
        removalModes.removeValue(forKey: tabId)
        disappearingTabIds.remove(tabId)
        return true
    }

    private func isLastRowRemoval(tabId: UUID) -> Bool {
        renderedRows.count == 1
            && renderedRows[0].identity == .tab(tabId)
    }

    private func finalRows(
        removing tabId: UUID
    ) -> [SidebarVisualSceneProjection.RegularRow] {
        renderedRows.filter { row in
            row.identity != .tab(tabId)
        }
    }
}
