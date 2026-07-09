//
//  VisibleTabPreparationPlan.swift
//  Sumi
//
//  Plans which tab WebViews a window should materialize for its visible layout.
//

import Foundation

enum VisibleTabPreparationPlan {
    static func visibleTabIDs(
        currentTabId: UUID?,
        splitTabIds: [UUID]
    ) -> [UUID] {
        guard let currentTabId else { return [] }

        guard splitTabIds.contains(currentTabId) else {
            return [currentTabId]
        }

        var seenIDs = Set<UUID>()
        var orderedIDs: [UUID] = []
        for tabId in splitTabIds {
            guard seenIDs.insert(tabId).inserted else { continue }
            orderedIDs.append(tabId)
        }
        return orderedIDs.isEmpty ? [currentTabId] : orderedIDs
    }
}
