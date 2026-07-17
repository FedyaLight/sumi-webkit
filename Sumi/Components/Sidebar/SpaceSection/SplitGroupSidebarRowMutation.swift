//
//  SplitGroupSidebarRowMutation.swift
//  Sumi
//

import SumiDomain
import SwiftUI

extension SplitGroupSidebarRow {
    func performSplitSidebarMutation(_ update: () -> Void) {
        guard !reduceMotion && !sumiSettings.shouldReduceChromeMotion else {
            update()
            return
        }
        withAnimation(SidebarDropMotion.contentLayout, update)
    }

    var shouldAnimateProjectedLayout: Bool {
        !reduceMotion && !sumiSettings.shouldReduceChromeMotion
    }

    var resolvedDisplayItems: [SplitGroupSidebarItem] {
        displayedItems.isEmpty ? items : displayedItems
    }

    func isDeparting(_ item: SplitGroupSidebarItem) -> Bool {
        departingItemIds.contains(item.id)
    }

    func shouldShowSeparator(after index: Int, in rowItems: [SplitGroupSidebarItem]) -> Bool {
        guard index < rowItems.count - 1 else { return false }
        guard !isDeparting(rowItems[index]) else { return false }
        return rowItems[(index + 1)...].contains { !isDeparting($0) }
    }

    func performSegmentMutation(for item: SplitGroupSidebarItem, in rowItems: [SplitGroupSidebarItem]) {
        let memberID = item.id
        guard !reduceMotion && !sumiSettings.shouldReduceChromeMotion else {
            onSegmentAction(memberID)
            return
        }

        onSegmentActionAnimationStart(memberID)
        withAnimation(SidebarDropMotion.contentLayout) {
            let _ = departingItemIds.insert(item.id)
            if shouldCollapseRowAfterRemoving(item, from: rowItems) {
                isCollapsingRow = true
            }
        }
        let completionDelay = segmentActionCompletionDelay(for: item)
        DispatchQueue.main.asyncAfter(deadline: .now() + completionDelay) {
            onSegmentAction(memberID)
        }
    }

    func segmentActionCompletionDelay(for item: SplitGroupSidebarItem) -> Double {
        segmentAction(item) == .restore
            ? SidebarDropMotion.shortcutRestoreActionDelay
            : SidebarDropMotion.contentLayoutDuration
    }

    func shouldCollapseRowAfterRemoving(
        _ item: SplitGroupSidebarItem,
        from rowItems: [SplitGroupSidebarItem]
    ) -> Bool {
        guard !group.container.isShortcutSidebar,
              segmentAction(item) == .close
        else {
            return false
        }

        let activeItems = rowItems.filter { !isDeparting($0) }
        guard activeItems.count <= SplitGroup.minimumMembers else {
            return false
        }

        let remainingItems = activeItems.filter { $0.id != item.id }
        return remainingItems.count == 1 && isShortcutBacked(remainingItems[0])
    }

    func isShortcutBacked(_ item: SplitGroupSidebarItem) -> Bool {
        if case .shortcutPin = item.id { return true }
        return false
    }

    func reconcileDisplayedItems(with newItems: [SplitGroupSidebarItem]) {
        guard !reduceMotion && !sumiSettings.shouldReduceChromeMotion else {
            displayedItems = newItems
            departingItemIds.removeAll()
            return
        }

        let oldItems = displayedItems.isEmpty ? items : displayedItems
        let newItemsById = Dictionary(uniqueKeysWithValues: newItems.map { ($0.id, $0) })
        let newIds = Set(newItems.map(\.id))
        let removedIds = Set(oldItems.map(\.id)).subtracting(newIds)

        guard !removedIds.isEmpty else {
            withAnimation(SidebarDropMotion.contentLayout) {
                displayedItems = newItems
                departingItemIds.formIntersection(newIds)
            }
            return
        }

        if removedIds.isSubset(of: departingItemIds) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            transaction.animation = nil
            withTransaction(transaction) {
                displayedItems = newItems
                departingItemIds.subtract(removedIds)
            }
            return
        }

        var seenIds = Set<SplitMemberID>()
        var projectedItems: [SplitGroupSidebarItem] = oldItems.map { oldItem in
            seenIds.insert(oldItem.id)
            return newItemsById[oldItem.id] ?? oldItem
        }
        projectedItems.append(contentsOf: newItems.filter { seenIds.insert($0.id).inserted })

        withAnimation(SidebarDropMotion.contentLayout) {
            displayedItems = projectedItems
            departingItemIds.formUnion(removedIds)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + SidebarDropMotion.contentLayoutDuration) {
            displayedItems = newItems
            departingItemIds.subtract(removedIds)
        }
    }

    var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }

}
