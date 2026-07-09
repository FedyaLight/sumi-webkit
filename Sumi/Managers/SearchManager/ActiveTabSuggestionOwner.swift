//
//  ActiveTabSuggestionOwner.swift
//  Sumi
//
//

import Foundation

/// Ranks and filters a window's open tabs into "active tab" suggestions:
/// candidates come from the current profile's regular tabs plus any live
/// shortcut tabs for the window, excluding tabs already visible in a split
/// and Sumi-native surfaces, then ranked by recent window selection history
/// (falling back to last-selected time, current space, and index).
///
/// Depends only on narrow closures over `TabManager` collaborators, so the
/// ranking/candidate logic can be exercised with fixture tabs and a
/// synthetic `BrowserWindowState` instead of a live `TabManager`.
@MainActor
final class ActiveTabSuggestionOwner {
    private let allTabsForCurrentProfile: @MainActor () -> [Tab]
    private let liveShortcutTabs: @MainActor (_ windowId: UUID) -> [Tab]
    private let shortcutLiveTab: @MainActor (_ pinId: UUID, _ windowId: UUID) -> Tab?
    private let visibleSplitTabIds: @MainActor (_ windowId: UUID) -> Set<UUID>

    init(
        allTabsForCurrentProfile: @escaping @MainActor () -> [Tab],
        liveShortcutTabs: @escaping @MainActor (_ windowId: UUID) -> [Tab],
        shortcutLiveTab: @escaping @MainActor (_ pinId: UUID, _ windowId: UUID) -> Tab?,
        visibleSplitTabIds: @escaping @MainActor (_ windowId: UUID) -> Set<UUID>
    ) {
        self.allTabsForCurrentProfile = allTabsForCurrentProfile
        self.liveShortcutTabs = liveShortcutTabs
        self.shortcutLiveTab = shortcutLiveTab
        self.visibleSplitTabIds = visibleSplitTabIds
    }

    func suggestions(for windowState: BrowserWindowState) -> [SearchManager.SearchSuggestion] {
        let visibleSplitTabIds = visibleSplitTabIds(windowState.id)
        let rankByTabId = rankById(for: windowState)
        let currentSpaceId = windowState.currentSpaceId
        var seenTabIds = Set<UUID>()

        return candidates(for: windowState)
            .filter { tab in
                guard seenTabIds.insert(tab.id).inserted else { return false }
                guard visibleSplitTabIds.contains(tab.id) == false else { return false }
                return tab.representsSumiNativeSurface == false
            }
            .sorted { lhs, rhs in
                let lhsRank = rankByTabId[lhs.id]
                let rhsRank = rankByTabId[rhs.id]
                if lhsRank != rhsRank {
                    return (lhsRank ?? Int.max) < (rhsRank ?? Int.max)
                }

                let lhsSelected = lhs.suspensionStateOwner.lastSelectedAt ?? .distantPast
                let rhsSelected = rhs.suspensionStateOwner.lastSelectedAt ?? .distantPast
                if lhsSelected != rhsSelected {
                    return lhsSelected > rhsSelected
                }

                if lhs.spaceId == currentSpaceId, rhs.spaceId != currentSpaceId {
                    return true
                }
                if lhs.spaceId != currentSpaceId, rhs.spaceId == currentSpaceId {
                    return false
                }

                if lhs.index != rhs.index {
                    return lhs.index < rhs.index
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map { tab in
                SearchManager.SearchSuggestion(text: tab.name, type: .tab(tab))
            }
    }

    private func candidates(for windowState: BrowserWindowState) -> [Tab] {
        if windowState.isIncognito {
            return windowState.ephemeralTabs
        }

        var candidates: [Tab] = []
        var seenTabIds = Set<UUID>()
        func append(_ tab: Tab) {
            guard seenTabIds.insert(tab.id).inserted else { return }
            candidates.append(tab)
        }

        allTabsForCurrentProfile()
            .filter { $0.isShortcutLiveInstance == false }
            .forEach(append)
        liveShortcutTabs(windowState.id)
            .forEach(append)

        return candidates
    }

    private func rankById(for windowState: BrowserWindowState) -> [UUID: Int] {
        var orderedIds: [UUID] = []
        var seenIds = Set<UUID>()

        func append(_ tabId: UUID?) {
            guard let tabId, seenIds.insert(tabId).inserted else { return }
            orderedIds.append(tabId)
        }

        func appendSelectionHistory(_ items: [BrowserWindowSelectionHistoryItem]) {
            for item in items {
                switch item {
                case .regularTab(let tabId):
                    append(tabId)
                case .shortcutPin(let pinId):
                    append(shortcutLiveTab(pinId, windowState.id)?.id)
                }
            }
        }

        if let currentSpaceId = windowState.currentSpaceId {
            appendSelectionHistory(windowState.selectionHistory.recentSelectionItemsBySpace[currentSpaceId] ?? [])
            (windowState.selectionHistory.recentRegularTabIdsBySpace[currentSpaceId] ?? []).forEach(append)
        }

        for spaceId in windowState.selectionHistory.recentSelectionItemsBySpace.keys.sorted(by: { $0.uuidString < $1.uuidString })
            where spaceId != windowState.currentSpaceId {
            appendSelectionHistory(windowState.selectionHistory.recentSelectionItemsBySpace[spaceId] ?? [])
        }

        windowState.activeTabForSpace.values.forEach(append)

        return Dictionary(uniqueKeysWithValues: orderedIds.enumerated().map { ($0.element, $0.offset) })
    }
}
