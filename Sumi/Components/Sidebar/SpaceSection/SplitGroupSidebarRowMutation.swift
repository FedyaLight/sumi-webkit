//
//  SplitGroupSidebarRowMutation.swift
//  Sumi
//

import SumiDomain
import SwiftUI

extension SplitGroupSidebarRow {
    var shouldAnimateProjectedLayout: Bool {
        !reduceMotion && !sumiSettings.shouldReduceChromeMotion
    }

    var projectedLayoutAnimation: Animation? {
        SidebarMotionPolicy.contentLayoutAnimation(
            for: SidebarMotionPolicy.currentMode(
                reduceMotion: !shouldAnimateProjectedLayout
            )
        )
    }

    var resolvedDisplayItems: [SplitGroupSidebarItem] {
        SplitGroupSidebarModel.displayItems(
            current: items,
            animationSnapshot: displayedItems
        )
    }

    func isDeparting(_ item: SplitGroupSidebarItem) -> Bool {
        departingItemIds.contains(item.id)
    }

    func shouldShowSeparator(after index: Int, in rowItems: [SplitGroupSidebarItem]) -> Bool {
        guard index < rowItems.count - 1 else { return false }
        guard !isDeparting(rowItems[index]) else { return false }
        return rowItems[(index + 1)...].contains { !isDeparting($0) }
    }

    func reconcileDisplayedItems(with newItems: [SplitGroupSidebarItem]) {
        presentationGeneration &+= 1
        let generation = presentationGeneration

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
            withAnimation(projectedLayoutAnimation) {
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

        withAnimation(
            projectedLayoutAnimation,
            completionCriteria: .logicallyComplete
        ) {
            displayedItems = projectedItems
            departingItemIds.formUnion(removedIds)
        } completion: {
            guard presentationGeneration == generation else { return }
            SidebarMotionTransaction.withoutAnimation {
                displayedItems = newItems
                departingItemIds.subtract(removedIds)
            }
        }
    }

    var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }
}
